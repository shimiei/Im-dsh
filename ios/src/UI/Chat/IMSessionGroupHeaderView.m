//
//  IMSessionGroupHeaderView.m
//  IMDSH — 会话列表的项目分组表头
//
//  结构：一块液态玻璃底（IMGlassView，iOS 26 以下自带模糊兜底）+
//        箭头 / 项目名 / 会话条数 / 运行中提示。
//  交互：整块挂 UITapGestureRecognizer，点击回调 onToggle；箭头用 transform 旋转，
//        旋转与行删除/插入同时进行，视觉上是一次「展开/收起」。
//

#import "IMSessionGroupHeaderView.h"
#import "IMTheme.h"
#import "IMGlass.h"

/// 表头内容的左右内边距：左侧与卡片内文字对齐（卡片内缩 12 + 文字缩进 16 = 28）。
static const CGFloat IMSessionGroupHeaderLeadingInset = 12;
static const CGFloat IMSessionGroupHeaderTrailingInset = 16;
static const CGFloat IMSessionGroupHeaderChevronBox = 14;

@interface IMSessionGroupHeaderView ()

@property (nonatomic, strong) IMGlassView *glassView;
@property (nonatomic, strong) UIView *chevronBox;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIView *runningDot;
@property (nonatomic, strong) UILabel *runningLabel;
@property (nonatomic, strong) UIView *hairline;
/// 真实折叠状态（公开属性 collapsed 是只读的，getter 手动实现）。
@property (nonatomic, assign) BOOL collapsedState;

@end

@implementation IMSessionGroupHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self buildSubviews];
    }
    return self;
}

- (BOOL)isCollapsed {
    return self.collapsedState;
}

#pragma mark - 视图

- (void)buildSubviews {
    IMTheme *theme = IMTheme.shared;
    self.backgroundColor = UIColor.clearColor;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;

    // 玻璃底：低于 iOS 26 时 IMGlassView 内部自动退化成 UIBlurEffect。
    _glassView = [[IMGlassView alloc] initWithStyle:IMGlassStyleRegular];
    _glassView.translatesAutoresizingMaskIntoConstraints = NO;
    _glassView.cornerRadius = 0;
    _glassView.showsStroke = NO;
    [self addSubview:_glassView];

    // 所有内容都挂在玻璃的 contentView 上（材质之上），不要直接加到 self。
    UIView *content = _glassView.contentView;

    _chevronBox = [[UIView alloc] init];
    _chevronBox.translatesAutoresizingMaskIntoConstraints = NO;

    _chevronView = [[UIImageView alloc] initWithImage:IMSymbol(@"chevron.right", 10, UIImageSymbolWeightSemibold)];
    _chevronView.tintColor = theme.labelTertiary;
    _chevronView.contentMode = UIViewContentModeCenter;
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    // 先入视图树再连约束：旋转后的图形始终落在 14x14 的盒子里，不会压到项目名。
    [_chevronBox addSubview:_chevronView];

    _nameLabel = [[UILabel alloc] init];
    _nameLabel.font = [IMTheme fontCallout];
    _nameLabel.textColor = theme.labelSecondary;
    _nameLabel.numberOfLines = 1;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    // 项目名最长（cwd 尾段可能很长），空间不够时优先让它截断。
    [_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    _countLabel = [[UILabel alloc] init];
    _countLabel.font = [IMTheme fontCaption];
    _countLabel.textColor = theme.labelTertiary;
    _countLabel.numberOfLines = 1;
    _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_countLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_countLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _runningDot = [[UIView alloc] init];
    _runningDot.translatesAutoresizingMaskIntoConstraints = NO;
    _runningDot.backgroundColor = theme.accentColor;
    _runningDot.layer.cornerRadius = 3;
    _runningDot.hidden = YES;

    _runningLabel = [[UILabel alloc] init];
    _runningLabel.font = [IMTheme fontCaption];
    _runningLabel.textColor = theme.accentColor;
    _runningLabel.numberOfLines = 1;
    _runningLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _runningLabel.hidden = YES;
    [_runningLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_runningLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *leftStack = [[UIStackView alloc] initWithArrangedSubviews:@[_chevronBox, _nameLabel]];
    leftStack.translatesAutoresizingMaskIntoConstraints = NO;
    leftStack.axis = UILayoutConstraintAxisHorizontal;
    leftStack.alignment = UIStackViewAlignmentCenter;
    leftStack.spacing = 6;

    UIStackView *rightStack = [[UIStackView alloc] initWithArrangedSubviews:@[_countLabel, _runningDot, _runningLabel]];
    rightStack.translatesAutoresizingMaskIntoConstraints = NO;
    rightStack.axis = UILayoutConstraintAxisHorizontal;
    rightStack.alignment = UIStackViewAlignmentCenter;
    rightStack.spacing = 5;

    _hairline = [[UIView alloc] init];
    _hairline.translatesAutoresizingMaskIntoConstraints = NO;
    _hairline.backgroundColor = theme.separatorColor;

    [content addSubview:leftStack];
    [content addSubview:rightStack];
    [content addSubview:_hairline];

    [NSLayoutConstraint activateConstraints:@[
        [_glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [leftStack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:IMSessionGroupHeaderLeadingInset],
        [leftStack.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [leftStack.trailingAnchor constraintLessThanOrEqualToAnchor:rightStack.leadingAnchor constant:-8],

        [rightStack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-IMSessionGroupHeaderTrailingInset],
        [rightStack.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],

        [_chevronBox.widthAnchor constraintEqualToConstant:IMSessionGroupHeaderChevronBox],
        [_chevronBox.heightAnchor constraintEqualToConstant:IMSessionGroupHeaderChevronBox],
        [_chevronView.centerXAnchor constraintEqualToAnchor:_chevronBox.centerXAnchor],
        [_chevronView.centerYAnchor constraintEqualToAnchor:_chevronBox.centerYAnchor],

        [_runningDot.widthAnchor constraintEqualToConstant:6],
        [_runningDot.heightAnchor constraintEqualToConstant:6],

        [_hairline.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:IMSessionGroupHeaderLeadingInset],
        [_hairline.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-IMSessionGroupHeaderLeadingInset],
        [_hairline.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [_hairline.heightAnchor constraintEqualToConstant:theme.hairline],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self addGestureRecognizer:tap];
}

#pragma mark - 内容

- (void)updateWithProjectName:(NSString *)projectName
                 sessionCount:(NSInteger)sessionCount
                 runningCount:(NSInteger)runningCount
                    collapsed:(BOOL)collapsed
                     animated:(BOOL)animated {
    NSString *name = [projectName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.nameLabel.text = name.length > 0 ? name : @"未指定项目";
    self.countLabel.text = [NSString stringWithFormat:@"%ld 个会话", (long)sessionCount];

    BOOL showsRunning = runningCount > 0;
    self.runningDot.hidden = !showsRunning;
    self.runningLabel.hidden = !showsRunning;
    self.runningLabel.text = showsRunning ? [NSString stringWithFormat:@"%ld 运行中", (long)runningCount] : nil;

    [self setCollapsed:collapsed animated:animated];

    // VoiceOver：整块作为一个按钮朗读，不逐个念子视图。
    NSMutableArray<NSString *> *spoken = [NSMutableArray array];
    [spoken addObject:self.nameLabel.text ?: @""];
    [spoken addObject:[NSString stringWithFormat:@"%ld 个会话", (long)sessionCount]];
    if (showsRunning) [spoken addObject:[NSString stringWithFormat:@"%ld 个运行中", (long)runningCount]];
    [spoken addObject:collapsed ? @"已收起" : @"已展开"];
    self.accessibilityLabel = [spoken componentsJoinedByString:@"，"];
    self.accessibilityHint = collapsed ? @"轻点展开该项目的会话" : @"轻点收起该项目的会话";
}

- (void)setCollapsed:(BOOL)collapsed animated:(BOOL)animated {
    self.collapsedState = collapsed;
    // 收起 = 箭头朝右（identity），展开 = 旋转 90° 朝下。
    CGAffineTransform target = collapsed ? CGAffineTransformIdentity : CGAffineTransformMakeRotation((CGFloat)M_PI_2);
    if (!animated) {
        self.chevronView.transform = target;
        return;
    }
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.22
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.chevronView.transform = target;
    } completion:nil];
}

#pragma mark - 交互

- (void)handleTap:(UITapGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state != UIGestureRecognizerStateEnded) return;
    if (self.onToggle) self.onToggle();
}

- (BOOL)accessibilityActivate {
    if (self.onToggle) self.onToggle();
    return YES;
}

/// 点击反馈：玻璃表面轻微压暗，松手恢复。
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    self.alpha = 0.62;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    self.alpha = 1.0;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.alpha = 1.0;
}

@end
