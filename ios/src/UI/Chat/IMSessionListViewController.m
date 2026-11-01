//
//  IMSessionListViewController.m
//  IMDSH — 会话列表
//

#import "IMSessionListViewController.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"
#import "IMChatService.h"
#import "IMServerStore.h"

#pragma mark - 行

/// 路径尾段（Windows 反斜杠也要认）。
static NSString *IMPathTail(NSString *path);

@interface IMSessionRowCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIView *runningDot;
- (void)configureWithRow:(IMSessionRow *)row;
@end

@interface IMSessionRowCell ()
@property (nonatomic, strong) NSLayoutConstraint *indentConstraint;
@property (nonatomic, strong) NSLayoutConstraint *badgeWidthConstraint;
@end

@implementation IMSessionRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        IMTheme *theme = IMTheme.shared;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectedBackgroundView = [[UIView alloc] init];
        self.selectedBackgroundView.backgroundColor = theme.backgroundLayer2;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _titleLabel.textColor = theme.labelPrimary;
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _badgeLabel = [[UILabel alloc] init];
        _badgeLabel.font = [IMTheme fontCaption];
        _badgeLabel.textColor = theme.labelTertiary;
        _badgeLabel.text = @"子会话";
        _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_badgeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_badgeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _runningDot = [[UIView alloc] init];
        _runningDot.translatesAutoresizingMaskIntoConstraints = NO;
        _runningDot.layer.cornerRadius = 3.5;
        _runningDot.backgroundColor = theme.accentColor;
        _runningDot.hidden = YES;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [IMTheme fontFootnote];
        _subtitleLabel.textColor = theme.labelTertiary;
        _subtitleLabel.numberOfLines = 1;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self.contentView addSubview:_runningDot];
        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_badgeLabel];
        [self.contentView addSubview:_subtitleLabel];

        _indentConstraint = [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:theme.spacingL];
        _badgeWidthConstraint = [_badgeLabel.widthAnchor constraintEqualToConstant:0];

        [NSLayoutConstraint activateConstraints:@[
            _indentConstraint,
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_badgeLabel.leadingAnchor constant:-6],

            [_badgeLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_badgeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-theme.spacingL],
            _badgeWidthConstraint,

            [_runningDot.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_runningDot.trailingAnchor constraintLessThanOrEqualToAnchor:_badgeLabel.leadingAnchor constant:-6],
            [_runningDot.widthAnchor constraintEqualToConstant:7],
            [_runningDot.heightAnchor constraintEqualToConstant:7],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-theme.spacingL],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)configureWithRow:(IMSessionRow *)row {
    IMTheme *theme = IMTheme.shared;
    self.titleLabel.text = [row displayTitle];

    // 子会话：缩进 + 弱化，和父会话区分开。
    self.indentConstraint.constant = row.isSubagent ? theme.spacingXL + theme.spacingS : theme.spacingL;
    self.titleLabel.textColor = row.isSubagent ? theme.labelSecondary : theme.labelPrimary;
    self.titleLabel.font = [UIFont systemFontOfSize:row.isSubagent ? 14 : 15 weight:row.isSubagent ? UIFontWeightRegular : UIFontWeightSemibold];
    self.badgeLabel.hidden = !row.isSubagent;
    self.badgeWidthConstraint.constant = row.isSubagent ? 42 : 0;

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (row.updatedAt > 0) [parts addObject:IMRelativeTimeString([NSDate dateWithTimeIntervalSince1970:row.updatedAt])];
    if (row.tokenCount > 0) [parts addObject:[NSString stringWithFormat:@"%@ tokens", IMTokenCountString(row.tokenCount)]];
    if (row.cwd.length > 0) [parts addObject:IMPathTail(row.cwd)];
    self.subtitleLabel.text = [parts componentsJoinedByString:@" · "];

    self.runningDot.hidden = !row.running;
    if (row.running) {
        [self.runningDot.layer removeAnimationForKey:@"imdsh.breath"];
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = @(1.0);
        animation.toValue = @(0.25);
        animation.duration = 1.1;
        animation.autoreverses = YES;
        animation.repeatCount = HUGE_VALF;
        [self.runningDot.layer addAnimation:animation forKey:@"imdsh.breath"];
    }
}

/// 路径尾段（Windows 反斜杠也要认）。
static NSString *IMPathTail(NSString *path) {
    NSString *trimmed = [path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"]];
    NSRange slash = [trimmed rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"] options:NSBackwardsSearch];
    return slash.location == NSNotFound ? trimmed : [trimmed substringFromIndex:NSMaxRange(slash)];
}

@end

#pragma mark - 列表

@interface IMSessionListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *stateView;
@property (nonatomic, strong) UIImageView *stateIconView;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) IMGlassButton *stateButton;

@property (nonatomic, strong) IMChatService *service;
@property (nonatomic, strong) NSMutableArray<IMSessionRow *> *rows;
/// 搜索命中的行（未搜索时等于 rows）。
@property (nonatomic, strong) NSArray<IMSessionRow *> *filteredRows;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy, nullable) NSString *nextCursor;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL loadingMore;
/// 配对签名（identifier|token|baseURL）：没变就不重建列表，避免设置页写时间戳把整表刷掉。
@property (nonatomic, copy, nullable) NSString *lastPairingSignature;
/// 上次成功拉列表的时间，回前台时用它判断数据是否还新。
@property (nonatomic, assign) NSTimeInterval lastReloadTime;
/// noteSessionActivity 的合并刷新标记。
@property (nonatomic, assign) BOOL activityRefreshScheduled;
@property (nonatomic, copy, nullable) NSString *loadErrorText;
@property (nonatomic, assign) BOOL needsPairing;
@end

@implementation IMSessionListViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _rows = [NSMutableArray array];
        _service = [[IMChatService alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    IMTheme *theme = IMTheme.shared;
    self.title = @"会话";
    self.view.backgroundColor = theme.backgroundBase;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 62;
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, theme.spacingXL, 0);
    [self.tableView registerClass:IMSessionRowCell.class forCellReuseIdentifier:@"IMSessionRowCell"];
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(handleRefresh) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];

    [self buildStateView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:IMSymbol(@"arrow.clockwise", 15, UIImageSymbolWeightSemibold)
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(handleRefresh)];

    [self buildSearchController];
    [self startControlStream];
    [self reloadSessions];
    [self startObserving];
}

#pragma mark - 搜索

- (void)buildSearchController {
    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.searchResultsUpdater = self;
    searchController.delegate = self;
    // 结果直接落在本表里：不要遮罩，否则打字时看不到列表。
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchBar.placeholder = @"搜索会话";
    searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchController = searchController;

    self.navigationItem.searchController = searchController;
    // 桌面端搜索框常驻在大标题下方，不随滚动收起。
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (BOOL)isFiltering {
    return self.searchController.isActive;
}

- (NSArray<IMSessionRow *> *)visibleRows {
    return [self isFiltering] ? self.filteredRows : self.rows;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilterWithQuery:searchController.searchBar.text];
}

- (void)didDismissSearchController:(UISearchController *)searchController {
    [self applyFilterWithQuery:nil];
}

- (void)applyFilterWithQuery:(nullable NSString *)query {
    NSString *keyword = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (keyword.length == 0) {
        self.filteredRows = self.rows;
    } else {
        NSMutableArray<IMSessionRow *> *matches = [NSMutableArray array];
        for (IMSessionRow *row in self.rows) {
            // 标题 + cwd 尾段本地过滤；数据本来就都在 session/list 里，不需要远程搜索接口。
            NSString *title = [row displayTitle] ?: @"";
            NSString *cwdTail = row.cwd.length > 0 ? IMPathTail(row.cwd) : @"";
            if ([title localizedCaseInsensitiveContainsString:keyword] ||
                [cwdTail localizedCaseInsensitiveContainsString:keyword]) {
                [matches addObject:row];
            }
        }
        self.filteredRows = matches;
    }
    [self.tableView reloadData];
    [self updateStateView];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.service stopControlStream];
}

- (void)startObserving {
    self.lastPairingSignature = [self currentPairingSignature];
    // 配对状态变了必须重来：客户端是按主机 + token 建的。
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleServerStoreChange) name:IMServerStoreDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
}

/// 配对签名：主机 + token + baseURL。没变就没必要时重建（设置页一进来就会 updateServer 写时间戳）。
- (NSString *)currentPairingSignature {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil) return @"";
    return [NSString stringWithFormat:@"%@|%@|%@",
            server.identifier ?: @"",
            server.deviceToken ?: @"",
            server.baseURLString ?: @""];
}

- (void)handleServerStoreChange {
    NSString *signature = [self currentPairingSignature];
    if (self.lastPairingSignature != nil && [self.lastPairingSignature isEqualToString:signature]) return;
    self.lastPairingSignature = signature;
    [self resetAndReload];
}

- (void)handleDidBecomeActive {
    // 回前台可能只是切换了一下 App：签名没变且数据还新，就别整表重建（会丢游标、跳滚动位置）。
    NSString *signature = [self currentPairingSignature];
    BOOL signatureChanged = (self.lastPairingSignature == nil) || ![self.lastPairingSignature isEqualToString:signature];
    BOOL stale = (self.lastReloadTime <= 0) || (NSDate.date.timeIntervalSince1970 - self.lastReloadTime > 60);
    if (!signatureChanged && !stale) return;
    self.lastPairingSignature = signature;
    [self resetAndReload];
}

- (void)resetAndReload {
    self.isLoading = NO;
    self.nextCursor = nil;
    self.needsPairing = !self.service.isPaired;
    [self startControlStream];
    [self reloadSessions];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.rows.count == 0 && !self.isLoading) [self reloadSessions];
}

#pragma mark - 状态视图

- (void)buildStateView {
    IMTheme *theme = IMTheme.shared;
    self.stateView = [[UIView alloc] init];
    self.stateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateView.hidden = YES;
    [self.view addSubview:self.stateView];

    self.stateIconView = [[UIImageView alloc] initWithImage:IMSymbol(@"bubble.left.and.bubble.right", 32, UIImageSymbolWeightRegular)];
    self.stateIconView.tintColor = theme.labelDimmed;
    self.stateIconView.translatesAutoresizingMaskIntoConstraints = NO;

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.font = [IMTheme fontCallout];
    self.stateLabel.textColor = theme.labelSecondary;
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    self.stateLabel.numberOfLines = 0;
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.stateButton = [IMGlassButton buttonWithTitle:@"重试" systemImage:nil prominent:NO];
    self.stateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateButton addTarget:self action:@selector(stateButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.stateIconView, self.stateLabel, self.stateButton]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = theme.spacingM;
    [self.stateView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.stateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.stateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
        [self.stateView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:theme.spacingXL],
        [self.stateView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-theme.spacingXL],
        [stack.topAnchor constraintEqualToAnchor:self.stateView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.stateView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.stateView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.stateView.bottomAnchor],
        [self.stateLabel.widthAnchor constraintLessThanOrEqualToConstant:320],
    ]];
}

- (void)updateStateView {
    BOOL filtering = [self isFiltering];
    BOOL showsState = [self visibleRows].count == 0;
    self.stateView.hidden = !showsState;
    if (!showsState) return;

    if (filtering) {
        // 搜索框激活时只可能是"没搜到"，不要把配对/加载状态挤出来。
        self.stateIconView.image = IMSymbol(@"magnifyingglass", 32, UIImageSymbolWeightRegular);
        self.stateLabel.text = @"没有匹配的会话";
        self.stateButton.hidden = YES;
        return;
    }

    if (self.needsPairing) {
        self.stateIconView.image = IMSymbol(@"link.badge.plus", 32, UIImageSymbolWeightRegular);
        self.stateLabel.text = @"还没有配对的主机。\n在设置页填入 DSH 的地址和配对码即可。";
        [self.stateButton setButtonTitle:@"去设置" systemImage:@"gearshape"];
        self.stateButton.hidden = NO;
    } else if (self.loadErrorText.length > 0) {
        self.stateIconView.image = IMSymbol(@"exclamationmark.triangle", 32, UIImageSymbolWeightRegular);
        self.stateLabel.text = self.loadErrorText;
        [self.stateButton setButtonTitle:@"重试" systemImage:nil];
        self.stateButton.hidden = NO;
    } else if (self.isLoading) {
        self.stateIconView.image = IMSymbol(@"hourglass", 32, UIImageSymbolWeightRegular);
        self.stateLabel.text = @"正在读取会话…";
        self.stateButton.hidden = YES;
    } else {
        self.stateIconView.image = IMSymbol(@"bubble.left.and.bubble.right", 32, UIImageSymbolWeightRegular);
        self.stateLabel.text = @"还没有会话。\n在 DSH 里发起一次对话后，这里就会出现。";
        [self.stateButton setButtonTitle:@"刷新" systemImage:nil];
        self.stateButton.hidden = NO;
    }
}

- (void)stateButtonTapped {
    if (self.needsPairing) {
        if (self.onRequirePairing) self.onRequirePairing();
        return;
    }
    [self reloadSessions];
}

#pragma mark - 数据

- (void)reloadSessions {
    if (self.isLoading) return;
    self.isLoading = YES;

    if (!self.service.isPaired) {
        self.isLoading = NO;
        self.needsPairing = YES;
        [self.refreshControl endRefreshing];
        [self updateStateView];
        return;
    }
    self.needsPairing = NO;

    __weak typeof(self) weakSelf = self;
    [self.service loadSessionsWithCursor:nil completion:^(NSArray<IMSessionRow *> *rows, NSString *nextCursor, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.isLoading = NO;
        [self.refreshControl endRefreshing];

        if (error != nil) {
            if ([IMChatService isUnauthorizedError:error]) {
                self.needsPairing = YES;
                self.loadErrorText = nil;
            } else {
                self.loadErrorText = [IMChatService messageForError:error];
            }
            [self.tableView reloadData];
            [self updateStateView];
            return;
        }

        self.loadErrorText = nil;
        self.nextCursor = nextCursor;
        self.lastReloadTime = NSDate.date.timeIntervalSince1970;
        [self applyRows:rows ?: @[]];
        [self updateStateView];
    }];
}

- (void)applyRows:(NSArray<IMSessionRow *> *)rows {
    // 运行中的会话置顶，其余按更新时间倒序；搜索过滤沿用同一顺序。
    NSArray<IMSessionRow *> *sorted = [rows sortedArrayUsingComparator:^NSComparisonResult(IMSessionRow *lhs, IMSessionRow *rhs) {
        if (lhs.running != rhs.running) return lhs.running ? NSOrderedAscending : NSOrderedDescending;
        if (lhs.updatedAt == rhs.updatedAt) return [lhs.sessionId compare:rhs.sessionId];
        return lhs.updatedAt > rhs.updatedAt ? NSOrderedAscending : NSOrderedDescending;
    }];
    [self.rows setArray:sorted];

    if ([self isFiltering]) {
        [self applyFilterWithQuery:self.searchController.searchBar.text];
    } else {
        self.filteredRows = self.rows;
        [self.tableView reloadData];
    }
}

- (void)handleRefresh {
    [self reloadSessions];
}

- (void)noteSessionActivity:(NSString *)sessionId {
    NSUInteger index = [self.rows indexOfObjectPassingTest:^BOOL(IMSessionRow *row, NSUInteger idx, BOOL *stop) {
        return [row.sessionId isEqualToString:sessionId];
    }];
    if (index == NSNotFound) return;
    self.rows[index].updatedAt = [NSDate date].timeIntervalSince1970;

    // 一条消息会带来多帧事件：合并成一次刷新，否则 iPad 双列同屏时列表疯狂跳动、点不中行。
    if (self.activityRefreshScheduled) return;
    self.activityRefreshScheduled = YES;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.activityRefreshScheduled = NO;
        if ([self isFiltering]) {
            // 正在搜索：只更新模型，别在打字期间重排列表。
            [self applyFilterWithQuery:self.searchController.searchBar.text];
            return;
        }
        [self applyRows:self.rows];
    });
}

- (void)loadMoreIfNeeded {
    if ([self isFiltering]) return;   // 搜索期间不翻页，结果只来自本地过滤
    if (self.nextCursor.length == 0 || self.loadingMore || self.isLoading) return;
    self.loadingMore = YES;
    NSString *cursor = self.nextCursor;
    __weak typeof(self) weakSelf = self;
    [self.service loadSessionsWithCursor:cursor completion:^(NSArray<IMSessionRow *> *rows, NSString *nextCursor, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.loadingMore = NO;
        if (error != nil) return;
        self.nextCursor = nextCursor;
        NSMutableArray *merged = [self.rows mutableCopy];
        [merged addObjectsFromArray:rows ?: @[]];
        [self applyRows:merged];
    }];
}

#pragma mark - 投影流（实时标题 / 用量）

- (void)startControlStream {
    __weak typeof(self) weakSelf = self;
    [self.service startControlStreamWithHandler:^(NSString *sessionId, NSString *key, id value) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (![key isEqualToString:@"title"] && ![key isEqualToString:@"tokenUsage"] && ![key isEqualToString:@"sessionListMetadata"]) return;

        NSUInteger index = [self.rows indexOfObjectPassingTest:^BOOL(IMSessionRow *row, NSUInteger idx, BOOL *stop) {
            return [row.sessionId isEqualToString:sessionId];
        }];
        if (index == NSNotFound) return;

        IMSessionRow *row = self.rows[index];
        if ([key isEqualToString:@"title"] && [value isKindOfClass:NSString.class]) {
            if ([row.title isEqualToString:value]) return;
            row.title = value;
        } else if ([key isEqualToString:@"tokenUsage"] && [value isKindOfClass:NSDictionary.class]) {
            // 投影值可能是 null：直接 integerValue 会在 NSNull 上抛 unrecognized selector。
            id rawInput = ((NSDictionary *)value)[@"uncachedInputTokens"];
            id rawOutput = ((NSDictionary *)value)[@"outputTokens"];
            NSInteger input = [rawInput isKindOfClass:NSNumber.class] ? [(NSNumber *)rawInput integerValue] : 0;
            NSInteger output = [rawOutput isKindOfClass:NSNumber.class] ? [(NSNumber *)rawOutput integerValue] : 0;
            if (row.tokenCount == input + output) return;
            row.tokenCount = input + output;
        } else {
            return;
        }

        NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
        // 正在输入搜索词时不动表格：焦点与列表 diff 分开处理，避免打断打字。
        if ([self isFiltering]) return;
        if ([[self.tableView indexPathsForVisibleRows] containsObject:path]) {
            [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
        }
    }];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self visibleRows].count;
}

- (nullable IMSessionRow *)rowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<IMSessionRow *> *rows = [self visibleRows];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count) return nil;
    return rows[(NSUInteger)indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMSessionRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"IMSessionRowCell" forIndexPath:indexPath];
    IMSessionRow *row = [self rowAtIndexPath:indexPath];
    if (row != nil) [cell configureWithRow:row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IMSessionRow *row = [self rowAtIndexPath:indexPath];
    if (row == nil) return;
    self.selectedSessionId = row.sessionId;
    if ([self.delegate respondsToSelector:@selector(sessionListViewController:didSelectRow:)]) {
        [self.delegate sessionListViewController:self didSelectRow:row];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.contentOffset.y > scrollView.contentSize.height - scrollView.bounds.size.height - 240) {
        [self loadMoreIfNeeded];
    }
}

@end
