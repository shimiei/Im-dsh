//
//  IMPairingSheet.m
//  IMDSH — 「添加 / 重新配对主机」的统一弹窗
//

#import "IMPairingSheet.h"
#import "IMPairingViewController.h"

#import <objc/runtime.h>

/// 关闭按钮的 target：UIBarButtonItem 不持有 target，所以必须有人活着。
/// 这里把它 associate 到 nav 上，随弹窗一起释放。
@interface IMPairingSheetDismisser : NSObject
@property (nonatomic, weak, nullable) UIViewController *presenter;
@end

@implementation IMPairingSheetDismisser

- (void)dismiss:(id)sender {
    [self.presenter dismissViewControllerAnimated:YES completion:nil];
}

@end

void IMPresentPairingSheet(UIViewController *presenter, void (^onPaired)(void)) {
    if (presenter == nil) return;

    IMPairingViewController *pairing = [[IMPairingViewController alloc] init];
    pairing.onPaired = onPaired;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:pairing];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;

    IMPairingSheetDismisser *dismisser = [[IMPairingSheetDismisser alloc] init];
    dismisser.presenter = presenter;

    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                              target:dismisser
                                                                              action:@selector(dismiss:)];
    closeItem.accessibilityLabel = @"关闭";
    pairing.navigationItem.leftBarButtonItem = closeItem;

    static const void *IMPairingSheetDismisserKey = &IMPairingSheetDismisserKey;
    objc_setAssociatedObject(nav, IMPairingSheetDismisserKey, dismisser, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [presenter presentViewController:nav animated:YES completion:nil];
}
