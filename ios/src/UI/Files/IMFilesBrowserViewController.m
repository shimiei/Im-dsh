//
//  IMFilesBrowserViewController.m
//  IMDSH — 工作区文件树页
//
//  为什么列表页自己管作用域：文件属于「某个会话的工作区」，作用域是这一页的全局状态，
//  把它放在树页而不是宿主页，才能让 iPad 的左右两列各自独立、也让下拉胶囊和面包屑就近。
//

#import "IMFilesBrowserViewController.h"

#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"
#import "IMServerStore.h"
#import "files-IMFileKind.h"
#import "files-IMFilesSkeletonView.h"

NSNotificationName const IMFilesDidRequestOpenInSessionNotification = @"IMFilesDidRequestOpenInSessionNotification";
NSString *const IMFilesNotificationScopeIdKey = @"scopeId";
NSString *const IMFilesNotificationPathKey = @"path";
NSString *const IMFilesNotificationResourceAddressKey = @"resourceAddress";

/// 上次选中的会话（记住作用域，避免每次进文件页都从第一项开始找）。
static NSString * const IMScopeDefaultsKey = @"IMFilesLastScopeSessionId";
static const CGFloat IMRowHeight = 58.0;

#pragma mark - 行

@interface IMFilesRowCell : UITableViewCell
@property (nonatomic, strong) UIView *iconContainer;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIImageView *chevronView;
- (void)configureWithEntry:(IMFilesEntry *)entry;
@end

@implementation IMFilesRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        IMTheme *theme = IMTheme.shared;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        UIView *selected = [[UIView alloc] init];
        selected.backgroundColor = theme.backgroundLayer2;
        self.selectedBackgroundView = selected;

        _iconContainer = [[UIView alloc] init];
        _iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
        _iconContainer.layer.cornerRadius = 10;
        _iconContainer.layer.cornerCurve = kCACornerCurveContinuous;
        [self.contentView addSubview:_iconContainer];

        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconContainer addSubview:_iconView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [IMTheme fontBody];
        _nameLabel.textColor = theme.labelPrimary;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_nameLabel];

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailLabel.font = [IMTheme fontFootnote];
        _detailLabel.textColor = theme.labelTertiary;
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_detailLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_detailLabel];

        _chevronView = [[UIImageView alloc] init];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.image = IMSymbol(@"chevron.right", 11, UIImageSymbolWeightSemibold);
        _chevronView.tintColor = theme.labelDimmed;
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_chevronView];

        [NSLayoutConstraint activateConstraints:@[
            [_iconContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_iconContainer.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconContainer.widthAnchor constraintEqualToConstant:34],
            [_iconContainer.heightAnchor constraintEqualToConstant:34],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconContainer.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconContainer.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:19],
            [_iconView.heightAnchor constraintEqualToConstant:19],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconContainer.trailingAnchor constant:12],
            [_nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-8],

            [_detailLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_detailLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:1],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],

            [_chevronView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_chevronView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:10],
        ]];
    }
    return self;
}

- (void)configureWithEntry:(IMFilesEntry *)entry {
    IMFileKind kind = entry.isDirectory ? IMFileKindDirectory : IMFileKindForName(entry.name);
    UIColor *color = IMFileKindColor(kind);
    self.iconView.image = IMSymbol(IMFileKindSymbol(kind), 17, UIImageSymbolWeightRegular);
    self.iconView.tintColor = color;
    self.iconContainer.backgroundColor = [color colorWithAlphaComponent:0.14];

    self.nameLabel.text = entry.name;

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (entry.isDirectory) {
        [parts addObject:@"文件夹"];
    } else {
        if (entry.hasSize) [parts addObject:IMFileSizeString(entry.size, YES)];
        if (entry.modifiedAt != nil) [parts addObject:IMRelativeTimeString(entry.modifiedAt)];
        if (parts.count == 0) [parts addObject:IMFileKindDisplayName(kind)];
        if (entry.type == IMFilesEntryTypeOther) [parts addObject:@"可能无法打开"];
    }
    self.detailLabel.text = [parts componentsJoinedByString:@" · "];
    self.chevronView.hidden = !entry.isDirectory;
    self.accessibilityLabel = entry.name;
}

@end

#pragma mark - 页面

@interface IMFilesBrowserViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSString *scopeId;
@property (nonatomic, copy) NSString *currentPath;
@property (nonatomic, copy, nullable) NSString *sessionTitle;

@property (nonatomic, strong) IMGlassBar *topBar;
@property (nonatomic, strong) IMGlassButton *scopeButton;
@property (nonatomic, strong) IMGlassButton *refreshButton;
@property (nonatomic, strong) UIScrollView *breadcrumbScrollView;
@property (nonatomic, strong) UIStackView *breadcrumbStack;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) IMFilesSkeletonView *skeletonView;

@property (nonatomic, strong) UIView *stateView;
@property (nonatomic, strong) UIImageView *stateIconView;
@property (nonatomic, strong) UILabel *stateTitleLabel;
@property (nonatomic, strong) UILabel *stateDetailLabel;
@property (nonatomic, strong) IMGlassButton *stateActionButton;

@property (nonatomic, copy) NSArray<IMFilesSession *> *sessions;
@property (nonatomic, strong, nullable) IMFilesListing *listing;

@property (nonatomic) BOOL loadingSessions;
@property (nonatomic) BOOL loadingListing;
@property (nonatomic, copy, nullable) NSString *watchStreamId;
@property (nonatomic, strong, nullable) NSTimer *watchTimer;
/// 状态按钮点下去要做什么（重试 / 刷新会话 / 去设置）。文案可变，语义不能靠文案猜。
@property (nonatomic) SEL stateActionTarget;
/// 配对状态观察者（吊销/重新配对后要重判，并丢掉旧会话与旧目录）。
@property (nonatomic, strong, nullable) id storeObserverToken;
/// 上次处理过的「主机 + token」签名：一次配对会连发好几条通知，签名没变就不重复拉。
@property (nonatomic, copy, nullable) NSString *lastPairingSignature;

@end

@implementation IMFilesBrowserViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _scopeId = @"";
        _currentPath = @"";
        _sessions = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    IMTheme *theme = IMTheme.shared;
    self.view.backgroundColor = theme.backgroundBase;
    self.title = @"文件";
    [self buildInterface];
    self.lastPairingSignature = [self pairingSignature];

    // 配对状态会在设置里被改（吊销本机 / 重新配对 / 换主机）：
    // 收到通知就重判一次——没配对给「去设置」引导，配好了自动重拉文件树。
    __weak typeof(self) weakSelf = self;
    self.storeObserverToken = [NSNotificationCenter.defaultCenter addObserverForName:IMServerStoreDidChangeNotification
                                                                             object:nil
                                                                              queue:NSOperationQueue.mainQueue
                                                                         usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) self = weakSelf;
        [self handleServerStoreChange];
    }];

    [self reloadForCurrentHost];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.sessions.count == 0 && !self.loadingSessions) {
        [self reloadForCurrentHost];
        return;
    }
    // 上次的目录请求没成（配对/会话就绪晚一步、或请求被拒）就补一次：
    // 否则那一次静默失败会一直留着一张空表，直到用户手动下拉刷新。
    if (self.listing == nil && self.scopeId.length > 0 && !self.loadingListing && !self.loadingSessions) {
        [self reloadListing];
        return;
    }
    [self startWatchingCurrentPath];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 离开就停 watch：目录监听在后台继续跑纯属浪费主机资源。
    [self stopWatching];
}

- (void)dealloc {
    [self.watchTimer invalidate];
    if (self.storeObserverToken != nil) {
        [NSNotificationCenter.defaultCenter removeObserver:self.storeObserverToken];
        self.storeObserverToken = nil;
    }
}

#pragma mark - 配对状态

/// 按当前主机状态决定显示什么：没主机 / 没配对 / 正常加载。
- (void)reloadForCurrentHost {
    IMFilesService *service = IMFilesService.shared;
    if (!service.hasServer) {
        [self showStateIcon:@"bolt.slash"
                      title:@"还没连接主机"
                     detail:@"到「设置」里配对一台 DSH 主机后，这里会列出它的工作区文件。"
                 actionText:nil
               actionTarget:NULL];
        return;
    }
    if (!service.isPaired) {
        [self showUnpairedState];
        return;
    }
    [self loadSessionsThenReload];
}

/// 未配对（token 被吊销 / 主机被移除）：给「去设置」的引导，而不是一句 401。
- (void)showUnpairedState {
    self.loadingSessions = NO;
    self.loadingListing = NO;
    [self stopWatching];
    self.scopeId = @"";
    self.listing = nil;
    self.sessions = @[];
    self.scopeButton.menu = nil;
    [self updateScopePill];
    [self.tableView reloadData];
    [self showStateIcon:@"iphone.and.arrow.forward"
                  title:@"这台主机还没配对"
                 detail:@"请在设置里重新配对后再浏览文件"
             actionText:@"去设置"
           actionTarget:@selector(goToSettings)];
}

- (void)handleServerStoreChange {
    // 一次配对/吊销会连发多条通知（persist + currentServer 各发一次），
    // 签名没变就说明配对状态其实没变（例如只改了设备名），不必重拉。
    NSString *signature = [self pairingSignature];
    if ([signature isEqualToString:self.lastPairingSignature ?: @""]) return;
    self.lastPairingSignature = signature;

    [self stopWatching];
    // 不依赖通知到达顺序：先扔掉旧客户端（旧 token），再按新状态重判。
    [IMFilesService.shared discardClient];
    self.loadingSessions = NO;
    self.loadingListing = NO;
    self.sessions = @[];
    self.listing = nil;
    self.scopeButton.menu = nil;
    [self.tableView reloadData];
    [self reloadForCurrentHost];
}

- (void)goToSettings {
    UITabBarController *tabs = self.tabBarController;
    if (tabs != nil && tabs.viewControllers.count > 2) {
        tabs.selectedIndex = 2;
        return;
    }
    IMShowToast(self.view, @"请到「设置」里重新配对这台主机");
}

/// 配对状态指纹：主机标识 + 设备 token + 地址。任何一个变了才算「配对变了」。
- (NSString *)pairingSignature {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil) return @"none";
    return [NSString stringWithFormat:@"%@|%@|%@",
            server.identifier ?: @"", server.deviceToken ?: @"", server.baseURLString ?: @""];
}

#pragma mark - 界面

- (void)buildInterface {
    IMTheme *theme = IMTheme.shared;

    self.topBar = [[IMGlassBar alloc] initWithStyle:IMGlassStyleRegular];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topBar];

    self.scopeButton = [IMGlassButton buttonWithTitle:@"当前会话" systemImage:@"chevron.down" prominent:NO];
    [self.scopeButton addTarget:self action:@selector(scopeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scopeButton setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.topBar.stackView addArrangedSubview:self.scopeButton];

    UIView *spacer = [[UIView alloc] init];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.topBar.stackView addArrangedSubview:spacer];

    self.refreshButton = [IMGlassButton iconButtonWithSystemImage:@"arrow.clockwise" diameter:36];
    self.refreshButton.accessibilityLabel = @"刷新（长按可在会话中打开）";
    [self.refreshButton addTarget:self action:@selector(refreshTapped) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(refreshLongPressed:)];
    longPress.minimumPressDuration = 0.45;
    [self.refreshButton addGestureRecognizer:longPress];
    [self.topBar.stackView addArrangedSubview:self.refreshButton];

    // ── 面包屑
    self.breadcrumbScrollView = [[UIScrollView alloc] init];
    self.breadcrumbScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.breadcrumbScrollView.showsHorizontalScrollIndicator = NO;
    self.breadcrumbScrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.breadcrumbScrollView];

    self.breadcrumbStack = [[UIStackView alloc] init];
    self.breadcrumbStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.breadcrumbStack.axis = UILayoutConstraintAxisHorizontal;
    self.breadcrumbStack.spacing = 4;
    self.breadcrumbStack.alignment = UIStackViewAlignmentCenter;
    [self.breadcrumbScrollView addSubview:self.breadcrumbStack];

    // ── 列表
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = theme.separatorColor;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 62, 0, 16);
    self.tableView.rowHeight = IMRowHeight;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.tableView registerClass:IMFilesRowCell.class forCellReuseIdentifier:@"IMFilesRowCell"];
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    // ── 骨架 / 状态
    self.skeletonView = [[IMFilesSkeletonView alloc] initWithFrame:CGRectZero];
    self.skeletonView.translatesAutoresizingMaskIntoConstraints = NO;
    self.skeletonView.hidden = YES;
    [self.view addSubview:self.skeletonView];

    self.stateView = [[UIView alloc] init];
    self.stateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateView.hidden = YES;
    [self.view addSubview:self.stateView];

    self.stateIconView = [[UIImageView alloc] init];
    self.stateIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.stateIconView.tintColor = theme.labelTertiary;

    self.stateTitleLabel = [[UILabel alloc] init];
    self.stateTitleLabel.font = [IMTheme fontHeadline];
    self.stateTitleLabel.textColor = theme.labelPrimary;
    self.stateTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.stateTitleLabel.numberOfLines = 2;

    self.stateDetailLabel = [[UILabel alloc] init];
    self.stateDetailLabel.font = [IMTheme fontCallout];
    self.stateDetailLabel.textColor = theme.labelSecondary;
    self.stateDetailLabel.textAlignment = NSTextAlignmentCenter;
    self.stateDetailLabel.numberOfLines = 0;

    self.stateActionButton = [IMGlassButton buttonWithTitle:@"重试" systemImage:@"arrow.clockwise" prominent:YES];
    [self.stateActionButton addTarget:self action:@selector(stateActionTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stateStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.stateIconView, self.stateTitleLabel, self.stateDetailLabel, self.stateActionButton]];
    stateStack.translatesAutoresizingMaskIntoConstraints = NO;
    stateStack.axis = UILayoutConstraintAxisVertical;
    stateStack.alignment = UIStackViewAlignmentCenter;
    stateStack.spacing = theme.spacingM;
    [self.stateView addSubview:stateStack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],

        [self.breadcrumbScrollView.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor constant:8],
        [self.breadcrumbScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [self.breadcrumbScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [self.breadcrumbScrollView.heightAnchor constraintEqualToConstant:30],

        [self.breadcrumbStack.topAnchor constraintEqualToAnchor:self.breadcrumbScrollView.contentLayoutGuide.topAnchor],
        [self.breadcrumbStack.bottomAnchor constraintEqualToAnchor:self.breadcrumbScrollView.contentLayoutGuide.bottomAnchor],
        [self.breadcrumbStack.leadingAnchor constraintEqualToAnchor:self.breadcrumbScrollView.contentLayoutGuide.leadingAnchor],
        [self.breadcrumbStack.trailingAnchor constraintEqualToAnchor:self.breadcrumbScrollView.contentLayoutGuide.trailingAnchor],
        [self.breadcrumbStack.heightAnchor constraintEqualToAnchor:self.breadcrumbScrollView.frameLayoutGuide.heightAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:self.breadcrumbScrollView.bottomAnchor constant:6],
        [self.tableView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [self.skeletonView.topAnchor constraintEqualToAnchor:self.tableView.topAnchor constant:16],
        [self.skeletonView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.skeletonView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.stateView.topAnchor constraintEqualToAnchor:self.tableView.topAnchor],
        [self.stateView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.stateView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stateView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [stateStack.centerYAnchor constraintEqualToAnchor:self.stateView.centerYAnchor constant:-30],
        [stateStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.stateView.leadingAnchor constant:28],
        [stateStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateView.trailingAnchor constant:-28],
        [stateStack.widthAnchor constraintLessThanOrEqualToConstant:400],
        [self.stateIconView.widthAnchor constraintEqualToConstant:36],
        [self.stateIconView.heightAnchor constraintEqualToConstant:36],
    ]];

    [self rebuildBreadcrumb];
    [self updateScopePill];
}

#pragma mark - 数据加载

- (void)loadSessionsThenReload {
    if (self.loadingSessions) return;
    if (!IMFilesService.shared.isPaired) {
        [self reloadForCurrentHost];
        return;
    }
    self.loadingSessions = YES;
    [self showSkeletonWithCaption:@"正在读取会话…"];

    __weak typeof(self) weakSelf = self;
    [IMFilesService.shared loadSessionsWithCompletion:^(NSArray<IMFilesSession *> *sessions, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.loadingSessions = NO;
        [self.skeletonView stopAnimating];
        self.skeletonView.hidden = YES;
        [self.refreshControl endRefreshing];

        if (error != nil) {
            [self showStateForError:error];
            return;
        }

        self.sessions = sessions ?: @[];
        NSString *wanted = self.scopeId.length > 0 ? self.scopeId : [NSUserDefaults.standardUserDefaults stringForKey:IMScopeDefaultsKey];
        IMFilesSession *picked = nil;
        for (IMFilesSession *candidate in self.sessions) {
            if (wanted.length > 0 && [candidate.sessionId isEqualToString:wanted]) {
                picked = candidate;
                break;
            }
        }
        if (picked == nil) picked = self.sessions.firstObject;

        if (picked == nil) {
            self.scopeId = @"";
            [self updateScopePill];
            [self.tableView reloadData];
            [self showStateIcon:@"bubble.left.and.slash"
                          title:@"没有可用的会话"
                         detail:@"DSH 里还没有带工作目录的会话。先让它在某个项目目录里跑一次任务，再回来刷新。"
                     actionText:@"刷新会话列表"
                   actionTarget:@selector(loadSessionsThenReload)];
            return;
        }

        self.scopeId = picked.sessionId;
        self.sessionTitle = picked.displayName;
        [NSUserDefaults.standardUserDefaults setObject:picked.sessionId forKey:IMScopeDefaultsKey];
        [self updateScopePill];
        [self rebuildScopeMenu];

        // 换作用域后目录树必须从头来，否则会停在上一个会话的路径上。
        self.currentPath = @"";
        [self rebuildBreadcrumb];
        [self reloadListing];
    }];
}

- (void)reloadListing {
    if (self.loadingListing) return;
    if (self.scopeId.length == 0) {
        // 没有作用域就别发请求（主机一定回 gateway/lookup-failed）。但也不能直接 return：
        // 那会停在「骨架已收起 + 空表 + 无状态视图」，用户看到的就是一整页空白。
        [self.skeletonView stopAnimating];
        self.skeletonView.hidden = YES;
        [self.refreshControl endRefreshing];
        self.listing = nil;
        [self.tableView reloadData];
        [self showStateIcon:@"bubble.left.and.slash"
                      title:@"还没有选定会话工作区"
                     detail:@"文件树属于某个会话的工作目录。先在顶部胶囊里选一个会话，或刷新会话列表。"
                 actionText:@"刷新会话列表"
               actionTarget:@selector(loadSessionsThenReload)];
        return;
    }
    self.loadingListing = YES;

    BOOL hasVisibleContent = (self.listing.entries.count > 0);
    if (!hasVisibleContent) [self showSkeletonWithCaption:@"正在读取目录…"];

    __weak typeof(self) weakSelf = self;
    [IMFilesService.shared listDirectory:self.currentPath scopeId:self.scopeId completion:^(IMFilesListing *listing, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.loadingListing = NO;
        [self.skeletonView stopAnimating];
        self.skeletonView.hidden = YES;
        [self.refreshControl endRefreshing];

        if (error != nil) {
            self.listing = nil;
            [self.tableView reloadData];
            [self showStateForError:error];
            return;
        }

        self.listing = listing;
        [self.stateView setHidden:YES];
        [self.tableView reloadData];
        [self updateTableFooter];
        if (listing.entries.count == 0) {
            [self showStateIcon:@"folder"
                          title:@"这个目录是空的"
                         detail:[self currentPathDisplay].length > 0
                              ? [NSString stringWithFormat:@"「%@」里没有任何文件。", [self currentPathDisplay]]
                              : @"工作区根目录下没有任何文件。"
                     actionText:@"刷新"
                   actionTarget:@selector(reloadListing)];
        }
        [self startWatchingCurrentPath];
    }];
}

- (void)handlePullToRefresh {
    if (self.loadingListing || self.loadingSessions) {
        [self.refreshControl endRefreshing];
        return;
    }
    if (self.scopeId.length == 0) {
        // 没有作用域（未配对 / 没有会话）：下拉等于「按当前主机状态重判一次」，
        // 否则 reloadListing 会直接 return，转圈图标停不下来。
        [self.refreshControl endRefreshing];
        [self reloadForCurrentHost];
        return;
    }
    [self reloadListing];
}

- (void)refreshTapped {
    if (self.loadingListing || self.loadingSessions) {
        [self.refreshControl endRefreshing];
        return;
    }
    if (self.scopeId.length == 0) {
        [self.refreshControl endRefreshing];
        [self reloadForCurrentHost];
        return;
    }
    [self.refreshControl beginRefreshing];
    [self reloadListing];
}

- (void)reloadFromRoot {
    self.currentPath = @"";
    [self rebuildBreadcrumb];
    [self reloadListing];
}

- (void)applyScopeId:(NSString *)scopeId sessionTitle:(NSString *)title {
    if (scopeId.length == 0) return;
    self.scopeId = scopeId;
    self.sessionTitle = title;
    [NSUserDefaults.standardUserDefaults setObject:scopeId forKey:IMScopeDefaultsKey];
    [self updateScopePill];
    [self rebuildBreadcrumb];
    if (self.isViewLoaded) [self reloadListing];
}

#pragma mark - 会话作用域胶囊

- (void)updateScopePill {
    BOOL paired = IMFilesService.shared.isPaired;
    // 未配对时胶囊只是块死肉：不许点（否则会点出一个空菜单）。
    self.scopeButton.enabled = paired;
    NSString *title = @"选择会话";
    if (!paired) {
        title = @"未配对";
    } else if (self.scopeId.length > 0) {
        title = self.sessionTitle.length > 0 ? self.sessionTitle : @"当前会话";
    }
    if (title.length > 16) title = [[title substringToIndex:15] stringByAppendingString:@"…"];
    [self.scopeButton setButtonTitle:title systemImage:paired ? @"chevron.down" : nil];
}

- (void)rebuildScopeMenu {
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    NSUInteger limit = MIN(self.sessions.count, 24);
    for (NSUInteger index = 0; index < limit; index++) {
        IMFilesSession *session = self.sessions[index];
        UIAction *action = [UIAction actionWithTitle:session.displayName
                                               image:IMSymbol(@"bubble.left.and.bubble.right", 14, UIImageSymbolWeightRegular)
                                          identifier:nil
                                             handler:^(__kindof UIAction *selected) {
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) return;
            [self applyScopeId:session.sessionId sessionTitle:session.displayName];
        }];
        if (session.cwdTail.length > 0) action.subtitle = session.cwdTail;
        if ([session.sessionId isEqualToString:self.scopeId]) action.state = UIMenuElementStateOn;
        [items addObject:action];
    }
    if (items.count == 0) {
        [items addObject:[UIAction actionWithTitle:@"暂无可选会话" image:nil identifier:nil handler:^(__kindof UIAction *action) {}]];
    }
    [items addObject:[UIAction actionWithTitle:@"刷新会话列表"
                                          image:IMSymbol(@"arrow.clockwise", 14, UIImageSymbolWeightRegular)
                                     identifier:nil
                                        handler:^(__kindof UIAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self loadSessionsThenReload];
    }]];

    self.scopeButton.menu = [UIMenu menuWithTitle:@"会话作用域" children:items];
    self.scopeButton.showsMenuAsPrimaryAction = YES;
}

- (void)scopeButtonTapped {
    // showsMenuAsPrimaryAction 已经接管点击；这里只是兜底（例如菜单被系统收走时）。
    if (self.scopeButton.menu == nil) [self rebuildScopeMenu];
}

#pragma mark - 面包屑

- (NSString *)currentPathDisplay {
    return self.currentPath ?: @"";
}

- (void)rebuildBreadcrumb {
    IMStackRemoveAllArrangedSubviews(self.breadcrumbStack);
    IMTheme *theme = IMTheme.shared;

    NSArray<NSString *> *components = [IMFilesService pathComponentsForWorkspacePath:self.currentPath];
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithObject:@"工作区"];
    [titles addObjectsFromArray:components];

    for (NSUInteger index = 0; index < titles.count; index++) {
        BOOL isLast = (index == titles.count - 1);
        UIButton *crumb = [UIButton buttonWithType:UIButtonTypeSystem];
        crumb.translatesAutoresizingMaskIntoConstraints = NO;
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = titles[index];
        config.contentInsets = NSDirectionalEdgeInsetsMake(4, 10, 4, 10);
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.baseForegroundColor = isLast ? theme.labelPrimary : theme.accentColor;
        config.background.backgroundColor = isLast ? theme.backgroundLayer3 : UIColor.clearColor;
        config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
            NSMutableDictionary *out = [attrs mutableCopy];
            out[NSFontAttributeName] = [IMTheme fontCaption];
            return out;
        };
        crumb.configuration = config;
        crumb.tag = (NSInteger)index;
        // 最后一段是「当前位置」，不该可点，但也要保持正常颜色——
        // 用 userInteractionEnabled 而不是 enabled（后者会把文字压暗，看着像禁用功能）。
        crumb.userInteractionEnabled = !isLast;
        if (!isLast) {
            [crumb addTarget:self action:@selector(crumbTapped:) forControlEvents:UIControlEventTouchUpInside];
        }
        [self.breadcrumbStack addArrangedSubview:crumb];

        if (!isLast) {
            UILabel *separator = [[UILabel alloc] init];
            separator.text = @"/";
            separator.font = [IMTheme fontCaption];
            separator.textColor = theme.labelDimmed;
            [separator setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [separator setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [self.breadcrumbStack addArrangedSubview:separator];
        }
    }
    // 面包屑只做导航，不需要横向压缩：放不下就让 scrollView 横滑。
    [self.breadcrumbScrollView setContentOffset:CGPointMake(MAX(0, self.breadcrumbStack.bounds.size.width - self.breadcrumbScrollView.bounds.size.width), 0) animated:NO];
}

- (void)crumbTapped:(UIButton *)sender {
    NSUInteger index = (NSUInteger)MAX(0, sender.tag);
    if (index == 0) {
        [self navigateToPath:@""];
        return;
    }
    NSArray<NSString *> *components = [IMFilesService pathComponentsForWorkspacePath:self.currentPath];
    NSUInteger count = MIN(index, components.count);
    NSArray<NSString *> *prefix = count > 0 ? [components subarrayWithRange:NSMakeRange(0, count)] : @[];
    [self navigateToPath:[prefix componentsJoinedByString:@"/"]];
}

- (void)navigateToPath:(NSString *)path {
    self.currentPath = path ?: @"";
    [self rebuildBreadcrumb];
    [self reloadListing];
}

#pragma mark - 状态视图

- (void)showSkeletonWithCaption:(NSString *)caption {
    self.stateView.hidden = YES;
    self.skeletonView.captionLabel.text = caption.length > 0 ? caption : @"正在读取…";
    self.skeletonView.hidden = NO;
    [self.skeletonView startAnimating];
}

- (void)showStateIcon:(NSString *)symbol
                title:(NSString *)title
               detail:(nullable NSString *)detail
           actionText:(nullable NSString *)actionText
         actionTarget:(nullable SEL)action {
    [self.skeletonView stopAnimating];
    self.skeletonView.hidden = YES;
    IMTheme *theme = IMTheme.shared;
    self.stateIconView.image = IMSymbol(symbol, 30, UIImageSymbolWeightRegular);
    self.stateIconView.tintColor = theme.labelTertiary;
    self.stateTitleLabel.text = title;
    self.stateDetailLabel.text = detail ?: @"";
    self.stateDetailLabel.hidden = detail.length == 0;
    if (actionText.length > 0 && action != NULL) {
        self.stateActionTarget = action;
        self.stateActionButton.hidden = NO;
        [self.stateActionButton setButtonTitle:actionText systemImage:nil];
    } else {
        self.stateActionTarget = NULL;
        self.stateActionButton.hidden = YES;
    }
    self.stateView.hidden = NO;
}

- (void)showStateForError:(NSError *)error {
    [self showStateIcon:@"exclamationmark.triangle"
                  title:[IMFilesService messageForError:error]
                 detail:[IMFilesService detailForError:error]
             actionText:@"重试"
           actionTarget:@selector(stateRetryTapped)];
}

- (void)stateRetryTapped {
    if (self.sessions.count == 0) {
        [self loadSessionsThenReload];
        return;
    }
    [self reloadListing];
}

- (void)stateActionTapped {
    // 语义在 showStateIcon 里就定了（重试 / 刷新会话 / 去设置），不靠按钮文案反推。
    SEL target = self.stateActionTarget;
    if (target == NULL) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self performSelector:target];
#pragma clang diagnostic pop
}

#pragma mark - 表

- (void)updateTableFooter {
    if (self.listing.truncated) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
        label.text = @"目录项太多，只显示了前 2000 项";
        label.font = [IMTheme fontFootnote];
        label.textColor = IMTheme.shared.labelTertiary;
        label.textAlignment = NSTextAlignmentCenter;
        self.tableView.tableFooterView = label;
    } else {
        self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 8)];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.listing.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    IMFilesRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"IMFilesRowCell" forIndexPath:indexPath];
    if (indexPath.row < (NSInteger)self.listing.entries.count) {
        [cell configureWithEntry:self.listing.entries[(NSUInteger)indexPath.row]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.listing.entries.count) return;
    IMFilesEntry *entry = self.listing.entries[(NSUInteger)indexPath.row];

    if (entry.isDirectory) {
        [self navigateToPath:entry.path];
        return;
    }
    if (self.onOpenEntry != nil) {
        self.onOpenEntry(entry, self.scopeId);
    }
}

#pragma mark - 在会话中打开

- (void)refreshLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    NSString *address = [IMFilesService resourceAddressForScopeId:self.scopeId path:self.currentPath];
    NSString *title = [self currentPath].length > 0 ? [self currentPathDisplay] : @"工作区根目录";

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"在会话中打开"
                                                                  message:address
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"复制「%@」的地址", title]
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self copyResourceAddressAndNotify:address];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.refreshButton;
    sheet.popoverPresentationController.sourceRect = self.refreshButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)copyResourceAddressAndNotify:(NSString *)address {
    // 为什么复制地址而不是直接跳聊天：文件域不拥有聊天页，硬跳会把两个域耦死。
    // 复制 dsh-resource 地址后用户粘到会话里即可被 DSH 解析成文件引用；
    // 同时广播通知，聊天域想接管输入框预填时自己监听。
    NSDictionary *userInfo = @{IMFilesNotificationScopeIdKey: self.scopeId ?: @"",
                               IMFilesNotificationPathKey: self.currentPath ?: @"",
                               IMFilesNotificationResourceAddressKey: address ?: @""};
    [NSNotificationCenter.defaultCenter postNotificationName:IMFilesDidRequestOpenInSessionNotification
                                                      object:self
                                                    userInfo:userInfo];
    // IMCopyText 顺带负责「写剪贴板 + 玻璃提示」，别再自己写一份。
    IMCopyText(address, self.view, @"已复制文件地址，粘贴到会话即可引用");
}

#pragma mark - 目录变动监听

- (void)startWatchingCurrentPath {
    [self stopWatching];
    if (self.scopeId.length == 0) return;
    if (self.view.window == nil) return;   // 不在屏上就别订阅

    NSString *streamId = [NSString stringWithFormat:@"files-watch-%@", NSUUID.UUID.UUIDString];
    self.watchStreamId = streamId;
    __weak typeof(self) weakSelf = self;
    [IMFilesService.shared watchPath:self.currentPath
                             scopeId:self.scopeId
                            streamId:streamId
                            onChange:^{
        __strong typeof(weakSelf) self = weakSelf;
        [self scheduleWatchRefresh];
    }
                             onError:^(NSError *error) {
        // 主机不支持 watch（workspace-file/watch-unsupported）时静默降级：
        // 用户还有下拉刷新和右上角刷新按钮，不该为此弹错误。
    }];
}

- (void)stopWatching {
    [self.watchTimer invalidate];
    self.watchTimer = nil;
    if (self.watchStreamId.length > 0) {
        [IMFilesService.shared stopWatching:self.watchStreamId];
        self.watchStreamId = nil;
    }
}

- (void)scheduleWatchRefresh {
    [self.watchTimer invalidate];
    __weak typeof(self) weakSelf = self;
    // 去抖 1.2s：编辑器保存一次会连发好几个 change 帧。
    self.watchTimer = [NSTimer scheduledTimerWithTimeInterval:1.2 repeats:NO block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (self.view.window == nil) return;
        [self reloadListing];
    }];
}

@end
