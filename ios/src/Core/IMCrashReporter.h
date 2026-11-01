#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 极简崩溃与运行日志。
///
/// 为什么需要它：这个 App 没有 Mac / Xcode / 真机调试通道，出问题时唯一能拿到
/// 现场证据的办法就是让它自己把堆栈写到 Documents 里，再用「文件」App 取出来。
///
/// 产物（都在 App 的 Documents/IMDSH-logs/ 下）：
///   crash-<时间>.log   崩溃现场：异常名 / 原因 / 调用栈，或信号名 + 回溯
///   running.log        运行日志（环形，超过 512 KB 自动截断），记录关键节点与计数
@interface IMCrashReporter : NSObject

/// 安装崩溃捕获。在 main.m 里尽早调用。
+ (void)install;

/// 运行日志。会带上时间戳与当前线程名，追加到 running.log。
+ (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

/// 日志目录（不存在会自动创建）。取不到时返回 nil。
+ (nullable NSURL *)logDirectory;

/// 已经记录的崩溃日志路径（按时间倒序，最多 20 条）。
+ (NSArray<NSURL *> *)crashLogs;

@end

NS_ASSUME_NONNULL_END
