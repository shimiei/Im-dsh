//
//  IMMessageCardViews.m
//  IMDSH — 消息内的四类卡片
//

#import "IMMessageCardViews.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"

#pragma mark - 公共小件

/// 工具名 → 图标（提前声明，配置时要用）。
static NSString *IMToolSymbolName(NSString *name);

static dispatch_queue_t IMChatWorkQueue(void) {    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("imdsh.chat.work", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static UIImageView *IMCardSymbol(NSString *name, CGFloat size, UIColor *color) {    UIImageView *view = [[UIImageView alloc] initWithImage:IMSymbol(name, size, UIImageSymbolWeightMedium)];
    view.tintColor = color;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [view setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return view;
}

static UILabel *IMCardLabel(UIFont *font, UIColor *color, NSInteger lines) {
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = lines;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

/// 状态点：运行中呼吸闪烁，结束时常亮。
static UIView *IMCardStatusDot(CGFloat diameter) {
    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.layer.cornerRadius = diameter / 2.0;
    [dot.widthAnchor constraintEqualToConstant:diameter].active = YES;
    [dot.heightAnchor constraintEqualToConstant:diameter].active = YES;
    [dot setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return dot;
}

static void IMCardSetDotBreathing(UIView *dot, BOOL breathing) {
    [dot.layer removeAnimationForKey:@"imdsh.breath"];
    if (!breathing) {
        dot.layer.opacity = 1.0;
        return;
    }
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = @(1.0);
    animation.toValue = @(0.25);
    animation.duration = 1.0;
    animation.autoreverses = YES;
    animation.repeatCount = HUGE_VALF;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [dot.layer addAnimation:animation forKey:@"imdsh.breath"];
}

#pragma mark - 折叠条（推理 + 待办共用的头部交互）

/// 展开/收起的箭头。
static UIImageView *IMCardChevron(void) {
    return IMCardSymbol(@"chevron.right", 10, IMTheme.shared.labelTertiary);
}

static void IMCardRotateChevron(UIImageView *chevron, BOOL expanded) {
    chevron.transform = expanded ? CGAffineTransformMakeRotation(M_PI_2) : CGAffineTransformIdentity;
}

#pragma mark - 等宽文本块（参数 / 结果 / 推理正文）

@interface IMMonoBlockView : UIView
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) void (^onHeightChange)(void);
- (void)configureWithText:(NSString *)text color:(UIColor *)color maxLength:(NSUInteger)maxLength;
@end

@interface IMMonoBlockView ()
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, copy, nullable) NSString *fullText;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) NSUInteger maxLength;
@property (nonatomic, strong) NSLayoutConstraint *moreHeightConstraint;
@end

@implementation IMMonoBlockView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = IMTheme.shared.codeBackgroundColor;
        self.layer.cornerRadius = IMTheme.shared.radiusSmall;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _label = IMCardLabel([IMTheme fontMonoSmall], IMTheme.shared.labelSecondary, 0);
        [self addSubview:_label];

        _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _moreButton.titleLabel.font = [IMTheme fontCaption];
        [_moreButton setTitleColor:IMTheme.shared.accentColor forState:UIControlStateNormal];
        _moreButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_moreButton];

        _moreHeightConstraint = [_moreButton.heightAnchor constraintEqualToConstant:0];

        [NSLayoutConstraint activateConstraints:@[
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:9],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-9],

            [_moreButton.topAnchor constraintEqualToAnchor:_label.bottomAnchor constant:2],
            [_moreButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:9],
            [_moreButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-9],
            _moreHeightConstraint,
            [_moreButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
        ]];
    }
    return self;
}

- (void)configureWithText:(NSString *)text color:(UIColor *)color maxLength:(NSUInteger)maxLength {
    self.fullText = text ?: @"";
    self.maxLength = maxLength;
    self.expanded = NO;
    self.label.textColor = color ?: IMTheme.shared.labelSecondary;
    [self applyTruncation];
}

- (void)applyTruncation {
    NSString *text = self.fullText ?: @"";
    BOOL needsMore = self.maxLength > 0 && text.length > self.maxLength;
    if (needsMore && !self.expanded) {
        self.label.text = [text substringToIndex:self.maxLength];
        self.moreHeightConstraint.constant = 26;
        self.moreButton.hidden = NO;
        [self.moreButton setTitle:[NSString stringWithFormat:@"查看全部（%lu 字）", (unsigned long)text.length]
                         forState:UIControlStateNormal];
    } else {
        self.label.text = text;
        self.moreHeightConstraint.constant = 0;
        self.moreButton.hidden = YES;
    }
    self.hidden = text.length == 0;
}

- (void)moreTapped {
    self.expanded = !self.expanded;
    [self applyTruncation];
    if (self.onHeightChange) self.onHeightChange();
}

@end

#pragma mark - 推理折叠

@interface IMReasoningFoldView ()
@property (nonatomic, strong) UIButton *headerButton;
@property (nonatomic, strong) UIImageView *chevron;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) IMMonoBlockView *bodyView;
@property (nonatomic, assign, readwrite) BOOL expanded;
@property (nonatomic, copy, nullable) NSString *reasoningText;
@property (nonatomic, assign) NSTimeInterval seconds;
@property (nonatomic, assign) BOOL inProgress;
@end

@implementation IMReasoningFoldView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _chevron = IMCardChevron();
        _statusDot = IMCardStatusDot(6);
        _statusDot.backgroundColor = IMTheme.shared.warningColor;
        _statusDot.hidden = YES;

        _titleLabel = IMCardLabel([IMTheme fontFootnote], IMTheme.shared.labelTertiary, 1);
        [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        _headerButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _headerButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_headerButton addTarget:self action:@selector(headerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_headerButton];

        UIStackView *headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[_chevron, _statusDot, _titleLabel]];
        headerRow.translatesAutoresizingMaskIntoConstraints = NO;
        headerRow.axis = UILayoutConstraintAxisHorizontal;
        headerRow.alignment = UIStackViewAlignmentCenter;
        headerRow.spacing = 6;
        headerRow.userInteractionEnabled = NO;
        [self addSubview:headerRow];

        _bodyView = [[IMMonoBlockView alloc] initWithFrame:CGRectZero];
        _bodyView.hidden = YES;
        [self addSubview:_bodyView];

        [NSLayoutConstraint activateConstraints:@[
            [headerRow.topAnchor constraintEqualToAnchor:self.topAnchor],
            [headerRow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [headerRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],

            [_headerButton.topAnchor constraintEqualToAnchor:headerRow.topAnchor constant:-4],
            [_headerButton.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor constant:-4],
            [_headerButton.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor constant:8],
            [_headerButton.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:4],

            [_bodyView.topAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:6],
            [_bodyView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_bodyView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_bodyView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)configureWithText:(NSString *)text seconds:(NSTimeInterval)seconds expanded:(BOOL)expanded inProgress:(BOOL)inProgress {
    self.reasoningText = text ?: @"";
    self.seconds = seconds;
    self.inProgress = inProgress;
    self.expanded = expanded;
    self.hidden = self.reasoningText.length == 0;

    self.statusDot.hidden = !inProgress;
    IMCardSetDotBreathing(self.statusDot, inProgress);

    if (inProgress) {
        self.titleLabel.text = @"正在思考…";
    } else if (expanded) {
        self.titleLabel.text = self.seconds > 0
            ? [NSString stringWithFormat:@"思考了 %.0f 秒", self.seconds]
            : @"思考过程";
    } else {
        self.titleLabel.text = self.seconds > 0
            ? [NSString stringWithFormat:@"思考了 %.0f 秒 · 点开", self.seconds]
            : @"思考过程 · 点开";
    }
    IMCardRotateChevron(self.chevron, expanded);

    self.bodyView.hidden = !expanded;
    if (expanded) {
        [self.bodyView configureWithText:self.reasoningText color:IMTheme.shared.labelSecondary maxLength:2400];
    }
}

- (void)headerTapped {
    if (self.reasoningText.length == 0) return;
    self.expanded = !self.expanded;
    [self configureWithText:self.reasoningText seconds:self.seconds expanded:self.expanded inProgress:self.inProgress];
    if (self.onToggle) self.onToggle(self.expanded);
    if (self.onHeightChange) self.onHeightChange();
}

@end

#pragma mark - 工具调用卡

@interface IMToolCallCardView ()
@property (nonatomic, strong) IMToolCallEntry *entry;
@property (nonatomic, strong) UIButton *headerButton;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *chevron;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UIStackView *detailStack;
@property (nonatomic, strong) UILabel *argumentsTitle;
@property (nonatomic, strong) IMMonoBlockView *argumentsView;
@property (nonatomic, strong) UILabel *resultTitle;
@property (nonatomic, strong) IMMonoBlockView *resultView;
@property (nonatomic, assign) BOOL prettyPending;
@end

@implementation IMToolCallCardView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = IMTheme.shared.backgroundLayer2;
        self.layer.cornerRadius = IMTheme.shared.radiusMedium;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _iconView = IMCardSymbol(@"wrench.and.screwdriver", 13, IMTheme.shared.labelSecondary);
        _chevron = IMCardChevron();
        _statusDot = IMCardStatusDot(7);
        _statusDot.backgroundColor = IMTheme.shared.warningColor;

        _nameLabel = IMCardLabel([UIFont systemFontOfSize:13 weight:UIFontWeightSemibold], IMTheme.shared.labelPrimary, 1);
        [_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

        _summaryLabel = IMCardLabel([IMTheme fontFootnote], IMTheme.shared.labelTertiary, 1);
        _summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        _headerButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _headerButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_headerButton addTarget:self action:@selector(headerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_headerButton];

        UIStackView *headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _nameLabel, _statusDot, _chevron]];
        headerRow.translatesAutoresizingMaskIntoConstraints = NO;
        headerRow.axis = UILayoutConstraintAxisHorizontal;
        headerRow.alignment = UIStackViewAlignmentCenter;
        headerRow.spacing = 6;
        headerRow.userInteractionEnabled = NO;
        [self addSubview:headerRow];

        _argumentsTitle = IMCardLabel([IMTheme fontCaption], IMTheme.shared.labelTertiary, 1);
        _argumentsTitle.text = @"参数";
        _resultTitle = IMCardLabel([IMTheme fontCaption], IMTheme.shared.labelTertiary, 1);
        _resultTitle.text = @"结果";

        _argumentsView = [[IMMonoBlockView alloc] initWithFrame:CGRectZero];
        _resultView = [[IMMonoBlockView alloc] initWithFrame:CGRectZero];

        _detailStack = [[UIStackView alloc] initWithArrangedSubviews:@[_argumentsTitle, _argumentsView, _resultTitle, _resultView]];
        _detailStack.translatesAutoresizingMaskIntoConstraints = NO;
        _detailStack.axis = UILayoutConstraintAxisVertical;
        _detailStack.spacing = 4;
        _detailStack.hidden = YES;
        [self addSubview:_detailStack];

        __weak typeof(self) weakSelf = self;
        void (^heightBlock)(void) = ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) return;
            [self invalidateIntrinsicContentSize];
            if (self.onHeightChange) self.onHeightChange();
        };
        _argumentsView.onHeightChange = heightBlock;
        _resultView.onHeightChange = heightBlock;

        [NSLayoutConstraint activateConstraints:@[
            [headerRow.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [headerRow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [headerRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-10],

            [_summaryLabel.topAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:2],
            [_summaryLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_summaryLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],

            [_headerButton.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_headerButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_headerButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_headerButton.bottomAnchor constraintEqualToAnchor:_summaryLabel.bottomAnchor],

            [_detailStack.topAnchor constraintEqualToAnchor:_summaryLabel.bottomAnchor constant:6],
            [_detailStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_detailStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_detailStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)configureWithEntry:(IMToolCallEntry *)entry {
    self.entry = entry;
    self.nameLabel.text = entry.name.length > 0 ? entry.name : @"tool";
    self.iconView.image = IMSymbol(IMToolSymbolName(entry.name), 13, UIImageSymbolWeightMedium);
    self.summaryLabel.text = [entry argumentsSummary];
    self.summaryLabel.hidden = self.summaryLabel.text.length == 0;
    self.detailStack.hidden = !entry.expanded;
    IMCardRotateChevron(self.chevron, entry.expanded);
    [self refreshStatus];

    if (entry.expanded) {
        [self rebuildDetailWithArguments:entry.prettyArguments ?: entry.argumentsText
                                  result:entry.prettyResult ?: entry.resultText];
        [self preparePrettyTextIfNeeded];
    }
}

- (void)refreshStatus {
    IMToolCallState state = self.entry.state;
    UIColor *color = state == IMToolCallStateSucceeded
        ? IMTheme.shared.successColor
        : (state == IMToolCallStateFailed ? IMTheme.shared.dangerColor : IMTheme.shared.warningColor);
    self.statusDot.backgroundColor = color;
    IMCardSetDotBreathing(self.statusDot, state == IMToolCallStateRunning);
}

/// 工具名 → 图标。按前端常见的几类工具给视觉锚点。
static NSString *IMToolSymbolName(NSString *name) {
    NSString *lower = name.lowercaseString;
    if ([lower containsString:@"write"] || [lower containsString:@"edit"] || [lower containsString:@"patch"]) return @"square.and.pencil";
    if ([lower containsString:@"read"]) return @"doc.text";
    if ([lower containsString:@"grep"] || [lower containsString:@"search"] || [lower containsString:@"glob"]) return @"magnifyingglass";
    if ([lower containsString:@"shell"] || [lower containsString:@"bash"] || [lower containsString:@"terminal"]) return @"terminal";
    if ([lower containsString:@"web"] || [lower containsString:@"fetch"] || [lower containsString:@"http"]) return @"globe";
    if ([lower containsString:@"todo"]) return @"checklist";
    if ([lower containsString:@"team"] || [lower containsString:@"subagent"]) return @"person.2";
    return @"wrench.and.screwdriver";
}

- (void)rebuildDetailWithArguments:(NSString *)arguments result:(NSString *)result {
    self.argumentsTitle.hidden = arguments.length == 0;
    self.argumentsView.hidden = arguments.length == 0;
    [self.argumentsView configureWithText:arguments color:IMTheme.shared.labelSecondary maxLength:1200];

    BOOL hasResult = result.length > 0;
    self.resultTitle.hidden = !hasResult;
    self.resultView.hidden = !hasResult;
    if (hasResult) {
        UIColor *color = self.entry.state == IMToolCallStateFailed ? IMTheme.shared.dangerColor : IMTheme.shared.labelSecondary;
        [self.resultView configureWithText:result color:color maxLength:1600];
    }
}

/// JSON 美化是纯 CPU 活，放后台；结果写回 entry，卡片复用时直接命中。
- (void)preparePrettyTextIfNeeded {
    IMToolCallEntry *entry = self.entry;
    if (entry == nil || self.prettyPending) return;
    BOOL needsArguments = entry.prettyArguments == nil && entry.argumentsText.length > 0;
    BOOL needsResult = entry.prettyResult == nil && entry.resultText.length > 0;
    if (!needsArguments && !needsResult) return;

    self.prettyPending = YES;
    NSString *rawArguments = entry.argumentsText;
    NSString *rawResult = entry.resultText;
    __weak typeof(self) weakSelf = self;
    dispatch_async(IMChatWorkQueue(), ^{
        NSString *prettyArguments = needsArguments ? IMPrettyJSONString(rawArguments) : nil;
        NSString *prettyResult = needsResult ? IMPrettyJSONString(rawResult) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            entry.prettyArguments = prettyArguments ?: rawArguments;
            entry.prettyResult = needsResult ? (prettyResult ?: rawResult) : entry.prettyResult;
            if (self == nil) return;
            self.prettyPending = NO;
            if (self.entry != entry || !entry.expanded) return;
            [self rebuildDetailWithArguments:entry.prettyArguments ?: entry.argumentsText
                                      result:entry.prettyResult ?: entry.resultText];
            if (self.onHeightChange) self.onHeightChange();
        });
    });
}

- (void)headerTapped {
    IMToolCallEntry *entry = self.entry;
    if (entry == nil) return;
    entry.expanded = !entry.expanded;
    [self configureWithEntry:entry];
    if (self.onToggle) self.onToggle(entry.callId, entry.expanded);
    if (self.onHeightChange) self.onHeightChange();
}

@end

#pragma mark - 待办卡

@interface IMTodoCardView ()
@property (nonatomic, strong) UIButton *headerButton;
@property (nonatomic, strong) UIImageView *chevron;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIStackView *rowsStack;
@property (nonatomic, assign, readwrite) BOOL expanded;
@property (nonatomic, strong) NSArray<IMTodoEntry *> *todos;
@end

@implementation IMTodoCardView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = IMTheme.shared.backgroundLayer2;
        self.layer.cornerRadius = IMTheme.shared.radiusMedium;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _chevron = IMCardChevron();
        _titleLabel = IMCardLabel([IMTheme fontFootnote], IMTheme.shared.labelSecondary, 1);

        _headerButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _headerButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_headerButton addTarget:self action:@selector(headerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_headerButton];

        UIStackView *headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[_chevron, _titleLabel]];
        headerRow.translatesAutoresizingMaskIntoConstraints = NO;
        headerRow.axis = UILayoutConstraintAxisHorizontal;
        headerRow.alignment = UIStackViewAlignmentCenter;
        headerRow.spacing = 6;
        headerRow.userInteractionEnabled = NO;
        [self addSubview:headerRow];

        _rowsStack = [[UIStackView alloc] init];
        _rowsStack.translatesAutoresizingMaskIntoConstraints = NO;
        _rowsStack.axis = UILayoutConstraintAxisVertical;
        _rowsStack.spacing = 5;
        [self addSubview:_rowsStack];

        [NSLayoutConstraint activateConstraints:@[
            [headerRow.topAnchor constraintEqualToAnchor:self.topAnchor constant:9],
            [headerRow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [headerRow.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-10],

            [_headerButton.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_headerButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_headerButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_headerButton.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:4],

            [_rowsStack.topAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:6],
            [_rowsStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_rowsStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_rowsStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)configureWithTodos:(NSArray<IMTodoEntry *> *)todos expanded:(BOOL)expanded {
    self.todos = todos ?: @[];
    self.expanded = expanded;

    NSInteger completed = 0;
    for (IMTodoEntry *entry in self.todos) {
        if (entry.status == IMTodoStatusCompleted) completed += 1;
    }
    self.titleLabel.text = [NSString stringWithFormat:@"待办 · %ld/%lu", (long)completed, (unsigned long)self.todos.count];
    IMCardRotateChevron(self.chevron, expanded);

    IMStackRemoveAllArrangedSubviews(self.rowsStack);
    self.rowsStack.hidden = !expanded;
    if (!expanded) return;

    for (IMTodoEntry *entry in self.todos) {
        NSString *symbol = @"circle";
        UIColor *color = IMTheme.shared.labelTertiary;
        if (entry.status == IMTodoStatusCompleted) {
            symbol = @"checkmark.circle.fill";
            color = IMTheme.shared.successColor;
        } else if (entry.status == IMTodoStatusInProgress) {
            symbol = @"circle.dotted";
            color = IMTheme.shared.accentColor;
        }

        UIImageView *icon = IMCardSymbol(symbol, 12, color);
        UILabel *label = IMCardLabel([IMTheme fontFootnote], IMTheme.shared.labelPrimary, 0);
        if (entry.status == IMTodoStatusCompleted) {
            label.attributedText = [[NSAttributedString alloc] initWithString:entry.content ?: @"" attributes:@{
                NSFontAttributeName: [IMTheme fontFootnote],
                NSForegroundColorAttributeName: IMTheme.shared.labelTertiary,
                NSStrikethroughStyleAttributeName: @(NSUnderlineStyleSingle),
            }];
        } else {
            label.text = entry.content;
        }

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentTop;
        row.spacing = 7;
        [self.rowsStack addArrangedSubview:row];
    }
}

- (void)headerTapped {
    self.expanded = !self.expanded;
    [self configureWithTodos:self.todos expanded:self.expanded];
    if (self.onToggle) self.onToggle(self.expanded);
    if (self.onHeightChange) self.onHeightChange();
}

@end

#pragma mark - 提示条

@interface IMNoticeBarView ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *label;
@end

@implementation IMNoticeBarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = IMTheme.shared.backgroundLayer2;
        self.layer.cornerRadius = IMTheme.shared.radiusSmall;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _iconView = IMCardSymbol(@"info.circle", 11, IMTheme.shared.labelTertiary);
        _label = IMCardLabel([IMTheme fontFootnote], IMTheme.shared.labelSecondary, 0);

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, _label]];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentTop;
        row.spacing = 6;
        [self addSubview:row];

        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:7],
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:9],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-9],
            [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-7],
        ]];
    }
    return self;
}

- (void)configureWithText:(NSString *)text isError:(BOOL)isError {
    UIColor *color = isError ? IMTheme.shared.dangerColor : IMTheme.shared.labelSecondary;
    self.label.text = text;
    self.label.textColor = color;
    self.iconView.image = IMSymbol(isError ? @"exclamationmark.triangle" : @"info.circle", 11, UIImageSymbolWeightMedium);
    self.iconView.tintColor = isError ? IMTheme.shared.dangerColor : IMTheme.shared.labelTertiary;
    self.hidden = text.length == 0;
}

@end
