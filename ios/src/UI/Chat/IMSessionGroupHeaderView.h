//
//  IMSessionGroupHeaderView.h
//  IMDSH — 会话列表的项目分组表头（吸顶、可点、带旋转箭头）
//
//  为什么单独一个类：分组表头是「吸顶 + 折叠」的唯一入口，会话列表页里还要处理
//  搜索扁平化、显示更多、投影刷新，塞在一个文件里会互相牵制；抽出来以后表头的
//  视觉（玻璃 + 箭头旋转）和交互（点击折叠）都能独立演进。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 会话列表的项目分组表头：项目名 + 会话条数 + 运行中提示 + 展开/收起箭头。
/// 整块可点，点击回调交给列表页处理（表头自己不改数据）。
@interface IMSessionGroupHeaderView : UIView

/// 点击回调：列表页负责改折叠状态并刷新表格。
@property (nonatomic, copy, nullable) void (^onToggle)(void);

/// 是否处于收起状态（箭头朝向由它决定）。
@property (nonatomic, assign, readonly, getter=isCollapsed) BOOL collapsed;

/// 一次性刷新全部内容；animated = YES 时箭头带旋转动画。
- (void)updateWithProjectName:(nullable NSString *)projectName
                 sessionCount:(NSInteger)sessionCount
                 runningCount:(NSInteger)runningCount
                    collapsed:(BOOL)collapsed
                     animated:(BOOL)animated;

/// 只同步箭头朝向：折叠动画进行中调用，避免整块内容重建。
- (void)setCollapsed:(BOOL)collapsed animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
