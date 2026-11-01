#import <UIKit/UIKit.h>
#import "IMAppDelegate.h"
#import "IMCrashReporter.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 尽早装上崩溃捕获：之后任何未捕获异常或致命信号都会落盘到 Documents/IMDSH-logs。
        [IMCrashReporter install];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([IMAppDelegate class]));
    }
}
