//
//  IMPairingSheet.h
//  IMDSH — 以 sheet 形式弹出「添加 / 重新配对主机」流程
//
//  设置页、主机管理、主机详情三处入口都要同一套行为：包一层 UINavigationController、
//  补一个「关闭」按钮、配对成功后回调。放在这里统一，避免三份几乎相同的复制。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 弹出配对流程（内部是 IMPairingViewController）。
/// 配对页成功后自己会 dismiss；本函数额外提供「关闭」入口，避免用户误入后无路可退。
void IMPresentPairingSheet(UIViewController *presenter, void (^ _Nullable onPaired)(void));

NS_ASSUME_NONNULL_END
