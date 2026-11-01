//
//  IMServerDetailViewController.m
//  IMDSH — 单台主机详情
//

#import "IMServerDetailViewController.h"
#import "IMServerSummaryView.h"
#import "IMSettingsCardView.h"
#import "IMSettingsRowView.h"
#import "IMPairDeviceViewController.h"
#import "IMFormatting.h"
#import "IMPairingSheet.h"

#import "IMTheme.h"
#import "IMGlass.h"
#import "IMServerStore.h"
#import "IMPairingService.h"
#import "IMAPIClient.h"

@interface IMServerDetailViewController ()
@property (nonatomic, strong) IMServer *server;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) NSLayoutConstraint *maxContentWidthConstraint;
@property (nonatomic, copy, nullable) NSString *gatewayVersion;
@property (nonatomic, assign) BOOL probing;
@property (nonatomic, weak, nullable) IMSettingsRowView *gatewayVersionRow;
@end

@implementation IMServerDetailViewController

#pragma mark - 构造

- (instancetype)initWithServer:(IMServer *)server {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _server = server;
    }
    return self;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.server.displayName;
    self.view.backgroundColor = IMTheme.shared.backgroundBase;
    [self buildHierarchy];

    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(serverStoreDidChange:)
                                              name:IMServerStoreDidChangeNotification
                                            object:nil];

    [self buildContent];
    [self probeGateway];
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

/// 永远拿 store 里的最新实例：别处改名/删机后，这里显示的不能是旧快照。
- (nullable IMServer *)liveServer {
    IMServer *fresh = [IMServerStore.shared serverWithIdentifier:self.server.identifier];
    if (fresh != nil) self.server = fresh;
    return fresh;
}

#pragma mark - 骨架

- (void)buildHierarchy {
    IMTheme *theme = IMTheme.shared;

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = theme.spacingL;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.contentStack];

    NSLayoutConstraint *fillWidth = [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor
                                                                                  constant:-(theme.spacingL * 2)];
    fillWidth.priority = (UILayoutPriority)999;
    self.maxContentWidthConstraint = [self.contentStack.widthAnchor constraintLessThanOrEqualToConstant:[theme maxContentWidthForSize:self.view.bounds.size]];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
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

#pragma mark - 内容

- (void)buildContent {
    IMServer *server = [self liveServer];
    if (server == nil) return;

    IMStackRemoveAllArrangedSubviews(self.contentStack);
    __weak typeof(self) weakSelf = self;

    IMServerSummaryView *summary = [IMServerSummaryView viewWithServer:server];
    [self.contentStack addArrangedSubview:summary];

    // 主机信息
    IMSettingsCardView *infoCard = [[IMSettingsCardView alloc] initWithTitle:@"主机信息"];

    IMSettingsRowView *nameRow = [IMSettingsRowView rowWithTitle:@"名称" systemImage:@"pencil"];
    nameRow.valueText = server.displayName;
    nameRow.accessory = IMSettingsRowAccessoryChevron;
    nameRow.onTap = ^{ [weakSelf promptRename]; };
    [infoCard addRow:nameRow];

    IMSettingsRowView *addressRow = [IMSettingsRowView rowWithTitle:@"地址" systemImage:@"link"];
    addressRow.valueText = server.baseURLString;
    addressRow.monospacedValue = YES;
    addressRow.subtitle = @"长按可复制";
    addressRow.copyableText = server.baseURLString;
    [infoCard addRow:addressRow];

    IMSettingsRowView *statusRow = [IMSettingsRowView rowWithTitle:@"配对状态" systemImage:@"key"];
    if (server.hasToken) {
        statusRow.valueText = @"已配对";
        statusRow.valueColor = IMTheme.shared.successColor;
    } else {
        statusRow.valueText = @"令牌缺失";
        statusRow.valueColor = IMTheme.shared.warningColor;
    }
    [infoCard addRow:statusRow];

    IMSettingsRowView *pairedRow = [IMSettingsRowView rowWithTitle:@"配对时间" systemImage:@"calendar"];
    pairedRow.valueText = server.pairedAt ? IMShortDateTimeString(server.pairedAt) : @"—";
    pairedRow.monospacedValue = NO;
    [infoCard addRow:pairedRow];

    IMSettingsRowView *seenRow = [IMSettingsRowView rowWithTitle:@"最近连接" systemImage:@"bolt"];
    seenRow.valueText = server.lastConnectedAt ? IMRelativeTimeString(server.lastConnectedAt) : @"本次会话尚未连接";
    [infoCard addRow:seenRow];

    IMSettingsRowView *gatewayRow = [IMSettingsRowView rowWithTitle:@"网关版本" systemImage:@"antenna.radiowaves.left.and.right"];
    gatewayRow.valueText = self.gatewayVersion ?: (self.probing ? @"检测中" : @"—");
    gatewayRow.monospacedValue = YES;
    self.gatewayVersionRow = gatewayRow;
    [infoCard addRow:gatewayRow];

    [self.contentStack addArrangedSubview:infoCard];

    // 操作
    IMSettingsCardView *actionCard = [[IMSettingsCardView alloc] initWithTitle:@"操作"];
    BOOL isCurrent = [server.identifier isEqualToString:IMServerStore.shared.currentServer.identifier];

    if (!isCurrent) {
        IMSettingsRowView *activateRow = [IMSettingsRowView rowWithTitle:@"设为当前主机" systemImage:@"checkmark.circle"];
        activateRow.subtitle = @"切换后会话与文件会改为连接这台主机";
        activateRow.valueText = @"切换";
        activateRow.valueColor = IMTheme.shared.accentColor;
        activateRow.onTap = ^{ [weakSelf activateServer]; };
        [actionCard addRow:activateRow];
    }

    IMSettingsRowView *codeRow = [IMSettingsRowView rowWithTitle:@"生成配对码" systemImage:@"qrcode"];
    if (server.hasToken) {
        codeRow.subtitle = @"给另一台设备授权时使用";
        codeRow.accessory = IMSettingsRowAccessoryChevron;
        codeRow.onTap = ^{ [weakSelf showPairingCode]; };
    } else {
        codeRow.subtitle = @"这台主机还没有有效的设备令牌";
        codeRow.enabled = NO;
    }
    [actionCard addRow:codeRow];

    if (!server.hasToken) {
        // 令牌缺失时把恢复入口放在最显眼的位置：没有它，这个页面只能删机。
        IMSettingsRowView *repairRow = [IMSettingsRowView rowWithTitle:@"重新配对这台主机" systemImage:@"key.badge.plus"];
        repairRow.subtitle = @"重新输入配对码，恢复本机对这台主机的访问";
        repairRow.valueText = @"去配对";
        repairRow.valueColor = IMTheme.shared.accentColor;
        repairRow.onTap = ^{
            __weak typeof(weakSelf) weakSelf2 = weakSelf;
            IMPresentPairingSheet(weakSelf2, ^{
                __strong typeof(weakSelf2) strongSelf2 = weakSelf2;
                if (strongSelf2 == nil) return;
                [strongSelf2 buildContent];
                IMShowToast(strongSelf2.view, @"已重新配对");
            });
        };
        [actionCard addRow:repairRow];
    }

    IMSettingsRowView *probeRow = [IMSettingsRowView rowWithTitle:@"重新检测连接" systemImage:@"arrow.clockwise"];
    probeRow.subtitle = @"访问主机的 /__webim/ping";
    probeRow.valueText = self.probing ? @"检测中" : @"检测";
    probeRow.valueColor = IMTheme.shared.accentColor;
    probeRow.onTap = ^{ [weakSelf probeGateway]; };
    [actionCard addRow:probeRow];

    IMSettingsRowView *deleteRow = [IMSettingsRowView rowWithTitle:@"删除这台主机" systemImage:@"trash"];
    deleteRow.destructive = YES;
    deleteRow.onTap = ^{ [weakSelf confirmDelete]; };
    [actionCard addRow:deleteRow];

    [self.contentStack addArrangedSubview:actionCard];
}

#pragma mark - 数据

- (void)probeGateway {
    IMServer *server = [self liveServer];
    if (server.baseURL == nil) return;

    self.probing = YES;
    if (self.gatewayVersionRow) self.gatewayVersionRow.valueText = @"检测中";

    __weak typeof(self) weakSelf = self;
    [IMPairingService probeServerAtURL:server.baseURL completion:^(BOOL reachable, NSString *version, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;

        strongSelf.probing = NO;
        if (!reachable) {
            strongSelf.gatewayVersion = nil;
            strongSelf.gatewayVersionRow.valueText = @"未连通";
            strongSelf.gatewayVersionRow.valueColor = IMTheme.shared.warningColor;
            IMShowToast(strongSelf.view, [IMAPIClient localizedMessageForError:error]);
            return;
        }

        strongSelf.gatewayVersion = version.length > 0 ? version : @"可用";
        strongSelf.gatewayVersionRow.valueText = strongSelf.gatewayVersion;

        IMServer *latest = [strongSelf liveServer];
        latest.lastConnectedAt = NSDate.date;
        [IMServerStore.shared updateServer:latest];
        [strongSelf buildContent];
    }];
}

#pragma mark - 动作

- (void)promptRename {
    IMServer *server = [self liveServer];
    if (server == nil) return;

    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名主机"
                                                                  message:server.baseURLString
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = server.displayName;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // 弱引用 alert：action 的 block 由 alert 持有，强捕获会形成 alert → action → block → alert 的循环（泄漏整个弹窗）。
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length == 0) return;
        server.displayName = text;
        [IMServerStore.shared updateServer:server];
        strongSelf.title = text;
        [strongSelf buildContent];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)activateServer {
    IMServer *server = [self liveServer];
    if (server == nil) return;
    if ([server.identifier isEqualToString:IMServerStore.shared.currentServer.identifier]) return;

    IMServerStore.shared.currentServer = server;
    [IMServerStore.shared updateServer:server];   // 触发持久化
    [self buildContent];
    IMShowToast(self.view, [NSString stringWithFormat:@"已切换到 %@", server.displayName]);
}

- (void)showPairingCode {
    IMServer *server = [self liveServer];
    if (server == nil || !server.hasToken) {
        IMShowToast(self.view, @"这台主机还不能生成配对码");
        return;
    }
    IMPairDeviceViewController *pairCode = [[IMPairDeviceViewController alloc] initWithServer:server];
    [self.navigationController pushViewController:pairCode animated:YES];
}

- (void)confirmDelete {
    IMServer *server = [self liveServer];
    if (server == nil) return;
    BOOL isCurrent = [server.identifier isEqualToString:IMServerStore.shared.currentServer.identifier];

    __weak typeof(self) weakSelf = self;
    NSString *message = isCurrent
        ? @"这是当前主机。删除后本机会切换到另一台主机（如有），需要重新配对才能回到这台主机。"
        : @"删除只移除本机保存的记录与令牌；主机上这台设备的授权仍然存在。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"删除「%@」？", server.displayName]
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [IMServerStore.shared removeServer:server];
        [strongSelf popSelfIfVisible];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 通知

- (void)serverStoreDidChange:(NSNotification *)notification {
    // 主机在别处被删掉了：这一页没有意义，直接退回上一级。
    if ([self liveServer] == nil) {
        [self popSelfIfVisible];
        return;
    }
    [self buildContent];
}

/// 只在自己仍是栈顶、且没有正在退场时 pop。
/// removeServer: 的删除动画和随后那条异步通知都会走到这里，没有守卫就会双 pop。
- (void)popSelfIfVisible {
    if (self.isMovingFromParentViewController || self.isBeingDismissed) return;
    UINavigationController *nav = self.navigationController;
    if (nav == nil) return;                       // 删最后一台时 SceneDelegate 会整体换根，nav 已脱离
    if (nav.topViewController != self) return;    // 已经被另一次 pop 顶掉
    [nav popViewControllerAnimated:YES];
}

@end

