//
//  IMFilePreviewViewController.h
//  IMDSH — 单个工作区文件的预览页（文本 / 代码 / 图片 / QuickLook / 元信息）
//
//  为什么单独成一个页面：iPhone 上它是 push 出来的详情页，iPad 上是分栏的第二列，
//  两种场景共用同一套「加载中骨架 → 成功 / 失败重试」状态机，避免写两遍。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMFilePreviewViewController : UIViewController

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// scopeId = 会话 id（协议里的 workspaceFileScopeId），path = 工作区相对路径。
/// size/hasSize 来自目录条目，用来在加载前判断「是不是超大文件」。
- (instancetype)initWithScopeId:(NSString *)scopeId
                           path:(NSString *)path
                           name:(NSString *)name
                           size:(unsigned long long)size
                        hasSize:(BOOL)hasSize NS_DESIGNATED_INITIALIZER;

/// iPad 分栏第二列的「还没选文件」占位页。
+ (instancetype)placeholderController;

/// 当前预览的文件路径（分栏宿主用来判断是否同一个文件，避免重复创建）。
@property (nonatomic, copy, readonly) NSString *path;

@end

NS_ASSUME_NONNULL_END
