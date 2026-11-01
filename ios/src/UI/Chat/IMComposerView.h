//
//  IMComposerView.h
//  IMDSH — 输入区：悬浮玻璃胶囊（多行自增高 + 图片附件 + 发送/停止 + 生成中状态条）
//

#import <UIKit/UIKit.h>
#import "IMImageAttachment.h"

NS_ASSUME_NONNULL_BEGIN

@class IMComposerView;

@protocol IMComposerViewDelegate <NSObject>
- (void)composerViewDidTapSend:(IMComposerView *)composer;
- (void)composerViewDidTapStop:(IMComposerView *)composer;
/// 点了左侧「+」：由控制器弹相册 / 相机菜单。
- (void)composerViewDidTapAttach:(IMComposerView *)composer;
/// 删掉指定 id 的待发图片；控制器同步自己的数组后再回调 setAttachments: 重画。
- (void)composerView:(IMComposerView *)composer didRemoveAttachmentWithId:(NSString *)attachmentId;
@end

@interface IMComposerView : UIView

@property (nonatomic, weak, nullable) id<IMComposerViewDelegate> delegate;

@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, readonly) BOOL hasText;
@property (nonatomic, readonly) BOOL running;
/// 待发送图片数量（只有图片也算可发送）。
@property (nonatomic, readonly) NSUInteger attachmentCount;

/// 运行中：按钮变「停止」，并显示"生成中…"状态条。
- (void)setRunning:(BOOL)running;
/// 状态条右侧的用量文案（nil 或空串则隐藏）。
- (void)setTokenSummary:(nullable NSString *)summary;
/// 重画缩略图 chip 行（传空数组即清空并收起该行）。
- (void)setAttachments:(nullable NSArray<IMImageAttachment *> *)attachments;
/// 发送失败：把文本还回输入框（不要丢掉用户刚打的内容）。
- (void)restoreText:(nullable NSString *)text;
- (void)clearText;
- (void)beginEditing;

@end

NS_ASSUME_NONNULL_END
