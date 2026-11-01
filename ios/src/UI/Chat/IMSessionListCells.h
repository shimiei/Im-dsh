//
//  IMSessionListCells.h
//  IMDSH — 会话列表的两种行：会话行 / 「显示更多」行
//
//  为什么单独拆出来：列表页要同时管分组、折叠、分批显示、搜索、投影刷新，
//  行内的视觉（卡片圆角随位置变化、呼吸点、选中态）放这里才不会互相牵连。
//

#import <UIKit/UIKit.h>
#import "IMChatModels.h"

NS_ASSUME_NONNULL_BEGIN

/// 行在卡片里的位置：决定哪几个角是圆的、要不要画分隔线。
/// 同一分组的行拼成一张连续卡片（首行圆上角、末行圆下角、中间直角）。
typedef NS_ENUM(NSInteger, IMSessionListCellPosition) {
    IMSessionListCellPositionSingle = 0,
    IMSessionListCellPositionTop,
    IMSessionListCellPositionMiddle,
    IMSessionListCellPositionBottom,
};

/// 一条会话：标题 + 相对时间/用量 + 运行中呼吸点 + 当前会话高亮。
@interface IMSessionListRowCell : UITableViewCell

- (void)configureWithRow:(IMSessionRow *)row
                position:(IMSessionListCellPosition)position
               isCurrent:(BOOL)isCurrent;

/// 只更新卡片形状（「显示更多」插入/删除行后，首尾行的圆角会变）。
- (void)applyCardPosition:(IMSessionListCellPosition)position;
/// 只更新「当前会话」高亮（iPad 双列切换选中时用，不重建整行）。
- (void)setCurrentSession:(BOOL)isCurrent;

@end

/// 分组末尾的「显示更多（还有 N 条）」/「收起」行。
@interface IMSessionListShowMoreCell : UITableViewCell

/// hiddenCount > 0 → 显示「显示更多（还有 N 条）」；== 0 → 显示「收起」。
- (void)configureWithHiddenCount:(NSInteger)hiddenCount position:(IMSessionListCellPosition)position;

- (void)applyCardPosition:(IMSessionListCellPosition)position;

@end

NS_ASSUME_NONNULL_END
