#import "IMAppDelegate.h"
#import "IMTheme.h"

@implementation IMAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 让系统的玻璃材质在整棵树上生效：窗口透明 + 内容自绘背景。
    [[UIView appearance] setTintColor:IMTheme.shared.accentColor];
    return YES;
}

@end
