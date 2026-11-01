//
//  IMChatViewController.m
//  IMDSH — 会话域容器
//

#import "IMChatViewController.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMSessionListViewController.h"
#import "IMConversationViewController.h"

static const CGFloat IMListPaneMinWidth = 300;
static const CGFloat IMListPaneMaxWidth = 380;
static const CGFloat IMListPaneRatio = 0.34;

#pragma mark - iPad 空态

@interface IMChatPlaceholderViewController : UIViewController
@end

@implementation IMChatPlaceholderViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    IMTheme *theme = IMTheme.shared;
    self.view.backgroundColor = theme.backgroundBase;
    self.title = @"会话";

    UIImageView *icon = [[UIImageView alloc] initWithImage:IMSymbol(@"bubble.left.and.bubble.right", 40, UIImageSymbolWeightRegular)];
    icon.tintColor = theme.labelDimmed;
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = @"从左侧选择一个会话";
    label.font = [IMTheme fontCallout];
    label.textColor = theme.labelTertiary;
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = theme.spacingM;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

@end

#pragma mark - 容器

@interface IMChatViewController () <IMSessionListViewControllerDelegate>
@property (nonatomic, strong) IMSessionListViewController *listViewController;
@property (nonatomic, strong) UINavigationController *listNav;
@property (nonatomic, strong) UINavigationController *detailNav;
@property (nonatomic, strong) IMChatPlaceholderViewController *placeholderViewController;
@property (nonatomic, strong) UIView *dividerView;
@property (nonatomic, strong, nullable) IMConversationViewController *conversation;
@property (nonatomic, strong) NSLayoutConstraint *listWidthConstraint;
@property (nonatomic, assign) BOOL twoPane;
/// 重建期间的重入保护：旋转 + trait 回调可能在同一帧里连触发两次。
@property (nonatomic, assign) BOOL rebuilding;
/// 内部导航是否已建立（首帧还没建时为 NO）。
@property (nonatomic, assign) BOOL interfaceBuilt;
@end

@implementation IMChatViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.shared.backgroundBase;
    self.title = @"会话";

    self.listViewController = [[IMSessionListViewController alloc] init];
    self.listViewController.delegate = self;
    __weak typeof(self) weakSelf = self;
    self.listViewController.onRequirePairing = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self showSettingsTab];
    };

    self.placeholderViewController = [[IMChatPlaceholderViewController alloc] init];

    self.dividerView = [[UIView alloc] init];
    self.dividerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dividerView.backgroundColor = IMTheme.shared.separatorColor;

    self.twoPane = [self shouldUseTwoPane];
    [self rebuildInterface];

    // 尺寸类变化（iPad 分屏拖动）不一定伴随 viewWillTransitionToSize，用注册式回调补一次。
    [self registerForTraitChanges:@[UITraitHorizontalSizeClass.class]
                      withHandler:^(__kindof id<UITraitEnvironment> traitEnvironment, UITraitCollection *previousTraitCollection) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self rebuildInterfaceIfNeeded];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 外壳把每个标签页都包了一层导航控制器；它只负责包一层，标题栏用我们自己的内部导航。
    UINavigationController *nav = self.navigationController;
    if (nav != nil && nav.viewControllers.firstObject == self) {
        [nav setNavigationBarHidden:YES animated:animated];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 这里只做兜底判断，绝不在这里重建：布局过程中摘/挂控制器会让同一个 view 短期内归属两个
    // 控制器（"A view can only be associated with at most one view controller"）并直接崩。
    // 真正需要重建时留给 viewWillTransitionToSize / traitCollectionDidChange。
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    // 等过渡结束、真实尺寸落地后再判断；过渡期间重建会撞上 UIKit 的动画快照。
    __weak typeof(self) weakSelf = self;
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self rebuildInterfaceIfNeeded];
    }];
}

/// 只有「宽窄布局真的变了」或「还没建过」才重建；其它情况直接返回。
- (void)rebuildInterfaceIfNeeded {
    if (self.rebuilding) return;
    BOOL twoPane = [self shouldUseTwoPane];
    if (self.interfaceBuilt && twoPane == self.twoPane) return;
    self.twoPane = twoPane;
    [self rebuildInterface];
}

#pragma mark - 布局

- (BOOL)shouldUseTwoPane {
    BOOL regular = self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
    return regular && self.view.bounds.size.width >= 680;
}

- (UINavigationController *)makeNavigationControllerWithRoot:(UIViewController *)root {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.prefersLargeTitles = YES;
    nav.view.backgroundColor = IMTheme.shared.backgroundBase;
    return nav;
}

/// 把根控制器从旧导航栈里彻底摘出来：先清空栈（根随之脱离），再移除导航控制器本身。
- (void)detachNavigationController:(UINavigationController *)nav root:(UIViewController *)root {
    if (nav != nil) {
        [nav setViewControllers:@[] animated:NO];
        [nav willMoveToParentViewController:nil];
        [nav.view removeFromSuperview];
        [nav removeFromParentViewController];
    }
    if (root.parentViewController != nil) {
        // 兜底：万一还挂着（例如旧栈不是我们建的），显式摘干净。
        // 同一个控制器挂两处会触发 "A view can only be associated with at most one view controller" 崩溃。
        [root willMoveToParentViewController:nil];
        [root removeFromParentViewController];
    }
}

- (void)rebuildInterface {
    if (self.rebuilding) return;
    self.rebuilding = YES;

    // 先把根控制器从旧导航栈摘干净，避免同一个控制器同时挂在两个导航栈上。
    [self detachNavigationController:self.listNav root:self.listViewController];
    [self detachNavigationController:self.detailNav root:self.conversation ?: self.placeholderViewController];
    self.listNav = nil;
    self.detailNav = nil;
    [self.dividerView removeFromSuperview];

    // 原来是两条 NSAssert：只要构建里没定义 NS_BLOCK_ASSERTIONS（Release 默认就没定义），
    // 命中就是 SIGABRT —— 真机上表现为「旋转 / 分屏拖动后必崩」。改成可恢复的补摘动作：
    // 真正致命的是同一个 view 同时挂在两个控制器上，所以这里再摘一次而不是中断整个重建。
    void (^imForceDetach)(UIViewController *) = ^(UIViewController *controller) {
        if (controller == nil || controller.parentViewController == nil) return;
        [controller willMoveToParentViewController:nil];
        [controller removeFromParentViewController];
    };
    imForceDetach(self.listViewController);
    imForceDetach(self.conversation);

    IMTheme *theme = IMTheme.shared;
    BOOL twoPane = self.twoPane;

    UINavigationController *listNav = [self makeNavigationControllerWithRoot:self.listViewController];
    listNav.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self addChildViewController:listNav];
    [self.view addSubview:listNav.view];
    [listNav didMoveToParentViewController:self];
    self.listNav = listNav;

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    if (twoPane) {
        UINavigationController *detailNav = [self makeNavigationControllerWithRoot:self.conversation ?: self.placeholderViewController];
        detailNav.view.translatesAutoresizingMaskIntoConstraints = NO;
        [self addChildViewController:detailNav];
        [self.view addSubview:detailNav.view];
        [detailNav didMoveToParentViewController:self];
        self.detailNav = detailNav;

        [self.view addSubview:self.dividerView];

        CGFloat width = MIN(IMListPaneMaxWidth, MAX(IMListPaneMinWidth, self.view.bounds.size.width * IMListPaneRatio));
        self.listWidthConstraint = [listNav.view.widthAnchor constraintEqualToConstant:width];

        [NSLayoutConstraint activateConstraints:@[
            self.listWidthConstraint,
            [listNav.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [listNav.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [listNav.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

            [self.dividerView.leadingAnchor constraintEqualToAnchor:listNav.view.trailingAnchor],
            [self.dividerView.widthAnchor constraintEqualToConstant:theme.hairline],
            [self.dividerView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [self.dividerView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

            [detailNav.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [detailNav.view.leadingAnchor constraintEqualToAnchor:self.dividerView.trailingAnchor],
            [detailNav.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [detailNav.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [listNav.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [listNav.view.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
            [listNav.view.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
            [listNav.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        ]];
        if (self.conversation != nil) {
            [listNav pushViewController:self.conversation animated:NO];
        }
    }

    self.interfaceBuilt = YES;
    self.rebuilding = NO;
}

#pragma mark - 会话

- (void)presentConversation:(IMConversationViewController *)conversation {
    self.conversation = conversation;
    self.listViewController.selectedSessionId = conversation.row.sessionId;

    if (self.twoPane) {
        [self.detailNav setViewControllers:@[conversation] animated:NO];
    } else {
        [self.listNav pushViewController:conversation animated:YES];
    }
}

- (void)sessionListViewController:(IMSessionListViewController *)controller didSelectRow:(IMSessionRow *)row {
    IMConversationViewController *conversation = [[IMConversationViewController alloc] initWithSessionRow:row];

    __weak typeof(self) weakSelf = self;
    conversation.onRequirePairing = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self showSettingsTab];
    };
    conversation.onSessionActivity = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self.listViewController noteSessionActivity:row.sessionId];
    };

    [self presentConversation:conversation];
}

- (void)showSettingsTab {
    UITabBarController *tabs = self.tabBarController;
    if (tabs == nil) return;
    [tabs.viewControllers enumerateObjectsUsingBlock:^(__kindof UIViewController *viewController, NSUInteger index, BOOL *stop) {
        if ([viewController.tabBarItem.title isEqualToString:@"设置"]) {
            tabs.selectedIndex = (NSInteger)index;
            *stop = YES;
        }
    }];
}

@end
