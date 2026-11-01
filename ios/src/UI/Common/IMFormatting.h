//
//  IMFormatting.h
//  IMDSH — 时间格式化 / 容错解析 / 轻提示等小工具
//
//  设置域到处要「最近连接 3 分钟前」「配对码 2026-03-01 到期」这类文案，
//  统一放这里，避免各控制器各写一份 NSDateFormatter（也少踩多处格式不一致的坑）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 会话式相对时间："刚刚" / "5 分钟前" / "今天 14:03" / "昨天 09:12" / "2026年3月1日"。
FOUNDATION_EXPORT NSString *IMRelativeTimeString(NSDate * _Nullable date);
/// 精确到分钟："2026-03-01 14:03"；nil 返回 "—"。
FOUNDATION_EXPORT NSString *IMShortDateTimeString(NSDate * _Nullable date);
/// 容错解析：NSNumber（秒/毫秒按量级自动判断）、ISO 8601 字符串、
/// "yyyy-MM-dd HH:mm:ss"、纯数字字符串；无法识别或 <= 0 时返回 nil。
FOUNDATION_EXPORT NSDate * _Nullable IMDateFromFlexibleValue(id _Nullable value);

/// 复制到剪贴板，并在 hostView 上闪一条玻璃提示；message 为空时默认「已复制」。
FOUNDATION_EXPORT void IMCopyText(NSString * _Nullable text, UIView * _Nullable hostView, NSString * _Nullable message);

/// 只弹提示、不复制（操作成功的轻反馈）。
FOUNDATION_EXPORT void IMShowToast(UIView * _Nullable hostView, NSString * _Nullable message);

/// 清空纵向栈的全部 arrangedSubviews（先解除 arranged 关系再移除，避免残留高度）。
FOUNDATION_EXPORT void IMStackRemoveAllArrangedSubviews(UIStackView *stack);

NS_ASSUME_NONNULL_END
