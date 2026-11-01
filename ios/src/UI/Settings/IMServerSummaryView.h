//
//  IMServerSummaryView.h
//  IMDSH — 当前主机摘要卡（名称 / 状态徽标 / 地址 / 最近连接）
//
//  设置首页和主机详情页都要「一眼看清这台主机是谁、通不通」，
//  用同一块卡，保证两处信息布局和状态语义完全一致。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class IMServer;

@interface IMServerSummaryView : UIControl

/// server 为 nil 时渲染空态（引导添加主机）。
+ (instancetype)viewWithServer:(nullable IMServer *)server;

/// 传 nil 进入空态。
- (void)updateWithServer:(nullable IMServer *)server;

/// 点击回调；设置后玻璃会变成可交互材质（按压有液态回弹）。
@property (nonatomic, copy, nullable) void (^onTap)(void);

@end

NS_ASSUME_NONNULL_END
