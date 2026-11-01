//
//  IMPairingViewController.h
//  IMDSH — 首屏配对：填地址 + 配对码
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPairingViewController : UIViewController

/// 由设置页「添加主机」复用时传入，配对成功后回调。
@property (nonatomic, copy, nullable) void (^onPaired)(void);

@end

NS_ASSUME_NONNULL_END
