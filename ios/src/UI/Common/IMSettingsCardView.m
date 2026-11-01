//
//  IMSettingsCardView.m
//  IMDSH — 设置页的分区卡片
//

#import "IMSettingsCardView.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"   // IMStackRemoveAllArrangedSubviews

@interface IMSettingsCardView ()
@property (nonatomic, strong) UIStackView *outerStack;
@property (nonatomic, strong) IMGlassView *glassView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong, nullable) UILabel *titleLabel;
@property (nonatomic, strong, nullable) UILabel *footerLabel;
@property (nonatomic, strong, nullable) UIView *footerContainer;
@property (nonatomic, strong) NSLayoutConstraint *contentTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentBottomConstraint;
@end

@implementation IMSettingsCardView

#pragma mark - 构造

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _contentInsets = UIEdgeInsetsZero;
        [self buildHierarchy];

        if (title.length > 0) {
            UILabel *label = [[UILabel alloc] init];
            label.text = title;
            label.font = [IMTheme fontCaption];
            label.textColor = IMTheme.shared.labelTertiary;
            label.numberOfLines = 0;
            self.titleLabel = label;
            [self.outerStack addArrangedSubview:[IMSettingsCardView paddedView:label horizontal:6]];
            [self.outerStack setCustomSpacing:7 afterView:self.outerStack.arrangedSubviews.lastObject];
        }
    }
    return self;
}

- (void)buildHierarchy {
    IMTheme *theme = IMTheme.shared;

    self.translatesAutoresizingMaskIntoConstraints = NO;

    self.outerStack = [[UIStackView alloc] init];
    self.outerStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.outerStack.axis = UILayoutConstraintAxisVertical;
    self.outerStack.spacing = 0;
    self.outerStack.alignment = UIStackViewAlignmentFill;
    [self addSubview:self.outerStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.outerStack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.outerStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.outerStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.outerStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    self.glassView = [[IMGlassView alloc] initWithStyle:IMGlassStyleRegular];
    self.glassView.cornerRadius = theme.radiusCard;
    self.glassView.showsStroke = YES;
    [self.outerStack addArrangedSubview:self.glassView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 0;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    // 卡片里的行必须能被点到：内容栈保持交互打开（行在玻璃 contentView 之上）。
    self.contentStack.userInteractionEnabled = YES;
    [self.glassView.contentView addSubview:self.contentStack];

    self.contentTopConstraint = [self.contentStack.topAnchor constraintEqualToAnchor:self.glassView.contentView.topAnchor constant:self.contentInsets.top];
    self.contentLeadingConstraint = [self.contentStack.leadingAnchor constraintEqualToAnchor:self.glassView.contentView.leadingAnchor constant:self.contentInsets.left];
    self.contentTrailingConstraint = [self.contentStack.trailingAnchor constraintEqualToAnchor:self.glassView.contentView.trailingAnchor constant:-self.contentInsets.right];
    self.contentBottomConstraint = [self.contentStack.bottomAnchor constraintEqualToAnchor:self.glassView.contentView.bottomAnchor constant:-self.contentInsets.bottom];
    [NSLayoutConstraint activateConstraints:@[
        self.contentTopConstraint, self.contentLeadingConstraint,
        self.contentTrailingConstraint, self.contentBottomConstraint,
    ]];
}

/// 把任意视图塞进一个带水平内缩的容器，让文字不贴卡片边缘。
+ (UIView *)paddedView:(UIView *)view horizontal:(CGFloat)horizontal {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    // 这个容器只承载文字（分区标题 / 脚注）：让它对触摸透明，
    // 别在卡片里当一层看不见的挡板。
    container.userInteractionEnabled = NO;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:container.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:horizontal],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-horizontal],
    ]];
    return container;
}

#pragma mark - 内容

- (void)addRow:(UIView *)row {
    [self addRow:row showsDivider:YES];
}

/// 分组场景：组标题下面是自绘分隔线，紧跟的第一行不该再要一条，否则像给标题画了下划线。
- (void)addRow:(UIView *)row showsDivider:(BOOL)showsDivider {
    if (row == nil) return;
    if (showsDivider && self.contentStack.arrangedSubviews.count > 0) {
        [self.contentStack addArrangedSubview:[self hairlineView]];
    }
    [self.contentStack addArrangedSubview:row];
}

- (void)addView:(UIView *)view {
    if (view == nil) return;
    [self.contentStack addArrangedSubview:view];
}

- (void)clearContent {
    IMStackRemoveAllArrangedSubviews(self.contentStack);
}

- (UIView *)hairlineView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.userInteractionEnabled = NO;

    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = IMTheme.shared.separatorColor;
    [container addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [line.heightAnchor constraintEqualToConstant:MAX(IMTheme.shared.hairline, 0.5)],
        [line.topAnchor constraintEqualToAnchor:container.topAnchor],
        [line.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:IMTheme.shared.spacingL],
        [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-IMTheme.shared.spacingL],
    ]];
    return container;
}

- (void)setFooterText:(NSString *)footerText {
    if (footerText.length == 0) {
        if (self.footerContainer) {
            [self.outerStack removeArrangedSubview:self.footerContainer];
            [self.footerContainer removeFromSuperview];
            self.footerContainer = nil;
            self.footerLabel = nil;
        }
        return;
    }

    if (self.footerLabel == nil) {
        UILabel *label = [[UILabel alloc] init];
        label.font = [IMTheme fontFootnote];
        label.textColor = IMTheme.shared.labelTertiary;
        label.numberOfLines = 0;
        self.footerLabel = label;

        UIView *container = [IMSettingsCardView paddedView:label horizontal:IMTheme.shared.spacingL];
        self.footerContainer = container;
        [self.outerStack addArrangedSubview:container];
        [self.outerStack setCustomSpacing:6 afterView:container];
    }
    self.footerLabel.text = footerText;
}

- (void)setContentInsets:(UIEdgeInsets)contentInsets {
    _contentInsets = contentInsets;
    self.contentTopConstraint.constant = contentInsets.top;
    self.contentLeadingConstraint.constant = contentInsets.left;
    self.contentTrailingConstraint.constant = -contentInsets.right;
    self.contentBottomConstraint.constant = -contentInsets.bottom;
}

@end
