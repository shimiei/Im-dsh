//
//  IMPairDeviceViewController.h
//  IMDSH — 在手机上为主机生成一枚新配对码（给另一台设备用）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class IMServer;

@interface IMPairDeviceViewController : UIViewController

/// server 必须已有设备令牌（否侧网关会拒绝生成码，页面会自动进入不可用态）。
- (instancetype)initWithServer:(IMServer *)server;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

