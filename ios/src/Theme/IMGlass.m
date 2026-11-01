#import "IMGlass.h"
#import "IMTheme.h"

UIImage *IMSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIImageConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:cfg];
    return image ?: [UIImage systemImageNamed:@"circle.fill" withConfiguration:cfg];
}

#pragma mark - IMGlassView

@interface IMGlassView ()
@property (nonatomic, strong) UIVisualEffectView *effectView;
@property (nonatomic, strong) UIGlassEffect *glassEffect;
@end

@implementation IMGlassView

- (instancetype)initWithStyle:(IMGlassStyle)style {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _glassStyle = style;
        _cornerRadius = IMTheme.shared.radiusCard;
        _showsStroke = NO;
        [self setupEffectView];
        __weak typeof(self) weakSelf = self;
        [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
                          withHandler:^(id<UITraitEnvironment> traitEnvironment, UITraitCollection *previous) {
            __strong typeof(weakSelf) self = weakSelf;
            if (self.showsStroke) {
                self.effectView.layer.borderColor = IMTheme.shared.glassStrokeColor.CGColor;
            }
        }];
    }
    return self;
}

- (void)setupEffectView {
    [self.effectView removeFromSuperview];

    UIVisualEffect *effect = nil;
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = [UIGlassEffect effectWithStyle:(self.glassStyle == IMGlassStyleClear
                                                               ? UIGlassEffectStyleClear
                                                               : UIGlassEffectStyleRegular)];
        glass.interactive = self.interactive;
        if (self.tintColor) glass.tintColor = self.tintColor;
        self.glassEffect = glass;
        effect = glass;
    } else {
        // 低于 iOS 26 没有液态玻璃：退化成系统材质，界面照常可用，而不是首启崩在 dyld。
        self.glassEffect = nil;
        effect = [UIBlurEffect effectWithStyle:(self.glassStyle == IMGlassStyleClear
                                                ? UIBlurEffectStyleSystemUltraThinMaterial
                                                : UIBlurEffectStyleSystemThinMaterial)];
    }

    UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:effect];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.clipsToBounds = YES;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.cornerRadius = self.cornerRadius;
    [self addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:self.topAnchor],
        [view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [view.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    self.effectView = view;

    if (self.showsStroke) {
        view.layer.borderWidth = IMTheme.shared.hairline;
        view.layer.borderColor = IMTheme.shared.glassStrokeColor.CGColor;
    }

    self.clipsToBounds = NO;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.cornerRadius = self.cornerRadius;
}

- (UIView *)contentView {
    return self.effectView.contentView;
}

- (void)setGlassStyle:(IMGlassStyle)glassStyle {
    if (_glassStyle == glassStyle) return;
    _glassStyle = glassStyle;
    [self setupEffectView];
}

- (void)setTintColor:(UIColor *)tintColor {
    _tintColor = tintColor;
    self.glassEffect.tintColor = tintColor;
}

- (void)setInteractive:(BOOL)interactive {
    _interactive = interactive;
    self.glassEffect.interactive = interactive;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.layer.cornerRadius = cornerRadius;
    self.effectView.layer.cornerRadius = cornerRadius;
}

- (void)setShowsStroke:(BOOL)showsStroke {
    _showsStroke = showsStroke;
    self.effectView.layer.borderWidth = showsStroke ? IMTheme.shared.hairline : 0;
    self.effectView.layer.borderColor = showsStroke ? IMTheme.shared.glassStrokeColor.CGColor : UIColor.clearColor.CGColor;
}

- (void)dealloc { }

@end

#pragma mark - IMGlassGroupView

@implementation IMGlassGroupView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _mergeSpacing = 12;
        [self setup];
    }
    return self;
}

- (instancetype)init {
    return [self initWithFrame:CGRectZero];
}

- (void)setup {
    UIVisualEffect *effect = nil;
    if (@available(iOS 26.0, *)) {
        UIGlassContainerEffect *container = [UIGlassContainerEffect new];
        container.spacing = self.mergeSpacing;
        effect = container;
    } else {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    }

    UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:effect];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:self.topAnchor],
        [view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [view.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    _contentView = view.contentView;
}

- (void)setMergeSpacing:(CGFloat)mergeSpacing {
    _mergeSpacing = mergeSpacing;
    if (@available(iOS 26.0, *)) {
        UIVisualEffectView *view = (UIVisualEffectView *)self.subviews.firstObject;
        if ([view.effect isKindOfClass:UIGlassContainerEffect.class]) {
            UIGlassContainerEffect *effect = (UIGlassContainerEffect *)view.effect;
            effect.spacing = mergeSpacing;
        }
    }
}

@end

#pragma mark - IMGlassButton

@implementation IMGlassButton

+ (UIButtonConfiguration *)baseConfigurationProminent:(BOOL)prominent {
    UIButtonConfiguration *config = nil;
    if (@available(iOS 26.0, *)) {
        config = prominent
            ? [UIButtonConfiguration prominentGlassButtonConfiguration]
            : [UIButtonConfiguration glassButtonConfiguration];
    } else {
        config = prominent
            ? [UIButtonConfiguration filledButtonConfiguration]
            : [UIButtonConfiguration grayButtonConfiguration];
    }
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.imagePlacement = NSDirectionalRectEdgeLeading;
    config.imagePadding = 6;
    config.contentInsets = NSDirectionalEdgeInsetsMake(8, 14, 8, 14);
    config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
        NSMutableDictionary *out = [attrs mutableCopy];
        out[NSFontAttributeName] = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        return out;
    };
    return config;
}

+ (instancetype)buttonWithTitle:(NSString *)title systemImage:(NSString *)systemImageName prominent:(BOOL)prominent {
    IMGlassButton *button = [IMGlassButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [self baseConfigurationProminent:prominent];
    config.title = title;
    if (systemImageName.length > 0) {
        config.image = IMSymbol(systemImageName, 14, UIImageSymbolWeightSemibold);
    }
    button.configuration = config;
    button.tintColor = IMTheme.shared.accentColor;
    return button;
}

+ (instancetype)iconButtonWithSystemImage:(NSString *)systemImageName diameter:(CGFloat)diameter {
    IMGlassButton *button = [IMGlassButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = nil;
    if (@available(iOS 26.0, *)) {
        config = [UIButtonConfiguration glassButtonConfiguration];
    } else {
        config = [UIButtonConfiguration grayButtonConfiguration];
    }
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.image = IMSymbol(systemImageName, 15, UIImageSymbolWeightSemibold);
    config.contentInsets = NSDirectionalEdgeInsetsMake(0, 0, 0, 0);
    button.configuration = config;
    button.tintColor = IMTheme.shared.labelPrimary;
    [button.widthAnchor constraintEqualToConstant:diameter].active = YES;
    [button.heightAnchor constraintEqualToConstant:diameter].active = YES;
    return button;
}

- (void)applyProminentStyle {
    UIButtonConfiguration *config = [IMGlassButton baseConfigurationProminent:YES];
    config.title = self.configuration.title;
    config.image = self.configuration.image;
    self.configuration = config;
    self.tintColor = IMTheme.shared.accentColor;
}

- (void)setButtonTitle:(NSString *)title systemImage:(NSString *)systemImageName {
    UIButtonConfiguration *config = [self.configuration copy];
    config.title = title;
    config.image = systemImageName.length > 0 ? IMSymbol(systemImageName, 14, UIImageSymbolWeightSemibold) : nil;
    self.configuration = config;
}

@end

#pragma mark - IMGlassBar

@interface IMGlassBar ()
@property (nonatomic, strong) UIStackView *stackView;
@end

@implementation IMGlassBar

- (instancetype)initWithStyle:(IMGlassStyle)style {
    self = [super initWithStyle:style];
    if (self) {
        _contentInsets = UIEdgeInsetsMake(8, 10, 8, 10);
        _stackView = [[UIStackView alloc] init];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView.axis = UILayoutConstraintAxisHorizontal;
        _stackView.alignment = UIStackViewAlignmentCenter;
        _stackView.spacing = IMTheme.shared.spacingS;
        [self.contentView addSubview:_stackView];
        [NSLayoutConstraint activateConstraints:@[
            [_stackView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:_contentInsets.top],
            [_stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:_contentInsets.left],
            [_stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-_contentInsets.right],
            [_stackView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-_contentInsets.bottom],
        ]];
        self.cornerRadius = IMTheme.shared.radiusPill;
        self.showsStroke = YES;
    }
    return self;
}

- (void)setContentInsets:(UIEdgeInsets)contentInsets {
    _contentInsets = contentInsets;
    for (NSLayoutConstraint *c in self.contentView.constraints) {
        if (c.firstItem == self.stackView || c.secondItem == self.stackView) c.constant = 0; // resolved below
    }
    // 重新按新内边距布局（简单可靠：整体重建约束）。
    [self.contentView removeConstraints:self.contentView.constraints];
    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:contentInsets.top],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:contentInsets.left],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-contentInsets.right],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-contentInsets.bottom],
    ]];
}

@end
