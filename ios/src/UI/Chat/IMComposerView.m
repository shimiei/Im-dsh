//
//  IMComposerView.m
//  IMDSH — 输入区
//

#import "IMComposerView.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"
#import <objc/runtime.h>

/// chip 删除按钮上挂的 attachmentId（避免用 tag 下标反查数组）。
static char IMComposerChipIdKey;
@interface IMComposerView () <UITextViewDelegate>
@property (nonatomic, strong) IMGlassView *glassView;
@property (nonatomic, strong) UIStackView *rootStack;
@property (nonatomic, strong) UIScrollView *attachmentScrollView;
@property (nonatomic, strong) UIStackView *attachmentStack;
@property (nonatomic, strong) NSLayoutConstraint *attachmentRowHeight;
@property (nonatomic, strong) UIView *statusRow;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *tokenLabel;
@property (nonatomic, strong) UIView *inputRow;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) IMGlassButton *attachButton;
@property (nonatomic, strong) IMGlassButton *actionButton;
@property (nonatomic, strong) NSLayoutConstraint *textViewHeightConstraint;
@property (nonatomic, assign, readwrite) BOOL running;
@property (nonatomic, copy, nullable) NSString *tokenSummary;
@property (nonatomic, copy) NSArray<IMImageAttachment *> *attachments;
@end

@implementation IMComposerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self build];
    }
    return self;
}

- (void)build {
    IMTheme *theme = IMTheme.shared;
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _glassView = [[IMGlassView alloc] initWithStyle:IMGlassStyleRegular];
    _glassView.cornerRadius = theme.radiusCard;
    _glassView.showsStroke = YES;
    _glassView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_glassView];
    [NSLayoutConstraint activateConstraints:@[
        [_glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    _rootStack = [[UIStackView alloc] init];
    _rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    _rootStack.axis = UILayoutConstraintAxisVertical;
    _rootStack.spacing = 4;
    _rootStack.layoutMarginsRelativeArrangement = YES;
    _rootStack.layoutMargins = UIEdgeInsetsMake(8, 12, 8, 8);
    [_glassView.contentView addSubview:_rootStack];
    [NSLayoutConstraint activateConstraints:@[
        [_rootStack.topAnchor constraintEqualToAnchor:_glassView.contentView.topAnchor],
        [_rootStack.leadingAnchor constraintEqualToAnchor:_glassView.contentView.leadingAnchor],
        [_rootStack.trailingAnchor constraintEqualToAnchor:_glassView.contentView.trailingAnchor],
        [_rootStack.bottomAnchor constraintEqualToAnchor:_glassView.contentView.bottomAnchor],
    ]];

    // 状态条：生成中 + token 用量
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [IMTheme fontCaption];
    _statusLabel.textColor = theme.labelSecondary;
    _statusLabel.text = @"生成中…";

    _tokenLabel = [[UILabel alloc] init];
    _tokenLabel.font = [IMTheme fontCaption];
    _tokenLabel.textColor = theme.labelTertiary;
    _tokenLabel.textAlignment = NSTextAlignmentRight;
    [_tokenLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _statusRow = [[UIView alloc] init];
    UIStackView *statusStack = [[UIStackView alloc] initWithArrangedSubviews:@[_statusLabel, _tokenLabel]];
    statusStack.translatesAutoresizingMaskIntoConstraints = NO;
    statusStack.axis = UILayoutConstraintAxisHorizontal;
    statusStack.alignment = UIStackViewAlignmentCenter;
    statusStack.spacing = 8;
    [_statusRow addSubview:statusStack];
    [NSLayoutConstraint activateConstraints:@[
        [statusStack.topAnchor constraintEqualToAnchor:_statusRow.topAnchor],
        [statusStack.leadingAnchor constraintEqualToAnchor:_statusRow.leadingAnchor constant:4],
        [statusStack.trailingAnchor constraintEqualToAnchor:_statusRow.trailingAnchor],
        [statusStack.bottomAnchor constraintEqualToAnchor:_statusRow.bottomAnchor],
    ]];
    _statusRow.hidden = YES;
    [_rootStack addArrangedSubview:_statusRow];

    // 缩略图 chip 行：默认收起（高度 0），选图后展开到 64。
    _attachmentStack = [[UIStackView alloc] init];
    _attachmentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _attachmentStack.axis = UILayoutConstraintAxisHorizontal;
    _attachmentStack.alignment = UIStackViewAlignmentCenter;
    _attachmentStack.spacing = 8;

    _attachmentScrollView = [[UIScrollView alloc] init];
    _attachmentScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _attachmentScrollView.showsHorizontalScrollIndicator = NO;
    _attachmentScrollView.alwaysBounceHorizontal = YES;
    [_attachmentScrollView addSubview:_attachmentStack];

    _attachmentRowHeight = [_attachmentScrollView.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [_attachmentStack.topAnchor constraintEqualToAnchor:_attachmentScrollView.contentLayoutGuide.topAnchor constant:4],
        [_attachmentStack.bottomAnchor constraintEqualToAnchor:_attachmentScrollView.contentLayoutGuide.bottomAnchor constant:-4],
        [_attachmentStack.leadingAnchor constraintEqualToAnchor:_attachmentScrollView.contentLayoutGuide.leadingAnchor constant:2],
        [_attachmentStack.trailingAnchor constraintEqualToAnchor:_attachmentScrollView.contentLayoutGuide.trailingAnchor constant:-2],
        // 用 <= 而不是 ==：收起时行高是 0，等式会算出负高度并报约束冲突。
        [_attachmentStack.heightAnchor constraintLessThanOrEqualToAnchor:_attachmentScrollView.frameLayoutGuide.heightAnchor],
        _attachmentRowHeight,
    ]];
    _attachmentScrollView.hidden = YES;
    [_rootStack insertArrangedSubview:_attachmentScrollView atIndex:0];

    // 输入行
    _textView = [[UITextView alloc] init];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.backgroundColor = UIColor.clearColor;
    _textView.font = [IMTheme fontBody];
    _textView.textColor = theme.labelPrimary;
    _textView.tintColor = theme.accentColor;
    _textView.textContainerInset = UIEdgeInsetsMake(6, 0, 6, 0);
    _textView.textContainer.lineFragmentPadding = 0;
    _textView.delegate = self;
    _textView.returnKeyType = UIReturnKeyDefault;
    _textView.showsVerticalScrollIndicator = NO;
    _textView.alwaysBounceVertical = NO;
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_textView setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];

    _placeholderLabel = [[UILabel alloc] init];
    _placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _placeholderLabel.text = @"给 DSH 发消息…";
    _placeholderLabel.font = [IMTheme fontBody];
    _placeholderLabel.textColor = theme.labelTertiary;
    _placeholderLabel.userInteractionEnabled = NO;

    _actionButton = [IMGlassButton iconButtonWithSystemImage:@"arrow.up" diameter:34];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
    [_actionButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_actionButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _attachButton = [IMGlassButton iconButtonWithSystemImage:@"plus" diameter:34];
    _attachButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_attachButton addTarget:self action:@selector(attachTapped) forControlEvents:UIControlEventTouchUpInside];
    [_attachButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_attachButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _inputRow = [[UIView alloc] init];
    [_inputRow addSubview:_attachButton];
    [_inputRow addSubview:_textView];
    [_inputRow addSubview:_placeholderLabel];
    [_inputRow addSubview:_actionButton];

    _textViewHeightConstraint = [_textView.heightAnchor constraintEqualToConstant:34];
    [NSLayoutConstraint activateConstraints:@[
        [_attachButton.leadingAnchor constraintEqualToAnchor:_inputRow.leadingAnchor],
        [_attachButton.bottomAnchor constraintEqualToAnchor:_inputRow.bottomAnchor],

        [_textView.topAnchor constraintEqualToAnchor:_inputRow.topAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:_attachButton.trailingAnchor constant:8],
        [_textView.bottomAnchor constraintEqualToAnchor:_inputRow.bottomAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:_actionButton.leadingAnchor constant:-8],
        _textViewHeightConstraint,

        [_placeholderLabel.topAnchor constraintEqualToAnchor:_textView.topAnchor constant:6],
        [_placeholderLabel.leadingAnchor constraintEqualToAnchor:_textView.leadingAnchor constant:2],
        [_placeholderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_textView.trailingAnchor],

        [_actionButton.trailingAnchor constraintEqualToAnchor:_inputRow.trailingAnchor],
        [_actionButton.bottomAnchor constraintEqualToAnchor:_inputRow.bottomAnchor],
    ]];
    [_rootStack addArrangedSubview:_inputRow];

    [self updateActionButton];
}

#pragma mark - 尺寸

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateHeightForWidth:self.textView.bounds.size.width];
}

- (void)updateHeightForWidth:(CGFloat)width {
    if (width <= 0) return;
    UIFont *font = [IMTheme fontBody];
    CGFloat lineHeight = ceil(font.lineHeight * [IMTheme bodyLineHeightMultiple]);
    CGFloat maxHeight = lineHeight * 6 + 12;

    CGSize size = [self.textView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat target = MIN(maxHeight, MAX(lineHeight + 12, ceil(size.height)));
    if (fabs(self.textViewHeightConstraint.constant - target) > 0.5) {
        self.textViewHeightConstraint.constant = target;
        [self invalidateIntrinsicContentSize];
    }
    self.textView.scrollEnabled = size.height > maxHeight + 1;
}

#pragma mark - 附件

- (NSUInteger)attachmentCount {
    return self.attachments.count;
}

- (void)setAttachments:(NSArray<IMImageAttachment *> *)attachments {
    _attachments = [attachments copy] ?: @[];

    IMStackRemoveAllArrangedSubviews(self.attachmentStack);
    for (NSUInteger index = 0; index < _attachments.count; index++) {
        [self.attachmentStack addArrangedSubview:[self chipViewForAttachment:_attachments[index] index:index]];
    }

    BOOL shows = _attachments.count > 0;
    self.attachmentScrollView.hidden = !shows;
    self.attachmentRowHeight.constant = shows ? 64 : 0;
    [self updateActionButton];
    [self invalidateIntrinsicContentSize];
}

- (UIView *)chipViewForAttachment:(IMImageAttachment *)attachment index:(NSUInteger)index {
    UIView *chip = [[UIView alloc] init];
    chip.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *imageView = [[UIImageView alloc] initWithImage:attachment.thumbnail];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.layer.cornerRadius = 10;
    imageView.layer.cornerCurve = kCACornerCurveContinuous;
    [chip addSubview:imageView];

    UIButton *removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    removeButton.translatesAutoresizingMaskIntoConstraints = NO;
    // 按 attachmentId 记，不用 tag 下标：同 runloop 连点或 delegate 还没回写时会错位删错图。
    removeButton.tag = (NSInteger)index;
    objc_setAssociatedObject(removeButton, &IMComposerChipIdKey, attachment.identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [removeButton setImage:IMSymbol(@"xmark", 10, UIImageSymbolWeightBold) forState:UIControlStateNormal];
    removeButton.tintColor = UIColor.whiteColor;
    removeButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    removeButton.layer.cornerRadius = 9;
    [removeButton addTarget:self action:@selector(removeChipTapped:) forControlEvents:UIControlEventTouchUpInside];
    [chip addSubview:removeButton];

    [NSLayoutConstraint activateConstraints:@[
        [chip.widthAnchor constraintEqualToConstant:56],
        [chip.heightAnchor constraintEqualToConstant:56],

        [imageView.topAnchor constraintEqualToAnchor:chip.topAnchor],
        [imageView.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor],

        [removeButton.topAnchor constraintEqualToAnchor:chip.topAnchor constant:2],
        [removeButton.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-2],
        [removeButton.widthAnchor constraintEqualToConstant:18],
        [removeButton.heightAnchor constraintEqualToConstant:18],
    ]];
    return chip;
}

- (void)removeChipTapped:(UIButton *)sender {
    NSString *attachmentId = objc_getAssociatedObject(sender, &IMComposerChipIdKey);
    if (![attachmentId isKindOfClass:NSString.class] || attachmentId.length == 0) return;
    if ([self.delegate respondsToSelector:@selector(composerView:didRemoveAttachmentWithId:)]) {
        [self.delegate composerView:self didRemoveAttachmentWithId:attachmentId];
    }
}

#pragma mark - 状态

- (NSString *)text {
    return self.textView.text ?: @"";
}

- (BOOL)hasText {
    return [self.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}

- (void)setRunning:(BOOL)running {
    _running = running;
    [self updateActionButton];
    [self updateStatusRow];
}

- (void)setTokenSummary:(NSString *)summary {
    _tokenSummary = [summary copy];
    self.tokenLabel.text = summary;
    [self updateStatusRow];
}

- (void)updateStatusRow {
    BOOL showsTokens = self.tokenSummary.length > 0;
    self.tokenLabel.hidden = !showsTokens;
    self.statusLabel.hidden = !self.running;
    self.statusRow.hidden = !self.running && !showsTokens;
}

- (void)updateActionButton {
    if (self.running) {
        [self.actionButton setButtonTitle:nil systemImage:@"stop.fill"];
        self.actionButton.tintColor = IMTheme.shared.dangerColor;
        self.actionButton.enabled = YES;
    } else {
        [self.actionButton setButtonTitle:nil systemImage:@"arrow.up"];
        [self.actionButton applyProminentStyle];
        // 只有图片没有文字也应该能发。
        self.actionButton.enabled = self.hasText || self.attachmentCount > 0;
    }
}

- (void)restoreText:(NSString *)text {
    self.textView.text = text ?: @"";
    [self textChanged];
}

- (void)clearText {
    self.textView.text = @"";
    [self textChanged];
}

- (void)beginEditing {
    [self.textView becomeFirstResponder];
}

#pragma mark - 动作

- (void)actionTapped {
    if (self.running) {
        [self.delegate composerViewDidTapStop:self];
        return;
    }
    if (!self.hasText && self.attachmentCount == 0) return;
    [self.delegate composerViewDidTapSend:self];
}

- (void)attachTapped {
    if ([self.delegate respondsToSelector:@selector(composerViewDidTapAttach:)]) {
        [self.delegate composerViewDidTapAttach:self];
    }
}

- (void)textChanged {
    self.placeholderLabel.hidden = self.text.length > 0;
    [self updateActionButton];
    [self updateHeightForWidth:self.textView.bounds.size.width];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    [self textChanged];
}

@end
