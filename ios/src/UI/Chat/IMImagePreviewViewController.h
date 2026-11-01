//
//  IMImagePreviewViewController.h
//  IMDSH — 图片全屏预览（黑色背景 + 捏合缩放 + 双击放大，不引三方库）
//

#import <UIKit/UIKit.h>
#import "IMChatModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMImagePreviewViewController : UIViewController

/// placeholder 先把已有的缩略图铺上，真正的原图由内部按 attachmentId 拉，失败就留在缩略图上。
- (instancetype)initWithPlaceholderImage:(nullable UIImage *)image
                              attachment:(IMAttachmentRef *)attachment
                               sessionId:(NSString *)sessionId;

@end

NS_ASSUME_NONNULL_END
