//
//  IMSettingsViewController.h
//  IMDSH — 设置域入口
//
//  负责：当前主机摘要与切换、主机管理入口、本机设备身份、主机上已配对的设备
//  （含吊销）、生成配对码入口、关于信息。具体子流程在各自的控制器里。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 设置域：当前主机、多机管理、设备名、配对码管理入口、关于。
@interface IMSettingsViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
