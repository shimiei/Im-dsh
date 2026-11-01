#import "IMCrashReporter.h"

#import <UIKit/UIKit.h>
#import <execinfo.h>
#import <signal.h>
#import <string.h>
#import <unistd.h>
#import <fcntl.h>
#import <sys/time.h>

static NSString *const IMCrashLogDirectoryName = @"IMDSH-logs";
static const unsigned long long IMRunningLogLimit = 512 * 1024;
static const int IMCrashBacktraceDepth = 64;

@implementation IMCrashReporter

#pragma mark - 路径

+ (NSURL *)logDirectory {
    static NSURL *dir = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSURL *docs = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        if (docs == nil) return;
        NSURL *target = [docs URLByAppendingPathComponent:IMCrashLogDirectoryName isDirectory:YES];
        if (![fm createDirectoryAtURL:target withIntermediateDirectories:YES attributes:nil error:NULL]) return;
        dir = target;
    });
    return dir;
}

+ (NSArray<NSURL *> *)crashLogs {
    NSURL *dir = [self logDirectory];
    if (dir == nil) return @[];
    NSArray<NSURL *> *all = [NSFileManager.defaultManager contentsOfDirectoryAtURL:dir
                                                      includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                           error:NULL];
    NSMutableArray<NSURL *> *matched = [NSMutableArray array];
    for (NSURL *url in all ?: @[]) {
        if ([url.lastPathComponent hasPrefix:@"crash-"] && [url.pathExtension isEqualToString:@"log"]) {
            [matched addObject:url];
        }
    }
    [matched sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *da = nil;
        NSDate *db = nil;
        [a getResourceValue:&da forKey:NSURLContentModificationDateKey error:NULL];
        [b getResourceValue:&db forKey:NSURLContentModificationDateKey error:NULL];
        return [(db ?: NSDate.distantPast) compare:(da ?: NSDate.distantPast)];
    }];
    return matched.count > 20 ? [matched subarrayWithRange:NSMakeRange(0, 20)] : matched;
}

static NSString *IMTimestamp(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm parts;
    time_t seconds = tv.tv_sec;
    localtime_r(&seconds, &parts);
    char buffer[40];
    snprintf(buffer, sizeof(buffer), "%04d-%02d-%02d %02d:%02d:%02d.%03d",
             parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday,
             parts.tm_hour, parts.tm_min, parts.tm_sec, (int)(tv.tv_usec / 1000));
    return [NSString stringWithUTF8String:buffer] ?: @"?";
}

static NSString *IMFileNameTimestamp(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm parts;
    time_t seconds = tv.tv_sec;
    localtime_r(&seconds, &parts);
    char buffer[40];
    snprintf(buffer, sizeof(buffer), "%04d%02d%02d-%02d%02d%02d-%03d",
             parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday,
             parts.tm_hour, parts.tm_min, parts.tm_sec, (int)(tv.tv_usec / 1000));
    return [NSString stringWithUTF8String:buffer] ?: @"0";
}

static NSString *IMDeviceSummary(void) {
    UIDevice *device = UIDevice.currentDevice;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary ?: @{};
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = info[@"CFBundleVersion"] ?: @"?";
    return [NSString stringWithFormat:@"%@ %@ (%@) / iOS %@ / theme %@",
            device.model, device.systemName, device.systemVersion, version, build];
}

#pragma mark - 运行日志

+ (void)log:(NSString *)format, ... {
    if (format.length == 0) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (message == nil) return;

    NSLog(@"[IMDSH] %@", message);

    NSURL *dir = [self logDirectory];
    if (dir == nil) return;
    NSURL *file = [dir URLByAppendingPathComponent:@"running.log"];
    NSString *line = [NSString stringWithFormat:@"%@ [%@] %@\n",
                      IMTimestamp(),
                      NSThread.isMainThread ? @"main" : (NSThread.currentThread.name ?: @"bg"),
                      message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) return;

    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:file.path]) {
        [data writeToURL:file atomically:YES];
        return;
    }
    // 环形：超过上限就整体截断重来。日志只用于看最近发生了什么，不需要归档。
    NSDictionary *attrs = [fm attributesOfItemAtPath:file.path error:NULL];
    if ([attrs[NSFileSize] unsignedLongLongValue] > IMRunningLogLimit) {
        [data writeToURL:file atomically:YES];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:file.path];
    if (handle == nil) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
    } @catch (__unused NSException *exception) {
        // 日志写不进去也不能影响主流程。
    } @finally {
        [handle closeFile];
    }
}

#pragma mark - 崩溃捕获

static void IMWriteCrashFile(NSString *body) {
    NSURL *dir = [IMCrashReporter logDirectory];
    NSString *text = body ?: @"(empty)";
    NSLog(@"[IMDSH] crash captured:\n%@", text);
    if (dir == nil) return;
    NSString *name = [NSString stringWithFormat:@"crash-%@.log", IMFileNameTimestamp()];
    NSURL *file = [dir URLByAppendingPathComponent:name];
    [[text dataUsingEncoding:NSUTF8StringEncoding] writeToURL:file atomically:YES];
}

+ (void)writeCrashFile:(NSString *)body {
    IMWriteCrashFile(body);
}

static void IMUncaughtExceptionHandler(NSException *exception) {
    NSMutableString *text = [NSMutableString string];
    [text appendString:@"==== IMDSH 未捕获异常 ====\n"];
    [text appendFormat:@"时间      %@\n", IMTimestamp()];
    [text appendFormat:@"设备      %@\n", IMDeviceSummary()];
    [text appendFormat:@"异常名    %@\n", exception.name ?: @"?"];
    [text appendFormat:@"原因      %@\n", exception.reason ?: @"?"];
    [text appendString:@"--- 调用栈 ---\n"];
    for (NSString *symbol in exception.callStackSymbols ?: @[]) {
        [text appendFormat:@"%@\n", symbol];
    }
    NSDictionary *userInfo = exception.userInfo;
    if (userInfo.count > 0) {
        [text appendFormat:@"--- userInfo ---\n%@\n", userInfo];
    }
    [text appendFormat:@"--- 全部线程 ---\n%@\n", NSThread.callStackSymbols ?: @[]];
    [IMCrashReporter writeCrashFile:text];
}

static const char *IMSignalNameC(int signalNumber) {
    switch (signalNumber) {
        case SIGABRT: return "SIGABRT (abort：未捕获的 ObjC 异常或断言)";
        case SIGSEGV: return "SIGSEGV (野指针 / 访问非法内存)";
        case SIGBUS: return "SIGBUS (内存对齐 / 映射问题)";
        case SIGILL: return "SIGILL (非法指令)";
        case SIGFPE: return "SIGFPE (算术异常)";
        case SIGTRAP: return "SIGTRAP (调试陷阱)";
        default: return "unknown signal";
    }
}

/// install 时填好，信号上下文里直接读：信号处理器里不能调用任何 ObjC / malloc / dispatch_once。
static char IMCrashDirectoryPath[PATH_MAX] = {0};

static void IMSignalHandler(int signalNumber, siginfo_t *info, void *context) {
    char header[512];
    int length = snprintf(header, sizeof(header),
                          "\n==== IMDSH 收到信号 ====\nsignal %d: %s\naddr %p\n",
                          signalNumber,
                          IMSignalNameC(signalNumber),
                          info != NULL ? info->si_addr : NULL);
    int fd = -1;
    if (IMCrashDirectoryPath[0] != '\0') {
        char path[PATH_MAX];
        struct timeval tv;
        gettimeofday(&tv, NULL);
        snprintf(path, sizeof(path), "%s/crash-signal-%lld.log",
                 IMCrashDirectoryPath, (long long)tv.tv_sec);
        fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    }
    int target = fd >= 0 ? fd : STDERR_FILENO;
    if (length > 0) {
        ssize_t ignored = write(target, header, (size_t)length);
        (void)ignored;
        void *frames[IMCrashBacktraceDepth];
        int count = backtrace(frames, IMCrashBacktraceDepth);
        backtrace_symbols_fd(frames, count, target);
    }
    if (fd >= 0) close(fd);

    // 恢复默认处理并重新抛出，保持系统原本的崩溃行为（不要吞掉信号）。
    signal(signalNumber, SIG_DFL);
    raise(signalNumber);
}

+ (void)install {
    NSSetUncaughtExceptionHandler(&IMUncaughtExceptionHandler);

    // SIGPIPE 默认会杀掉进程：App 里 socket 写入竞争很常见，改成忽略。
    signal(SIGPIPE, SIG_IGN);

    static const int signals[] = {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP};
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = IMSignalHandler;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    for (size_t index = 0; index < sizeof(signals) / sizeof(signals[0]); index += 1) {
        sigaction(signals[index], &action, NULL);
    }

    [self log:@"==== 启动 ==== %@", IMDeviceSummary()];
    [self log:@"日志目录 %@", [self logDirectory].path ?: @"(不可用)"];
}

@end
