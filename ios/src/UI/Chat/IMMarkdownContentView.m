//
//  IMMarkdownContentView.m
//  IMDSH — Markdown 渲染视图
//

#import "IMMarkdownContentView.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"

/// 单行代码超过这个长度就视觉断行，避免几万点的标签把内存和滚动拖垮。
static const NSUInteger IMCodeLineSoftLimit = 200;
/// 默认最多显示多少行代码，超出折叠。
static const NSInteger IMCodeCollapsedLines = 24;

#pragma mark - 自撑高的文本视图

@interface IMMarkdownTextView : UITextView <UITextViewDelegate>
@property (nonatomic, copy, nullable) void (^onLinkTap)(NSURL *url);
@property (nonatomic, assign) CGFloat lastMeasuredWidth;
@end

@implementation IMMarkdownTextView

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.editable = NO;
    self.scrollEnabled = NO;
    self.selectable = YES;
    self.backgroundColor = UIColor.clearColor;
    self.textContainerInset = UIEdgeInsetsZero;
    self.textContainer.lineFragmentPadding = 0;
    self.dataDetectorTypes = UIDataDetectorTypeNone;
    self.adjustsFontForContentSizeCategory = NO;
    self.userInteractionEnabled = YES;
    self.delegate = self;
    self.linkTextAttributes = @{
        NSForegroundColorAttributeName: IMTheme.shared.accentColor,
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone),
    };
}

- (CGSize)intrinsicContentSize {
    CGFloat width = self.bounds.size.width;
    if (width <= 0) {
        width = self.superview.bounds.size.width;
    }
    if (width <= 0) return CGSizeMake(UIViewNoIntrinsicMetric, 0);
    CGSize size = [self sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    return CGSizeMake(UIViewNoIntrinsicMetric, ceil(size.height));
}

- (void)layoutSubviews {
    CGFloat previous = self.bounds.size.width;
    [super layoutSubviews];
    if (fabs(previous - self.bounds.size.width) > 0.5) {
        [self invalidateIntrinsicContentSize];
    }
}

// UITextItemInteraction 在 iOS 17 起被 text item 系列取代；这里只需要拦下点击拿到 URL，
// 用老回调最省事，显式压掉这条 deprecation 警告。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction {
    if (self.onLinkTap) {
        self.onLinkTap(URL);
        return NO;
    }
    return YES;
}
#pragma clang diagnostic pop

@end

#pragma mark - 代码块

@interface IMCodeBlockView : UIView
@property (nonatomic, copy, nullable) NSString *code;
@property (nonatomic, copy, nullable) NSString *language;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, copy, nullable) void (^onHeightChange)(void);
@end

@interface IMCodeBlockView ()
@property (nonatomic, strong) UILabel *languageLabel;
@property (nonatomic, strong) UIButton *docCopyButton;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) NSLayoutConstraint *codeHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *codeWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *scrollHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *toggleHeightConstraint;
@property (nonatomic, assign) NSInteger totalLines;
@end

@implementation IMCodeBlockView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self build];
    }
    return self;
}

- (void)build {
    IMTheme *theme = IMTheme.shared;
    self.backgroundColor = theme.codeBackgroundColor;
    self.layer.cornerRadius = theme.radiusMedium;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;

    self.languageLabel = [[UILabel alloc] init];
    self.languageLabel.font = [IMTheme fontCaption];
    self.languageLabel.textColor = theme.labelTertiary;
    self.languageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.languageLabel];

    self.docCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightMedium];
    [self.docCopyButton setImage:[UIImage systemImageNamed:@"doc.on.doc" withConfiguration:config] forState:UIControlStateNormal];
    self.docCopyButton.tintColor = theme.labelTertiary;
    self.docCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.docCopyButton addTarget:self action:@selector(copyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.docCopyButton];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsHorizontalScrollIndicator = YES;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.alwaysBounceHorizontal = NO;
    self.scrollView.backgroundColor = UIColor.clearColor;
    [self addSubview:self.scrollView];

    self.codeLabel = [[UILabel alloc] init];
    self.codeLabel.numberOfLines = 0;
    self.codeLabel.lineBreakMode = NSLineBreakByClipping;
    self.codeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.codeLabel];

    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.titleLabel.font = [IMTheme fontCaption];
    [self.toggleButton setTitleColor:theme.accentColor forState:UIControlStateNormal];
    self.toggleButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleButton addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.toggleButton];

    self.codeHeightConstraint = [self.codeLabel.heightAnchor constraintEqualToConstant:0];
    self.codeWidthConstraint = [self.codeLabel.widthAnchor constraintEqualToConstant:0];
    self.scrollHeightConstraint = [self.scrollView.heightAnchor constraintEqualToConstant:0];
    self.toggleHeightConstraint = [self.toggleButton.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.languageLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [self.languageLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:7],
        [self.languageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.docCopyButton.leadingAnchor constant:-8],

        [self.docCopyButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [self.docCopyButton.centerYAnchor constraintEqualToAnchor:self.languageLabel.centerYAnchor],
        [self.docCopyButton.widthAnchor constraintEqualToConstant:24],
        [self.docCopyButton.heightAnchor constraintEqualToConstant:24],

        [self.scrollView.topAnchor constraintEqualToAnchor:self.languageLabel.bottomAnchor constant:5],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        self.scrollHeightConstraint,

        [self.codeLabel.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.codeLabel.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.codeLabel.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.codeLabel.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        self.codeHeightConstraint,
        self.codeWidthConstraint,

        [self.toggleButton.topAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:2],
        [self.toggleButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [self.toggleButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        self.toggleHeightConstraint,
        [self.toggleButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
    ]];
}

- (void)setLanguage:(NSString *)language {
    _language = [language copy];
    self.languageLabel.text = language.length > 0 ? language.lowercaseString : @"代码";
}

- (void)setCode:(NSString *)code {
    _code = [code copy];
    [self rebuild];
}

- (void)setExpanded:(BOOL)expanded {
    _expanded = expanded;
    [self rebuild];
}

/// 把超长单行拆成多行显示（复制时仍用原文）。
static NSString *IMSoftWrappedCode(NSString *code) {
    NSArray<NSString *> *lines = [code componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *output = [NSMutableArray array];
    for (NSString *line in lines) {
        if (line.length <= IMCodeLineSoftLimit) {
            [output addObject:line];
            continue;
        }
        NSUInteger offset = 0;
        while (offset < line.length) {
            NSUInteger length = MIN(IMCodeLineSoftLimit, line.length - offset);
            [output addObject:[line substringWithRange:NSMakeRange(offset, length)]];
            offset += length;
        }
    }
    return [output componentsJoinedByString:@"\n"];
}

- (void)rebuild {
    NSString *display = IMSoftWrappedCode(self.code ?: @"");
    NSArray<NSString *> *lines = [display componentsSeparatedByString:@"\n"];
    self.totalLines = (NSInteger)lines.count;

    NSAttributedString *attributed = [IMMarkdownRenderer attributedCode:display];
    self.codeLabel.attributedText = attributed;

    UIFont *font = [IMTheme fontMonoBody];
    CGFloat widest = 0;
    NSDictionary *attributes = @{NSFontAttributeName: font};
    for (NSString *line in lines) {
        CGFloat width = [line sizeWithAttributes:attributes].width;
        if (width > widest) widest = width;
    }
    widest = MIN(widest, 6000);

    // 折叠态按行数截断；行数少的时候不显示展开按钮。
    BOOL needsToggle = self.totalLines > IMCodeCollapsedLines;
    NSInteger visibleLines = self.expanded ? self.totalLines : MIN(self.totalLines, IMCodeCollapsedLines);
    CGFloat lineHeight = ceil(font.lineHeight * 1.25);

    self.codeHeightConstraint.constant = MAX(lineHeight, visibleLines * lineHeight + 2);
    self.codeWidthConstraint.constant = ceil(widest) + 4;
    self.scrollHeightConstraint.constant = self.codeHeightConstraint.constant;

    self.toggleHeightConstraint.constant = needsToggle ? 26 : 0;
    self.toggleButton.hidden = !needsToggle;
    if (needsToggle) {
        NSString *title = self.expanded
            ? @"收起"
            : [NSString stringWithFormat:@"展开全部（%ld 行）", (long)self.totalLines];
        [self.toggleButton setTitle:title forState:UIControlStateNormal];
    }

    self.scrollView.contentOffset = CGPointMake(0, 0);
    [self invalidateIntrinsicContentSize];
}

- (void)toggleTapped {
    self.expanded = !self.expanded;
    if (self.onHeightChange) self.onHeightChange();
}

- (void)copyTapped {
    IMCopyText(self.code, self, @"代码已复制");
}

@end

#pragma mark - 容器

@interface IMMarkdownContentView ()
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, copy, nullable) NSString *currentMarkdown;
@property (nonatomic, assign) NSInteger generation;
@end

static NSCache<NSString *, NSArray<IMMarkdownNode *> *> *IMMarkdownCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 300;
    });
    return cache;
}

static dispatch_queue_t IMMarkdownQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("imdsh.markdown.parse", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    });
    return queue;
}

@implementation IMMarkdownContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView = [[UIStackView alloc] init];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView.axis = UILayoutConstraintAxisVertical;
        _stackView.alignment = UIStackViewAlignmentFill;
        _stackView.spacing = 6;
        [self addSubview:_stackView];
        [NSLayoutConstraint activateConstraints:@[
            [_stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)renderMarkdownText:(NSString *)markdown {
    NSString *text = markdown ?: @"";
    self.currentMarkdown = text;
    NSInteger generation = ++self.generation;

    if (text.length == 0) {
        [self applyNodes:@[]];
        return;
    }

    NSArray<IMMarkdownNode *> *cached = [IMMarkdownCache() objectForKey:text];
    if (cached != nil) {
        [self applyNodes:cached];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSString *key = [text copy];
    dispatch_async(IMMarkdownQueue(), ^{
        NSArray<IMMarkdownNode *> *nodes = [IMMarkdownRenderer parseMarkdown:key];
        [IMMarkdownCache() setObject:nodes forKey:key cost:key.length];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil || generation != self.generation) return;
            [self applyNodes:nodes];
        });
    });
}

- (void)renderStreamingMarkdown:(NSString *)markdown {
    NSString *text = markdown ?: @"";
    self.currentMarkdown = text;
    NSInteger generation = ++self.generation;

    if (text.length == 0) {
        [self applyNodes:@[]];
        return;
    }

    // 流式期间不能拿整篇当 key 反复全量解析（长回答时 CPU 与缓存都是平方增长）。
    // 只在最后一个空行处切：前半段是「已完成的段落」，内容不再变化、缓存必然命中；
    // 后半段是不完整的尾行，直接当纯文本渲染，不参与 Markdown 解析。
    NSRange splitRange = [text rangeOfString:@"\n\n" options:NSBackwardsSearch];
    NSString *head = @"";
    NSString *tail = text;
    if (splitRange.location != NSNotFound) {
        head = [text substringToIndex:splitRange.location];
        tail = [text substringFromIndex:splitRange.location];
    }

    NSArray<IMMarkdownNode *> *headNodes = head.length > 0 ? [IMMarkdownCache() objectForKey:head] : @[];
    if (headNodes != nil) {
        [self applyNodes:[self nodesByAppendingPlainTail:tail toNodes:headNodes]];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSString *headKey = [head copy];
    dispatch_async(IMMarkdownQueue(), ^{
        NSArray<IMMarkdownNode *> *nodes = [IMMarkdownRenderer parseMarkdown:headKey];
        [IMMarkdownCache() setObject:nodes forKey:headKey cost:headKey.length];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil || generation != self.generation) return;
            [self applyNodes:[self nodesByAppendingPlainTail:tail toNodes:nodes]];
        });
    });
}

/// 把未完成的尾巴当纯文本接在已解析段落后面。
- (NSArray<IMMarkdownNode *> *)nodesByAppendingPlainTail:(NSString *)tail toNodes:(NSArray<IMMarkdownNode *> *)nodes {
    NSMutableArray<IMMarkdownNode *> *result = [NSMutableArray arrayWithArray:nodes ?: @[]];
    NSAttributedString *attributed = [IMMarkdownRenderer attributedPlainText:tail];
    if (attributed.length > 0) {
        IMMarkdownNode *node = [IMMarkdownNode new];
        node.type = IMMarkdownNodeTypeText;
        node.attributedText = attributed;
        [result addObject:node];
    }
    return result;
}

- (void)renderPlainText:(NSString *)text {
    self.generation += 1;   // 让在途的 Markdown 解析结果作废
    self.currentMarkdown = text;
    IMMarkdownNode *node = [IMMarkdownNode new];
    node.type = IMMarkdownNodeTypeText;
    node.attributedText = [IMMarkdownRenderer attributedPlainText:text];
    [self applyNodes:text.length > 0 ? @[node] : @[]];
}

- (void)resetExpansion {
    for (UIView *view in self.stackView.arrangedSubviews) {
        if ([view isKindOfClass:IMCodeBlockView.class]) ((IMCodeBlockView *)view).expanded = NO;
    }
}

- (void)renderNodes:(NSArray<IMMarkdownNode *> *)nodes {
    [self applyNodes:nodes];
}

- (void)applyNodes:(NSArray<IMMarkdownNode *> *)nodes {
    IMStackRemoveAllArrangedSubviews(self.stackView);

    for (IMMarkdownNode *node in nodes) {
        switch (node.type) {
            case IMMarkdownNodeTypeText: {
                if (node.attributedText.length == 0) break;
                IMMarkdownTextView *textView = [[IMMarkdownTextView alloc] init];
                textView.translatesAutoresizingMaskIntoConstraints = NO;
                textView.attributedText = node.attributedText;
                textView.onLinkTap = ^(NSURL *url) {
                    [self handleLink:url];
                };
                [self.stackView addArrangedSubview:textView];
                break;
            }
            case IMMarkdownNodeTypeCode: {
                IMCodeBlockView *codeView = [[IMCodeBlockView alloc] initWithFrame:CGRectZero];
                codeView.translatesAutoresizingMaskIntoConstraints = NO;
                codeView.language = node.language;
                codeView.code = node.rawText ?: @"";
                __weak typeof(self) weakSelf = self;
                codeView.onHeightChange = ^{
                    __strong typeof(weakSelf) self = weakSelf;
                    if (self == nil) return;
                    [self invalidateIntrinsicContentSize];
                    if ([self.delegate respondsToSelector:@selector(markdownContentViewDidChangeHeight:)]) {
                        [self.delegate markdownContentViewDidChangeHeight:self];
                    }
                };
                [self.stackView addArrangedSubview:codeView];
                break;
            }
            case IMMarkdownNodeTypeRule: {
                UIView *rule = [[UIView alloc] init];
                rule.translatesAutoresizingMaskIntoConstraints = NO;
                rule.backgroundColor = IMTheme.shared.separatorColor;
                [rule.heightAnchor constraintEqualToConstant:IMTheme.shared.hairline].active = YES;
                UIView *wrapper = [[UIView alloc] init];
                wrapper.translatesAutoresizingMaskIntoConstraints = NO;
                [wrapper addSubview:rule];
                [NSLayoutConstraint activateConstraints:@[
                    [rule.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
                    [rule.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],
                    [rule.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:4],
                    [rule.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-4],
                ]];
                [self.stackView addArrangedSubview:wrapper];
                break;
            }
        }
    }
    [self invalidateIntrinsicContentSize];
}

- (void)handleLink:(NSURL *)url {
    if (url == nil) return;
    if ([self.delegate respondsToSelector:@selector(markdownContentView:didTapLink:)]) {
        [self.delegate markdownContentView:self didTapLink:url];
        return;
    }
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
