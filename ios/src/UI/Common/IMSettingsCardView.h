//
//  IMSettingsCardView.h
//  IMDSH — 设置页的分区卡片（标题 + 液态玻璃卡 + 行 + 脚注）
//
//  为什么不用 UITableView(insetGrouped)：系统分组会把「灰底板 + 白卡」叠出来，
//  和我们液态玻璃的视觉基准冲突。这里用真实玻璃卡承载行，行与行之间自己画 hairline。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class IMGlassView;

@interface IMSettingsCardView : UIView

/// title 为空时不显示分区标题。
- (instancetype)initWithTitle:(nullable NSString *)title NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// 底下的玻璃卡片（需要改 tint / 圆角时用）。
@property (nonatomic, readonly) IMGlassView *glassView;
/// 卡片内部的纵向栈，行都加在这里。
@property (nonatomic, readonly) UIStackView *contentStack;
/// 卡片内边距，默认 0（行自带水平内边距）；仅当 addView: 放自定义内容时才需要设。
@property (nonatomic, assign) UIEdgeInsets contentInsets;

/// 追加一行，自动在这一行前面补一条 hairline 分隔线（首行不加）。
- (void)addRow:(UIView *)row;
/// showsDivider = NO 时不留行间分隔线（紧跟在自绘组标题下的那一行用）。
- (void)addRow:(UIView *)row showsDivider:(BOOL)showsDivider;
/// 追加任意视图，不加分隔线（用于自绘的摘要块、说明块）。
- (void)addView:(UIView *)view;
/// 清空所有行/视图（保留卡片本体），用于就地局部刷新。
- (void)clearContent;
/// 卡片下方的说明文字；传 nil 清除。
- (void)setFooterText:(nullable NSString *)footerText;

@end

NS_ASSUME_NONNULL_END
