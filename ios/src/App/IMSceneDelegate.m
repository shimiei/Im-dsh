#import "IMSceneDelegate.h"
#import "IMServerStore.h"
#import "IMTheme.h"
#import "IMShellController.h"
#import "IMPairingViewController.h"

@interface IMSceneDelegate ()
@property (nonatomic, assign) BOOL observing;
@end

@implementation IMSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];
    window.backgroundColor = IMTheme.shared.backgroundBase;
    self.window = window;

    [self installRootControllerAnimated:NO];
    [window makeKeyAndVisible];

    if (!self.observing) {
        self.observing = YES;
        [NSNotificationCenter.defaultCenter addObserver:self
                                              selector:@selector(serverStoreDidChange:)
                                                  name:IMServerStoreDidChangeNotification
                                                object:nil];
    }
}

- (void)serverStoreDidChange:(NSNotification *)notification {
    BOOL needsPairing = IMServerStore.shared.currentServer == nil;
    BOOL showingPairing = [self.window.rootViewController isKindOfClass:IMPairingViewController.class]
        || [self.window.rootViewController isKindOfClass:UINavigationController.class];
    if (showingPairing != needsPairing) {
        [self installRootControllerAnimated:YES];
    }
}

- (void)installRootControllerAnimated:(BOOL)animated {
    UIViewController *root;
    if (IMServerStore.shared.currentServer == nil) {
        IMPairingViewController *pairing = [[IMPairingViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:pairing];
        nav.navigationBar.prefersLargeTitles = YES;
        root = nav;
    } else {
        root = [[IMShellController alloc] init];
    }

    if (animated && self.window.rootViewController != nil) {
        [UIView transitionWithView:self.window
                          duration:0.32
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
            self.window.rootViewController = root;
        } completion:nil];
    } else {
        self.window.rootViewController = root;
    }
}

@end
