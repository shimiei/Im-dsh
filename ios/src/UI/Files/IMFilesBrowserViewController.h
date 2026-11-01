//
//  IMFilesBrowserViewController.h
//  IMDSH — 工作区文件树页：会话作用域胶囊 + 面包屑 + 目录列表
//
#import <UIKit/UIKit.h>
#import "IMFilesService.h"

NS_ASSUME_NONNULL_BEGIN

/// 「在会话中打开」请求：文件域只负责把 dsh-resource 地址交给系统剪贴板并广播这条通知，
/// 聊天域（UI/Chat）想接管输入框预填时监听即可——文件域不直接依赖聊天域。
FOUNDATION_EXPORT NSNotificationName const IMFilesDidRequestOpenInSessionNotification;
FOUNDATION_EXPORT NSString *const IMFilesNotificationScopeIdKey;
FOUNDATION_EXPORT NSString *const IMFilesNotificationPathKey;
FOUNDATION_EXPORT NSString *const IMFilesNotificationResourceAddressKey;

@interface IMFilesBrowserViewController : UIViewController

/// 用户点开一个文件时回调：宿主决定 iPhone push 还是 iPad 第二列。
@property (nonatomic, copy, nullable) void (^onOpenEntry)(IMFilesEntry *entry, NSString *scopeId);

/// 当前会话作用域（工作区根由它决定）；nil 表示还没选到。
@property (nonatomic, copy, readonly, nullable) NSString *scopeId;
/// 当前目录（工作区相对路径，根目录是空串）。
@property (nonatomic, copy, readonly) NSString *currentPath;

/// 外部指定作用域（例如从会话里跳过来）。会记住，下次打开优先它。
- (void)applyScopeId:(NSString *)scopeId sessionTitle:(nullable NSString *)title;
/// 回到工作区根并重新拉取。
- (void)reloadFromRoot;

@end

NS_ASSUME_NONNULL_END
