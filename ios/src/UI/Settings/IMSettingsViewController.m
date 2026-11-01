//
//  IMSettingsViewController.m
//  IMDSH — 设置域入口
//

#import "IMSettingsViewController.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMServerStore.h"
#import "IMPairingService.h"
#import "IMAPIClient.h"

#import "IMSettingsCardView.h"
#import "IMSettingsRowView.h"
#import "IMServerSummaryView.h"
#import "IMSettingsPairingGateway.h"
#import "IMServerListViewController.h"
#import "IMServerDetailViewController.h"
#import "IMPairDeviceViewController.h"
#import "IMFormatting.h"
#import "IMPairingSheet.h"

@interface IMSettingsViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSLayoutConstraint *maxContentWidthConstraint;

// 主机侧数据：设备表 + 配对码表（一次请求同时拿到）
@property (nonatomic, strong) NSArray<IMPairingDevice *> *devices;
@property (nonatomic, strong) NSArray<IMPairingCodeRecord *> *codes;
@property (nonatomic, strong, nullable) NSError *inventoryError;
@property (nonatomic, assign) BOOL inventoryLoading;
@property (nonatomic, strong, nullable) IMSettingsCardView *devicesCard;
@property (nonatomic, strong, nullable) IMSettingsCardView *codesCard;

// 网关版本（ping 拿到才有）
@property (nonatomic, copy, nullable) NSString *gatewayVersion;
@property (nonatomic, assign) BOOL gatewayProbeRunning;
@property (nonatomic, weak, nullable) IMSettingsRowView *gatewayVersionRow;

@property (nonatomic, copy, nullable) NSString *observedServerIdentifier;
/// 自己刚触发过重建时，抑制「同一份数据」的那条通知，避免双次淡入。
/// 用状态签名而不是布尔量：通知是异步投递的，布尔标志会把随后一条无关变更（改名、吊销）一并吃掉，
/// 让设置页停在旧数据上。
@property (nonatomic, copy, nullable) NSString *suppressedStoreSignature;

@end

@implementation IMSettingsViewController

#pragma mark - 生命周期

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _devices = @[];
        _codes = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"设置";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.view.backgroundColor = IMTheme.shared.backgroundBase;

    [self buildHierarchy];

    // 添加主机放导航栏：没有任何主机时这是唯一入口，必须一眼可见。
    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithImage:IMSymbol(@"plus", 16, UIImageSymbolWeightSemibold)
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(presentAddHost)];
    addItem.accessibilityLabel = @"添加主机";
    self.navigationItem.rightBarButtonItem = addItem;

    self.observedServerIdentifier = IMServerStore.shared.currentServer.identifier;
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(serverStoreDidChange:)
                                              name:IMServerStoreDidChangeNotification
                                            object:nil];

    [self rebuildContentAnimated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 每次出现都取一次最新数据：从配对码页/详情页返回时列表可能已经变了。
    [self refreshAll];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat maxWidth = [IMTheme.shared maxContentWidthForSize:self.view.bounds.size];
    if (fabs(self.maxContentWidthConstraint.constant - maxWidth) > 0.5) {
        self.maxContentWidthConstraint.constant = maxWidth;
    }
}

#pragma mark - 骨架

- (void)buildHierarchy {
    IMTheme *theme = IMTheme.shared;

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = theme.labelTertiary;
    [self.refreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];
    // 必须挂成 scrollView.refreshControl：直接 addSubview: 只是把它塞成滚动视图的一个普通子视图，
    // 下拉刷新永远不触发（endRefreshing 也就失去意义），而它本身是个 UIControl ——
    // 当它铺在内容上方时会把那一带的点击整片吃掉。
    self.scrollView.refreshControl = self.refreshControl;
    // 行都是 UIControl：默认 delaysContentTouches 会把点击压后到手势判定结束，
    // 手指轻微位移就被 pan 手势取消，表现成「点了没反应」。
    self.scrollView.delaysContentTouches = NO;
    self.scrollView.canCancelContentTouches = YES;

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = theme.spacingL;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.contentStack];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    // 宽度：先尽量铺满（999），iPad 上再由 maxContentWidthForSize 收窄并居中（1000 优先）。
    NSLayoutConstraint *fillWidth = [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor
                                                                                  constant:-(theme.spacingL * 2)];
    fillWidth.priority = (UILayoutPriority)999;
    self.maxContentWidthConstraint = [self.contentStack.widthAnchor constraintLessThanOrEqualToConstant:[theme maxContentWidthForSize:self.view.bounds.size]];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:theme.spacingL],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-(theme.spacingXL + theme.spacingL)],
        [self.contentStack.centerXAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.centerXAnchor],

        fillWidth,
        self.maxContentWidthConstraint,
    ]];
}

#pragma mark - 内容重建

- (void)rebuildContentAnimated:(BOOL)animated {
    if (animated && self.contentStack.arrangedSubviews.count > 0) {
        // 切换主机、配对完成这类「内容整体变了」的场合：整块淡入淡出，比逐行增删稳。
        [UIView transitionWithView:self.contentStack
                          duration:0.24
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ [self buildContent]; }
                        completion:nil];
    } else {
        [self buildContent];
    }
}

- (void)buildContent {
    IMStackRemoveAllArrangedSubviews(self.contentStack);

    IMServerStore *store = IMServerStore.shared;
    IMServer *current = store.currentServer;
    __weak typeof(self) weakSelf = self;

    // 1. 当前主机
    IMServerSummaryView *summary = [IMServerSummaryView viewWithServer:current];
    summary.onTap = ^{ [weakSelf showCurrentHostDetail]; };
    [self.contentStack addArrangedSubview:summary];

    // 2. 其他主机（多机时提供一键切换）
    NSMutableArray<IMServer *> *others = [NSMutableArray array];
    for (IMServer *server in store.servers) {
        if (![server.identifier isEqualToString:current.identifier]) [others addObject:server];
    }
    if (others.count > 0) {
        IMSettingsCardView *card = [[IMSettingsCardView alloc] initWithTitle:@"其他主机"];
        for (IMServer *other in others) {
            IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:other.displayName systemImage:@"server.rack"];
            row.subtitle = other.baseURLString;
            row.valueText = other.hasToken ? @"切换" : @"需配对";
            row.valueColor = other.hasToken ? IMTheme.shared.accentColor : IMTheme.shared.warningColor;
            row.onTap = ^{ [weakSelf switchToServer:other]; };
            [card addRow:row];
        }
        [card setFooterText:@"切换后会话与文件会改为连接所选主机。"];
        [self.contentStack addArrangedSubview:card];
        [self.contentStack setCustomSpacing:IMTheme.shared.spacingM afterView:self.contentStack.arrangedSubviews.lastObject];
    }

    // 3. 本机设备
    [self.contentStack addArrangedSubview:[self buildLocalDeviceCard]];

    // 4. 主机上已配对的设备
    self.devicesCard = [[IMSettingsCardView alloc] initWithTitle:@"主机上已配对的设备"];
    [self.contentStack addArrangedSubview:self.devicesCard];
    [self rebuildDevicesSection];

    // 5. 配对码（未使用 / 已使用 / 已过期·已作废）
    self.codesCard = [[IMSettingsCardView alloc] initWithTitle:@"配对码"];
    [self.contentStack addArrangedSubview:self.codesCard];
    [self rebuildCodesSection];

    // 6. 配对与主机
    [self.contentStack addArrangedSubview:[self buildPairingCard]];

    // 7. 关于
    [self.contentStack addArrangedSubview:[self buildAboutCard]];
}

#pragma mark - 各分区

- (IMSettingsCardView *)buildLocalDeviceCard {
    __weak typeof(self) weakSelf = self;

    IMSettingsCardView *card = [[IMSettingsCardView alloc] initWithTitle:@"本机设备"];

    IMSettingsRowView *nameRow = [IMSettingsRowView rowWithTitle:@"设备名称" systemImage:@"iphone.gen3"];
    nameRow.valueText = [IMDeviceIdentity deviceName];
    nameRow.accessory = IMSettingsRowAccessoryChevron;
    nameRow.onTap = ^{ [weakSelf promptRenameDevice]; };
    [card addRow:nameRow];

    NSString *deviceId = [IMDeviceIdentity deviceId];
    IMSettingsRowView *idRow = [IMSettingsRowView rowWithTitle:@"设备 ID" systemImage:@"number"];
    idRow.valueText = deviceId.length > 8 ? [deviceId substringToIndex:8] : deviceId;
    idRow.monospacedValue = YES;
    idRow.subtitle = @"长按可复制完整 ID";
    idRow.copyableText = deviceId;
    [card addRow:idRow];

    // 平台标识写死为 ios（服务端按它判别客户端类型），这里把系统版本一起展示。
    IMSettingsRowView *platformRow = [IMSettingsRowView rowWithTitle:@"平台" systemImage:@"cpu"];
    platformRow.valueText = [IMSettingsPairingGateway platformDisplayNameForText:[IMDeviceIdentity platform]];
    platformRow.subtitle = [IMDeviceIdentity defaultDeviceName];
    [card addRow:platformRow];

    [card setFooterText:@"设备名在配对时上报给主机，改名只影响本机显示。"];
    return card;
}

- (IMSettingsCardView *)buildPairingCard {
    IMServerStore *store = IMServerStore.shared;
    IMServer *current = store.currentServer;
    __weak typeof(self) weakSelf = self;

    IMSettingsCardView *card = [[IMSettingsCardView alloc] initWithTitle:@"配对与主机"];

    IMSettingsRowView *manageRow = [IMSettingsRowView rowWithTitle:@"主机管理" systemImage:@"list.bullet.rectangle"];
    manageRow.subtitle = store.servers.count > 0
        ? [NSString stringWithFormat:@"共 %lu 台，可重命名、删除、切换", (unsigned long)store.servers.count]
        : @"还没有添加主机";
    manageRow.accessory = IMSettingsRowAccessoryChevron;
    manageRow.onTap = ^{ [weakSelf showServerList]; };
    [card addRow:manageRow];

    IMSettingsRowView *codeRow = [IMSettingsRowView rowWithTitle:@"生成配对码" systemImage:@"qrcode"];
    IMSettingsRowView *addRow = [IMSettingsRowView rowWithTitle:@"添加主机" systemImage:@"plus.circle"];

    // 令牌缺失（例如本机授权被吊销）时，这一屏必须给出明确的恢复入口，
    // 否则用户回到会话/文件页只会看到「授权失效」而不知道往哪走。
    if (current != nil && !current.hasToken) {
        IMSettingsRowView *repairRow = [IMSettingsRowView rowWithTitle:@"重新配对这台主机" systemImage:@"key.badge.plus"];
        repairRow.subtitle = @"本机授权已失效，重新输入配对码即可恢复连接";
        repairRow.valueText = @"去配对";
        repairRow.valueColor = IMTheme.shared.accentColor;
        repairRow.accessory = IMSettingsRowAccessoryChevron;
        repairRow.onTap = ^{ [weakSelf presentAddHost]; };
        [card addRow:repairRow];
    }

    if (current.hasToken) {
        codeRow.subtitle = @"在本机生成一枚码，去另一台设备上输入";
        codeRow.accessory = IMSettingsRowAccessoryChevron;
        codeRow.onTap = ^{ [weakSelf showPairingCode]; };
    } else {
        codeRow.subtitle = current == nil ? @"需要先在主机上生成配对码" : @"这台主机还没完成配对";
        codeRow.enabled = NO;
    }
    [card addRow:codeRow];

    addRow.subtitle = @"输入新主机的地址与配对码";
    addRow.accessory = IMSettingsRowAccessoryChevron;
    addRow.onTap = ^{ [weakSelf presentAddHost]; };
    [card addRow:addRow];

    [card setFooterText:@"配对码一码一机、可在主机上随时吊销。"];
    return card;
}

- (IMSettingsCardView *)buildAboutCard {

    IMSettingsCardView *card = [[IMSettingsCardView alloc] initWithTitle:@"关于"];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;

    IMSettingsRowView *versionRow = [IMSettingsRowView rowWithTitle:@"版本" systemImage:@"tag"];
    versionRow.valueText = info[@"CFBundleShortVersionString"] ?: @"—";
    versionRow.monospacedValue = YES;
    [card addRow:versionRow];

    IMSettingsRowView *buildRow = [IMSettingsRowView rowWithTitle:@"构建号" systemImage:@"hammer"];
    buildRow.valueText = info[@"CFBundleVersion"] ?: @"—";
    buildRow.monospacedValue = YES;
    [card addRow:buildRow];

    IMSettingsRowView *gatewayRow = [IMSettingsRowView rowWithTitle:@"主机网关版本" systemImage:@"antenna.radiowaves.left.and.right"];
    gatewayRow.valueText = self.gatewayVersion ?: (self.gatewayProbeRunning ? @"检测中" : @"—");
    gatewayRow.monospacedValue = YES;
    self.gatewayVersionRow = gatewayRow;
    [card addRow:gatewayRow];

    [card setFooterText:@"IMDSH · 非官方 DSH 客户端。所有请求直连你本机的主机，不经过任何中转。"];
    return card;
}

#pragma mark - 已配对设备分区

- (void)rebuildDevicesSection {
    IMSettingsCardView *card = self.devicesCard;
    if (card == nil) return;

    [card clearContent];
    IMServer *server = IMServerStore.shared.currentServer;
    __weak typeof(self) weakSelf = self;

    if (server == nil) {
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"还没有添加主机" systemImage:@"server.rack"];
        row.subtitle = @"添加并配对一台主机后，这里会列出所有已授权的设备";
        row.accessory = IMSettingsRowAccessoryChevron;
        row.onTap = ^{ [weakSelf presentAddHost]; };
        [card addRow:row];
        [card setFooterText:nil];
        return;
    }

    if (!server.hasToken) {
        // 本机授权缺失（被吊销或从未取得）：这是「需要重新配对」，不是网络错误。
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"本机尚未获得授权" systemImage:@"key.slash"];
        row.subtitle = @"无法读取主机上的设备表。请在下方「重新配对这台主机」恢复连接。";
        row.subtitleLineLimit = 0;
        row.iconTintColor = IMTheme.shared.warningColor;
        row.valueText = @"重新配对";
        row.valueColor = IMTheme.shared.accentColor;
        row.onTap = ^{ [weakSelf presentAddHost]; };
        [card addRow:row];
        [card setFooterText:nil];
        return;
    }

    if (self.inventoryLoading && self.devices.count == 0) {
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"正在读取设备列表…" systemImage:@"arrow.triangle.2.circlepath"];
        row.accessory = IMSettingsRowAccessorySpinner;
        [row setAccessorySpinning:YES];
        [card addRow:row];
        [card setFooterText:nil];
        return;
    }

    if (self.inventoryError != nil && self.devices.count == 0) {
        // 失败不吞掉原因：把可读的错误和「重试」放在同一行上。
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"读取失败" systemImage:@"exclamationmark.triangle"];
        row.subtitle = [IMSettingsPairingGateway messageForError:self.inventoryError];
        row.subtitleLineLimit = 0;
        row.iconTintColor = IMTheme.shared.warningColor;
        row.valueText = @"重试";
        row.valueColor = IMTheme.shared.accentColor;
        row.userInteractionEnabled = YES;
        row.onTap = ^{ [weakSelf loadInventory]; };
        [card addRow:row];
        [card setFooterText:@"下拉也可以重新刷新。若持续失败，可能需要在主机上重新配对。"];
        return;
    }

    if (self.devices.count == 0) {
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"暂无已配对设备" systemImage:@"iphone.slash"];
        row.subtitle = @"在主机 DSH 设置页生成配对码，然后在本机输入即可授权";
        [card addRow:row];
        [card setFooterText:nil];
        return;
    }

    for (IMPairingDevice *device in self.devices) {
        [card addRow:[self rowForDevice:device server:server]];
    }
    [card setFooterText:@"吊销后该设备需要重新配对才能访问主机；本机被吊销会立即断开。"];
}

- (IMSettingsRowView *)rowForDevice:(IMPairingDevice *)device server:(IMServer *)server {
    __weak typeof(self) weakSelf = self;

    NSString *title = device.name.length > 0
        ? device.name
        : [NSString stringWithFormat:@"未命名设备 · %@", device.shortIdentifier];

    NSMutableArray<NSString *> *meta = [NSMutableArray array];
    [meta addObject:device.platformDisplayName];
    if (device.lastSeenAt != nil) {
        [meta addObject:[NSString stringWithFormat:@"最后活跃 %@", IMRelativeTimeString(device.lastSeenAt)]];
    } else if (device.pairedAt != nil) {
        [meta addObject:[NSString stringWithFormat:@"配对于 %@", IMRelativeTimeString(device.pairedAt)]];
    } else {
        [meta addObject:@"没有活跃记录"];
    }
    if (device.currentDevice) [meta insertObject:@"本机" atIndex:0];

    IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:title systemImage:device.currentDevice ? @"iphone.gen3" : @"iphone"];
    row.subtitle = [meta componentsJoinedByString:@" · "];
    row.iconTintColor = device.currentDevice ? IMTheme.shared.accentColor : IMTheme.shared.labelSecondary;
    if (device.currentDevice) {
        row.valueText = @"当前";
        row.valueColor = IMTheme.shared.accentColor;
    }

    // 用显式按钮而不是左滑：行内就有入口，且对 VoiceOver 可操作。
    IMGlassButton *revokeButton = [IMGlassButton iconButtonWithSystemImage:@"person.badge.minus" diameter:32];
    revokeButton.tintColor = IMTheme.shared.dangerColor;
    revokeButton.accessibilityLabel = [NSString stringWithFormat:@"吊销 %@", title];
    [revokeButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [weakSelf confirmRevokeDevice:device];
    }] forControlEvents:UIControlEventTouchUpInside];
    row.trailingAccessoryView = revokeButton;
    return row;
}

#pragma mark - 配对码分区

- (void)rebuildCodesSection {
    IMSettingsCardView *card = self.codesCard;
    if (card == nil) return;

    [card clearContent];
    IMServer *server = IMServerStore.shared.currentServer;
    __weak typeof(self) weakSelf = self;

    if (server == nil) {
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"还没有添加主机" systemImage:@"qrcode"];
        row.subtitle = @"配对主机后，这里会列出主机签发过的所有配对码";
        [card addRow:row];
        [card setFooterText:nil];
        return;
    }

    if (!server.hasToken) {
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"本机尚未获得授权" systemImage:@"key.slash"];
        row.subtitle = @"重新配对后才能查看主机签发过的配对码。";
        row.iconTintColor = IMTheme.shared.warningColor;
        [card addRow:row];
        [card setFooterText:nil];
        return;
    }

    if (self.inventoryLoading && self.codes.count == 0) {
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"正在读取配对码…" systemImage:@"arrow.triangle.2.circlepath"];
        row.accessory = IMSettingsRowAccessorySpinner;
        [row setAccessorySpinning:YES];
        [card addRow:row];
        [card setFooterText:nil];
        return;
    }

    if (self.inventoryError != nil && self.codes.count == 0) {
        // 与设备卡片同一次请求：原因已经在上方说清楚了，这里只给一个重试入口。
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"暂时读不到配对码" systemImage:@"exclamationmark.triangle"];
        row.subtitle = @"下拉刷新重试";
        row.iconTintColor = IMTheme.shared.warningColor;
        row.valueText = @"重试";
        row.valueColor = IMTheme.shared.accentColor;
        row.onTap = ^{ [weakSelf loadInventory]; };
        [card addRow:row];
        [card setFooterText:nil];
        return;
    }

    if (self.codes.count == 0) {
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"还没有生成过配对码" systemImage:@"qrcode"];
        row.subtitle = @"在上方「生成配对码」里签发一枚，用来给另一台设备授权";
        [card addRow:row];
        [card setFooterText:nil];
        return;
    }

    NSMutableArray<IMPairingCodeRecord *> *unused = [NSMutableArray array];
    NSMutableArray<IMPairingCodeRecord *> *redeemed = [NSMutableArray array];
    NSMutableArray<IMPairingCodeRecord *> *dead = [NSMutableArray array];
    for (IMPairingCodeRecord *record in self.codes) {
        switch (record.state) {
            case IMPairingCodeStateUnused: [unused addObject:record]; break;
            case IMPairingCodeStateRedeemed: [redeemed addObject:record]; break;
            case IMPairingCodeStateDead: [dead addObject:record]; break;
        }
    }

    BOOL firstGroup = YES;
    if (unused.count > 0) {
        [self addCodeGroup:[NSString stringWithFormat:@"未使用（%lu）", (unsigned long)unused.count]
                   records:unused
                    server:server
             showSeparator:!firstGroup];
        firstGroup = NO;
    }
    if (redeemed.count > 0) {
        [self addCodeGroup:[NSString stringWithFormat:@"已使用（%lu）", (unsigned long)redeemed.count]
                   records:redeemed
                    server:server
             showSeparator:!firstGroup];
        firstGroup = NO;
    }
    if (dead.count > 0) {
        [self addCodeGroup:[NSString stringWithFormat:@"已过期或已作废（%lu）", (unsigned long)dead.count]
                   records:dead
                    server:server
             showSeparator:!firstGroup];
    }

    [card setFooterText:@"配对码一码一机：用过即失效。未使用的码可以复制或吊销。"];
}

/// 一组配对码：组标题 + 若干行（组内第一行不再重复画分隔线）。
- (void)addCodeGroup:(NSString *)title
             records:(NSArray<IMPairingCodeRecord *> *)records
              server:(IMServer *)server
       showSeparator:(BOOL)showSeparator {
    IMSettingsCardView *card = self.codesCard;
    if (card == nil) return;

    [card addView:[self codeGroupHeaderWithText:title showSeparator:showSeparator]];
    BOOL first = YES;
    for (IMPairingCodeRecord *record in records) {
        [card addRow:[self rowForCode:record server:server] showsDivider:!first];
        first = NO;
    }
}

/// 组内小标题（比卡片分区标题更轻，用于「未使用 / 已使用 / 已作废」三组）。
- (UIView *)codeGroupHeaderWithText:(NSString *)text showSeparator:(BOOL)showSeparator {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [IMTheme fontCaption];
    label.textColor = IMTheme.shared.labelTertiary;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.userInteractionEnabled = NO;
    // 组标题前面留一条 hairline，让三组在视觉上分开（卡片内没有独立分隔线可用）。
    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = IMTheme.shared.separatorColor;
    if (showSeparator) [container addSubview:line];
    [container addSubview:label];

    CGFloat inset = IMTheme.shared.spacingL;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:inset],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-inset],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-2],
    ]];

    if (showSeparator) {
        // line 只有在真的加入层级后才有共同祖先，约束必须跟着条件加，否则会崩。
        [NSLayoutConstraint activateConstraints:@[
            [line.topAnchor constraintEqualToAnchor:container.topAnchor],
            [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:inset],
            [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-inset],
            [line.heightAnchor constraintEqualToConstant:MAX(IMTheme.shared.hairline, 0.5)],
            [label.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:10],
        ]];
    } else {
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:4].active = YES;
    }
    return container;
}

- (IMSettingsRowView *)rowForCode:(IMPairingCodeRecord *)record server:(IMServer *)server {
    __weak typeof(self) weakSelf = self;

    IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:record.displayCode systemImage:nil];
    row.monospacedTitle = YES;
    row.subtitle = [self subtitleForCode:record];
    row.copyableText = record.plainCode;   // 长按任意一条码都能复制

    switch (record.state) {
        case IMPairingCodeStateUnused: {
            row.valueText = @"可用";
            row.valueColor = IMTheme.shared.successColor;

            IMGlassButton *copyButton = [IMGlassButton iconButtonWithSystemImage:@"doc.on.doc" diameter:30];
            copyButton.tintColor = IMTheme.shared.accentColor;
            copyButton.accessibilityLabel = [NSString stringWithFormat:@"复制配对码 %@", record.displayCode];
            [copyButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
                IMCopyText(record.plainCode, weakSelf.view, @"配对码已复制");
            }] forControlEvents:UIControlEventTouchUpInside];

            IMGlassButton *revokeButton = [IMGlassButton iconButtonWithSystemImage:@"trash" diameter:30];
            revokeButton.tintColor = IMTheme.shared.dangerColor;
            revokeButton.accessibilityLabel = [NSString stringWithFormat:@"吊销配对码 %@", record.displayCode];
            [revokeButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
                [weakSelf confirmRevokeCode:record server:server];
            }] forControlEvents:UIControlEventTouchUpInside];

            UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[copyButton, revokeButton]];
            actions.translatesAutoresizingMaskIntoConstraints = NO;
            actions.axis = UILayoutConstraintAxisHorizontal;
            actions.spacing = IMTheme.shared.spacingXS;
            actions.alignment = UIStackViewAlignmentCenter;
            row.trailingAccessoryView = actions;
            break;
        }
        case IMPairingCodeStateRedeemed:
            row.valueText = @"已使用";
            row.valueColor = IMTheme.shared.labelTertiary;
            break;
        case IMPairingCodeStateDead:
            row.valueText = record.revoked ? @"已作废" : @"已过期";
            row.valueColor = IMTheme.shared.labelTertiary;
            row.titleLabel.textColor = IMTheme.shared.labelTertiary;   // 失效的码不该抢注意力
            break;
    }
    return row;
}

- (NSString *)subtitleForCode:(IMPairingCodeRecord *)record {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    switch (record.state) {
        case IMPairingCodeStateUnused:
            if (record.neverExpires) {
                [parts addObject:@"长期有效"];
            } else if (record.expiresAt != nil) {
                [parts addObject:[NSString stringWithFormat:@"%@ 到期", IMShortDateTimeString(record.expiresAt)]];
            } else if (record.remainingDays >= 0) {
                [parts addObject:[NSString stringWithFormat:@"有效期 %ld 天", (long)record.remainingDays]];
            }
            break;
        case IMPairingCodeStateRedeemed:
            [parts addObject:record.redeemedDevicePrefix.length > 0
                ? [NSString stringWithFormat:@"已用于设备 %@", record.redeemedDevicePrefix]
                : @"已被某台设备使用"];
            break;
        case IMPairingCodeStateDead:
            [parts addObject:record.revoked ? @"已吊销" : @"已过期"];
            break;
    }

    if (record.createdAt != nil) {
        [parts addObject:[NSString stringWithFormat:@"生成于 %@", IMRelativeTimeString(record.createdAt)]];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (void)confirmRevokeCode:(IMPairingCodeRecord *)record server:(IMServer *)server {
    if (record == nil || server == nil) return;

    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"吊销配对码 %@？", record.displayCode]
                                                                  message:@"吊销后这枚码不能再用于配对。已经用它配好的设备不受影响。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"吊销" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [IMSettingsPairingGateway revokeCode:record forServer:server completion:^(NSError *error) {
            if (error != nil) {
                [strongSelf presentSimpleAlertWithTitle:@"吊销失败"
                                                message:[IMSettingsPairingGateway messageForError:error]];
                return;
            }
            [strongSelf loadInventory];
            IMShowToast(strongSelf.view, @"已吊销该配对码");
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentSimpleAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 数据

- (void)refreshAll {
    [self loadInventory];
    [self probeGateway];
}

- (void)loadInventory {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil) {
        self.devices = @[];
        self.codes = @[];
        self.inventoryError = nil;
        self.inventoryLoading = NO;
        [self refreshInventorySectionsAnimated:NO];
        [self endRefreshingIfIdle];
        return;
    }

    self.inventoryLoading = YES;
    [self refreshInventorySectionsAnimated:NO];

    __weak typeof(self) weakSelf = self;
    [IMSettingsPairingGateway fetchInventoryForServer:server completion:^(NSArray<IMPairingDevice *> *list, NSArray<IMPairingCodeRecord *> *codeList, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;

        strongSelf.inventoryLoading = NO;
        IMServer *nowCurrent = IMServerStore.shared.currentServer;
        // 请求期间用户可能切换了主机：丢掉过期响应，别把旧主机的数据画到新主机上。
        if (nowCurrent == nil || ![nowCurrent.identifier isEqualToString:server.identifier]) {
            [strongSelf endRefreshingIfIdle];
            return;
        }

        if (error != nil) {
            strongSelf.inventoryError = error;
            if (strongSelf.devices.count == 0) strongSelf.devices = @[];
            if (strongSelf.codes.count == 0) strongSelf.codes = @[];
        } else {
            strongSelf.inventoryError = nil;
            strongSelf.devices = list ?: @[];
            strongSelf.codes = codeList ?: @[];
        }
        [strongSelf refreshInventorySectionsAnimated:YES];
        [strongSelf endRefreshingIfIdle];
    }];
}

- (void)probeGateway {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server.baseURL == nil) {
        self.gatewayProbeRunning = NO;
        self.gatewayVersion = nil;
        self.gatewayVersionRow.valueText = @"—";
        [self endRefreshingIfIdle];
        return;
    }

    self.gatewayProbeRunning = YES;
    if (self.gatewayVersionRow) self.gatewayVersionRow.valueText = @"检测中";

    __weak typeof(self) weakSelf = self;
    [IMPairingService probeServerAtURL:server.baseURL completion:^(BOOL reachable, NSString *version, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;

        strongSelf.gatewayProbeRunning = NO;
        if (!reachable) {
            strongSelf.gatewayVersion = nil;
            strongSelf.gatewayVersionRow.valueText = @"未连通";
            [strongSelf endRefreshingIfIdle];
            return;
        }

        NSString *text = version.length > 0 ? version : @"可用";
        strongSelf.gatewayVersion = text;
        strongSelf.gatewayVersionRow.valueText = text;

        // 记住「最近连接」时间：只在明显过期时写回，避免每次下拉刷新都触发一次落盘。
        IMServer *latest = IMServerStore.shared.currentServer;
        if ([latest.identifier isEqualToString:server.identifier]) {
            NSDate *previous = latest.lastConnectedAt;
            if (previous == nil || [previous timeIntervalSinceNow] < -60) {
                latest.lastConnectedAt = NSDate.date;
                [IMServerStore.shared updateServer:latest];
            }
        }
        [strongSelf endRefreshingIfIdle];
    }];
}

- (void)refreshInventorySectionsAnimated:(BOOL)animated {
    if (self.devicesCard == nil || self.codesCard == nil) {
        [self rebuildContentAnimated:NO];
        return;
    }
    if (!animated) {
        [self rebuildDevicesSection];
        [self rebuildCodesSection];
        return;
    }

    // 设备与配对码来自同一次请求，各淡入一次，避免整页重排造成的跳动。
    [UIView transitionWithView:self.devicesCard
                      duration:0.22
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{ [self rebuildDevicesSection]; }
                    completion:nil];
    [UIView transitionWithView:self.codesCard
                      duration:0.22
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{ [self rebuildCodesSection]; }
                    completion:nil];
}

- (void)endRefreshingIfIdle {
    if (self.inventoryLoading || self.gatewayProbeRunning) return;
    if (self.refreshControl.isRefreshing) [self.refreshControl endRefreshing];
}

- (void)handlePullToRefresh {
    [self refreshAll];
}

#pragma mark - 通知

- (void)serverStoreDidChange:(NSNotification *)notification {
    // 只抑制「状态和我刚刚渲染的完全一致」的那一条通知；一变就走正常重建，绝不吞掉真实变更。
    NSString *signature = [self storeSignature];
    NSString *suppressed = self.suppressedStoreSignature;
    self.suppressedStoreSignature = nil;   // 一次性：无论是被消费还是已过期，都只可能抑制一条
    if (suppressed != nil && [suppressed isEqualToString:signature]) {
        return;
    }

    IMServer *current = IMServerStore.shared.currentServer;
    NSString *identifier = current.identifier;
    BOOL sameHost = (self.observedServerIdentifier == nil && identifier == nil)
        || [self.observedServerIdentifier isEqualToString:identifier];
    self.observedServerIdentifier = identifier;

    // 被动变化（改名、别处吊销、ping 写回时间）就地重建即可，不做整块淡入，避免闪烁。
    [self rebuildContentAnimated:NO];

    if (!sameHost) {
        self.devices = @[];
        self.codes = @[];
        self.inventoryError = nil;
        [self loadInventory];
        [self probeGateway];
    }
}

/// 当前主机上会影响这一屏渲染的字段签名（自己改完 store 后立刻重建，用它挡掉紧随其后的那条回声通知）。
- (NSString *)storeSignature {
    IMServer *current = IMServerStore.shared.currentServer;
    if (current == nil) return @"<none>";
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%lu|%.0f",
            current.identifier ?: @"",
            current.deviceToken ?: @"",
            current.displayName ?: @"",
            current.baseURLString ?: @"",
            current.deviceName ?: @"",
            (unsigned long)IMServerStore.shared.servers.count,
            current.lastConnectedAt.timeIntervalSince1970];
}

- (void)suppressNextStoreEcho {
    self.suppressedStoreSignature = [self storeSignature];
}

#pragma mark - 动作

- (void)showCurrentHostDetail {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil) {
        [self presentAddHost];
        return;
    }
    IMServerDetailViewController *detail = [[IMServerDetailViewController alloc] initWithServer:server];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)showServerList {
    IMServerListViewController *list = [[IMServerListViewController alloc] init];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)showPairingCode {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil || !server.hasToken) {
        IMShowToast(self.view, @"这台主机还没有完成配对");
        return;
    }
    IMPairDeviceViewController *pairCode = [[IMPairDeviceViewController alloc] initWithServer:server];
    [self.navigationController pushViewController:pairCode animated:YES];
}

- (void)presentAddHost {
    __weak typeof(self) weakSelf = self;
    // 重新配对同一台主机时，redeem 会新建一条记录，把原来「无 token 的空壳」清掉，
    // 否则主机列表里会长期留一台永远连不上的重复主机。
    IMPresentPairingSheet(self, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [strongSelf removeStaleHostsMatchingCurrent];
        // 配对成功后 store 会连续变更（新增/写 token/切当前），这里已经按最终状态重建过一次，
        // 回声通知用状态签名挡掉；此后再有任何真实变化仍会正常重建。
        [strongSelf suppressNextStoreEcho];
        [strongSelf rebuildContentAnimated:YES];
        [strongSelf loadInventory];
        [strongSelf probeGateway];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            IMShowToast(strongSelf.view, @"主机已添加");
        });
    });
}

/// 清掉与新配对结果同地址、且没有令牌的旧记录（只会是重复配对留下的空壳）。
- (void)removeStaleHostsMatchingCurrent {
    IMServerStore *store = IMServerStore.shared;
    IMServer *current = store.currentServer;
    if (current == nil || current.deviceToken.length == 0) return;

    for (IMServer *server in [store.servers copy]) {
        if ([server.identifier isEqualToString:current.identifier]) continue;
        if (server.deviceToken.length > 0) continue;
        if (![server.baseURLString isEqualToString:current.baseURLString]) continue;
        [store removeServer:server];
    }
}

- (void)switchToServer:(IMServer *)server {
    if (server == nil) return;
    if ([server.identifier isEqualToString:IMServerStore.shared.currentServer.identifier]) return;

    IMServerStore.shared.currentServer = server;
    // currentServer 的 setter 不落盘，必须走 updateServer: 触发 persist。
    [IMServerStore.shared updateServer:server];
    // 状态已定：挡掉这次落盘回声，避免刚做完的淡入再被打断一次。
    [self suppressNextStoreEcho];

    self.observedServerIdentifier = server.identifier;
    self.devices = @[];
    self.codes = @[];
    self.inventoryError = nil;
    [self rebuildContentAnimated:YES];
    [self loadInventory];
    [self probeGateway];

    IMShowToast(self.view, [NSString stringWithFormat:@"已切换到 %@", server.displayName]);
}

- (void)promptRenameDevice {
    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设备名称"
                                                                  message:@"名称在配对时上报给主机，改名只影响本机显示。留空则恢复默认名称。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [IMDeviceIdentity deviceName];
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // 弱引用 alert：action 的 block 由 alert 持有，强捕获会形成 alert → action → block → alert 的循环（泄漏整个弹窗）。
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [IMDeviceIdentity setDeviceName:text];
        [strongSelf rebuildContentAnimated:NO];
        IMShowToast(strongSelf.view, @"设备名称已更新");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmRevokeDevice:(IMPairingDevice *)device {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil || device == nil) return;

    NSString *name = device.name.length > 0 ? device.name : [NSString stringWithFormat:@"设备 %@", device.shortIdentifier];
    NSString *title = device.currentDevice ? @"吊销这台设备？" : [NSString stringWithFormat:@"吊销「%@」？", name];
    // 吊销自己等于把本机踢下线：文案必须把后果说清楚再让用户确认。
    NSString *message = device.currentDevice
        ? @"这是当前正在使用的设备。吊销后本机会立即失去这台主机的访问权限，需要重新配对才能恢复。"
        : @"吊销后这台设备需要重新配对才能访问主机。";

    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:device.currentDevice ? @"仍要吊销" : @"吊销"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [weakSelf revokeDevice:device server:server];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)revokeDevice:(IMPairingDevice *)device server:(IMServer *)server {
    __weak typeof(self) weakSelf = self;
    [IMSettingsPairingGateway revokeDevice:device forServer:server completion:^(NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"吊销失败"
                                                                          message:[IMSettingsPairingGateway messageForError:error]
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }

        if (device.currentDevice) {
            // 令牌已作废：立刻清掉本地 token，界面不能继续显示「已配对」。
            // updateServer: 会发出 IMServerStoreDidChangeNotification —— 这就是给会话/文件页的信号：
            // 它们只需判断 currentServer.hasToken == NO 就能给出「重新配对」引导，不必等到请求 401。
            [IMServerStore.shared setDeviceToken:nil forServer:server];
            [IMServerStore.shared updateServer:server];
        }
        [strongSelf loadInventory];
        IMShowToast(strongSelf.view, device.currentDevice ? @"本机授权已吊销，请重新配对" : @"已吊销该设备");
    }];
}

@end


