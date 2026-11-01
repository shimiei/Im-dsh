//
//  IMServerListViewController.m
//  IMDSH — 主机管理
//

#import "IMServerListViewController.h"
#import "IMServerDetailViewController.h"
#import "IMSettingsCardView.h"
#import "IMSettingsRowView.h"
#import "IMFormatting.h"
#import "IMPairingSheet.h"

#import "IMTheme.h"
#import "IMGlass.h"
#import "IMServerStore.h"

@interface IMServerListViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) NSLayoutConstraint *maxContentWidthConstraint;
@end

@implementation IMServerListViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"主机管理";
    self.view.backgroundColor = IMTheme.shared.backgroundBase;
    [self buildHierarchy];

    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithImage:IMSymbol(@"plus", 16, UIImageSymbolWeightSemibold)
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(presentAddHost)];
    addItem.accessibilityLabel = @"添加主机";
    self.navigationItem.rightBarButtonItem = addItem;

    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(serverStoreDidChange:)
                                              name:IMServerStoreDidChangeNotification
                                            object:nil];
    [self buildContent];
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
    IMStackRemoveAllArrangedSubviews(self.contentStack);

    NSArray<IMServer *> *servers = IMServerStore.shared.servers;
    IMServer *current = IMServerStore.shared.currentServer;
    __weak typeof(self) weakSelf = self;

    if (servers.count == 0) {
        IMSettingsCardView *card = [[IMSettingsCardView alloc] initWithTitle:@"主机"];
        IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:@"添加第一台主机" systemImage:@"plus.circle"];
        row.subtitle = @"在电脑上打开 DSH → 远程接入 → 设备配对，生成配对码后填入";
        row.accessory = IMSettingsRowAccessoryChevron;
        row.onTap = ^{ [weakSelf presentAddHost]; };
        [card addRow:row];
        [self.contentStack addArrangedSubview:card];
        return;
    }

    IMSettingsCardView *card = [[IMSettingsCardView alloc] initWithTitle:@"已配对主机"];
    for (IMServer *server in servers) {
        [card addRow:[self rowForServer:server isCurrent:[server.identifier isEqualToString:current.identifier]]];
    }
    [card setFooterText:@"点按「⋯」可以切换、重命名或删除主机。删除只影响本机记录，不会吊销主机上的授权。"];
    [self.contentStack addArrangedSubview:card];

    IMSettingsCardView *addCard = [[IMSettingsCardView alloc] initWithTitle:@"添加"];
    IMSettingsRowView *addRow = [IMSettingsRowView rowWithTitle:@"添加主机" systemImage:@"plus.circle"];
    addRow.subtitle = @"输入新主机的地址与配对码";
    addRow.accessory = IMSettingsRowAccessoryChevron;
    addRow.onTap = ^{ [weakSelf presentAddHost]; };
    [addCard addRow:addRow];
    [self.contentStack addArrangedSubview:addCard];
}

- (IMSettingsRowView *)rowForServer:(IMServer *)server isCurrent:(BOOL)isCurrent {
    __weak typeof(self) weakSelf = self;

    IMSettingsRowView *row = [IMSettingsRowView rowWithTitle:server.displayName systemImage:@"server.rack"];
    NSMutableArray<NSString *> *meta = [NSMutableArray array];
    [meta addObject:server.baseURLString ?: @"地址缺失"];
    [meta addObject:server.hasToken ? @"已配对" : @"令牌缺失"];
    row.subtitle = [meta componentsJoinedByString:@" · "];
    row.iconTintColor = isCurrent ? IMTheme.shared.accentColor : IMTheme.shared.labelSecondary;
    if (isCurrent) {
        row.valueText = @"当前";
        row.valueColor = IMTheme.shared.accentColor;
    }
    row.onTap = ^{ [weakSelf showDetailForServer:server]; };

    IMGlassButton *menuButton = [IMGlassButton iconButtonWithSystemImage:@"ellipsis" diameter:32];
    menuButton.tintColor = IMTheme.shared.labelSecondary;
    menuButton.showsMenuAsPrimaryAction = YES;
    menuButton.accessibilityLabel = [NSString stringWithFormat:@"%@ 的更多操作", server.displayName];
    menuButton.menu = [self menuForServer:server isCurrent:isCurrent];
    row.trailingAccessoryView = menuButton;
    return row;
}

- (UIMenu *)menuForServer:(IMServer *)server isCurrent:(BOOL)isCurrent {
    __weak typeof(self) weakSelf = self;

    UIAction *activate = [UIAction actionWithTitle:@"设为当前主机"
                                            image:IMSymbol(@"checkmark.circle", 15, UIImageSymbolWeightRegular)
                                       identifier:nil
                                          handler:^(UIAction *action) {
        [weakSelf switchToServer:server];
    }];
    activate.state = isCurrent ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *rename = [UIAction actionWithTitle:@"重命名"
                                           image:IMSymbol(@"pencil", 15, UIImageSymbolWeightRegular)
                                      identifier:nil
                                         handler:^(UIAction *action) {
        [weakSelf promptRenameServer:server];
    }];

    UIAction *delete = [UIAction actionWithTitle:@"删除主机"
                                           image:IMSymbol(@"trash", 15, UIImageSymbolWeightRegular)
                                      identifier:nil
                                         handler:^(UIAction *action) {
        [weakSelf confirmDeleteServer:server];
    }];
    delete.attributes = UIMenuElementAttributesDestructive;

    return [UIMenu menuWithChildren:@[activate, rename, delete]];
}

#pragma mark - 动作

- (void)showDetailForServer:(IMServer *)server {
    IMServerDetailViewController *detail = [[IMServerDetailViewController alloc] initWithServer:server];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)switchToServer:(IMServer *)server {
    IMServer *fresh = [IMServerStore.shared serverWithIdentifier:server.identifier] ?: server;
    if ([fresh.identifier isEqualToString:IMServerStore.shared.currentServer.identifier]) return;

    IMServerStore.shared.currentServer = fresh;
    // setter 不落盘：走 updateServer: 触发持久化。
    [IMServerStore.shared updateServer:fresh];
    [UIView transitionWithView:self.contentStack
                      duration:0.22
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{ [self buildContent]; }
                    completion:nil];
    IMShowToast(self.view, [NSString stringWithFormat:@"已切换到 %@", fresh.displayName]);
}

- (void)promptRenameServer:(IMServer *)server {
    IMServer *fresh = [IMServerStore.shared serverWithIdentifier:server.identifier] ?: server;
    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名主机"
                                                                  message:fresh.baseURLString
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = fresh.displayName;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.placeholder = @"例如 书房 MacBook";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // 弱引用 alert：action 的 block 由 alert 持有，强捕获会形成 alert → action → block → alert 的循环（泄漏整个弹窗）。
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length == 0) return;   // 空名字会让列表不可辨识，直接忽略
        fresh.displayName = text;
        [IMServerStore.shared updateServer:fresh];
        [strongSelf buildContent];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteServer:(IMServer *)server {
    IMServer *fresh = [IMServerStore.shared serverWithIdentifier:server.identifier] ?: server;
    BOOL isCurrent = [fresh.identifier isEqualToString:IMServerStore.shared.currentServer.identifier];

    NSString *message = isCurrent
        ? @"这是当前主机。删除后本机会切换到另一台主机（如有），并需要重新配对才能回到这台主机。"
        : @"删除只移除本机保存的记录与令牌；主机上这台设备的授权仍然存在，需要时可再吊销。";

    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"删除「%@」？", fresh.displayName]
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [IMServerStore.shared removeServer:fresh];
        [strongSelf buildContent];
        IMShowToast(strongSelf.view, @"已删除主机");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentAddHost {
    __weak typeof(self) weakSelf = self;
    IMPresentPairingSheet(self, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [strongSelf buildContent];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            IMShowToast(strongSelf.view, @"主机已添加");
        });
    });
}

#pragma mark - 通知

- (void)serverStoreDidChange:(NSNotification *)notification {
    [self buildContent];
}

@end

