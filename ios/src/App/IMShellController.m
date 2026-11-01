#import "IMShellController.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMChatViewController.h"
#import "IMFilesViewController.h"
#import "IMSettingsViewController.h"

@implementation IMShellController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = IMTheme.shared.backgroundBase;
    [self rebuildTabs];
}

- (UINavigationController *)wrap:(UIViewController *)controller title:(NSString *)title image:(NSString *)imageName {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    nav.navigationBar.prefersLargeTitles = YES;
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
                                                   image:IMSymbol(imageName, 20, UIImageSymbolWeightRegular)
                                                     tag:0];
    nav.tabBarItem.title = title;
    return nav;
}

- (void)rebuildTabs {
    UIViewController *chat = [self wrap:[[IMChatViewController alloc] init] title:@"会话" image:@"bubble.left.and.bubble.right"];
    UIViewController *files = [self wrap:[[IMFilesViewController alloc] init] title:@"文件" image:@"folder"];
    UIViewController *settings = [self wrap:[[IMSettingsViewController alloc] init] title:@"设置" image:@"gearshape"];

    self.viewControllers = @[chat, files, settings];
}

@end
