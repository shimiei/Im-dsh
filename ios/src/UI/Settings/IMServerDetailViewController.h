//
//  IMServerDetailViewController.h
//  IMDSH — 单台主机详情（名称/地址/状态/连接探测 + 切换、重命名、生成配对码、删除）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class IMServer;

@interface IMServerDetailViewController : UIViewController

/// server 必须是 IMServerStore 里已有的主机（按 identifier 实时取最新值）。
- (instancetype)initWithServer:(IMServer *)server;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

