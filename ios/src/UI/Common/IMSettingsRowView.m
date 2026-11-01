//
//  IMSettingsRowView.m
//  IMDSH — 设置页的通用信息行
//

#import "IMSettingsRowView.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"

@interface IMSettingsRowView ()
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIStackView *textStack;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIView *spacer;
@property (nonatomic, strong) UIImageView *accessoryImageView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSLayoutConstraint *topConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bottomConstraint;
@property (nonatomic, assign) BOOL longPressInstalled;
@end

@implementation IMSettingsRowView

#pragma mark - 构造

+ (instancetype)rowWithTitle:(NSString *)title systemImage:(NSString *)systemImageName {
    IMSettingsRowView *row = [[IMSettingsRowView alloc] initWithFrame:CGRectZero];
    row.title = title;
    if (systemImageName.length > 0) {
        row.iconView.image = IMSymbol(systemImageName, 16, UIImageSymbolWeightMedium);
        row.iconView.hidden = NO;
    }
    return row;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _verticalPadding = IMTheme.shared.spacingM;
        _subtitleLineLimit = 2;
        [self buildHierarchy];
        [self addTarget:self action:@selector(handleTouchUpInside) forControlEvents:UIControlEventTouchUpInside];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitStaticText;
    }
    return self;
}

- (void)buildHierarchy {
    IMTheme *theme = IMTheme.shared;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisHorizontal;
    self.contentStack.alignment = UIStackViewAlignmentCenter;
    self.contentStack.spacing = theme.spacingM;
    [self addSubview:self.contentStack];

    self.topConstraint = [self.contentStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:self.verticalPadding];
    self.bottomConstraint = [self.contentStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-self.verticalPadding];
    [NSLayoutConstraint activateConstraints:@[
        self.topConstraint,
        self.bottomConstraint,
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:theme.spacingL],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-theme.spacingL],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];

    // 图标（默认隐藏，传了 systemImage 才出现）
    self.iconView = [[UIImageView alloc] init];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeCenter;
    self.iconView.tintColor = theme.labelSecondary;
    self.iconView.hidden = YES;
    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.widthAnchor constraintEqualToConstant:22],
        [self.iconView.heightAnchor constraintEqualToConstant:22],
    ]];
    [self.contentStack addArrangedSubview:self.iconView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [IMTheme fontBody];
    self.titleLabel.textColor = theme.labelPrimary;
    self.titleLabel.numberOfLines = 1;
    [self.titleLabel setContentCompressionResistancePriority:(UILayoutPriority)749 forAxis:UILayoutConstraintAxisHorizontal];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.font = [IMTheme fontFootnote];
    self.subtitleLabel.textColor = theme.labelSecondary;
    self.subtitleLabel.numberOfLines = self.subtitleLineLimit;
    self.subtitleLabel.hidden = YES;

    self.textStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subtitleLabel]];
    self.textStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.textStack.axis = UILayoutConstraintAxisVertical;
    self.textStack.spacing = 3;
    self.textStack.alignment = UIStackViewAlignmentFill;
    [self.contentStack addArrangedSubview:self.textStack];

    // 弹性占位：把值/附件推到右侧
    self.spacer = [[UIView alloc] init];
    self.spacer.translatesAutoresizingMaskIntoConstraints = NO;
    // 纯占位、铺在行中央：一旦它成为命中目标就会抢走整行的点击。
    self.spacer.userInteractionEnabled = NO;
    [self.spacer setContentHuggingPriority:(UILayoutPriority)1 forAxis:UILayoutConstraintAxisHorizontal];
    [self.spacer setContentCompressionResistancePriority:(UILayoutPriority)1 forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentStack addArrangedSubview:self.spacer];

    self.valueLabel = [[UILabel alloc] init];
    self.valueLabel.font = [IMTheme fontCallout];
    self.valueLabel.textColor = theme.labelSecondary;
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.numberOfLines = 1;
    self.valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.valueLabel setContentCompressionResistancePriority:(UILayoutPriority)752 forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentStack addArrangedSubview:self.valueLabel];

    self.accessoryImageView = [[UIImageView alloc] init];
    self.accessoryImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.accessoryImageView.contentMode = UIViewContentModeCenter;
    self.accessoryImageView.image = IMSymbol(@"chevron.right", 12, UIImageSymbolWeightSemibold);
    self.accessoryImageView.tintColor = theme.labelTertiary;
    self.accessoryImageView.hidden = YES;
    [self.contentStack addArrangedSubview:self.accessoryImageView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.hidden = YES;
    [self.contentStack addArrangedSubview:self.spinner];
}

#pragma mark - 内容

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    self.titleLabel.text = title;
    [self updateAccessibilityLabel];
}

- (void)setSubtitle:(NSString *)subtitle {
    _subtitle = [subtitle copy];
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = subtitle.length == 0;
    [self updateAccessibilityLabel];
}

- (void)setValueText:(NSString *)valueText {
    _valueText = [valueText copy];
    self.valueLabel.text = valueText;
    [self updateAccessibilityLabel];
}

- (void)setAccessory:(IMSettingsRowAccessory)accessory {
    _accessory = accessory;
    BOOL chevron = accessory == IMSettingsRowAccessoryChevron;
    BOOL checkmark = accessory == IMSettingsRowAccessoryCheckmark;
    BOOL spinner = accessory == IMSettingsRowAccessorySpinner;

    self.accessoryImageView.hidden = !(chevron || checkmark);
    if (checkmark) {
        self.accessoryImageView.image = IMSymbol(@"checkmark", 13, UIImageSymbolWeightSemibold);
        self.accessoryImageView.tintColor = IMTheme.shared.accentColor;
    } else {
        self.accessoryImageView.image = IMSymbol(@"chevron.right", 12, UIImageSymbolWeightSemibold);
        self.accessoryImageView.tintColor = IMTheme.shared.labelTertiary;
    }
    self.spinner.hidden = !spinner;
    if (!spinner) [self.spinner stopAnimating];
}

- (void)setAccessorySpinning:(BOOL)spinning {
    if (spinning) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
}

- (void)setMonospacedValue:(BOOL)monospacedValue {
    _monospacedValue = monospacedValue;
    self.valueLabel.font = monospacedValue ? [IMTheme fontMonoBody] : [IMTheme fontCallout];
    // 地址/ID 从中间截断更好认：保留头尾，去掉中段。
    self.valueLabel.lineBreakMode = monospacedValue ? NSLineBreakByTruncatingMiddle : NSLineBreakByTruncatingTail;
}

- (void)setValueColor:(UIColor *)valueColor {
    _valueColor = valueColor;
    self.valueLabel.textColor = valueColor ?: IMTheme.shared.labelSecondary;
}

- (void)setDestructive:(BOOL)destructive {
    _destructive = destructive;
    self.titleLabel.textColor = destructive ? IMTheme.shared.dangerColor : IMTheme.shared.labelPrimary;
}

- (void)setMonospacedTitle:(BOOL)monospacedTitle {
    _monospacedTitle = monospacedTitle;
    self.titleLabel.font = monospacedTitle ? [IMTheme fontMonoBody] : [IMTheme fontBody];
}

- (void)setIconTintColor:(UIColor *)iconTintColor {
    _iconTintColor = iconTintColor;
    self.iconView.tintColor = iconTintColor ?: IMTheme.shared.labelSecondary;
}

- (void)setTrailingAccessoryView:(UIView *)trailingAccessoryView {
    if (_trailingAccessoryView == trailingAccessoryView) return;
    [_trailingAccessoryView removeFromSuperview];   // 移出 superview 会自动退出 stack
    _trailingAccessoryView = trailingAccessoryView;
    if (trailingAccessoryView == nil) return;

    trailingAccessoryView.translatesAutoresizingMaskIntoConstraints = NO;
    NSUInteger index = [self.contentStack.arrangedSubviews indexOfObject:self.accessoryImageView];
    if (index == NSNotFound) index = self.contentStack.arrangedSubviews.count;
    [self.contentStack insertArrangedSubview:trailingAccessoryView atIndex:index];
}

- (void)setSubtitleLineLimit:(NSInteger)subtitleLineLimit {
    _subtitleLineLimit = subtitleLineLimit;
    self.subtitleLabel.numberOfLines = subtitleLineLimit;
}

- (void)setVerticalPadding:(CGFloat)verticalPadding {
    _verticalPadding = verticalPadding;
    self.topConstraint.constant = verticalPadding;
    self.bottomConstraint.constant = -verticalPadding;
}

- (void)setOnTap:(void (^)(void))onTap {
    _onTap = [onTap copy];
    // 可点的行必须开着交互；装饰性子视图统一由 hitTest: 让位给行本身。
    self.userInteractionEnabled = YES;
    self.accessibilityTraits = onTap ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
}

- (void)setCopyableText:(NSString *)copyableText {
    _copyableText = [copyableText copy];
    if (copyableText.length > 0 && !self.longPressInstalled) {
        self.longPressInstalled = YES;
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                            action:@selector(handleLongPress:)];
        press.minimumPressDuration = 0.4;
        [self addGestureRecognizer:press];
    }
    if (copyableText.length > 0) {
        // 长按可复制时给出提示，否则用户永远猜不到有这功能。
        self.accessibilityHint = @"长按复制";
    }
}

#pragma mark - 交互

/// 整行都是可点区域：装饰性子视图（内容栈、图标、标题/值文字、spacer、accessory）都不该成为命中目标。
/// 之前依赖「触摸沿响应者链回溯到 UIControl」这条隐式路径，任何一层容器（玻璃 effectView 的
/// contentView、UIStackView、占位 UIView）先把触摸接走，整屏的行就会表现为「看得见、点不动」。
/// 这里只把真正的交互控件（trailingAccessoryView 里的吊销/复制按钮）让出去，其余一律交给行本身。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == nil || hit == self) return hit;
    for (UIView *node = hit; node != nil && node != self; node = node.superview) {
        if ([node isKindOfClass:UIControl.class]) return hit;
    }
    return self;
}

- (void)handleTouchUpInside {
    if (!self.enabled) return;
    if (self.onTap) self.onTap();
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    if (self.copyableText.length == 0) return;
    IMCopyText(self.copyableText, self, nil);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    // 纯展示行（不可点、不可复制）不该有按压反馈，否则会暗示一个不存在的操作。
    BOOL interactive = self.enabled && (self.onTap != nil || self.copyableText.length > 0);
    if (highlighted && interactive) {
        self.alpha = 0.5;
    } else {
        self.alpha = self.enabled ? 1.0 : 0.45;
    }
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0 : 0.45;
    self.userInteractionEnabled = YES;   // 禁用态仍要能长按复制 ID 之类的文本
}

- (void)updateAccessibilityLabel {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (self.title.length > 0) [parts addObject:self.title];
    if (self.subtitle.length > 0) [parts addObject:self.subtitle];
    if (self.valueText.length > 0) [parts addObject:self.valueText];
    self.accessibilityLabel = [parts componentsJoinedByString:@"，"];
}

@end
