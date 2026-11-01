//
//  IMMessageCardViews.h
//  IMDSH — 消息内的四类卡片：推理折叠行、工具调用卡、待办清单、提示条
//
//  为什么拆成独立视图：这四类都是"可折叠 + 展开后高度变化"的卡片，
//  放在 cell 里内联实现会互相纠缠行高；独立视图各自负责自身高度，外层只管重算。
//

#import <UIKit/UIKit.h>
#import "IMChatModels.h"

NS_ASSUME_NONNULL_BEGIN

/// 推理（reasoning）：默认折叠成一行「思考了 N 秒 · 点开」，展开显示灰色等宽正文。
@interface IMReasoningFoldView : UIView

@property (nonatomic, copy, nullable) void (^onHeightChange)(void);
/// 展开状态变化（外部需要把状态写回模型，避免 cell 复用时丢失）。
@property (nonatomic, copy, nullable) void (^onToggle)(BOOL expanded);

@property (nonatomic, assign, readonly) BOOL expanded;

- (void)configureWithText:(NSString *)text seconds:(NSTimeInterval)seconds expanded:(BOOL)expanded inProgress:(BOOL)inProgress;

@end

/// 工具调用：一行卡片，图标 + 工具名 + 参数摘要 + 状态点；展开显示参数与结果。
@interface IMToolCallCardView : UIView

@property (nonatomic, copy, nullable) void (^onHeightChange)(void);
@property (nonatomic, copy, nullable) void (^onToggle)(NSString *callId, BOOL expanded);

- (void)configureWithEntry:(IMToolCallEntry *)entry;
/// 只刷新状态点（流式过程中参数在变，不必重建整张卡）。
- (void)refreshStatus;

@end

/// 待办清单：可折叠，勾选态用符号表示。
@interface IMTodoCardView : UIView

@property (nonatomic, copy, nullable) void (^onHeightChange)(void);
@property (nonatomic, copy, nullable) void (^onToggle)(BOOL expanded);

@property (nonatomic, assign, readonly) BOOL expanded;

- (void)configureWithTodos:(NSArray<IMTodoEntry *> *)todos expanded:(BOOL)expanded;

@end

/// 提示条：错误 / 中断 / 状态说明，灰底一行。
@interface IMNoticeBarView : UIView

- (void)configureWithText:(NSString *)text isError:(BOOL)isError;

@end

NS_ASSUME_NONNULL_END
