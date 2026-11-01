//
//  IMGlass.h
//  IMDSH — 液态玻璃组件库
//
//  全部基于 iOS 26+ 的原生 Liquid Glass：UIGlassEffect / UIGlassContainerEffect，
//  以及 UIButtonConfiguration 的 glass 系列（system 提供的真实玻璃按钮）。
//  自研的只有布局与动效外壳，材质一律交给系统，保证和 Apple 原生 App 观感一致。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMGlassStyle) {
    /// 标准玻璃：内容可读性优先。
    IMGlassStyleRegular = 0,
    /// 清透玻璃：用于悬浮在媒体之上的控件。
    IMGlassStyleClear = 1,
};

/// 一块液态玻璃表面。
@interface IMGlassView : UIView

- (instancetype)initWithStyle:(IMGlassStyle)style NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, assign) IMGlassStyle glassStyle;
/// 玻璃着色，nil = 系统默认。
@property (nonatomic, strong, nullable) UIColor *tintColor;
/// 交互式玻璃（按压时有弹性反馈）。
@property (nonatomic, assign) BOOL interactive;
/// 圆角，默认取 IMTheme.radiusCard。
@property (nonatomic, assign) CGFloat cornerRadius;
/// 是否画一圈极淡描边（浅色背景下定义边界）。
@property (nonatomic, assign) BOOL showsStroke;

/// 内容容器：所有子视图都必须加到这里。
@property (nonatomic, readonly) UIView *contentView;

@end

/// 玻璃合并容器：多个玻璃子元素靠近时会像液体一样融合（UIGlassContainerEffect）。
@interface IMGlassGroupView : UIView

/// 融合起始间距，默认 12。
@property (nonatomic, assign) CGFloat mergeSpacing;
@property (nonatomic, readonly) UIView *contentView;

@end

/// 玻璃胶囊按钮（系统 glass 按钮配置）。
@interface IMGlassButton : UIButton

/// 图标 + 文字的玻璃按钮。
+ (instancetype)buttonWithTitle:(nullable NSString *)title
                      systemImage:(nullable NSString *)systemImageName
                         prominent:(BOOL)prominent;

/// 仅图标的正方形玻璃按钮。
+ (instancetype)iconButtonWithSystemImage:(NSString *)systemImageName
                                  diameter:(CGFloat)diameter;

/// 主色强调样式（用于「发送」这类主动作）。
- (void)applyProminentStyle;
/// 文字样式变更（保持玻璃材质）。
- (void)setButtonTitle:(nullable NSString *)title systemImage:(nullable NSString *)systemImageName;

@end

/// 浮动玻璃条：顶部导航或底部工具条，自动避让安全区。
@interface IMGlassBar : IMGlassView

/// 内容栈（水平排列，已设置好常用间距）。
@property (nonatomic, readonly) UIStackView *stackView;

/// 条内边距，默认 10/10。
@property (nonatomic, assign) UIEdgeInsets contentInsets;

@end

/// 便捷构造 SF Symbol 图片（统一 weight/scale，避免各处手写）。
FOUNDATION_EXPORT UIImage *IMSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight);

NS_ASSUME_NONNULL_END
