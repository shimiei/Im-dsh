//
//  IMImageAttachment.m
//  IMDSH — 待发送图片
//

#import "IMImageAttachment.h"

static const CGFloat IMImageDefaultPixelSize = 1600;
static const NSInteger IMImageDefaultMaxCount = 4;
/// 缩略图上显示的尺寸（像素，@3x 也够）。
static const CGFloat IMImageThumbnailPixelSize = 180;

#pragma mark - 限制

@implementation IMImageLimits

+ (instancetype)defaultLimits {
    IMImageLimits *limits = [[IMImageLimits alloc] init];
    limits.maxPixelSize = IMImageDefaultPixelSize;
    limits.maxCount = IMImageDefaultMaxCount;
    limits.maxImageBytes = 0;
    limits.maxMessageBytes = 0;
    limits.maxPixels = 0;
    limits.mediaTypes = @[@"image/jpeg"];
    return limits;
}

+ (instancetype)limitsWithProjectionValue:(NSDictionary *)value {
    IMImageLimits *limits = [self defaultLimits];
    if (![value isKindOfClass:NSDictionary.class]) return limits;

    id dimension = value[@"maxImageDimension"];
    if ([dimension isKindOfClass:NSNumber.class] && [(NSNumber *)dimension doubleValue] > 0) {
        // 服务端更严就听服务端的，别硬顶 1600。
        CGFloat server = [(NSNumber *)dimension doubleValue];
        limits.maxPixelSize = MIN(IMImageDefaultPixelSize, server);
    }
    id perMessage = value[@"maxImagesPerMessage"];
    if ([perMessage isKindOfClass:NSNumber.class] && [(NSNumber *)perMessage integerValue] > 0) {
        limits.maxCount = [(NSNumber *)perMessage integerValue];
    }
    id imageBytes = value[@"maxImageBytes"];
    if ([imageBytes isKindOfClass:NSNumber.class]) limits.maxImageBytes = [(NSNumber *)imageBytes integerValue];
    id messageBytes = value[@"maxMessageImageBytes"];
    if ([messageBytes isKindOfClass:NSNumber.class]) limits.maxMessageBytes = [(NSNumber *)messageBytes integerValue];
    id pixels = value[@"maxImagePixels"];
    if ([pixels isKindOfClass:NSNumber.class]) limits.maxPixels = [(NSNumber *)pixels integerValue];

    id mediaTypes = value[@"mediaTypes"];
    if ([mediaTypes isKindOfClass:NSArray.class] && [(NSArray *)mediaTypes count] > 0) {
        NSMutableArray<NSString *> *filtered = [NSMutableArray array];
        for (id item in (NSArray *)mediaTypes) {
            if ([item isKindOfClass:NSString.class]) [filtered addObject:item];
        }
        if (filtered.count > 0) limits.mediaTypes = filtered;
    }
    return limits;
}

/// 选一个体积可控又一定被服务端接受的类型。
- (NSString *)preferredMediaType {
    if ([self.mediaTypes containsObject:@"image/jpeg"]) return @"image/jpeg";
    if ([self.mediaTypes containsObject:@"image/png"]) return @"image/png";
    if ([self.mediaTypes containsObject:@"image/webp"]) return @"image/webp";
    return @"image/jpeg";
}

@end

#pragma mark - 附件

@interface IMImageAttachment ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *mediaType;
@property (nonatomic, copy, readwrite) NSString *base64Data;
@property (nonatomic, assign, readwrite) NSInteger byteLength;
@property (nonatomic, strong, readwrite) UIImage *thumbnail;
@end

@implementation IMImageAttachment

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = NSUUID.UUID.UUIDString;
    }
    return self;
}

+ (NSUInteger)maxCount {
    return (NSUInteger)IMImageDefaultMaxCount;
}

/// 等比缩到最长边 maxPixel；本来就更小就原样返回。
static UIImage *IMResizeImage(UIImage *image, CGFloat maxPixel) {
    CGSize size = image.size;
    if (size.width <= 0 || size.height <= 0) return image;
    CGFloat pixelWidth = size.width * image.scale;
    CGFloat pixelHeight = size.height * image.scale;
    CGFloat longest = MAX(pixelWidth, pixelHeight);
    if (longest <= maxPixel) return image;

    CGFloat ratio = maxPixel / longest;
    CGSize target = CGSizeMake(MAX(1.0, floor(pixelWidth * ratio)), MAX(1.0, floor(pixelHeight * ratio)));

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    // drawInRect 会顺带修掉 exif 方向，之后不用再管 orientation。
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
}

static NSData *IMEncodeImage(UIImage *image, NSString *mediaType, CGFloat quality) {
    if ([mediaType isEqualToString:@"image/png"]) {
        return UIImagePNGRepresentation(image);
    }
    return UIImageJPEGRepresentation(image, quality);
}

+ (NSString *)defaultName {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HHmmss";
    return [NSString stringWithFormat:@"IMG_%@.jpg", [formatter stringFromDate:[NSDate date]]];
}

+ (dispatch_queue_t)workQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("imdsh.image.prepare", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

+ (void)prepareWithImage:(UIImage *)image
                    name:(NSString *)name
                  limits:(IMImageLimits *)limits
              completion:(void (^)(IMImageAttachment *, NSString *))completion {
    if (image == nil) {
        if (completion) completion(nil, @"没有读到图片内容");
        return;
    }
    IMImageLimits *resolved = limits ?: [IMImageLimits defaultLimits];
    NSString *resolvedName = name.length > 0 ? name : [self defaultName];
    NSString *mediaType = [resolved preferredMediaType];

    dispatch_async([self workQueue], ^{
        // 先按最长边压一次；压完还超字节/像素预算就降质量，再不行继续缩尺寸。
        CGFloat basePixel = resolved.maxPixelSize > 0 ? resolved.maxPixelSize : IMImageDefaultPixelSize;
        NSArray<NSNumber *> *qualityLadder = @[@0.82, @0.70, @0.60, @0.50];
        NSArray<NSNumber *> *shrinkLadder = @[@1.0, @0.75, @0.60];
        NSData *chosen = nil;
        UIImage *chosenImage = nil;

        for (NSNumber *shrink in shrinkLadder) {
            UIImage *resized = IMResizeImage(image, basePixel * shrink.doubleValue);
            // 像素数也要守住（服务端按解码后的真实尺寸校验）。
            if (resolved.maxPixels > 0) {
                double pixels = (double)resized.size.width * (double)resized.size.height;
                if (pixels > (double)resolved.maxPixels) {
                    CGFloat ratio = sqrt((double)resolved.maxPixels / pixels);
                    resized = IMResizeImage(resized, MAX(resized.size.width, resized.size.height) * ratio);
                }
            }
            for (NSNumber *quality in qualityLadder) {
                NSData *data = IMEncodeImage(resized, mediaType, quality.doubleValue);
                if (data.length == 0) continue;
                BOOL tooBig = resolved.maxImageBytes > 0 && (NSInteger)data.length > resolved.maxImageBytes;
                if (!tooBig) {
                    chosen = data;
                    chosenImage = resized;
                    break;
                }
            }
            if (chosen != nil) break;
        }

        if (chosen == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, @"图片过大，压缩后仍超过服务端限制");
            });
            return;
        }

        NSString *base64 = [chosen base64EncodedStringWithOptions:0];
        UIImage *thumbnail = IMResizeImage(chosenImage, IMImageThumbnailPixelSize);

        IMImageAttachment *attachment = [[IMImageAttachment alloc] init];
        attachment.name = resolvedName;
        attachment.mediaType = mediaType;
        attachment.base64Data = base64;
        attachment.byteLength = (NSInteger)chosen.length;
        attachment.thumbnail = thumbnail;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(attachment, nil);
        });
    });
}

@end
