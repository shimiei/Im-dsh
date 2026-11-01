//
//  IMChatViewController.h
//  IMDSH — 会话域容器：iPhone 单列（列表 → 聊天），iPad 双列（列表 + 聊天并排）
//
//  为什么不直接用 UISplitViewController：外壳（IMShellController）把每个标签页都包了一层
//  UINavigationController，而 split view controller 必须是导航根才安全；这里用自建双列容器
//  达到同样的并排效果，且能随分屏/旋转自由切换。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChatViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
