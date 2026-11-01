//
//  IMMessageCell.h
//  IMDSH — 一条消息的单元格（用户气泡 / 助手文本 / 工具卡 / 待办 / 提示条）
//

#import <UIKit/UIKit.h>
#import "IMChatModels.h"

NS_ASSUME_NONNULL_BEGIN

@class IMMessageCell;

@protocol IMMessageCellDelegate <NSObject>
/// 卡片展开/收起后自身高度变了，外层需要重算行高。
- (void)messageCellDidChangeHeight:(IMMessageCell *)cell;
/// 点了 Markdown 里的链接。
- (void)messageCell:(IMMessageCell *)cell didTapLink:(NSURL *)url;
/// 要历史图片缩略图：命中缓存可直接同步回调；拿不到就回调 nil，cell 退回纯文字 chip。
- (void)messageCell:(IMMessageCell *)cell
    loadThumbnailForAttachment:(IMAttachmentRef *)attachment
                    completion:(void (^)(UIImage * _Nullable image))completion;
/// 点了附件 chip。
- (void)messageCell:(IMMessageCell *)cell didTapAttachment:(IMAttachmentRef *)attachment;
@end

@interface IMMessageCell : UITableViewCell

@property (nonatomic, weak, nullable) id<IMMessageCellDelegate> delegate;

- (void)configureWithItem:(IMMessageItem *)item;

@end

NS_ASSUME_NONNULL_END
