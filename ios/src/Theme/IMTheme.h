//
//  IMTheme.h
//  IMDSH — 设计系统（颜色 / 字体 / 间距 / 圆角）
//
//  取值对齐 DeepSeek Harness 桌面端：主色取自 DSH 品牌蓝，语义色走系统动态色，
//  所有颜色都通过 colorWithDynamicProvider 支持浅色/深色，跟随系统外观。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMTheme : NSObject

+ (instancetype)shared;

#pragma mark - 颜色

/// 品牌强调色（DSH 蓝）。
@property (nonatomic, readonly) UIColor *accentColor;
/// 页面底色（iOS grouped 背景）。
@property (nonatomic, readonly) UIColor *backgroundBase;
/// 卡片/分区底色。
@property (nonatomic, readonly) UIColor *backgroundLayer1;
@property (nonatomic, readonly) UIColor *backgroundLayer2;
@property (nonatomic, readonly) UIColor *backgroundLayer3;

@property (nonatomic, readonly) UIColor *labelPrimary;
@property (nonatomic, readonly) UIColor *labelSecondary;
@property (nonatomic, readonly) UIColor *labelTertiary;
@property (nonatomic, readonly) UIColor *labelDimmed;

@property (nonatomic, readonly) UIColor *separatorColor;
@property (nonatomic, readonly) UIColor *successColor;
@property (nonatomic, readonly) UIColor *warningColor;
@property (nonatomic, readonly) UIColor *dangerColor;

/// 玻璃表面在浅色下需要的极淡描边，保证边界可辨。
@property (nonatomic, readonly) UIColor *glassStrokeColor;

/// 代码块底色。
@property (nonatomic, readonly) UIColor *codeBackgroundColor;
@property (nonatomic, readonly) UIColor *inlineCodeBackgroundColor;

#pragma mark - 字体

+ (UIFont *)fontLargeTitle;
+ (UIFont *)fontTitle;
+ (UIFont *)fontHeadline;
+ (UIFont *)fontBody;
+ (UIFont *)fontCallout;
+ (UIFont *)fontFootnote;
+ (UIFont *)fontCaption;
+ (UIFont *)fontMonoBody;
+ (UIFont *)fontMonoSmall;
/// 正文可读行高倍数（与 DSH markdown 的 22/14 比例一致）。
+ (CGFloat)bodyLineHeightMultiple;

#pragma mark - 度量

@property (nonatomic, readonly) CGFloat radiusSmall;    // 8
@property (nonatomic, readonly) CGFloat radiusMedium;   // 12
@property (nonatomic, readonly) CGFloat radiusLarge;    // 18
@property (nonatomic, readonly) CGFloat radiusCard;     // 22
@property (nonatomic, readonly) CGFloat radiusPill;     // 999
@property (nonatomic, readonly) CGFloat spacingXS;      // 4
@property (nonatomic, readonly) CGFloat spacingS;       // 8
@property (nonatomic, readonly) CGFloat spacingM;       // 12
@property (nonatomic, readonly) CGFloat spacingL;       // 16
@property (nonatomic, readonly) CGFloat spacingXL;      // 24
@property (nonatomic, readonly) CGFloat hairline;

/// 内容最大宽度：iPad 上把聊天/表单收窄，避免长行难读。
- (CGFloat)maxContentWidthForSize:(CGSize)size;

@end

NS_ASSUME_NONNULL_END
