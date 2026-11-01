//
//  IMAttachmentImageStore.h
//  IMDSH — 历史图片缓存（session/attachment 按需拉取）
//
//  为什么单独一层：一个会话里可能滚过几十张图，同一张会反复配置；用 NSCache 挡住重复请求，
//  并且任何一步失败都静默降级成文字 chip —— 历史图看不到不该打断阅读。
//

#import <UIKit/UIKit.h>
#import "IMChatModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAttachmentImageStore : NSObject

+ (instancetype)shared;

/// 同步命中缓存（没取过返回 nil）。
- (nullable UIImage *)cachedImageForAttachmentId:(NSString *)attachmentId;

/// 异步取图：命中缓存立即回调；失败回调 nil，调用方自行降级，不要提示用户。
- (void)imageForAttachment:(IMAttachmentRef *)attachment
                 sessionId:(NSString *)sessionId
                completion:(void (^)(UIImage * _Nullable image))completion;

@end

NS_ASSUME_NONNULL_END
