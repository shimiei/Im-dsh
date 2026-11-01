//
//  IMSettingsRowView.h
//  IMDSH — 设置页的通用信息行（图标 + 标题/副标题 + 右侧值 + 附件）
//
//  设置域里 90% 的条目都是「一段说明 + 一个值 + 一个功能」，统一成一个控件，
//  免得每个页面各写一遍 label 堆叠，也保证左右内边距、分隔线、点击高亮完全一致。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMSettingsRowAccessory) {
    IMSettingsRowAccessoryNone = 0,
    IMSettingsRowAccessoryChevron,      // >
    IMSettingsRowAccessoryCheckmark,    // ✓（当前项）
    IMSettingsRowAccessorySpinner,      // 加载中
};

@interface IMSettingsRowView : UIControl

/// 一行；systemImageName 传 nil 就不占图标位。
+ (instancetype)rowWithTitle:(NSString *)title systemImage:(nullable NSString *)systemImageName;

@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
/// 右侧的值文本。
@property (nonatomic, copy, nullable) NSString *valueText;
@property (nonatomic, assign) IMSettingsRowAccessory accessory;

@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
@property (nonatomic, strong, readonly) UILabel *valueLabel;
@property (nonatomic, strong, readonly, nullable) UIImageView *iconView;

/// 值用等宽字体（地址、设备 ID、配对码这类要逐字符核对的文本）。
@property (nonatomic, assign) BOOL monospacedValue;
/// 标题用等宽字体（配对码本身就该逐字符核对）。
@property (nonatomic, assign) BOOL monospacedTitle;
/// 右侧值的颜色，默认 labelSecondary。
@property (nonatomic, strong, nullable) UIColor *valueColor;
/// 标题用危险色（删除 / 吊销这类入口）。
@property (nonatomic, assign) BOOL destructive;
/// 图标着色，默认 labelSecondary。
@property (nonatomic, strong, nullable) UIColor *iconTintColor;
/// 右侧自定义附件（例如吊销按钮），排在 chevron 前。
@property (nonatomic, strong, nullable) UIView *trailingAccessoryView;
/// 点击回调；设了才可点（会有高亮反馈 + 无障碍 button 语义）。
@property (nonatomic, copy, nullable) void (^onTap)(void);
/// 长按可复制的完整文本（例如完整 deviceId）。
@property (nonatomic, copy, nullable) NSString *copyableText;
/// 副标题最多几行，默认 2。
@property (nonatomic, assign) NSInteger subtitleLineLimit;
/// 上下内边距，默认 12。
@property (nonatomic, assign) CGFloat verticalPadding;

/// 打开/关闭 accessory 的转圈（accessory 为 Spinner 时有效）。
- (void)setAccessorySpinning:(BOOL)spinning;

@end

NS_ASSUME_NONNULL_END
