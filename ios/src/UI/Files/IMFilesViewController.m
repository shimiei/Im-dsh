//
//  IMFilesViewController.m
//  IMDSH — 文件域根页（分栏宿主）
//
//  为什么根页是「拆分视图的宿主」而不是直接一个 UISplitViewController：
//  外壳（IMShellController）把每个 Tab 包在 UINavigationController 里，而 UISplitViewController
//  必须是导航栈的根才不被系统怪异处理。这里做成根页内嵌一个子拆分控制器，Tab 结构不用改，
//  iPad 上自然拿到「树 + 预览」两列，iPhone（compact）上则退化成单列 push。
//

#import "IMFilesViewController.h"

#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFilesBrowserViewController.h"
#import "IMFilePreviewViewController.h"

#pragma mark - 侧滑返回兜底

/// 隐藏导航栏后 UIKit 会顺手关掉侧滑返回（delegate 换了），
/// 但这套界面本来就没有系统返回栏，只剩玻璃条上的返回按钮——补回来更符合直觉。
@interface IMFilesPopGestureEnabler : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UINavigationController *navigationController;
@end

@implementation IMFilesPopGestureEnabler

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return self.navigationController.viewControllers.count > 1;
}

@end

#pragma mark - 根页

@interface IMFilesViewController () <UISplitViewControllerDelegate>

@property (nonatomic, strong) UISplitViewController *splitController;
@property (nonatomic, strong) IMFilesBrowserViewController *browser;
@property (nonatomic, strong) UINavigationController *browserNavigation;
@property (nonatomic, strong) UINavigationController *previewNavigation;
@property (nonatomic, strong) IMFilesPopGestureEnabler *browserPopEnabler;
@property (nonatomic, strong) IMFilesPopGestureEnabler *previewPopEnabler;
@property (nonatomic) BOOL didBuildColumns;

@end

@implementation IMFilesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    IMTheme *theme = IMTheme.shared;
    self.view.backgroundColor = theme.backgroundBase;
    self.title = @"文件";
    [self buildSplitController];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 文件页用自带的玻璃顶栏承载标题/作用域/刷新，系统导航栏留着只会多出一条空条。
    // 只影响本 Tab 的导航栈（每个 Tab 有独立的 UINavigationController）。
    if (self.navigationController.viewControllers.firstObject == self) {
        [self.navigationController setNavigationBarHidden:YES animated:NO];
    }
}

#pragma mark - 搭建

- (void)buildSplitController {
    self.browser = [[IMFilesBrowserViewController alloc] init];
    self.browserNavigation = [self navigationControllerWrapping:self.browser isBrowserColumn:YES];

    IMFilePreviewViewController *placeholder = [IMFilePreviewViewController placeholderController];
    self.previewNavigation = [self navigationControllerWrapping:placeholder isBrowserColumn:NO];

    UISplitViewController *split = [[UISplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
    split.delegate = self;
    split.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    split.preferredSplitBehavior = UISplitViewControllerSplitBehaviorTile;
    split.minimumPrimaryColumnWidth = 300;
    split.maximumPrimaryColumnWidth = 460;
    split.preferredPrimaryColumnWidthFraction = 0.40;
    split.presentsWithGesture = YES;
    split.view.translatesAutoresizingMaskIntoConstraints = NO;
    self.splitController = split;

    [self addChildViewController:split];
    [self.view addSubview:split.view];
    [NSLayoutConstraint activateConstraints:@[
        [split.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [split.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [split.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [split.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [split didMoveToParentViewController:self];

    // 列必须在拆分视图进入视图层级之后再设，否则 iPad 首帧会闪一下空列。
    [split setViewController:self.browserNavigation forColumn:UISplitViewControllerColumnPrimary];
    [split setViewController:self.previewNavigation forColumn:UISplitViewControllerColumnSecondary];
    self.didBuildColumns = YES;

    __weak typeof(self) weakSelf = self;
    self.browser.onOpenEntry = ^(IMFilesEntry *entry, NSString *scopeId) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self openEntry:entry scopeId:scopeId];
    };
}

/// 统一的「黑条」导航控制器：导航栏一律隐藏，返回按钮由各页自己的玻璃条提供。
- (UINavigationController *)navigationControllerWrapping:(UIViewController *)root isBrowserColumn:(BOOL)isBrowserColumn {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBarHidden = YES;
    nav.toolbarHidden = YES;
    nav.view.backgroundColor = IMTheme.shared.backgroundBase;

    IMFilesPopGestureEnabler *enabler = [[IMFilesPopGestureEnabler alloc] init];
    enabler.navigationController = nav;
    nav.interactivePopGestureRecognizer.delegate = enabler;
    if (isBrowserColumn) {
        self.browserPopEnabler = enabler;
    } else {
        self.previewPopEnabler = enabler;
    }
    return nav;
}

#pragma mark - 打开文件

- (void)openEntry:(IMFilesEntry *)entry scopeId:(NSString *)scopeId {
    IMFilePreviewViewController *preview = [[IMFilePreviewViewController alloc] initWithScopeId:scopeId
                                                                                           path:entry.path
                                                                                           name:entry.name
                                                                                           size:entry.size
                                                                                        hasSize:entry.hasSize];
    BOOL compact = self.splitController.isCollapsed || self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    if (compact) {
        // iPhone：真实 push，交给系统做转场和侧滑返回。
        preview.hidesBottomBarWhenPushed = YES;
        [self.browserNavigation pushViewController:preview animated:YES];
        return;
    }
    UINavigationController *nav = [self navigationControllerWrapping:preview isBrowserColumn:NO];
    [self.splitController showDetailViewController:nav sender:self];
}

#pragma mark - UISplitViewControllerDelegate

- (BOOL)splitViewController:(UISplitViewController *)splitViewController
   collapseSecondaryViewController:(UIViewController *)secondaryViewController
      ontoPrimaryViewController:(UIViewController *)primaryViewController {
    // 收起时不保留第二列：手机宽度下第二列通常是「还没选文件」的占位，
    // 真选了文件我们是直接 push 的，所以这里永远可以丢弃。
    return YES;
}

@end
