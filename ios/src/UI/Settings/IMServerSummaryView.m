//
//  IMServerSummaryView.m
//  IMDSH — 当前主机摘要卡
//

#import "IMServerSummaryView.h"
#import "IMServerStore.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"

#pragma mark - 状态徽标

/// 极小的胶囊徽标（已配对 / 令牌缺失 / 不可用）。单独实现是为了复用在其它卡片上。
@interface IMBadgeView : UIView
@property (nonatomic, strong) UILabel *label;
/// 语义色（success/warning/...），保留下来以便跟随深浅色重刷描边。
@property (nonatomic, strong, nullable) UIColor *semanticColor;
+ (instancetype)badgeWithText:(NSString *)text color:(UIColor *)color;
- (void)updateWithText:(nullable NSString *)text color:(nullable UIColor *)color;
@end

@implementation IMBadgeView

+ (instancetype)badgeWithText:(NSString *)text color:(UIColor *)color {
    IMBadgeView *badge = [[IMBadgeView alloc] initWithFrame:CGRectZero];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    badge.layer.cornerRadius = 7;
    badge.layer.masksToBounds = YES;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [IMTheme fontCaption];
    label.textAlignment = NSTextAlignmentCenter;
    badge.label = label;
    [badge addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:badge.topAnchor constant:2],
        [label.bottomAnchor constraintEqualToAnchor:badge.bottomAnchor constant:-2],
        [label.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:7],
        [label.trailingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:-7],
        [badge.heightAnchor constraintGreaterThanOrEqualToConstant:18],
    ]];

    __weak typeof(badge) weakBadge = badge;
    [badge registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
                       withHandler:^(id<UITraitEnvironment> traitEnvironment, UITraitCollection *previous) {
        IMBadgeView *strongBadge = weakBadge;
        [strongBadge refreshBorderColor];
    }];

    [badge updateWithText:text color:color];
    return badge;
}

- (void)updateWithText:(NSString *)text color:(UIColor *)color {
    self.label.text = text;
    self.label.textColor = color;
    self.semanticColor = color;
    self.hidden = text.length == 0;

    if (text.length == 0 || color == nil) {
        self.backgroundColor = UIColor.clearColor;
        self.layer.borderWidth = 0;
        return;
    }
    // 底色是同一语义色的一层薄雾：手动按 trait 解析，保证深色/浅色都对。
    self.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return [[color resolvedColorWithTraitCollection:traits] colorWithAlphaComponent:0.16];
    }];
    self.layer.borderWidth = IMTheme.shared.hairline;
    [self refreshBorderColor];
}

- (void)refreshBorderColor {
    UIColor *color = self.semanticColor;
    if (color == nil) return;
    self.layer.borderColor = [[color resolvedColorWithTraitCollection:self.traitCollection] colorWithAlphaComponent:0.28].CGColor;
}

@end

#pragma mark - 主机摘要

@interface IMServerSummaryView ()
@property (nonatomic, strong) IMGlassView *glassView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) IMBadgeView *badgeView;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@end

@implementation IMServerSummaryView

+ (instancetype)viewWithServer:(IMServer *)server {
    IMServerSummaryView *view = [[IMServerSummaryView alloc] initWithFrame:CGRectZero];
    [view updateWithServer:server];
    return view;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self buildHierarchy];
        [self addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)buildHierarchy {
    IMTheme *theme = IMTheme.shared;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    self.glassView = [[IMGlassView alloc] initWithStyle:IMGlassStyleRegular];
    self.glassView.translatesAutoresizingMaskIntoConstraints = NO;
    self.glassView.cornerRadius = theme.radiusCard;
    self.glassView.showsStroke = YES;
    // 玻璃只是这张卡的视觉层，卡内没有任何可交互子视图：整片命中交给 UIControl 自己，
    // 免得 effectView / contentView 在命中测试里先把点击接走（那会变成「看得见、点不动」）。
    self.glassView.userInteractionEnabled = NO;
    [self addSubview:self.glassView];
    [NSLayoutConstraint activateConstraints:@[
        [self.glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [IMTheme fontTitle];
    self.nameLabel.textColor = theme.labelPrimary;
    self.nameLabel.numberOfLines = 1;
    [self.nameLabel setContentCompressionResistancePriority:(UILayoutPriority)751 forAxis:UILayoutConstraintAxisHorizontal];

    self.badgeView = [IMBadgeView badgeWithText:nil color:nil];

    UIView *spacer = [[UIView alloc] init];
    [spacer setContentHuggingPriority:(UILayoutPriority)1 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:(UILayoutPriority)1 forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, spacer, self.badgeView]];
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    titleRow.axis = UILayoutConstraintAxisHorizontal;
    titleRow.spacing = theme.spacingS;
    titleRow.alignment = UIStackViewAlignmentCenter;

    self.addressLabel = [[UILabel alloc] init];
    self.addressLabel.font = [IMTheme fontMonoBody];
    self.addressLabel.textColor = theme.labelSecondary;
    self.addressLabel.numberOfLines = 1;
    self.addressLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    self.metaLabel = [[UILabel alloc] init];
    self.metaLabel.font = [IMTheme fontCaption];
    self.metaLabel.textColor = theme.labelTertiary;
    self.metaLabel.numberOfLines = 0;

    self.chevronView = [[UIImageView alloc] init];
    self.chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronView.image = IMSymbol(@"chevron.right", 13, UIImageSymbolWeightSemibold);
    self.chevronView.tintColor = theme.labelTertiary;
    self.chevronView.contentMode = UIViewContentModeCenter;
    self.chevronView.hidden = YES;

    UIView *metaSpacer = [[UIView alloc] init];
    [metaSpacer setContentHuggingPriority:(UILayoutPriority)1 forAxis:UILayoutConstraintAxisHorizontal];
    [metaSpacer setContentCompressionResistancePriority:(UILayoutPriority)1 forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *metaRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.metaLabel, metaSpacer, self.chevronView]];
    metaRow.translatesAutoresizingMaskIntoConstraints = NO;
    metaRow.axis = UILayoutConstraintAxisHorizontal;
    metaRow.spacing = theme.spacingS;
    metaRow.alignment = UIStackViewAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, self.addressLabel, metaRow]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 5;
    stack.alignment = UIStackViewAlignmentFill;
    [stack setCustomSpacing:theme.spacingS afterView:self.addressLabel];
    [self.glassView.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.glassView.contentView.topAnchor constant:theme.spacingL],
        [stack.bottomAnchor constraintEqualToAnchor:self.glassView.contentView.bottomAnchor constant:-theme.spacingL],
        [stack.leadingAnchor constraintEqualToAnchor:self.glassView.contentView.leadingAnchor constant:theme.spacingL],
        [stack.trailingAnchor constraintEqualToAnchor:self.glassView.contentView.trailingAnchor constant:-theme.spacingL],
    ]];
}

- (void)updateWithServer:(IMServer *)server {
    if (server == nil) {
        self.nameLabel.text = @"尚未添加主机";
        [self.badgeView updateWithText:@"未配对" color:IMTheme.shared.warningColor];
        self.addressLabel.text = @"配对一台 DSH 主机后即可开始";
        self.addressLabel.textColor = IMTheme.shared.labelTertiary;
        self.metaLabel.text = @"点击填写服务器地址与配对码";
        return;
    }

    self.nameLabel.text = server.displayName.length > 0 ? server.displayName : server.baseURLString;
    self.addressLabel.text = server.baseURLString;
    self.addressLabel.textColor = IMTheme.shared.labelSecondary;

    if (server.hasToken) {
        [self.badgeView updateWithText:@"已配对" color:IMTheme.shared.successColor];
    } else {
        [self.badgeView updateWithText:@"令牌缺失" color:IMTheme.shared.warningColor];
    }

    NSMutableArray<NSString *> *meta = [NSMutableArray array];
    if (server.hasToken) {
        if (server.lastConnectedAt != nil) {
            [meta addObject:[NSString stringWithFormat:@"最近连接 %@", IMRelativeTimeString(server.lastConnectedAt)]];
        } else {
            [meta addObject:@"本次会话尚未连接"];
        }
        if (server.pairingLabel.length > 0) {
            [meta addObject:[NSString stringWithFormat:@"配对码尾号 %@", server.pairingLabel]];
        }
    } else {
        // 令牌缺失时「最近连接」是过期信息，用户真正要知道的是下一步要做什么。
        [meta addObject:@"需要重新配对才能连接"];
    }
    self.metaLabel.text = [meta componentsJoinedByString:@" · "];
}

#pragma mark - 交互

/// 整张卡就是按钮：玻璃与其中的文字标签都不该成为命中目标，
/// 否则点按要靠响应者链回溯才到得了 UIControl，任何一层容器截住就整卡失效。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == nil || hit == self) return hit;
    if ([hit isKindOfClass:UIControl.class]) return hit;
    return self;
}

- (void)setOnTap:(void (^)(void))onTap {
    _onTap = [onTap copy];
    // 可点的卡必须开着交互。
    self.userInteractionEnabled = YES;
    self.chevronView.hidden = onTap == nil;
    self.glassView.interactive = onTap != nil;
    self.isAccessibilityElement = onTap != nil;
    self.accessibilityTraits = onTap ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
}

- (void)handleTap {
    if (self.onTap) self.onTap();
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    // 玻璃本体已经给了按压回弹，这里只加极轻的透明度变化，避免双重反馈。
    self.alpha = highlighted ? 0.92 : 1.0;
}

@end
