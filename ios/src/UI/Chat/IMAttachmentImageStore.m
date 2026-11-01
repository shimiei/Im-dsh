//
//  IMAttachmentImageStore.m
//  IMDSH — 历史图片缓存
//

#import "IMAttachmentImageStore.h"
#import "IMChatService.h"

/// 超过这个内存量就先淘汰（解码后的像素很占地方）。
static const NSInteger IMAttachmentCacheByteLimit = 48 * 1024 * 1024;

@interface IMAttachmentImageStore ()
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *cache;
/// 正在飞的请求：attachmentId → 等待中的回调列表（同一张图只发一次请求）。
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *pending;
@property (nonatomic, strong) IMChatService *service;
@end

@implementation IMAttachmentImageStore

+ (instancetype)shared {
    static IMAttachmentImageStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[IMAttachmentImageStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 80;
        _cache.totalCostLimit = (NSUInteger)IMAttachmentCacheByteLimit;
        _pending = [NSMutableDictionary dictionary];
        _service = [[IMChatService alloc] init];
    }
    return self;
}

- (UIImage *)cachedImageForAttachmentId:(NSString *)attachmentId {
    if (attachmentId.length == 0) return nil;
    return [self.cache objectForKey:attachmentId];
}

- (void)imageForAttachment:(IMAttachmentRef *)attachment
                 sessionId:(NSString *)sessionId
                completion:(void (^)(UIImage *))completion {
    if (completion == nil) return;
    NSString *attachmentId = attachment.attachmentId;
    if (attachmentId.length == 0 || sessionId.length == 0) {
        completion(nil);
        return;
    }

    UIImage *cached = [self.cache objectForKey:attachmentId];
    if (cached != nil) {
        completion(cached);
        return;
    }

    dispatch_block_t mainBlock = ^{
        NSMutableArray *waiters = self.pending[attachmentId];
        if (waiters != nil) {
            [waiters addObject:[completion copy]];
            return;
        }
        self.pending[attachmentId] = [NSMutableArray arrayWithObject:[completion copy]];

        __weak typeof(self) weakSelf = self;
        [self.service loadAttachmentWithId:attachmentId sessionId:sessionId completion:^(NSData *data, NSString *mediaType, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) return;

            UIImage *image = nil;
            if (error == nil && data.length > 0) {
                image = [UIImage imageWithData:data];
            }

            if (image != nil) {
                NSInteger cost = (NSInteger)(image.size.width * image.scale * image.size.height * image.scale * 4.0);
                [self.cache setObject:image forKey:attachmentId cost:(NSUInteger)MAX(cost, 1)];
            }

            NSMutableArray *callbacks = self.pending[attachmentId];
            [self.pending removeObjectForKey:attachmentId];
            for (void (^callback)(UIImage *) in callbacks) {
                callback(image);
            }
        }];
    };

    // pending 表是主线程状态；调用方都在主线程，这里只是兜底。
    if (NSThread.isMainThread) mainBlock();
    else dispatch_async(dispatch_get_main_queue(), mainBlock);
}

@end
