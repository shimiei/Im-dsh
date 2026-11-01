//
//  IMSessionListViewController.h
//  IMDSH — 会话列表（倒序、相对时间、运行态、子会话弱化、下拉刷新、分页）
//

#import <UIKit/UIKit.h>
#import "IMChatModels.h"

NS_ASSUME_NONNULL_BEGIN

@class IMSessionListViewController;

@protocol IMSessionListViewControllerDelegate <NSObject>
- (void)sessionListViewController:(IMSessionListViewController *)controller didSelectRow:(IMSessionRow *)row;
@end

@interface IMSessionListViewController : UIViewController

@property (nonatomic, weak, nullable) id<IMSessionListViewControllerDelegate> delegate;
/// 当前选中会话（iPad 双列时高亮）。
@property (nonatomic, copy, nullable) NSString *selectedSessionId;
/// 未配对时点"去设置"的回调（由外层切到设置页）。
@property (nonatomic, copy, nullable) void (^onRequirePairing)(void);

/// 重新拉一次列表（下拉刷新 / 回到前台 / 发完消息后）。
- (void)reloadSessions;
/// 本机会话有了新活动：只把该行的更新时间顶到最前再排序，不为此重新请求列表。
- (void)noteSessionActivity:(NSString *)sessionId;

@end

NS_ASSUME_NONNULL_END
