//
//  IMImageAttachment.h
//  IMDSH — 待发送图片（按会话的 imageLimits 缩放、重编码、转 base64）
//
//  为什么不直接发原图：手机原图 12MP 起步，base64 之后十几 MB，网关一次转发就卡住。
//  上限不是硬编码的——打开会话时从 projections.values.imageLimits 读，这里只给一个
//  兜底默认值（1600px / 4 张），服务端给得更严就按服务端的来。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 会话级图片限制（投影 imageLimits 的落地形态）。
@interface IMImageLimits : NSObject

@property (nonatomic, assign) CGFloat maxPixelSize;              // 最长边，默认 1600
@property (nonatomic, assign) NSInteger maxCount;                // 单条消息最多几张，默认 4
@property (nonatomic, assign) NSInteger maxImageBytes;           // 单张最大字节，0 = 未知
@property (nonatomic, assign) NSInteger maxMessageBytes;         // 单条消息图片总字节，0 = 未知
@property (nonatomic, assign) NSInteger maxPixels;               // 单张最大像素数，0 = 未知
@property (nonatomic, copy, nullable) NSArray<NSString *> *mediaTypes;

+ (instancetype)defaultLimits;
/// 解析 projections.values.imageLimits；字段缺失就沿用默认值。
+ (instancetype)limitsWithProjectionValue:(nullable NSDictionary *)value;

@end

@interface IMImageAttachment : NSObject

/// 本地唯一标识（UUID）：删除 chip 时按 id 查，不靠数组下标（连点会错位）。
@property (nonatomic, copy, readonly) NSString *identifier;
/// 文件名，例如 IMG_0001.jpg。
@property (nonatomic, copy, readonly) NSString *name;
/// image/jpeg 或 image/png（取决于会话允许的类型）。
@property (nonatomic, copy, readonly) NSString *mediaType;
/// 重编码后的 base64（不含 data URL 前缀）。
@property (nonatomic, copy, readonly) NSString *base64Data;
/// 重编码后的真实字节数（base64 解码后），用于发送前的总量校验。
@property (nonatomic, assign, readonly) NSInteger byteLength;
/// 输入区 chip 用的小图。
@property (nonatomic, strong, readonly) UIImage *thumbnail;

/// 默认上限（没有拿到 imageLimits 时用）。
+ (NSUInteger)maxCount;

/// 后台缩图 + 重编码 + base64，回调在主线程。name 传 nil 自动生成。
/// 超出 maxImageBytes / maxPixels 会逐级降质量再压尺寸；实在压不下去回 failureReason。
+ (void)prepareWithImage:(UIImage *)image
                    name:(nullable NSString *)name
                  limits:(nullable IMImageLimits *)limits
              completion:(void (^)(IMImageAttachment * _Nullable attachment, NSString * _Nullable failureReason))completion;

@end

NS_ASSUME_NONNULL_END
