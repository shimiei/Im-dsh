//
//  IMMessageCell.m
//  IMDSH — 消息单元格
//

#import "IMMessageCell.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"
#import "IMMarkdownContentView.h"
#import "IMMessageCardViews.h"

/// 流式输出时跟在正文末尾的光标。
static NSString *const IMStreamCursor = @" ▍";

@interface IMMessageCell () <IMMarkdownContentViewDelegate>

@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) IMMarkdownContentView *markdownView;
@property (nonatomic, strong) IMReasoningFoldView *reasoningView;
@property (nonatomic, strong) UIStackView *toolStack;
@property (nonatomic, strong) IMTodoCardView *todoView;
@property (nonatomic, strong) IMNoticeBarView *noticeView;
@property (nonatomic, strong) UIStackView *attachmentStack;

@property (nonatomic, strong) NSLayoutConstraint *alignLeftConstraint;
@property (nonatomic, strong) NSLayoutConstraint *alignRightConstraint;
/// attachmentId → 对应的缩略图视图（缩略图异步回来时按 id 找回）。
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImageView *> *thumbnailViews;

@property (nonatomic, strong, nullable) IMMessageItem *item;

@end

@implementation IMMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self build];
    }
    return self;
}

- (void)build {
    IMTheme *theme = IMTheme.shared;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _thumbnailViews = [NSMutableDictionary dictionary];

    _bubble = [[UIView alloc] init];
    _bubble.translatesAutoresizingMaskIntoConstraints = NO;
    _bubble.layer.cornerRadius = theme.radiusLarge;
    _bubble.layer.cornerCurve = kCACornerCurveContinuous;
    _bubble.clipsToBounds = YES;
    [self.contentView addSubview:_bubble];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = 8;
    _contentStack.layoutMarginsRelativeArrangement = YES;
    [_bubble addSubview:_contentStack];

    _attachmentStack = [[UIStackView alloc] init];
    _attachmentStack.axis = UILayoutConstraintAxisVertical;
    _attachmentStack.spacing = 4;

    _reasoningView = [[IMReasoningFoldView alloc] initWithFrame:CGRectZero];
    _markdownView = [[IMMarkdownContentView alloc] initWithFrame:CGRectZero];
    _markdownView.delegate = self;

    _toolStack = [[UIStackView alloc] init];
    _toolStack.axis = UILayoutConstraintAxisVertical;
    _toolStack.spacing = 6;

    _todoView = [[IMTodoCardView alloc] initWithFrame:CGRectZero];
    _noticeView = [[IMNoticeBarView alloc] initWithFrame:CGRectZero];

    for (UIView *view in @[_attachmentStack, _reasoningView, _markdownView, _toolStack, _todoView, _noticeView]) {
        [_contentStack addArrangedSubview:view];
    }

    __weak typeof(self) weakSelf = self;
    _reasoningView.onHeightChange = ^{ [weakSelf notifyHeightChange]; };
    _reasoningView.onToggle = ^(BOOL expanded) { weakSelf.item.reasoningExpanded = expanded; };
    _todoView.onHeightChange = ^{ [weakSelf notifyHeightChange]; };
    _todoView.onToggle = ^(BOOL expanded) { weakSelf.item.todosExpanded = expanded; };

    _alignLeftConstraint = [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:theme.spacingM];
    _alignRightConstraint = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-theme.spacingM];

    [NSLayoutConstraint activateConstraints:@[
        [_bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:theme.spacingXS],
        [_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-theme.spacingXS],
        [_bubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:theme.spacingM],
        [_bubble.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-theme.spacingM],
        [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.88],

        [_contentStack.topAnchor constraintEqualToAnchor:_bubble.topAnchor],
        [_contentStack.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor],
    ]];
}

- (void)notifyHeightChange {
    if ([self.delegate respondsToSelector:@selector(messageCellDidChangeHeight:)]) {
        [self.delegate messageCellDidChangeHeight:self];
    }
}

#pragma mark - 配置

- (void)configureWithItem:(IMMessageItem *)item {
    IMTheme *theme = IMTheme.shared;
    if (item == nil) {
        // 兜底：IMMessageItemKindUser 是 0，nil 会被当成「用户消息」画出空气泡。
        self.item = nil;
        [self configureAttachments:@[]];
        [self configureToolCalls:@[]];
        self.reasoningView.hidden = YES;
        self.markdownView.hidden = YES;
        [self.markdownView renderNodes:@[]];
        self.todoView.hidden = YES;
        self.noticeView.hidden = YES;
        return;
    }
    self.item = item;

    BOOL isUser = item.kind == IMMessageItemKindUser;
    self.alignLeftConstraint.active = !isUser;
    self.alignRightConstraint.active = isUser;

    // 用户消息：accent 淡底气泡；助手消息：无底色，只有极轻的内边距。
    self.bubble.backgroundColor = isUser ? [theme.accentColor colorWithAlphaComponent:0.16] : UIColor.clearColor;
    self.contentStack.layoutMargins = isUser ? UIEdgeInsetsMake(10, 13, 10, 13) : UIEdgeInsetsMake(4, 0, 4, 0);

    [self configureAttachments:item.attachments];

    // 推理
    self.reasoningView.hidden = item.reasoning.length == 0;
    if (item.reasoning.length > 0) {
        [self.reasoningView configureWithText:item.reasoning
                                       seconds:item.reasoningSeconds
                                      expanded:item.reasoningExpanded
                                    inProgress:item.reasoningInProgress];
    }

    // 正文
    if (item.text.length > 0) {
        self.markdownView.hidden = NO;
        NSString *text = item.streaming ? [item.text stringByAppendingString:IMStreamCursor] : item.text;
        if (isUser) {
            [self.markdownView renderPlainText:text];
        } else if (item.streaming) {
            // 流式期间走增量渲染：老代码每个 delta 都拿全文当 cache key 整篇重解析，
            // 长回答时 CPU/内存平方增长、缓存爆掉，越聊越卡。
            [self.markdownView renderStreamingMarkdown:text];
        } else {
            // 收尾帧：整篇正式渲染一次，得到最终排版。
            [self.markdownView renderMarkdownText:text];
        }
    } else {
        self.markdownView.hidden = YES;
        [self.markdownView renderNodes:@[]];
    }

    [self configureToolCalls:item.toolCalls];

    self.todoView.hidden = item.todos.count == 0;
    if (item.todos.count > 0) {
        [self.todoView configureWithTodos:item.todos expanded:item.todosExpanded];
    }

    self.noticeView.hidden = item.notice.length == 0;
    if (item.notice.length > 0) {
        [self.noticeView configureWithText:item.notice isError:item.noticeIsError];
    }
}

- (void)configureAttachments:(NSArray<IMAttachmentRef *> *)attachments {
    IMStackRemoveAllArrangedSubviews(self.attachmentStack);
    [self.thumbnailViews removeAllObjects];
    self.attachmentStack.hidden = attachments.count == 0;
    if (attachments.count == 0) return;

    IMMessageItem *item = self.item;
    for (NSUInteger index = 0; index < attachments.count; index++) {
        [self.attachmentStack addArrangedSubview:[self chipViewForAttachment:attachments[index] index:index]];
    }

    // 第二轮再拉缩略图：先把 chip 全部建好，回调回来直接往对应 imageView 里填。
    id<IMMessageCellDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(messageCell:loadThumbnailForAttachment:completion:)]) return;

    __weak typeof(self) weakSelf = self;
    for (NSUInteger index = 0; index < attachments.count; index++) {
        IMAttachmentRef *ref = attachments[index];
        if (!ref.isImage) continue;
        [delegate messageCell:self loadThumbnailForAttachment:ref completion:^(UIImage *image) {
            __strong typeof(weakSelf) cell = weakSelf;
            if (cell == nil || image == nil) return;
            // 回调可能是异步的：确认这条 cell 还在显示同一条消息的同一张图。
            if (cell.item != item) return;
            UIImageView *imageView = cell.thumbnailViews[ref.attachmentId];
            if (imageView == nil) return;
            imageView.image = image;
            imageView.hidden = NO;
        }];
    }
}

- (UIView *)chipViewForAttachment:(IMAttachmentRef *)attachment index:(NSUInteger)index {
    IMTheme *theme = IMTheme.shared;

    UIView *chip = [[UIView alloc] init];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    chip.backgroundColor = theme.inlineCodeBackgroundColor;
    chip.layer.cornerRadius = theme.radiusSmall;
    chip.layer.cornerCurve = kCACornerCurveContinuous;
    chip.clipsToBounds = YES;
    chip.tag = (NSInteger)index;

    UIImageView *imageView = [[UIImageView alloc] init];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.layer.cornerRadius = 6;
    imageView.layer.cornerCurve = kCACornerCurveContinuous;
    imageView.hidden = YES;   // 有缩略图才展开，否则纯文字 chip

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [IMTheme fontFootnote];
    label.textColor = theme.labelSecondary;
    label.text = attachment.isImage
        ? [NSString stringWithFormat:@"附件 · %@", attachment.displayName]
        : [NSString stringWithFormat:@"文件 · %@", attachment.displayName];
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[imageView, label]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 6;
    row.layoutMarginsRelativeArrangement = YES;
    row.layoutMargins = UIEdgeInsetsMake(2, 8, 2, 8);
    row.userInteractionEnabled = NO;
    [chip addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:chip.topAnchor],
        [row.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor],
        [row.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor],
        [imageView.widthAnchor constraintEqualToConstant:32],
        [imageView.heightAnchor constraintEqualToConstant:32],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(attachmentChipTapped:)];
    [chip addGestureRecognizer:tap];

    if (attachment.isImage) self.thumbnailViews[attachment.attachmentId] = imageView;
    return chip;
}

- (void)attachmentChipTapped:(UITapGestureRecognizer *)recognizer {
    NSInteger index = recognizer.view.tag;
    if (index < 0 || index >= (NSInteger)self.item.attachments.count) return;
    IMAttachmentRef *ref = self.item.attachments[(NSUInteger)index];
    if ([self.delegate respondsToSelector:@selector(messageCell:didTapAttachment:)]) {
        [self.delegate messageCell:self didTapAttachment:ref];
    }
}

- (void)configureToolCalls:(NSArray<IMToolCallEntry *> *)toolCalls {
    IMStackRemoveAllArrangedSubviews(self.toolStack);
    self.toolStack.hidden = toolCalls.count == 0;

    __weak typeof(self) weakSelf = self;
    for (IMToolCallEntry *entry in toolCalls) {
        IMToolCallCardView *card = [[IMToolCallCardView alloc] initWithFrame:CGRectZero];
        card.onHeightChange = ^{ [weakSelf notifyHeightChange]; };
        [card configureWithEntry:entry];
        [self.toolStack addArrangedSubview:card];
    }
}

#pragma mark - IMMarkdownContentViewDelegate

- (void)markdownContentViewDidChangeHeight:(IMMarkdownContentView *)view {
    [self notifyHeightChange];
}

- (void)markdownContentView:(IMMarkdownContentView *)view didTapLink:(NSURL *)url {
    if ([self.delegate respondsToSelector:@selector(messageCell:didTapLink:)]) {
        [self.delegate messageCell:self didTapLink:url];
    }
}

#pragma mark - 复用

- (void)prepareForReuse {
    [super prepareForReuse];
    self.item = nil;
    [self.thumbnailViews removeAllObjects];
    self.markdownView.delegate = self;
    [self.markdownView resetExpansion];
}

@end
