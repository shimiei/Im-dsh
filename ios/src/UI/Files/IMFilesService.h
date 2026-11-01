//
//  IMFilesService.h
//  IMDSH — 文件域 RPC 门面：会话列表 + workspaceFiles/{list,stat,read,readBytes,changes}
//
//  为什么要这一层：Net/IMDSHClient 只暴露 call:args:completion:，而四个文件端点的
//  返回形状各不相同（目录条目没有修改时间、read 是「行窗口」、readBytes 的字节走
//  multipart 附件），错误码也是 workspace-file/* 这种协议黑话。这里一次性把 JSON
//  收敛成模型、把错误翻成中文，UI 侧完全不碰原始 JSON。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class IMDSHClient;

#pragma mark - 目录条目

typedef NS_ENUM(NSInteger, IMFilesEntryType) {
    IMFilesEntryTypeFile = 0,
    IMFilesEntryTypeDirectory,
    /// 既不是普通文件也不是目录（设备、socket、以及 read 会拒绝的符号链接）。
    IMFilesEntryTypeOther,
};

/// 目录里的一个子项（contract: WorkspaceDirectoryEntry）。
@interface IMFilesEntry : NSObject

@property (nonatomic, copy) NSString *name;
/// 工作区相对路径，直接喂给 stat/read/readBytes。
@property (nonatomic, copy) NSString *path;
@property (nonatomic) IMFilesEntryType type;
@property (nonatomic) BOOL hasSize;
@property (nonatomic) unsigned long long size;
/// 修改时间。协议**没有**这个字段（contract 只有 name/type/size），
/// 这里只在后端额外塞了 mtime/version 时间戳时才有值，UI 必须容忍 nil。
@property (nonatomic, strong, nullable) NSDate *modifiedAt;

@property (nonatomic, readonly) BOOL isDirectory;

@end

/// 一次目录列表（contract: WorkspaceDirectoryListing）。
@interface IMFilesListing : NSObject

/// 该目录自身的工作区相对路径，根目录是空串。
@property (nonatomic, copy) NSString *path;
/// 已排序：文件夹在前，其余按名称自然序（中文/数字都能排对）。
@property (nonatomic, copy) NSArray<IMFilesEntry *> *entries;
/// 后端条目上限截断过。
@property (nonatomic) BOOL truncated;

@end

#pragma mark - 会话（文件作用域）

/// 一个会话 = 一个工作区作用域（workspaceFileScopeId）。
@interface IMFilesSession : NSObject

@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *cwd;
@property (nonatomic, strong, nullable) NSDate *updatedAt;

/// 胶囊上显示的短标题：会话标题 → cwd 尾段 → sessionId 尾段。
@property (nonatomic, readonly) NSString *displayName;
/// cwd 尾段（"dsh-webim"），副标题用；没有 cwd 时返回空串。
@property (nonatomic, readonly) NSString *cwdTail;

@end

#pragma mark - 文本页

/// 一页文本（contract: WorkspaceFileText）。read 是按行分页的，所以「加载全文」
/// 在协议里就是不断要下一页。
@interface IMFilesTextPage : NSObject

@property (nonatomic) NSInteger offset;
@property (nonatomic) NSInteger lines;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) BOOL eof;
@property (nonatomic) BOOL hasTotalBytes;
@property (nonatomic) unsigned long long totalBytes;
@property (nonatomic, copy, nullable) NSString *absolutePath;
@property (nonatomic, copy, nullable) NSString *version;

@end

#pragma mark - 服务

typedef void (^IMFilesSessionsHandler)(NSArray<IMFilesSession *> * _Nullable sessions, NSError * _Nullable error);
typedef void (^IMFilesListingHandler)(IMFilesListing * _Nullable listing, NSError * _Nullable error);
typedef void (^IMFilesStatHandler)(BOOL hasBytes, unsigned long long bytes, NSString * _Nullable version, NSError * _Nullable error);
typedef void (^IMFilesTextHandler)(IMFilesTextPage * _Nullable page, NSError * _Nullable error);
typedef void (^IMFilesBytesHandler)(NSData * _Nullable data, NSDictionary * _Nullable meta, NSError * _Nullable error);

@interface IMFilesService : NSObject

+ (instancetype)shared;

/// 文件域自己的错误域：只描述「本机状态不够」这类本地判定，主机错误仍走 IMDSHClientErrorDomain。
FOUNDATION_EXPORT NSString *const IMFilesErrorDomain;

typedef NS_ENUM(NSInteger, IMFilesErrorCode) {
    /// 还没配对：没有主机，或主机的设备 token 已被吊销。此时所有请求立刻短路，UI 要引导去设置。
    IMFilesErrorCodeUnpaired = 4010,
    /// 主机回包形状不对（JSON 不是预期的 {"value":…}）。
    IMFilesErrorCodeBadResponse = 4011,
    /// 还没选定作用域（没有会话可以当工作区）：此时请求必然拿到 gateway/lookup-failed，
    /// 所以在本地就短路掉，UI 拿去显示「先选一个会话」。
    IMFilesErrorCodeNoScope = 4012,
};

/// 是否配置了主机（可能是未配对状态）。
@property (nonatomic, readonly) BOOL hasServer;
/// 是否已配对：有主机且拿到设备 token。NO 时文件域一律短路，UI 应给「重新配对」引导。
@property (nonatomic, readonly) BOOL isPaired;
/// 按当前主机缓存的客户端：同一台主机复用一条连接，避免每个页面开一条 WS。
@property (nonatomic, readonly, nullable) IMDSHClient *client;

/// 丢弃缓存客户端并断开连接。配对状态变更（吊销/重新配对/换主机）后必须调用：
/// 旧客户端里揣着已作废的 token，继续用只会拿到 401。
- (void)discardClient;

- (void)loadSessionsWithCompletion:(IMFilesSessionsHandler)completion;
- (void)listDirectory:(NSString *)path scopeId:(NSString *)scopeId completion:(IMFilesListingHandler)completion;
- (void)statPath:(NSString *)path scopeId:(NSString *)scopeId completion:(IMFilesStatHandler)completion;
- (void)readTextPath:(NSString *)path
             scopeId:(NSString *)scopeId
              offset:(NSInteger)offset
               limit:(NSInteger)limit
          completion:(IMFilesTextHandler)completion;
- (void)readBytesPath:(NSString *)path scopeId:(NSString *)scopeId completion:(IMFilesBytesHandler)completion;

/// 订阅目录变动（workspaceFiles/changes，stream）。目录变化后回调，调用方自行去抖。
- (void)watchPath:(NSString *)path
          scopeId:(NSString *)scopeId
         streamId:(NSString *)streamId
         onChange:(void (^)(void))onChange
          onError:(void (^)(NSError *error))onError;
- (void)stopWatching:(NSString *)streamId;

/// 协议错误 → 中文一句话（权限/不存在/太大/不是文本…）。
+ (NSString *)messageForError:(NSError *)error;
/// 第二行细节（可显示"文件位于工作区外"这类补充）；没有就返回 nil。
+ (nullable NSString *)detailForError:(NSError *)error;
/// 是否属于「这个文件注定打不开」的硬错误（权限/超大/非文本），用于决定是否给重试按钮。
+ (BOOL)isRetryableError:(NSError *)error;

/// dsh-resource 地址：`dsh-resource://file/session/<sessionId>/<path>`，
/// 用于「在会话中打开/引用」时把文件地址交给别的域（剪贴板/消息草稿）。
+ (NSString *)resourceAddressForScopeId:(NSString *)scopeId path:(NSString *)path;

/// workspace 相对路径拆段（"a/b/c.txt" → @[@"a", @"b", @"c.txt"]；根路径返回空数组）。
+ (NSArray<NSString *> *)pathComponentsForWorkspacePath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
