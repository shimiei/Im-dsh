//
//  IMConversationViewController.m
//  IMDSH — 聊天页
//

#import "IMConversationViewController.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"
#import "IMChatService.h"
#import "IMMessageCell.h"
#import "IMComposerView.h"
#import "IMImageAttachment.h"
#import "IMAttachmentImageStore.h"
#import "IMImagePreviewViewController.h"
#import "IMMessageCardViews.h"
#import <PhotosUI/PhotosUI.h>

static const NSInteger IMInitialMessageBudget = 30;
static const NSInteger IMOlderMessageBudget = 30;
/// 距离底部小于这个距离就算"贴底"，新内容会自动跟随。
static const CGFloat IMStickToBottomThreshold = 90;

#pragma mark - 细条（断线提示 / 配对提示）

@interface IMChatInlineBar : UIView
@property (nonatomic, copy, nullable) void (^onTap)(void);
- (void)setText:(NSString *)text isError:(BOOL)isError;
@end

@interface IMChatInlineBar ()
@property (nonatomic, strong) UILabel *label;
@end

@implementation IMChatInlineBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _label = [[UILabel alloc] init];
        _label.font = [IMTheme fontCaption];
        _label.textColor = IMTheme.shared.labelSecondary;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.numberOfLines = 1;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)setText:(NSString *)text isError:(BOOL)isError {
    self.label.text = text;
    self.label.textColor = isError ? IMTheme.shared.dangerColor : IMTheme.shared.labelSecondary;
}

- (void)handleTap {
    if (self.onTap) self.onTap();
}

@end

#pragma mark - 历史加载头

@interface IMHistoryHeaderView : UIView
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, copy, nullable) void (^onTap)(void);
- (void)setState:(NSString *)text loading:(BOOL)loading;
@end

@implementation IMHistoryHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.hidesWhenStopped = YES;
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;

        _label = [[UILabel alloc] init];
        _label.font = [IMTheme fontFootnote];
        _label.textColor = IMTheme.shared.labelTertiary;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_spinner];
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_spinner.trailingAnchor constraintEqualToAnchor:_label.leadingAnchor constant:-6],
            [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor constant:10],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)setState:(NSString *)text loading:(BOOL)loading {
    self.label.text = text;
    if (loading) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
}

- (void)handleTap {
    if (self.onTap) self.onTap();
}

@end

#pragma mark - 展示行 / 日期分隔

/// 展示行：把 transcript.items 摊平成「消息 + 日期分隔」，并带上分组信息。
typedef NS_ENUM(NSInteger, IMConversationRowKind) {
    IMConversationRowKindMessage = 0,
    IMConversationRowKindDaySeparator,
};

@interface IMConversationRow : NSObject
@property (nonatomic, assign) IMConversationRowKind kind;
@property (nonatomic, strong, nullable) IMMessageItem *item;
@property (nonatomic, copy, nullable) NSString *dayText;
@property (nonatomic, assign) BOOL showAvatar;
@property (nonatomic, assign) BOOL showTime;
@property (nonatomic, assign) BOOL firstInGroup;
@property (nonatomic, assign) BOOL lastInGroup;
@end

@implementation IMConversationRow
@end

/// 居中的日期胶囊（今天 / 昨天 / 3月1日）。
@interface IMDaySeparatorCell : UITableViewCell
- (void)configureWithText:(NSString *)text;
@end

@interface IMDaySeparatorCell ()
@property (nonatomic, strong) UILabel *pill;
@end

@implementation IMDaySeparatorCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _pill = [[UILabel alloc] init];
        _pill.translatesAutoresizingMaskIntoConstraints = NO;
        _pill.font = [IMTheme fontCaption];
        _pill.textColor = IMTheme.shared.labelTertiary;
        _pill.textAlignment = NSTextAlignmentCenter;
        _pill.backgroundColor = [IMTheme.shared.labelPrimary colorWithAlphaComponent:0.06];
        _pill.layer.cornerRadius = 10;
        _pill.layer.cornerCurve = kCACornerCurveContinuous;
        _pill.clipsToBounds = YES;
        [self.contentView addSubview:_pill];

        [NSLayoutConstraint activateConstraints:@[
            [_pill.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_pill.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_pill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [_pill.heightAnchor constraintEqualToConstant:20],
            [_pill.widthAnchor constraintGreaterThanOrEqualToConstant:56],
        ]];
    }
    return self;
}

- (void)configureWithText:(NSString *)text {
    self.pill.text = [NSString stringWithFormat:@"  %@  ", text ?: @""];
}

@end

/// 同一发送者、同一天、间隔小于这个秒数，算同一组。
static const NSTimeInterval IMGroupMaxGap = 300;

static NSString *IMDayTextForTime(NSTimeInterval seconds) {
    if (seconds <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seconds];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) return @"今天";
    if ([calendar isDateInYesterday:date]) return @"昨天";
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"];
        formatter.dateFormat = @"M月d日";
    });
    return [formatter stringFromDate:date];
}

static BOOL IMSameDay(NSTimeInterval lhs, NSTimeInterval rhs) {
    if (lhs <= 0 || rhs <= 0) return lhs == rhs;
    NSCalendar *calendar = [NSCalendar currentCalendar];
    return [calendar isDate:[NSDate dateWithTimeIntervalSince1970:lhs]
        inSameDayAsDate:[NSDate dateWithTimeIntervalSince1970:rhs]];
}

static BOOL IMCanGroupTogether(IMMessageItem *lhs, IMMessageItem *rhs) {
    if (lhs == nil || rhs == nil) return NO;
    BOOL lhsUser = lhs.kind == IMMessageItemKindUser;
    BOOL rhsUser = rhs.kind == IMMessageItemKindUser;
    if (lhsUser != rhsUser) return NO;
    // 提示条是独立的一行，不参与分组。
    if (lhs.kind == IMMessageItemKindNotice || rhs.kind == IMMessageItemKindNotice) return NO;
    if (!IMSameDay(lhs.time, rhs.time)) return NO;
    return fabs(lhs.time - rhs.time) <= IMGroupMaxGap;
}

#pragma mark - 聊天页

@interface IMConversationViewController () <UITableViewDataSource, UITableViewDelegate, IMMessageCellDelegate, IMComposerViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate>

@property (nonatomic, strong) IMChatService *service;
@property (nonatomic, strong) IMChatTranscript *transcript;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) IMComposerView *composer;
@property (nonatomic, strong) IMChatInlineBar *reconnectBar;
@property (nonatomic, strong) IMChatInlineBar *pairingBar;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) IMHistoryHeaderView *historyHeader;

@property (nonatomic, strong) NSLayoutConstraint *reconnectBarHeight;
@property (nonatomic, strong) NSLayoutConstraint *pairingBarHeight;

@property (nonatomic, assign) BOOL following;
@property (nonatomic, assign) BOOL hasMoreOlder;
@property (nonatomic, assign) BOOL loadingOlder;
@property (nonatomic, assign) BOOL stickToBottom;
@property (nonatomic, assign) BOOL flushScheduled;
@property (nonatomic, assign) BOOL initialLoadDone;
@property (nonatomic, assign) BOOL needsResubscribe;
@property (nonatomic, assign) BOOL sending;
@property (nonatomic, assign) NSInteger lastRenderedItemCount;
@property (nonatomic, copy, nullable) NSString *pendingRetryText;
@property (nonatomic, copy, nullable) NSString *lastTitle;
@property (nonatomic, strong) NSMutableArray<IMImageAttachment *> *pendingImages;
/// 会话级图片上限，来自 projections.values.imageLimits。
@property (nonatomic, strong) IMImageLimits *imageLimits;

/// 摊平后的展示行（消息 + 日期分隔），表格直接用它。
@property (nonatomic, strong) NSMutableArray<IMConversationRow *> *displayRows;
/// 离开底部时出现的「回到底部」按钮。
@property (nonatomic, strong) UIButton *scrollToBottomButton;
@property (nonatomic, strong) UILabel *unreadBadge;
@property (nonatomic, assign) NSInteger unreadCount;
@property (nonatomic, assign) CGFloat lastHeaderWidth;
@end

@implementation IMConversationViewController

- (instancetype)initWithSessionRow:(IMSessionRow *)row {
    self = [super init];
    if (self) {
        _row = row;
        _service = [[IMChatService alloc] init];
        _transcript = [[IMChatTranscript alloc] init];
        _pendingImages = [NSMutableArray array];
        _imageLimits = [IMImageLimits defaultLimits];
        _displayRows = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    IMTheme *theme = IMTheme.shared;
    self.view.backgroundColor = theme.backgroundBase;
    self.title = [self.row displayTitle];
    self.stickToBottom = YES;

    [self buildInterface];
    [self subscribeToServiceState];
    [self openSessionStream];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.following && self.initialLoadDone) [self openSessionStream];
}

- (void)dealloc {
    [self.service closeSessionStream];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 表头宽度随旋转/分屏变化时补一次，避免停在旧的 0 宽度上。
    CGFloat width = self.tableView.bounds.size.width;
    if (self.historyHeader != nil && width > 0 && fabs(width - self.lastHeaderWidth) > 0.5) {
        [self updateHistoryHeader];
    }
}

#pragma mark - 界面

- (void)buildInterface {
    IMTheme *theme = IMTheme.shared;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    // 以前只设了 dataSource，delegate 从来没赋值 —— scrollViewDidScroll: / isNearBottom /
    // loadOlderMessages 全都是死代码，上滑永远翻不出更早的消息。
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 120;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.contentInset = UIEdgeInsetsMake(6, 0, theme.spacingM, 0);
    [self.tableView registerClass:IMMessageCell.class forCellReuseIdentifier:@"IMMessageCell"];
    [self.tableView registerClass:IMDaySeparatorCell.class forCellReuseIdentifier:@"IMDaySeparatorCell"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.font = [IMTheme fontCallout];
    self.emptyLabel.textColor = theme.labelTertiary;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    self.reconnectBar = [[IMChatInlineBar alloc] initWithFrame:CGRectZero];
    self.reconnectBar.backgroundColor = theme.backgroundLayer2;
    [self.reconnectBar setText:@"连接中断，正在重试…" isError:NO];
    self.reconnectBar.hidden = YES;
    [self.view addSubview:self.reconnectBar];

    self.pairingBar = [[IMChatInlineBar alloc] initWithFrame:CGRectZero];
    self.pairingBar.backgroundColor = theme.backgroundLayer2;
    [self.pairingBar setText:@"尚未配对，点此去设置页完成配对" isError:YES];
    self.pairingBar.hidden = YES;
    [self.view addSubview:self.pairingBar];

    __weak typeof(self) weakSelf = self;
    self.pairingBar.onTap = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (self.onRequirePairing) self.onRequirePairing();
    };

    self.composer = [[IMComposerView alloc] initWithFrame:CGRectZero];
    self.composer.delegate = self;
    [self.view addSubview:self.composer];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.reconnectBarHeight = [self.reconnectBar.heightAnchor constraintEqualToConstant:0];
    self.pairingBarHeight = [self.pairingBar.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.reconnectBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.reconnectBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.reconnectBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.reconnectBarHeight,

        [self.tableView.topAnchor constraintEqualToAnchor:self.reconnectBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.pairingBar.topAnchor],

        [self.pairingBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pairingBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.pairingBar.bottomAnchor constraintEqualToAnchor:self.composer.topAnchor constant:-4],
        self.pairingBarHeight,

        [self.composer.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:theme.spacingM],
        [self.composer.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-theme.spacingM],
        [self.composer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.composer.widthAnchor constraintLessThanOrEqualToConstant:780],
    ]];
    // 手机竖屏铺满安全区；iPad 上被 780 上限收窄后居中。
    // 全部 required，宽度用低优先级等式补：原来那条 priority 750 的 leading 等式
    // 会和「宽度 ≤ 780」在首次布局（bounds 还是 0）时互相打，刷一屏 unsatisfiable。
    NSLayoutConstraint *composerWidth = [self.composer.widthAnchor constraintEqualToAnchor:safe.widthAnchor
                                                                                constant:-theme.spacingM * 2];
    composerWidth.priority = UILayoutPriorityDefaultHigh;
    composerWidth.active = YES;

    // 输入区贴键盘：keyboardLayoutGuide 在键盘收起时等于安全区底部，不需要手写通知偏移。
    NSLayoutConstraint *composerBottom = [self.composer.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-theme.spacingS];
    composerBottom.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor constant:-30],
        [self.emptyLabel.widthAnchor constraintLessThanOrEqualToConstant:280],
    ]];

    // 回到底部：离开底部时出现，有新消息时带未读数。
    self.scrollToBottomButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollToBottomButton setImage:IMSymbol(@"chevron.down", 15, UIImageSymbolWeightSemibold)
                               forState:UIControlStateNormal];
    self.scrollToBottomButton.tintColor = theme.labelPrimary;
    self.scrollToBottomButton.backgroundColor = theme.backgroundLayer2;
    self.scrollToBottomButton.layer.cornerRadius = 20;
    self.scrollToBottomButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.scrollToBottomButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.scrollToBottomButton.layer.shadowOpacity = 0.12;
    self.scrollToBottomButton.layer.shadowRadius = 8;
    self.scrollToBottomButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.scrollToBottomButton.hidden = YES;
    [self.scrollToBottomButton addTarget:self
                                  action:@selector(scrollToBottomTapped)
                        forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.scrollToBottomButton];

    self.unreadBadge = [[UILabel alloc] init];
    self.unreadBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.unreadBadge.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    self.unreadBadge.textColor = UIColor.whiteColor;
    self.unreadBadge.textAlignment = NSTextAlignmentCenter;
    self.unreadBadge.backgroundColor = theme.accentColor;
    self.unreadBadge.layer.cornerRadius = 8;
    self.unreadBadge.layer.cornerCurve = kCACornerCurveContinuous;
    self.unreadBadge.clipsToBounds = YES;
    self.unreadBadge.hidden = YES;
    [self.scrollToBottomButton addSubview:self.unreadBadge];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollToBottomButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.scrollToBottomButton.bottomAnchor constraintEqualToAnchor:self.composer.topAnchor constant:-10],
        [self.scrollToBottomButton.widthAnchor constraintEqualToConstant:40],
        [self.scrollToBottomButton.heightAnchor constraintEqualToConstant:40],

        [self.unreadBadge.centerXAnchor constraintEqualToAnchor:self.scrollToBottomButton.trailingAnchor constant:-2],
        [self.unreadBadge.centerYAnchor constraintEqualToAnchor:self.scrollToBottomButton.topAnchor constant:2],
        [self.unreadBadge.heightAnchor constraintEqualToConstant:16],
        [self.unreadBadge.widthAnchor constraintGreaterThanOrEqualToConstant:16],
    ]];

    self.composer.hidden = !self.service.isPaired;
    [self updatePairingBar];
    [self updateComposerState];
}

- (void)updatePairingBar {
    BOOL paired = self.service.isPaired;
    self.pairingBar.hidden = paired;
    self.pairingBarHeight.constant = paired ? 0 : 26;
    self.composer.hidden = !paired;
}

#pragma mark - 订阅

- (void)subscribeToServiceState {
    __weak typeof(self) weakSelf = self;
    [self.service setConnectionHandler:^(BOOL connected) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.reconnectBar.hidden = connected;
        self.reconnectBarHeight.constant = connected ? 0 : 26;
        if (connected && self.needsResubscribe) {
            // 断线后服务端不续传：重开 follow 拿新快照对齐 seq。
            self.needsResubscribe = NO;
            [self openSessionStream];
        }
    }];
}

- (void)openSessionStream {
    if (!self.service.isPaired) return;
    self.following = YES;
    self.needsResubscribe = NO;
    [self.service closeSessionStream];

    __weak typeof(self) weakSelf = self;
    [self.service openSession:self.row
                  maxMessages:IMInitialMessageBudget
                   onSnapshot:^(NSDictionary *snapshot) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self applySnapshot:snapshot];
    }
                     onRecord:^(NSDictionary *record) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self handleIncomingRecord:record];
    }
                onStreamFrame:^(NSDictionary *frame) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self handleAssistantStreamFrame:frame];
    }
                        onEnd:^(void) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        // 服务端结束监听（会话被切走 / 权限变化）：下次重连时重新对齐。
        self.following = NO;
        self.needsResubscribe = YES;
    }
                      onError:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.following = NO;
        self.needsResubscribe = YES;
        if ([IMChatService isUnauthorizedError:error]) {
            [self updatePairingBar];
            return;
        }
        if (self.initialLoadDone) {
            self.reconnectBar.hidden = NO;
            self.reconnectBarHeight.constant = 26;
        } else {
            self.emptyLabel.text = [IMChatService messageForError:error];
            self.emptyLabel.hidden = NO;
        }
    }];
}

#pragma mark - 快照 / 事件

- (void)applySnapshot:(NSDictionary *)snapshot {
    self.initialLoadDone = YES;
    self.following = YES;

    NSArray *records = nil;
    id rawRecords = snapshot[@"records"];
    if ([rawRecords isKindOfClass:NSArray.class]) records = rawRecords;
    [self.transcript resetWithRecords:records];

    // hasMore 可能是 null/字符串：直接 boolValue 会在 NSNull 上炸 unrecognized selector。
    id rawHasMore = nil;
    if ([snapshot isKindOfClass:NSDictionary.class]) rawHasMore = snapshot[@"hasMore"];
    self.hasMoreOlder = [rawHasMore isKindOfClass:NSNumber.class] ? [(NSNumber *)rawHasMore boolValue] : NO;

    id projections = snapshot[@"projections"];
    id values = [projections isKindOfClass:NSDictionary.class] ? ((NSDictionary *)projections)[@"values"] : nil;
    if ([values isKindOfClass:NSDictionary.class]) {
        id usage = ((NSDictionary *)values)[@"tokenUsage"];
        if ([usage isKindOfClass:NSDictionary.class]) self.transcript.tokenUsage = usage;
        id title = ((NSDictionary *)values)[@"title"];
        if ([title isKindOfClass:NSString.class] && [(NSString *)title length] > 0) {
            self.title = title;
            self.lastTitle = title;
        }
        // 图片上限跟着会话走，不硬编码。
        id imageLimits = ((NSDictionary *)values)[@"imageLimits"];
        if ([imageLimits isKindOfClass:NSDictionary.class]) {
            self.imageLimits = [IMImageLimits limitsWithProjectionValue:imageLimits];
        }
    }

    self.reconnectBar.hidden = YES;
    self.reconnectBarHeight.constant = 0;
    [self rebuildDisplayRows];
    [self.tableView reloadData];
    self.lastRenderedItemCount = (NSInteger)self.transcript.items.count;
    [self updateHistoryHeader];
    [self updateEmptyState];
    [self updateComposerState];
    [self scrollToBottomAnimated:NO];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self scrollToBottomAnimated:NO];
    });
}

- (void)handleIncomingRecord:(NSDictionary *)record {
    BOOL hadGap = [self.transcript hasSeqGapAtEvent:record];
    if (hadGap) {
        // seq 跳号说明中间丢了事件：重开流拿快照重新对齐（文档 §6.3 的 gap 修复）。
        [self openSessionStream];
        return;
    }

    NSUInteger previousCount = self.transcript.items.count;
    if (![self.transcript appendRecord:record]) return;

    if (self.transcript.items.count != previousCount) {
        [self rebuildDisplayRows];
        [self.tableView reloadData];
        self.lastRenderedItemCount = (NSInteger)self.transcript.items.count;
        [self updateEmptyState];
        if (self.stickToBottom) {
            [self scrollToBottomAnimated:YES];
        } else {
            // 没贴底就是用户在翻历史：只累计未读，不抢滚动位置。
            self.unreadCount += 1;
            [self updateScrollToBottomButton];
        }
        if (self.onSessionActivity) self.onSessionActivity();
    } else {
        [self refreshLastItem];
    }
    [self updateComposerState];
}

- (void)handleAssistantStreamFrame:(NSDictionary *)frame {
    if (![self.transcript applyAssistantStreamFrame:frame]) return;
    NSUInteger currentCount = self.transcript.items.count;
    if ((NSInteger)currentCount != self.lastRenderedItemCount) {
        self.lastRenderedItemCount = (NSInteger)currentCount;
        [self rebuildDisplayRows];
        [self.tableView reloadData];
        if (self.stickToBottom) [self scrollToBottomAnimated:NO];
    }
    [self scheduleStreamFlush];
    [self updateComposerState];
}

- (void)scheduleStreamFlush {
    if (self.flushScheduled) return;
    self.flushScheduled = YES;
    __weak typeof(self) weakSelf = self;
    // 60ms 合帧：DSH 的 delta 一秒钟能来几十个，逐个刷新会把主线程打满。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.flushScheduled = NO;
        [self flushStreamingItem];
    });
}

- (void)flushStreamingItem {
    IMMessageItem *item = self.transcript.streamingItem;
    if (item == nil) return;
    NSInteger index = [self displayIndexForItem:item];
    if (index < 0 || index >= (NSInteger)self.displayRows.count) return;
    NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];

    BOOL wasStick = self.stickToBottom;
    IMMessageCell *cell = (IMMessageCell *)[self.tableView cellForRowAtIndexPath:path];
    IMConversationRow *row = self.displayRows[(NSUInteger)index];
    if (cell != nil) {
        [cell configureWithItem:row.item
                     showAvatar:row.showAvatar
                       showTime:row.showTime
                   firstInGroup:row.firstInGroup
                    lastInGroup:row.lastInGroup];
        // 自撑高 cell 原地更新后需要重算行高，否则打字机效果会把内容裁掉。
        [UIView performWithoutAnimation:^{
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
        }];
    } else if ([[self.tableView indexPathsForVisibleRows] containsObject:path]) {
        [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    }
    if (wasStick) [self scrollToBottomAnimated:NO];
}

- (void)refreshLastItem {
    NSInteger index = (NSInteger)self.displayRows.count - 1;
    while (index >= 0 && self.displayRows[(NSUInteger)index].kind != IMConversationRowKindMessage) {
        index -= 1;
    }
    if (index < 0) return;
    NSIndexPath *path = [NSIndexPath indexPathForRow:index inSection:0];
    BOOL wasStick = self.stickToBottom;
    IMMessageCell *cell = (IMMessageCell *)[self.tableView cellForRowAtIndexPath:path];
    if (cell != nil) {
        IMConversationRow *row = self.displayRows[(NSUInteger)index];
        [cell configureWithItem:row.item
                     showAvatar:row.showAvatar
                       showTime:row.showTime
                   firstInGroup:row.firstInGroup
                    lastInGroup:row.lastInGroup];
        [UIView performWithoutAnimation:^{
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
        }];
        if (wasStick) [self scrollToBottomAnimated:NO];
    } else if ([[self.tableView indexPathsForVisibleRows] containsObject:path]) {
        // 只在行确实可见时 reload，避免对不可见行做无效刷新。
        [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    }
}

#pragma mark - 状态刷新

- (void)updateComposerState {
    BOOL running = self.transcript.running || self.transcript.streamingItem.streaming;
    [self.composer setRunning:running];

    NSDictionary *usage = self.transcript.tokenUsage;
    NSString *summary = nil;
    if ([usage isKindOfClass:NSDictionary.class]) {
        id rawInput = usage[@"uncachedInputTokens"];
        id rawOutput = usage[@"outputTokens"];
        NSInteger input = [rawInput isKindOfClass:NSNumber.class] ? [(NSNumber *)rawInput integerValue] : 0;
        NSInteger output = [rawOutput isKindOfClass:NSNumber.class] ? [(NSNumber *)rawOutput integerValue] : 0;
        if (input > 0 || output > 0) {
            summary = [NSString stringWithFormat:@"输入 %@ · 输出 %@", IMTokenCountString(input), IMTokenCountString(output)];
        }
    }
    [self.composer setTokenSummary:summary];
}

- (void)updateEmptyState {
    BOOL empty = self.transcript.items.count == 0;
    if (empty && self.emptyLabel.text.length == 0) {
        self.emptyLabel.text = self.service.isPaired
            ? @"还没有消息。\n在下面输入框里说点什么，DSH 就会开始干活。"
            : @"尚未配对主机。";
    }
    self.emptyLabel.hidden = !empty;
}

#pragma mark - 展示行

/// 把 transcript.items 摊平成「日期分隔 + 消息」，并算好分组边界。
/// O(n) 且只在数据变化时跑，比在 cellForRow 里现算邻居安全得多。
- (void)rebuildDisplayRows {
    NSArray<IMMessageItem *> *items = self.transcript.items;
    [self.displayRows removeAllObjects];

    NSString *currentDay = nil;
    NSUInteger count = items.count;
    for (NSUInteger index = 0; index < count; index++) {
        IMMessageItem *item = items[index];

        NSString *day = IMDayTextForTime(item.time);
        if (day.length > 0 && ![day isEqualToString:currentDay ?: @""]) {
            IMConversationRow *separator = [IMConversationRow new];
            separator.kind = IMConversationRowKindDaySeparator;
            separator.dayText = day;
            [self.displayRows addObject:separator];
            currentDay = day;
        }

        IMMessageItem *previous = index > 0 ? items[index - 1] : nil;
        IMMessageItem *next = index + 1 < count ? items[index + 1] : nil;
        BOOL joinsPrevious = IMCanGroupTogether(previous, item);
        BOOL joinsNext = IMCanGroupTogether(item, next);

        IMConversationRow *row = [IMConversationRow new];
        row.kind = IMConversationRowKindMessage;
        row.item = item;
        row.firstInGroup = !joinsPrevious;
        row.lastInGroup = !joinsNext;
        // 头像和时间戳只画在组尾，这是主流 IM 的通行做法。
        row.showTime = row.lastInGroup;
        row.showAvatar = row.lastInGroup;
        [self.displayRows addObject:row];
    }
}

- (NSInteger)displayIndexForItem:(IMMessageItem *)item {
    if (item == nil) return -1;
    for (NSUInteger index = 0; index < self.displayRows.count; index++) {
        IMConversationRow *row = self.displayRows[index];
        if (row.kind == IMConversationRowKindMessage && row.item == item) return (NSInteger)index;
    }
    return -1;
}

- (void)updateScrollToBottomButton {
    BOOL shouldShow = !self.stickToBottom && self.displayRows.count > 0;
    self.scrollToBottomButton.hidden = !shouldShow;
    if (self.unreadCount > 0) {
        self.unreadBadge.hidden = NO;
        self.unreadBadge.text = self.unreadCount > 99
            ? @"99+"
            : [NSString stringWithFormat:@"%ld", (long)self.unreadCount];
    } else {
        self.unreadBadge.hidden = YES;
    }
}

- (void)scrollToBottomTapped {
    self.stickToBottom = YES;
    self.unreadCount = 0;
    [self updateScrollToBottomButton];
    [self scrollToBottomAnimated:YES];
}

#pragma mark - 历史分页

- (void)updateHistoryHeader {
    if (!self.hasMoreOlder || self.transcript.items.count == 0) {
        self.tableView.tableHeaderView = nil;
        return;
    }
    if (self.historyHeader == nil) {
        IMHistoryHeaderView *header = [[IMHistoryHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 40)];
        __weak typeof(self) weakSelf = self;
        header.onTap = ^{ [weakSelf loadOlderMessages]; };
        self.historyHeader = header;
    }
    // 宽度必须等表格真正布局完：首次进页面 bounds 还是 0，
    // 用 0 宽度塞进 tableHeaderView 会让内部全 Auto Layout 的表头刷 unsatisfiable。
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) return;
    self.lastHeaderWidth = width;
    self.historyHeader.frame = CGRectMake(0, 0, width, 40);
    if (self.loadingOlder) {
        [self.historyHeader setState:@"正在加载更早的消息…" loading:YES];
    } else {
        [self.historyHeader setState:@"上滑加载更早的消息" loading:NO];
    }
    self.tableView.tableHeaderView = self.historyHeader;
}

- (void)loadOlderMessages {
    if (self.loadingOlder || !self.hasMoreOlder) return;
    NSInteger oldest = self.transcript.oldestSeq;
    if (oldest <= 1) {
        self.hasMoreOlder = NO;
        [self updateHistoryHeader];
        return;
    }

    self.loadingOlder = YES;
    [self updateHistoryHeader];
    CGFloat previousHeight = self.tableView.contentSize.height;
    CGFloat previousOffset = self.tableView.contentOffset.y;

    __weak typeof(self) weakSelf = self;
    // 只用 hasMore 判断是否到底：maxMessages 是按 message/turn 对齐的，不是事件条数。
    [self.service loadOlderPageThroughSeq:oldest - 1 maxMessages:IMOlderMessageBudget completion:^(NSArray *records, BOOL hasMore, NSInteger throughSeq, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.loadingOlder = NO;
        if (error != nil) {
            [self.historyHeader setState:@"加载失败，点一下重试" loading:NO];
            return;
        }
        self.hasMoreOlder = hasMore;
        [self.transcript prependRecords:records];
        [self rebuildDisplayRows];
        [self.tableView reloadData];
        self.lastRenderedItemCount = (NSInteger)self.transcript.items.count;
        [self.tableView layoutIfNeeded];
        CGFloat newHeight = self.tableView.contentSize.height;
        // 保住视觉位置：新内容在顶部插入，偏移量按高度差补回。
        self.tableView.contentOffset = CGPointMake(0, previousOffset + (newHeight - previousHeight));
        [self updateHistoryHeader];
    }];
}

#pragma mark - 滚动

- (BOOL)isNearBottom {
    CGFloat height = self.tableView.bounds.size.height;
    CGFloat contentHeight = self.tableView.contentSize.height;
    if (contentHeight <= height) return YES;
    CGFloat offset = self.tableView.contentOffset.y;
    return offset + height >= contentHeight - IMStickToBottomThreshold;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.tableView) return;
    self.stickToBottom = [self isNearBottom];
    if (self.stickToBottom) self.unreadCount = 0;
    [self updateScrollToBottomButton];
    // 必须是用户真的在拖或惯性滚动才触发翻页：消息少时 contentOffset 天然贴着顶部，
    // 不判这两个标志会在每次布局/回弹时反复打 session/page。
    BOOL userScrolling = self.tableView.isDragging || self.tableView.isDecelerating;
    if (userScrolling && self.tableView.contentOffset.y < 120 && self.transcript.items.count > 0) {
        [self loadOlderMessages];
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    NSInteger rows = (NSInteger)self.displayRows.count;
    if (rows == 0) return;
    NSIndexPath *last = [NSIndexPath indexPathForRow:rows - 1 inSection:0];
    [self.tableView layoutIfNeeded];
    [self.tableView scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
    self.unreadCount = 0;
    [self updateScrollToBottomButton];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.displayRows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.displayRows.count) {
        return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"IMBlankCell"];
    }

    IMConversationRow *row = self.displayRows[(NSUInteger)indexPath.row];
    if (row.kind == IMConversationRowKindDaySeparator) {
        IMDaySeparatorCell *cell = [tableView dequeueReusableCellWithIdentifier:@"IMDaySeparatorCell"
                                                                  forIndexPath:indexPath];
        [cell configureWithText:row.dayText];
        return cell;
    }

    IMMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"IMMessageCell" forIndexPath:indexPath];
    cell.delegate = self;
    [cell configureWithItem:row.item
                 showAvatar:row.showAvatar
                   showTime:row.showTime
               firstInGroup:row.firstInGroup
                lastInGroup:row.lastInGroup];
    return cell;
}

#pragma mark - IMMessageCellDelegate

- (void)messageCellDidChangeHeight:(IMMessageCell *)cell {
    BOOL wasStick = self.stickToBottom;
    [UIView performWithoutAnimation:^{
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }];
    if (wasStick) [self scrollToBottomAnimated:NO];
}

- (void)messageCell:(IMMessageCell *)cell didTapLink:(NSURL *)url {
    if (url == nil) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)messageCell:(IMMessageCell *)cell
    loadThumbnailForAttachment:(IMAttachmentRef *)attachment
                    completion:(void (^)(UIImage *))completion {
    if (completion == nil) return;
    UIImage *cached = [IMAttachmentImageStore.shared cachedImageForAttachmentId:attachment.attachmentId];
    if (cached != nil) {
        completion(cached);
        return;
    }
    // 拉不到就回调 nil，cell 会退回纯文字 chip，全程静默。
    [IMAttachmentImageStore.shared imageForAttachment:attachment sessionId:self.row.sessionId completion:^(UIImage *image) {
        completion(image);
    }];
}

- (void)messageCell:(IMMessageCell *)cell didTapAttachment:(IMAttachmentRef *)attachment {
    if (!attachment.isImage) return;
    UIImage *placeholder = [IMAttachmentImageStore.shared cachedImageForAttachmentId:attachment.attachmentId];
    IMImagePreviewViewController *preview = [[IMImagePreviewViewController alloc] initWithPlaceholderImage:placeholder
                                                                                              attachment:attachment
                                                                                               sessionId:self.row.sessionId];
    preview.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    preview.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:preview animated:YES completion:nil];
}

#pragma mark - IMComposerViewDelegate

- (void)composerViewDidTapSend:(IMComposerView *)composer {
    if (self.sending) return;
    NSString *text = composer.text;
    BOOL hasText = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    NSArray<IMImageAttachment *> *images = [self.pendingImages copy];
    if (!hasText && images.count == 0) return;

    // 单条消息的图片总字节也受会话限制，先在本地拦一道，别等网关报错。
    if (self.imageLimits.maxMessageBytes > 0) {
        NSInteger totalBytes = 0;
        for (IMImageAttachment *attachment in images) totalBytes += attachment.byteLength;
        if (totalBytes > self.imageLimits.maxMessageBytes) {
            [self showSendFailure:@"图片总大小超过本会话限制，请减少张数"];
            return;
        }
    }

    self.sending = YES;
    self.pendingRetryText = text;
    __weak typeof(self) weakSelf = self;
    [self.service sendPromptWithText:text images:images requestId:NSUUID.UUID.UUIDString completion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.sending = NO;
        if (error != nil) {
            // 发送失败：文字和图片都留着，给一条可点击重试的提示。
            [self.composer restoreText:text];
            [self.composer setAttachments:self.pendingImages];
            [self showSendFailure:[IMChatService messageForError:error]];
            return;
        }
        self.pendingRetryText = nil;
        [self.pendingImages removeAllObjects];
        [self.composer setAttachments:@[]];
        [self.composer clearText];
        self.transcript.running = YES;
        [self updateComposerState];
        if (self.stickToBottom) [self scrollToBottomAnimated:YES];
        if (self.onSessionActivity) self.onSessionActivity();
    }];
}

- (void)composerViewDidTapAttach:(IMComposerView *)composer {
    NSInteger maxCount = self.imageLimits.maxCount > 0 ? self.imageLimits.maxCount : (NSInteger)[IMImageAttachment maxCount];
    if ((NSInteger)self.pendingImages.count >= maxCount) {
        [self showSendFailure:[NSString stringWithFormat:@"本会话一次最多 %ld 张图片", (long)maxCount]];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"从相册选择照片" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf presentPhotoPicker];
    }]];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"拍摄照片" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            // PHPicker 不支持拍照，相机这条仍然走 UIImagePickerController。
            [weakSelf presentImagePickerWithSourceType:UIImagePickerControllerSourceTypeCamera];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    // iPad 上 actionSheet 走 popover，必须给锚点，否则直接崩。
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover != nil) {
        popover.sourceView = self.composer;
        popover.sourceRect = CGRectMake(28, MAX(1, self.composer.bounds.size.height - 12), 1, 1);
        popover.permittedArrowDirections = UIPopoverArrowDirectionDown;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSInteger)remainingImageSlots {
    NSInteger maxCount = self.imageLimits.maxCount > 0 ? self.imageLimits.maxCount : (NSInteger)[IMImageAttachment maxCount];
    return MAX(0, maxCount - (NSInteger)self.pendingImages.count);
}

- (void)presentPhotoPicker {
    NSInteger remaining = [self remainingImageSlots];
    if (remaining <= 0) return;

    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    // 一次能选满剩余张数。
    configuration.selectionLimit = remaining;
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)presentImagePickerWithSourceType:(UIImagePickerControllerSourceType)sourceType {
    if (![UIImagePickerController isSourceTypeAvailable:sourceType]) return;
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = sourceType;
    picker.mediaTypes = @[@"public.image"];
    picker.allowsEditing = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)composerView:(IMComposerView *)composer didRemoveAttachmentWithId:(NSString *)attachmentId {
    if (attachmentId.length == 0) return;
    NSUInteger index = [self.pendingImages indexOfObjectPassingTest:^BOOL(IMImageAttachment *attachment, NSUInteger idx, BOOL *stop) {
        return [attachment.identifier isEqualToString:attachmentId];
    }];
    if (index == NSNotFound) return;
    [self.pendingImages removeObjectAtIndex:index];
    [self.composer setAttachments:self.pendingImages];
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    NSInteger remaining = [self remainingImageSlots];
    if (remaining <= 0) return;
    NSArray<PHPickerResult *> *selected = results.count > (NSUInteger)remaining
        ? [results subarrayWithRange:NSMakeRange(0, (NSUInteger)remaining)]
        : results;

    IMImageLimits *limits = self.imageLimits;
    for (PHPickerResult *result in selected) {
        NSItemProvider *provider = result.itemProvider;
        NSString *suggestedName = provider.suggestedName;
        __weak typeof(self) weakSelf = self;
        // 注意：这个回调在后台线程；缩图/重编码本身也是在 IMImageAttachment 的串行队列里跑，
        // 这里只是发起，不阻塞等待，不会死锁。
        [provider loadDataRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSData *data, NSError *error) {
            if (error != nil || data.length == 0) return;   // 单张失败静默跳过
            UIImage *image = [UIImage imageWithData:data];
            if (image == nil) return;
            [IMImageAttachment prepareWithImage:image name:suggestedName limits:limits completion:^(IMImageAttachment *attachment, NSString *failureReason) {
                __strong typeof(weakSelf) self = weakSelf;
                if (self == nil || attachment == nil) return;
                if ([self remainingImageSlots] <= 0) return;
                [self.pendingImages addObject:attachment];
                [self.composer setAttachments:self.pendingImages];
            }];
        }];
    }
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSURL *imageURL = info[UIImagePickerControllerImageURL];
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (![image isKindOfClass:UIImage.class]) return;

    NSInteger maxCount = self.imageLimits.maxCount > 0 ? self.imageLimits.maxCount : (NSInteger)[IMImageAttachment maxCount];
    if ((NSInteger)self.pendingImages.count >= maxCount) return;

    NSString *name = [imageURL isKindOfClass:NSURL.class] ? imageURL.lastPathComponent : nil;
    __weak typeof(self) weakSelf = self;
    // 缩图 + 重编码 + base64 都在后台串行队列，主线程只等结果。
    [IMImageAttachment prepareWithImage:image name:name limits:self.imageLimits completion:^(IMImageAttachment *attachment, NSString *failureReason) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (attachment == nil) {
            [self showSendFailure:failureReason.length > 0 ? failureReason : @"这张图片无法添加"];
            return;
        }
        if ((NSInteger)self.pendingImages.count >= maxCount) return;
        [self.pendingImages addObject:attachment];
        [self.composer setAttachments:self.pendingImages];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)composerViewDidTapStop:(IMComposerView *)composer {
    __weak typeof(self) weakSelf = self;
    [self.service cancelRunningTurnWithCompletion:^(NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (error != nil) {
            [self showSendFailure:[IMChatService messageForError:error]];
            return;
        }
        self.transcript.running = NO;
        [self updateComposerState];
    }];
}

- (void)showSendFailure:(NSString *)message {
    self.pairingBar.hidden = NO;
    self.pairingBarHeight.constant = 26;
    [self.pairingBar setText:[NSString stringWithFormat:@"%@（点此重试）", message] isError:YES];

    __weak typeof(self) weakSelf = self;
    self.pairingBar.onTap = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.pairingBar.hidden = YES;
        self.pairingBarHeight.constant = 0;
        if (self.pendingRetryText.length > 0 || self.pendingImages.count > 0) {
            [self.composer restoreText:self.pendingRetryText];
            [self composerViewDidTapSend:self.composer];
        }
    };
}

@end
