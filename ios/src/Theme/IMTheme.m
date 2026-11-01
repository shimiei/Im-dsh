#import "IMTheme.h"

@implementation IMTheme

+ (instancetype)shared {
    static IMTheme *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [IMTheme new]; });
    return shared;
}

#pragma mark - 颜色

- (UIColor *)accentColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.42 green:0.55 blue:1.00 alpha:1.0]
            : [UIColor colorWithRed:0.30 green:0.42 blue:0.99 alpha:1.0];
    }];
}

- (UIColor *)backgroundBase {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.067 green:0.071 blue:0.078 alpha:1.0]   // #111214
            : [UIColor colorWithRed:0.949 green:0.953 blue:0.961 alpha:1.0];  // #F2F3F5
    }];
}

- (UIColor *)backgroundLayer1 {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.106 green:0.110 blue:0.118 alpha:1.0]   // #1B1C1E
            : [UIColor colorWithWhite:1.0 alpha:1.0];
    }];
}

- (UIColor *)backgroundLayer2 {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.145 green:0.149 blue:0.157 alpha:1.0]   // #252628
            : [UIColor colorWithRed:0.976 green:0.980 blue:0.984 alpha:1.0];
    }];
}

- (UIColor *)backgroundLayer3 {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.192 green:0.196 blue:0.208 alpha:1.0]
            : [UIColor colorWithRed:0.929 green:0.933 blue:0.941 alpha:1.0];
    }];
}

- (UIColor *)labelPrimary {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.96 alpha:1.0]
            : [UIColor colorWithWhite:0.06 alpha:1.0];
    }];
}

- (UIColor *)labelSecondary {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.62 alpha:1.0]
            : [UIColor colorWithWhite:0.42 alpha:1.0];
    }];
}

- (UIColor *)labelTertiary {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.45 alpha:1.0]
            : [UIColor colorWithWhite:0.60 alpha:1.0];
    }];
}

- (UIColor *)labelDimmed {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.34 alpha:1.0]
            : [UIColor colorWithWhite:0.72 alpha:1.0];
    }];
}

- (UIColor *)separatorColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.09]
            : [UIColor colorWithWhite:0.0 alpha:0.08];
    }];
}

- (UIColor *)successColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.24 green:0.78 blue:0.48 alpha:1.0]
            : [UIColor colorWithRed:0.06 green:0.62 blue:0.34 alpha:1.0];
    }];
}

- (UIColor *)warningColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.98 green:0.75 blue:0.25 alpha:1.0]
            : [UIColor colorWithRed:0.78 green:0.52 blue:0.02 alpha:1.0];
    }];
}

- (UIColor *)dangerColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.99 green:0.42 blue:0.42 alpha:1.0]
            : [UIColor colorWithRed:0.83 green:0.16 blue:0.16 alpha:1.0];
    }];
}

- (UIColor *)glassStrokeColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.12]
            : [UIColor colorWithWhite:1.0 alpha:0.55];
    }];
}

- (UIColor *)codeBackgroundColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.078 green:0.082 blue:0.094 alpha:1.0]
            : [UIColor colorWithRed:0.961 green:0.965 blue:0.973 alpha:1.0];
    }];
}

- (UIColor *)inlineCodeBackgroundColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.08]
            : [UIColor colorWithWhite:0.0 alpha:0.055];
    }];
}

#pragma mark - 字体

+ (UIFont *)fontLargeTitle { return [UIFont systemFontOfSize:28 weight:UIFontWeightBold]; }
+ (UIFont *)fontTitle      { return [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontHeadline   { return [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontBody       { return [UIFont systemFontOfSize:15 weight:UIFontWeightRegular]; }
+ (UIFont *)fontCallout    { return [UIFont systemFontOfSize:14 weight:UIFontWeightRegular]; }
+ (UIFont *)fontFootnote   { return [UIFont systemFontOfSize:12 weight:UIFontWeightRegular]; }
+ (UIFont *)fontCaption    { return [UIFont systemFontOfSize:11 weight:UIFontWeightMedium]; }
+ (UIFont *)fontMonoBody   { return [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]; }
+ (UIFont *)fontMonoSmall  { return [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular]; }

+ (CGFloat)bodyLineHeightMultiple { return 1.45; }

#pragma mark - 度量

- (CGFloat)radiusSmall  { return 8; }
- (CGFloat)radiusMedium { return 12; }
- (CGFloat)radiusLarge  { return 18; }
- (CGFloat)radiusCard   { return 22; }
- (CGFloat)radiusPill   { return 999; }
- (CGFloat)spacingXS    { return 4; }
- (CGFloat)spacingS     { return 8; }
- (CGFloat)spacingM     { return 12; }
- (CGFloat)spacingL     { return 16; }
- (CGFloat)spacingXL    { return 24; }
- (CGFloat)hairline     { return 1.0 / MAX(1.0, UITraitCollection.currentTraitCollection.displayScale); }

- (CGFloat)maxContentWidthForSize:(CGSize)size {
    if (size.width >= 1024) return 860;
    if (size.width >= 700) return 720;
    return size.width;
}

@end
