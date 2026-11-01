//
//  IMSessionListViewController.m
//  IMDSH — 会话列表（按项目分组 / 折叠 / 显示更多 / 搜索扁平化）
//
//  数据形状：session/list 一次返回 475 条，其中 382 条是 subagent 子会话（服务层已过滤），
//  剩下的 89 条顶层会话分布在 19 个 cwd 里，最大的项目占 49 条。扁平列表既长又难找，
//  所以这里做三件事：
//    1) 按 projectKey（cwd 原值）分组，每组一个吸顶表头；
//    2) 表头可点折叠，折叠状态按 projectKey 持久化到 NSUserDefaults；
//    3) 每组默认只放 5 条，超出部分收进「显示更多（还有 N 条）」，点一次 +10 条。
//  搜索激活时切回扁平结果：分组 + 折叠会把命中项藏起来，等于没搜到。
//
//  表结构：非搜索态 section = 分组；搜索态 section = 1（扁平）。
//  行的位置（首/中/末）决定卡片圆角，同组多行拼成一张连续卡片。
//

#import "IMSessionListViewController.h"
#import "IMSessionListCells.h"
#import "IMSessionGroupHeaderView.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"
#import "IMChatService.h"
#import "IMServerStore.h"

#pragma mark - 常量

/// 每组默认展示条数。
static const NSInteger IMSessionListDefaultVisibleCount = 5;
/// 点一次「显示更多」多展示几条。
static const NSInteger IMSessionListShowMoreStep = 10;
/// 吸顶表头高度。
static const CGFloat IMSessionListGroupHeaderHeight = 40;
/// 折叠状态持久化：外层 key 固定，内层 key 就是 projectKey（cwd 原值，空串 = 未知项目）。
static NSString * const IMSessionListCollapsedDefaultsKey = @"imdsh.session.list.collapsedProjects";
static NSString * const IMSessionListRowCellIdentifier = @"IMSessionListRowCell";
static NSString * const IMSessionListMoreCellIdentifier = @"IMSessionListShowMoreCell";

#pragma mark - 列表

@interface IMSessionListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>

// 视图
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *stateView;
@property (nonatomic, strong) UIImageView *stateIconView;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) IMGlassButton *stateButton;
/// iPad / 宽屏时把列表收窄，避免拉成一条超宽行。
@property (nonatomic, strong) NSLayoutConstraint *tableWidthCapConstraint;

// 数据
@property (nonatomic, strong) IMChatService *service;
/// 全部顶层会话（权威顺序：运行中置顶，其余 updatedAt 倒序）。
@property (nonatomic, strong) NSMutableArray<IMSessionRow *> *rows;
/// 分组结果（非搜索态用；组内 updatedAt 倒序、组间按最新时间倒序）。
@property (nonatomic, strong) NSArray<IMSessionGroup *> *groups;
/// 搜索命中的行（扁平，不分组、不折叠）。
@property (nonatomic, strong) NSArray<IMSessionRow *> *filteredRows;
/// projectKey → 当前每组展示条数（内存，不持久化）。
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *visibleCounts;
/// projectKey → 折叠标记（持久化到 NSUserDefaults）。
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *collapsedProjects;

// 搜索 / 分页 / 状态
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
        _groups = @[];
        _filteredRows = @[];
        _visibleCounts = [NSMutableDictionary dictionary];
        _collapsedProjects = [NSMutableDictionary dictionary];
        _service = [[IMChatService alloc] init];
        [self loadCollapsedState];
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
    // 分组表头自己带高度，关掉系统给分组补的额外上间距，避免组与组之间空一大块。
    self.tableView.estimatedSectionHeaderHeight = 0;
    self.tableView.sectionFooterHeight = 0;
    self.tableView.sectionHeaderTopPadding = 0;
    self.tableView.contentInset = UIEdgeInsetsMake(theme.spacingS, 0, theme.spacingXL, 0);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:IMSessionListRowCell.class forCellReuseIdentifier:IMSessionListRowCellIdentifier];
    [self.tableView registerClass:IMSessionListShowMoreCell.class forCellReuseIdentifier:IMSessionListMoreCellIdentifier];
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(handleRefresh) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];

    [self buildStateView];

    // 宽度上限：iPhone / iPad 分栏里不生效，整屏 iPad 时把列表收窄并居中。
    NSLayoutConstraint *leading = [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor];
    leading.priority = UILayoutPriorityRequired - 1;
    NSLayoutConstraint *trailing = [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor];
    trailing.priority = UILayoutPriorityRequired - 1;
    self.tableWidthCapConstraint = [self.tableView.widthAnchor constraintLessThanOrEqualToConstant:[theme maxContentWidthForSize:self.view.bounds.size]];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        self.tableWidthCapConstraint,
        leading,
        trailing,
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

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGFloat cap = [IMTheme.shared maxContentWidthForSize:self.view.bounds.size];
    if (cap > 0 && fabs(self.tableWidthCapConstraint.constant - cap) > 0.5) {
        self.tableWidthCapConstraint.constant = cap;
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.service stopControlStream];
}

#pragma mark - 折叠状态持久化

- (void)loadCollapsedState {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:IMSessionListCollapsedDefaultsKey];
    if (![stored isKindOfClass:NSDictionary.class]) return;
    // 存的是 {projectKey: @YES}；读回来只认字符串 key + 数字 value，别的直接丢掉。
    for (id key in (NSDictionary *)stored) {
        if (![key isKindOfClass:NSString.class]) continue;
        id value = ((NSDictionary *)stored)[key];
        if (![value isKindOfClass:NSNumber.class]) continue;
        if ([(NSNumber *)value boolValue]) self.collapsedProjects[(NSString *)key] = @YES;
    }
}

- (void)persistCollapsedState {
    [NSUserDefaults.standardUserDefaults setObject:[self.collapsedProjects copy] forKey:IMSessionListCollapsedDefaultsKey];
}

- (BOOL)isProjectCollapsed:(NSString *)projectKey {
    NSNumber *flag = self.collapsedProjects[projectKey ?: @""];
    return flag.boolValue;
}

- (void)setProjectCollapsed:(BOOL)collapsed forKey:(NSString *)projectKey {
    NSString *key = projectKey ?: @"";
    if (collapsed) {
        self.collapsedProjects[key] = @YES;
    } else {
        [self.collapsedProjects removeObjectForKey:key];
    }
    [self persistCollapsedState];
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
            // 标题 + 项目名 + 完整 cwd 本地过滤；数据本来就都在 session/list 里，不需要远程搜索接口。
            NSString *title = [row displayTitle] ?: @"";
            NSString *projectName = row.projectName ?: @"";
            NSString *cwd = row.cwd ?: @"";
            if ([title localizedCaseInsensitiveContainsString:keyword] ||
                [projectName localizedCaseInsensitiveContainsString:keyword] ||
                [cwd localizedCaseInsensitiveContainsString:keyword]) {
                [matches addObject:row];
            }
        }
        self.filteredRows = matches;
    }
    [self.tableView reloadData];
    [self updateStateView];
}

#pragma mark - 通知

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

/// 有内容可看 = 有会话（分组折叠成只剩表头也算有内容，此时不该弹空态）。
- (BOOL)hasListContent {
    return [self isFiltering] ? self.filteredRows.count > 0 : self.rows.count > 0;
}

- (void)updateStateView {
    BOOL filtering = [self isFiltering];
    BOOL showsState = ![self hasListContent];
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
    }];
}

- (void)applyRows:(NSArray<IMSessionRow *> *)rows {
    // 运行中的会话置顶，其余按更新时间倒序；分组内部再由 IMSessionGroup 按 updatedAt 倒序。
    NSArray<IMSessionRow *> *sorted = [rows sortedArrayUsingComparator:^NSComparisonResult(IMSessionRow *lhs, IMSessionRow *rhs) {
        if (lhs.running != rhs.running) return lhs.running ? NSOrderedAscending : NSOrderedDescending;
        if (lhs.updatedAt == rhs.updatedAt) return [lhs.sessionId compare:rhs.sessionId];
        return lhs.updatedAt > rhs.updatedAt ? NSOrderedAscending : NSOrderedDescending;
    }];
    [self.rows setArray:sorted];

    [self rebuildGroups];

    if ([self isFiltering]) {
        [self applyFilterWithQuery:self.searchController.searchBar.text];
    } else {
        self.filteredRows = self.rows;
        [self.tableView reloadData];
        [self updateStateView];
    }
}

/// 重建分组，并把持久化的折叠状态贴回去（分组对象每次都是新的）。
- (void)rebuildGroups {
    NSArray<IMSessionGroup *> *groups = [IMSessionGroup groupsFromRows:self.rows];
    for (IMSessionGroup *group in groups) {
        group.collapsed = [self isProjectCollapsed:group.projectKey];
    }
    self.groups = groups;
}

- (void)handleRefresh {
    [self reloadSessions];
}

- (void)noteSessionActivity:(NSString *)sessionId {
    IMSessionRow *row = [self rowWithSessionId:sessionId];
    if (row == nil) return;
    row.updatedAt = [NSDate date].timeIntervalSince1970;

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

#pragma mark - 分组辅助

- (nullable IMSessionRow *)rowWithSessionId:(NSString *)sessionId {
    if (sessionId.length == 0) return nil;
    NSUInteger index = [self.rows indexOfObjectPassingTest:^BOOL(IMSessionRow *row, NSUInteger idx, BOOL *stop) {
        return [row.sessionId isEqualToString:sessionId];
    }];
    return index == NSNotFound ? nil : self.rows[index];
}

- (nullable IMSessionGroup *)groupAtSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.groups.count) return nil;
    return self.groups[(NSUInteger)section];
}

- (NSInteger)sectionForProjectKey:(NSString *)projectKey {
    for (NSInteger index = 0; index < (NSInteger)self.groups.count; index++) {
        if ([self.groups[(NSUInteger)index].projectKey isEqualToString:projectKey]) return index;
    }
    return -1;
}

/// 该组当前展示多少条（默认 5，点「显示更多」+10，上限是组内总数）。
- (NSInteger)visibleCountForGroup:(IMSessionGroup *)group {
    NSNumber *stored = self.visibleCounts[group.projectKey ?: @""];
    NSInteger wanted = stored != nil ? stored.integerValue : IMSessionListDefaultVisibleCount;
    if (wanted < IMSessionListDefaultVisibleCount) wanted = IMSessionListDefaultVisibleCount;
    NSInteger total = (NSInteger)group.rows.count;
    return wanted > total ? total : wanted;
}

/// 只有超过默认条数的组才需要末尾那一行「显示更多 / 收起」。
- (BOOL)groupHasMoreRow:(IMSessionGroup *)group {
    return (NSInteger)group.rows.count > IMSessionListDefaultVisibleCount;
}

- (NSInteger)runningCountForGroup:(IMSessionGroup *)group {
    NSInteger running = 0;
    for (IMSessionRow *row in group.rows) {
        if (row.running) running++;
    }
    return running;
}

- (NSInteger)numberOfRowsForSection:(NSInteger)section {
    if ([self isFiltering]) return (NSInteger)self.filteredRows.count;
    IMSessionGroup *group = [self groupAtSection:section];
    if (group == nil || group.collapsed) return 0;
    return [self visibleCountForGroup:group] + ([self groupHasMoreRow:group] ? 1 : 0);
}

/// 行在卡片里的位置：首行圆上角、末行圆下角、中间直角，整组拼成一张卡片。
- (IMSessionListCellPosition)positionForIndexPath:(NSIndexPath *)indexPath {
    NSInteger rowCount = [self numberOfRowsForSection:indexPath.section];
    if (rowCount <= 1) return IMSessionListCellPositionSingle;
    if (indexPath.row <= 0) return IMSessionListCellPositionTop;
    if (indexPath.row >= rowCount - 1) return IMSessionListCellPositionBottom;
    return IMSessionListCellPositionMiddle;
}

/// 该行是不是「显示更多 / 收起」那一行。
- (BOOL)isShowMoreIndexPath:(NSIndexPath *)indexPath {
    if ([self isFiltering]) return NO;
    IMSessionGroup *group = [self groupAtSection:indexPath.section];
    if (group == nil || group.collapsed) return NO;
    if (![self groupHasMoreRow:group]) return NO;
    return indexPath.row == [self visibleCountForGroup:group];
}

- (nullable IMSessionRow *)rowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isFiltering]) {
        if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.filteredRows.count) return nil;
        return self.filteredRows[(NSUInteger)indexPath.row];
    }
    IMSessionGroup *group = [self groupAtSection:indexPath.section];
    if (group == nil || group.collapsed) return nil;
    if (indexPath.row < 0 || indexPath.row >= [self visibleCountForGroup:group]) return nil;
    if (indexPath.row >= (NSInteger)group.rows.count) return nil;
    return group.rows[(NSUInteger)indexPath.row];
}

/// 会话行当前所在的 indexPath；被折叠或被「显示更多」藏起来时返回 nil。
- (nullable NSIndexPath *)indexPathForRow:(IMSessionRow *)row {
    if ([self isFiltering]) {
        NSUInteger index = [self.filteredRows indexOfObjectIdenticalTo:row];
        if (index == NSNotFound) return nil;
        return [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
    }
    for (NSInteger section = 0; section < (NSInteger)self.groups.count; section++) {
        IMSessionGroup *group = self.groups[(NSUInteger)section];
        if (group.collapsed) continue;
        NSUInteger index = [group.rows indexOfObjectIdenticalTo:row];
        if (index == NSNotFound) continue;
        if ((NSInteger)index >= [self visibleCountForGroup:group]) return nil;
        return [NSIndexPath indexPathForRow:(NSInteger)index inSection:section];
    }
    return nil;
}

#pragma mark - 折叠 / 显示更多

/// 点表头：折叠或展开一个项目。行用批量插入/删除，箭头同时旋转。
- (void)toggleGroupWithKey:(NSString *)projectKey {
    NSInteger section = [self sectionForProjectKey:projectKey];
    if (section < 0) return;
    IMSessionGroup *group = self.groups[(NSUInteger)section];
    BOOL collapsing = !group.collapsed;

    // 折叠前后要增删的行数（与折叠状态无关，只跟展示条数有关）。
    NSInteger rowCount = [self visibleCountForGroup:group] + ([self groupHasMoreRow:group] ? 1 : 0);

    group.collapsed = collapsing;
    [self setProjectCollapsed:collapsing forKey:projectKey];

    UIView *header = [self.tableView headerViewForSection:section];
    if ([header isKindOfClass:IMSessionGroupHeaderView.class]) {
        [(IMSessionGroupHeaderView *)header setCollapsed:collapsing animated:YES];
    }

    if (rowCount > 0) {
        NSMutableArray<NSIndexPath *> *paths = [NSMutableArray arrayWithCapacity:(NSUInteger)rowCount];
        for (NSInteger row = 0; row < rowCount; row++) {
            [paths addObject:[NSIndexPath indexPathForRow:row inSection:section]];
        }
        [self.tableView beginUpdates];
        if (collapsing) {
            [self.tableView deleteRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationFade];
        } else {
            [self.tableView insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationFade];
        }
        [self.tableView endUpdates];
    }
    [self updateStateView];
}

/// 点「显示更多」：+10 条；已经全展开时点「收起」：退回默认 5 条。
- (void)handleShowMoreAtSection:(NSInteger)section {
    IMSessionGroup *group = [self groupAtSection:section];
    if (group == nil) return;
    NSInteger total = (NSInteger)group.rows.count;
    NSInteger visible = [self visibleCountForGroup:group];
    NSInteger target;
    if (visible >= total) {
        target = MIN(IMSessionListDefaultVisibleCount, total);
    } else {
        target = MIN(total, visible + IMSessionListShowMoreStep);
    }
    if (target == visible) return;

    self.visibleCounts[group.projectKey ?: @""] = @(target);

    NSInteger delta = target - visible;
    NSInteger step = delta > 0 ? delta : -delta;
    NSMutableArray<NSIndexPath *> *paths = [NSMutableArray arrayWithCapacity:(NSUInteger)step];
    if (delta > 0) {
        for (NSInteger row = visible; row < target; row++) {
            [paths addObject:[NSIndexPath indexPathForRow:row inSection:section]];
        }
    } else {
        for (NSInteger row = target; row < visible; row++) {
            [paths addObject:[NSIndexPath indexPathForRow:row inSection:section]];
        }
    }

    [self.tableView beginUpdates];
    if (delta > 0) {
        [self.tableView insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.tableView deleteRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationFade];
    }
    [self.tableView endUpdates];

    // 首尾行换了：圆角要重算；「显示更多」那一行要换文案。
    [self refreshCardPositionsInSection:section];
    [self refreshShowMoreCellInSection:section];
}

- (void)refreshCardPositionsInSection:(NSInteger)section {
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
        if (path.section != section) continue;
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
        IMSessionListCellPosition position = [self positionForIndexPath:path];
        if ([cell isKindOfClass:IMSessionListRowCell.class]) {
            [(IMSessionListRowCell *)cell applyCardPosition:position];
        } else if ([cell isKindOfClass:IMSessionListShowMoreCell.class]) {
            [(IMSessionListShowMoreCell *)cell applyCardPosition:position];
        }
    }
}

- (void)refreshShowMoreCellInSection:(NSInteger)section {
    IMSessionGroup *group = [self groupAtSection:section];
    if (group == nil || group.collapsed || ![self groupHasMoreRow:group]) return;
    NSIndexPath *path = [NSIndexPath indexPathForRow:[self visibleCountForGroup:group] inSection:section];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
    if (![cell isKindOfClass:IMSessionListShowMoreCell.class]) return;
    NSInteger hidden = (NSInteger)group.rows.count - [self visibleCountForGroup:group];
    [(IMSessionListShowMoreCell *)cell configureWithHiddenCount:hidden position:[self positionForIndexPath:path]];
}

#pragma mark - 选中态

- (void)setSelectedSessionId:(nullable NSString *)selectedSessionId {
    _selectedSessionId = [selectedSessionId copy];
    [self refreshCurrentSessionAppearance];
}

- (void)refreshCurrentSessionAppearance {
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
        if (![cell isKindOfClass:IMSessionListRowCell.class]) continue;
        IMSessionRow *row = [self rowAtIndexPath:path];
        BOOL current = row != nil && self.selectedSessionId.length > 0 && [row.sessionId isEqualToString:self.selectedSessionId];
        [(IMSessionListRowCell *)cell setCurrentSession:current];
    }
}

#pragma mark - 投影流（实时标题 / 用量）

- (void)startControlStream {
    __weak typeof(self) weakSelf = self;
    [self.service startControlStreamWithHandler:^(NSString *sessionId, NSString *key, id value) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;

        BOOL isTitle = [key isEqualToString:@"title"];
        BOOL isUsage = [key isEqualToString:@"tokenUsage"];
        if (!isTitle && !isUsage) return;

        IMSessionRow *row = [self rowWithSessionId:sessionId];
        if (row == nil) return;

        if (isTitle) {
            // 投影值可能是 null：不校验类型直接当 NSString 用会撞 unrecognized selector。
            if (![value isKindOfClass:NSString.class]) return;
            if ([row.title isEqualToString:(NSString *)value]) return;
            row.title = (NSString *)value;
        } else {
            if (![value isKindOfClass:NSDictionary.class]) return;
            id rawInput = ((NSDictionary *)value)[@"uncachedInputTokens"];
            id rawOutput = ((NSDictionary *)value)[@"outputTokens"];
            NSInteger input = [rawInput isKindOfClass:NSNumber.class] ? [(NSNumber *)rawInput integerValue] : 0;
            NSInteger output = [rawOutput isKindOfClass:NSNumber.class] ? [(NSNumber *)rawOutput integerValue] : 0;
            if (row.tokenCount == input + output) return;
            row.tokenCount = input + output;
        }

        // 正在输入搜索词时不动表格：焦点与列表 diff 分开处理，避免打断打字。
        if ([self isFiltering]) return;
        NSIndexPath *path = [self indexPathForRow:row];
        if (path == nil) return;
        if (![[self.tableView indexPathsForVisibleRows] containsObject:path]) return;
        [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // 搜索态是扁平结果，只有一个 section（也就没有分组表头）。
    if ([self isFiltering]) return 1;
    return (NSInteger)self.groups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self numberOfRowsForSection:section];
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self isFiltering]) return nil;
    IMSessionGroup *group = [self groupAtSection:section];
    if (group == nil) return nil;

    IMSessionGroupHeaderView *header = [[IMSessionGroupHeaderView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, IMSessionListGroupHeaderHeight)];
    [header updateWithProjectName:group.projectName
                     sessionCount:(NSInteger)group.rows.count
                     runningCount:[self runningCountForGroup:group]
                        collapsed:group.collapsed
                         animated:NO];

    __weak typeof(self) weakSelf = self;
    NSString *key = group.projectKey ?: @"";
    header.onToggle = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self toggleGroupWithKey:key];
    };
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self isFiltering] ? 0 : IMSessionListGroupHeaderHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMSessionListCellPosition position = [self positionForIndexPath:indexPath];

    if ([self isShowMoreIndexPath:indexPath]) {
        IMSessionListShowMoreCell *cell = [tableView dequeueReusableCellWithIdentifier:IMSessionListMoreCellIdentifier forIndexPath:indexPath];
        IMSessionGroup *group = [self groupAtSection:indexPath.section];
        NSInteger visible = [self visibleCountForGroup:group];
        NSInteger hidden = (NSInteger)group.rows.count - visible;
        [cell configureWithHiddenCount:hidden position:position];
        return cell;
    }

    IMSessionListRowCell *cell = [tableView dequeueReusableCellWithIdentifier:IMSessionListRowCellIdentifier forIndexPath:indexPath];
    IMSessionRow *row = [self rowAtIndexPath:indexPath];
    BOOL current = row != nil && self.selectedSessionId.length > 0 && [row.sessionId isEqualToString:self.selectedSessionId];
    if (row != nil) {
        [cell configureWithRow:row position:position isCurrent:current];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([self isShowMoreIndexPath:indexPath]) {
        [self handleShowMoreAtSection:indexPath.section];
        return;
    }

    IMSessionRow *row = [self rowAtIndexPath:indexPath];
    if (row == nil) return;
    self.selectedSessionId = row.sessionId;
    if ([self.delegate respondsToSelector:@selector(sessionListViewController:didSelectRow:)]) {
        [self.delegate sessionListViewController:self didSelectRow:row];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // 分组后最后一屏可能凑不满一屏高度，光靠 scrollViewDidScroll 触发不到翻页。
    if ([self isFiltering]) return;
    if (indexPath.section != (NSInteger)self.groups.count - 1) return;
    NSInteger rowCount = [self numberOfRowsForSection:indexPath.section];
    if (rowCount > 0 && indexPath.row >= rowCount - 1) [self loadMoreIfNeeded];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.contentOffset.y > scrollView.contentSize.height - scrollView.bounds.size.height - 240) {
        [self loadMoreIfNeeded];
    }
}

@end
