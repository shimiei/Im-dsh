//
//  IMShellController.h
//  IMDSH — 主外壳：会话 / 文件 / 设置 三个入口
//
//  iPhone 上就是系统的液态玻璃标签栏；iPad 上沿用 iPadOS 26 的顶部浮动标签栏，
//  每个页面自己负责宽屏下的分栏（列表 + 详情）。
//

#import <UIKit/UIKit.h>

@interface IMShellController : UITabBarController

/// 重新构建标签（服务器切换、配对变化后可调用）。
- (void)rebuildTabs;

@end
