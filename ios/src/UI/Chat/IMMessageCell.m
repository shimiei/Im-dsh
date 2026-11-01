//
//  IMMessageCell.m
//  IMDSH — 消息单元格
//
//  视觉按即时通讯软件（Telegram / LINE）的通行做法：
//  - 自己右对齐、强调色气泡；助手左对齐、浅色气泡 + 小头像
//  - 连续同一发送者的消息成组：组内间距 2pt、组间 10pt，头像和时间只在组尾出现
//  - 气泡 18pt 连续圆角，最大宽度 86%
//

#import "IMMessageCell.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"
#import "IMMarkdownContentView.h"
#import "IMMessageCardViews.h"

/// 流式输出时跟在正文末尾的光标。
static NSString *const IMStreamCursor = @" ▍";

static const CGFloat IMAvatarSize = 26;
static const CGFloat IMBubbleRadius = 18;
static const CGFloat IMSideInset = 12;
static const CGFloat IMAvatarGap = 8;
static const CGFloat IMBubbleMaxWidthRatio = 0.86;
static const CGFloat IMGroupGapOuter = 10;
static const CGFloat IMGroupGapInner = 2;

/// 气泡里的时间戳统一走这里，避免每处各建一个 NSDateFormatter。
static NSString *IMMessageTimeString(NSTimeInterval seconds) {
    if (seconds <= 0) return @"";
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"];
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:seconds]];
}

@interface IMMessageCell () <IMMarkdownContentViewDelegate>

@property (nonatomic, strong) UIView *avatarView;
@property (nonatomic, strong) UIImageView *avatarIconView;
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) IMMarkdownContentView *markdownView;
@property (nonatomic, strong) IMReasoningFoldView *reasoningView;
@property (nonatomic, strong) UIStackView *toolStack;
@property (nonatomic, strong) IMTodoCardView *todoView;
@property (nonatomic, strong) IMNoticeBarView *noticeView;
@property (nonatomic, strong) UIStackView *attachmentStack;
@property (nonatomic, strong) UILabel *metaLabel;

@property (nonatomic, strong) NSLayoutConstraint *alignLeftConstraint;
@property (nonatomic, strong) NSLayoutConstraint *alignRightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *topPadConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bottomPadConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarTopConstraint;

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

    // 头像：助手侧的小圆标（自己发的消息不画头像，和主流 IM 一致）。
    _avatarView = [[UIView alloc] init];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarView.backgroundColor = [theme.accentColor colorWithAlphaComponent:0.16];
    _avatarView.layer.cornerRadius = IMAvatarSize / 2.0;
    _avatarView.layer.cornerCurve = kCACornerCurveContinuous;
    _avatarView.clipsToBounds = YES;
    _avatarView.userInteractionEnabled = NO;
    [self.contentView addSubview:_avatarView];

    _avatarIconView = [[UIImageView alloc] initWithImage:IMSymbol(@"sparkles", 13, UIImageSymbolWeightSemibold)];
    _avatarIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarIconView.tintColor = theme.accentColor;
    _avatarIconView.contentMode = UIViewContentModeCenter;
    [_avatarView addSubview:_avatarIconView];

    _bubble = [[UIView alloc] init];
    _bubble.translatesAutoresizingMaskIntoConstraints = NO;
    _bubble.layer.cornerRadius = IMBubbleRadius;
    _bubble.layer.cornerCurve = kCACornerCurveContinuous;
    _bubble.clipsToBounds = YES;
    [self.contentView addSubview:_bubble];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = 6;
    _contentStack.layoutMarginsRelativeArrangement = YES;
    _contentStack.layoutMargins = UIEdgeInsetsMake(8, 12, 8, 12);
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

    _metaLabel = [[UILabel alloc] init];
    _metaLabel.font = [IMTheme fontCaption];
    _metaLabel.textColor = theme.labelTertiary;
    _metaLabel.numberOfLines = 1;

    for (UIView *view in @[_attachmentStack, _reasoningView, _markdownView, _toolStack, _todoView, _noticeView, _metaLabel]) {
        [_contentStack addArrangedSubview:view];
    }

    __weak typeof(self) weakSelf = self;
    _reasoningView.onHeightChange = ^{ [weakSelf notifyHeightChange]; };
    _reasoningView.onToggle = ^(BOOL expanded) { weakSelf.item.reasoningExpanded = expanded; };
    _todoView.onHeightChange = ^{ [weakSelf notifyHeightChange]; };
    _todoView.onToggle = ^(BOOL expanded) { weakSelf.item.todosExpanded = expanded; };

    _topPadConstraint = [_bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:IMGroupGapOuter];
    _bottomPadConstraint = [_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-IMGroupGapOuter];
    _avatarTopConstraint = [_avatarView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:IMGroupGapOuter + 2];

    // 左右两种贴边方式，按发送者切换。
    _alignLeftConstraint = [_bubble.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:IMAvatarGap];
    _alignRightConstraint = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-IMSideInset];
    _alignRightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:IMSideInset],
        [_avatarView.widthAnchor constraintEqualToConstant:IMAvatarSize],
        [_avatarView.heightAnchor constraintEqualToConstant:IMAvatarSize],
        _avatarTopConstraint,

        [_avatarIconView.centerXAnchor constraintEqualToAnchor:_avatarView.centerXAnchor],
        [_avatarIconView.centerYAnchor constraintEqualToAnchor:_avatarView.centerYAnchor],

        _topPadConstraint,
        _bottomPadConstraint,
        [_bubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:IMSideInset],
        [_bubble.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-IMSideInset],
        [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:IMBubbleMaxWidthRatio],

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
    [self configureWithItem:item showAvatar:YES showTime:YES firstInGroup:YES lastInGroup:YES];
}

- (void)configureWithItem:(IMMessageItem *)item
               showAvatar:(BOOL)showAvatar
                 showTime:(BOOL)showTime
             firstInGroup:(BOOL)firstInGroup
              lastInGroup:(BOOL)lastInGroup {
    IMTheme *theme = IMTheme.shared;
    self.item = item;

    if (item == nil) {
        // 兜底：IMMessageItemKindUser 是 0，nil 会被当成「用户消息」画出空气泡。
        [self configureAttachments:@[]];
        [self configureToolCalls:@[]];
        self.reasoningView.hidden = YES;
        self.markdownView.hidden = YES;
        [self.markdownView renderNodes:@[]];
        self.todoView.hidden = YES;
        self.noticeView.hidden = YES;
        self.metaLabel.hidden = YES;
        self.avatarView.hidden = YES;
        return;
    }

    BOOL isUser = item.kind == IMMessageItemKindUser;
    BOOL isNotice = item.kind == IMMessageItemKindNotice;

    self.alignLeftConstraint.active = !isUser;
    self.alignRightConstraint.active = isUser;

    // 组内紧凑、组间留白：这是「看起来像 IM」最关键的一步。
    CGFloat topPad = firstInGroup ? IMGroupGapOuter : IMGroupGapInner;
    CGFloat bottomPad = lastInGroup ? IMGroupGapOuter : IMGroupGapInner;
    self.topPadConstraint.constant = topPad;
    self.bottomPadConstraint.constant = -bottomPad;
    self.avatarTopConstraint.constant = topPad + 2;

    self.avatarView.hidden = !(showAvatar && !isUser && !isNotice);

    // 气泡底色：自己 = 强调色淡底；助手 = 极浅中性底（原来助手完全透明，读起来像一片裸文本）。
    if (isUser) {
        self.bubble.backgroundColor = [theme.accentColor colorWithAlphaComponent:0.18];
    } else if (isNotice) {
        self.bubble.backgroundColor = UIColor.clearColor;
    } else {
        self.bubble.backgroundColor = [theme.labelPrimary colorWithAlphaComponent:0.055];
    }
    self.contentStack.layoutMargins = isNotice
        ? UIEdgeInsetsMake(2, 0, 2, 0)
        : UIEdgeInsetsMake(8, 12, 8, 12);

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
            // 流式期间走增量渲染：整篇重解析会让长回答的 CPU/内存平方增长。
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

    // 时间戳：只在组尾显示，右发靠右、左发靠左。
    NSString *timeText = showTime ? IMMessageTimeString(item.time) : @"";
    self.metaLabel.text = timeText;
    self.metaLabel.hidden = timeText.length == 0;
    self.metaLabel.textAlignment = isUser ? NSTextAlignmentRight : NSTextAlignmentLeft;
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
