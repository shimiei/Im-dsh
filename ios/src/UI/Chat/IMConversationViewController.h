//
//  IMConversationViewController.h
//  IMDSH — 聊天页（拉历史 + 订阅增量 + 打字机流式 + 发消息/中断）
//

#import <UIKit/UIKit.h>
#import "IMChatModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMConversationViewController : UIViewController

- (instancetype)initWithSessionRow:(IMSessionRow *)row;
- (instancetype)initWithNibName:(nullable NSString *)nameOrNil bundle:(nullable NSBundle *)bundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) IMSessionRow *row;
/// 未配对时点"去设置"。
@property (nonatomic, copy, nullable) void (^onRequirePairing)(void);
/// 会话有新活动（发出消息 / 收到回复），列表可据此刷新顺序。
@property (nonatomic, copy, nullable) void (^onSessionActivity)(void);

@end

NS_ASSUME_NONNULL_END
