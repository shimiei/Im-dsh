//
//  IMSessionListCells.m
//  IMDSH — 会话列表行 / 「显示更多」行
//

#import "IMSessionListCells.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"

#pragma mark - 卡片形状

/// 按行位置设置卡片圆角与分隔线：同组多行拼成一张连续卡片。
static void IMApplyCardPosition(UIView *cardView, IMSessionListCellPosition position) {
    CGFloat radius = IMTheme.shared.radiusMedium;
    cardView.layer.cornerCurve = kCACornerCurveContinuous;
    cardView.layer.cornerRadius = radius;
    switch (position) {
        case IMSessionListCellPositionSingle:
            cardView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner
                                         | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            break;
        case IMSessionListCellPositionTop:
            cardView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
            break;
        case IMSessionListCellPositionBottom:
            cardView.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            break;
        case IMSessionListCellPositionMiddle:
            cardView.layer.cornerRadius = 0;
            cardView.layer.maskedCorners = 0;
            break;
    }
}

/// 中间和首行要画一条内缩分隔线（末行下面是卡片边缘，不画）。
static BOOL IMShouldShowSeparator(IMSessionListCellPosition position) {
    return position == IMSessionListCellPositionTop || position == IMSessionListCellPositionMiddle;
}

#pragma mark - 会话行

@interface IMSessionListRowCell ()

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *accentBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *runningDot;
@property (nonatomic, strong) UILabel *runningLabel;
@property (nonatomic, strong) UIStackView *runningStack;
@property (nonatomic, strong) UIStackView *titleRow;
@property (nonatomic, strong) UIView *separator;
@property (nonatomic, assign) BOOL currentSession;

@end

@implementation IMSessionListRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        IMTheme *theme = IMTheme.shared;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] init];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = theme.backgroundLayer1;
        _cardView.clipsToBounds = YES;
        [self.contentView addSubview:_cardView];

        // 当前会话（iPad 双列）左侧的强调条。
        _accentBar = [[UIView alloc] init];
        _accentBar.translatesAutoresizingMaskIntoConstraints = NO;
        _accentBar.backgroundColor = theme.accentColor;
        _accentBar.layer.cornerRadius = 1.5;
        _accentBar.hidden = YES;
        [_cardView addSubview:_accentBar];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [IMTheme fontHeadline];
        _titleLabel.textColor = theme.labelPrimary;
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        _runningDot = [[UIView alloc] init];
        _runningDot.translatesAutoresizingMaskIntoConstraints = NO;
        _runningDot.backgroundColor = theme.accentColor;
        _runningDot.layer.cornerRadius = 3.5;
        _runningDot.hidden = YES;

        _runningLabel = [[UILabel alloc] init];
        _runningLabel.font = [IMTheme fontCaption];
        _runningLabel.textColor = theme.accentColor;
        _runningLabel.text = @"运行中";
        _runningLabel.numberOfLines = 1;
        _runningLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _runningLabel.hidden = YES;
        [_runningLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_runningLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _runningStack = [[UIStackView alloc] initWithArrangedSubviews:@[_runningDot, _runningLabel]];
        _runningStack.translatesAutoresizingMaskIntoConstraints = NO;
        _runningStack.axis = UILayoutConstraintAxisHorizontal;
        _runningStack.alignment = UIStackViewAlignmentCenter;
        _runningStack.spacing = 4;

        _titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _runningStack]];
        _titleRow.translatesAutoresizingMaskIntoConstraints = NO;
        _titleRow.axis = UILayoutConstraintAxisHorizontal;
        _titleRow.alignment = UIStackViewAlignmentCenter;
        _titleRow.spacing = 8;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [IMTheme fontFootnote];
        _subtitleLabel.textColor = theme.labelTertiary;
        _subtitleLabel.numberOfLines = 1;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _separator = [[UIView alloc] init];
        _separator.translatesAutoresizingMaskIntoConstraints = NO;
        _separator.backgroundColor = theme.separatorColor;
        _separator.hidden = YES;

        [_cardView addSubview:_titleRow];
        [_cardView addSubview:_subtitleLabel];
        [_cardView addSubview:_separator];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:theme.spacingM],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-theme.spacingM],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [_accentBar.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor],
            [_accentBar.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:9],
            [_accentBar.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-9],
            [_accentBar.widthAnchor constraintEqualToConstant:3],

            [_titleRow.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:10],
            [_titleRow.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:theme.spacingL],
            [_titleRow.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-theme.spacingL],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleRow.bottomAnchor constant:3],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleRow.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_cardView.trailingAnchor constant:-theme.spacingL],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-10],

            [_runningDot.widthAnchor constraintEqualToConstant:7],
            [_runningDot.heightAnchor constraintEqualToConstant:7],

            [_separator.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:theme.spacingL],
            [_separator.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor],
            [_separator.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor],
            [_separator.heightAnchor constraintEqualToConstant:theme.hairline],
        ]];
    }
    return self;
}

- (void)configureWithRow:(IMSessionRow *)row
                position:(IMSessionListCellPosition)position
               isCurrent:(BOOL)isCurrent {
    self.titleLabel.text = [row displayTitle];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (row.updatedAt > 0) {
        [parts addObject:IMRelativeTimeString([NSDate dateWithTimeIntervalSince1970:row.updatedAt])];
    }
    if (row.tokenCount > 0) {
        [parts addObject:[NSString stringWithFormat:@"%@ tokens", IMTokenCountString(row.tokenCount)]];
    }
    if (row.isSubagent) [parts addObject:@"子会话"];
    self.subtitleLabel.text = [parts componentsJoinedByString:@" · "];

    [self updateRunningAppearance:row.running];
    [self setCurrentSession:isCurrent];
    [self applyCardPosition:position];
}

- (void)applyCardPosition:(IMSessionListCellPosition)position {
    IMApplyCardPosition(self.cardView, position);
    self.separator.hidden = !IMShouldShowSeparator(position);
}

- (void)setCurrentSession:(BOOL)isCurrent {
    _currentSession = isCurrent;
    [self applyCardAppearance];
}

- (void)applyCardAppearance {
    IMTheme *theme = IMTheme.shared;
    BOOL active = self.currentSession || self.isHighlighted || self.isSelected;
    self.cardView.backgroundColor = active ? theme.backgroundLayer2 : theme.backgroundLayer1;
    self.accentBar.hidden = !self.currentSession;
}

- (void)updateRunningAppearance:(BOOL)running {
    self.runningStack.hidden = !running;
    self.runningDot.hidden = !running;
    self.runningLabel.hidden = !running;

    CALayer *dotLayer = self.runningDot.layer;
    if (!running) {
        [dotLayer removeAnimationForKey:@"imdsh.breath"];
        return;
    }
    if ([dotLayer animationForKey:@"imdsh.breath"] != nil) return;

    // 呼吸点：透明度 1 ↔ 0.3 往返，视觉上「还在跑」。
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = @(1.0);
    animation.toValue = @(0.3);
    animation.duration = 1.1;
    animation.autoreverses = YES;
    animation.repeatCount = HUGE_VALF;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [dotLayer addAnimation:animation forKey:@"imdsh.breath"];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [self applyCardAppearance];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    [self applyCardAppearance];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.runningDot.layer removeAnimationForKey:@"imdsh.breath"];
    self.runningStack.hidden = YES;
    self.runningDot.hidden = YES;
    self.runningLabel.hidden = YES;
    self.accentBar.hidden = YES;
    self.currentSession = NO;
    self.cardView.backgroundColor = IMTheme.shared.backgroundLayer1;
}

@end

#pragma mark - 显示更多

@interface IMSessionListShowMoreCell ()

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIView *separator;

@end

@implementation IMSessionListShowMoreCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        IMTheme *theme = IMTheme.shared;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[UIView alloc] init];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = theme.backgroundLayer1;
        _cardView.clipsToBounds = YES;
        [self.contentView addSubview:_cardView];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeCenter;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [IMTheme fontFootnote];
        _titleLabel.textColor = theme.accentColor;
        _titleLabel.numberOfLines = 1;
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _stack = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _titleLabel]];
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        _stack.axis = UILayoutConstraintAxisHorizontal;
        _stack.alignment = UIStackViewAlignmentCenter;
        _stack.spacing = 5;

        _separator = [[UIView alloc] init];
        _separator.translatesAutoresizingMaskIntoConstraints = NO;
        _separator.backgroundColor = theme.separatorColor;
        _separator.hidden = YES;

        [_cardView addSubview:_stack];
        [_cardView addSubview:_separator];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:theme.spacingM],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-theme.spacingM],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [_stack.centerXAnchor constraintEqualToAnchor:_cardView.centerXAnchor],
            [_stack.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:11],
            [_stack.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-11],
            [_stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_cardView.leadingAnchor constant:theme.spacingM],
            [_stack.trailingAnchor constraintLessThanOrEqualToAnchor:_cardView.trailingAnchor constant:-theme.spacingM],

            [_separator.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:theme.spacingL],
            [_separator.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor],
            [_separator.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor],
            [_separator.heightAnchor constraintEqualToConstant:theme.hairline],
        ]];
    }
    return self;
}

- (void)configureWithHiddenCount:(NSInteger)hiddenCount position:(IMSessionListCellPosition)position {
    IMTheme *theme = IMTheme.shared;
    BOOL showsMore = hiddenCount > 0;
    if (showsMore) {
        self.titleLabel.text = [NSString stringWithFormat:@"显示更多（还有 %ld 条）", (long)hiddenCount];
        self.titleLabel.textColor = theme.accentColor;
        self.iconView.image = IMSymbol(@"chevron.down", 10, UIImageSymbolWeightSemibold);
        self.iconView.tintColor = theme.accentColor;
    } else {
        self.titleLabel.text = @"收起";
        self.titleLabel.textColor = theme.labelSecondary;
        self.iconView.image = IMSymbol(@"chevron.up", 10, UIImageSymbolWeightSemibold);
        self.iconView.tintColor = theme.labelTertiary;
    }
    self.accessibilityLabel = self.titleLabel.text;
    [self applyCardPosition:position];
}

- (void)applyCardPosition:(IMSessionListCellPosition)position {
    IMApplyCardPosition(self.cardView, position);
    self.separator.hidden = !IMShouldShowSeparator(position);
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.cardView.backgroundColor = (highlighted || self.isSelected)
        ? IMTheme.shared.backgroundLayer2
        : IMTheme.shared.backgroundLayer1;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    self.cardView.backgroundColor = (selected || self.isHighlighted)
        ? IMTheme.shared.backgroundLayer2
        : IMTheme.shared.backgroundLayer1;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.cardView.backgroundColor = IMTheme.shared.backgroundLayer1;
}

@end
