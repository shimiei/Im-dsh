#import <UIKit/UIKit.h>

@interface DemoAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation DemoAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.systemBackgroundColor;

    // Liquid Glass: available iOS 26+; the 27.2 SDK declares it, so reference the class directly.
    UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    effect.interactive = YES;
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    glass.layer.cornerRadius = 24;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    [root.view addSubview:glass];

    UILabel *label = [UILabel new];
    label.text = @"IMDSH liquid glass probe";
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [glass.contentView addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [glass.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
        [glass.centerYAnchor constraintEqualToAnchor:root.view.centerYAnchor],
        [glass.widthAnchor constraintEqualToConstant:260],
        [glass.heightAnchor constraintEqualToConstant:96],
        [label.centerXAnchor constraintEqualToAnchor:glass.contentView.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:glass.contentView.centerYAnchor],
    ]];

    window.rootViewController = root;
    [window makeKeyAndVisible];
    self.window = window;
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([DemoAppDelegate class]));
    }
}
