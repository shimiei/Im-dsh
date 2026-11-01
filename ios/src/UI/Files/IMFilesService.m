//
//  IMFilesService.m
//  IMDSH — 文件域 RPC 门面
//
//  协议依据（imdsh/docs/protocol.md）：
//   · §7.1 session/list → args {"_request":{}}，item 里有 sessionId/cwd/origin/projections.values.title
//   · §7.2 workspaceFiles/list|read|stat、§8.3 workspaceFiles/readBytes（multipart）
//   · args 是「字段集合精确相等」校验：多一个少一个都会 gateway/arguments-invalid，
//     所以这里每个端点的 args 都是手写的最小集合，绝不复用同一个字典。
//

#import "IMFilesService.h"
#import "IMDSHClient.h"
#import "IMServerStore.h"
#import "IMFormatting.h"
#import "IMTheme.h"

NSString *const IMFilesErrorDomain = @"IMFilesErrorDomain";

#pragma mark - 基础工具

static NSNumber *IMNumberOrNil(id value) {
    return [value isKindOfClass:NSNumber.class] ? (NSNumber *)value : nil;
}

static NSString *IMStringOrNil(id value) {
    if ([value isKindOfClass:NSString.class]) return (NSString *)value;
    return nil;
}

static NSDictionary *IMDictOrNil(id value) {
    return [value isKindOfClass:NSDictionary.class] ? (NSDictionary *)value : nil;
}

/// 目录条目里协议没给的字段（修改时间）只能碰运气：
/// 后端如果塞了 mtime/mtimeMs/updatedAt 就用；version 一般不透明，只有它本身
/// 看起来像时间戳时才认（IMDateFromFlexibleValue 对乱码返回 nil，不会误判）。
static NSDate *IMEntryModifiedDate(NSDictionary *json) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"mtime", @"mtimeMs", @"modifiedAt", @"modified", @"updatedAt", @"ctime"];
    });
    for (NSString *key in keys) {
        NSDate *date = IMDateFromFlexibleValue(json[key]);
        if (date != nil) return date;
    }
    return IMDateFromFlexibleValue(json[@"version"]);
}

#pragma mark - IMFilesEntry

@interface IMFilesEntry ()
@property (nonatomic) BOOL isDirectory;
@end

@implementation IMFilesEntry

- (NSString *)description {
    return [NSString stringWithFormat:@"<IMFilesEntry %@ %@ size=%llu>",
            self.isDirectory ? @"dir" : @"file", self.path, self.size];
}

@end

#pragma mark - IMFilesListing

@implementation IMFilesListing

- (instancetype)init {
    self = [super init];
    if (self) {
        _path = @"";
        _entries = @[];
    }
    return self;
}

@end

#pragma mark - IMFilesSession

@implementation IMFilesSession

- (NSString *)cwdTail {
    NSString *cwd = [self.cwd stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (cwd.length == 0) return @"";
    // 后端跑在 Windows 上，"C:\\Users\\x\\proj" 的尾段要按反斜杠切；POSIX 用斜杠。
    NSString *normalized = [cwd stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    NSString *tail = normalized.lastPathComponent;
    if (tail.length == 0) tail = normalized.stringByDeletingLastPathComponent.lastPathComponent;
    return tail ?: @"";
}

- (NSString *)displayName {
    NSString *title = [self.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (title.length > 0) return title;
    NSString *tail = self.cwdTail;
    if (tail.length > 0) return tail;
    NSString *sid = self.sessionId ?: @"";
    if (sid.length > 12) return [NSString stringWithFormat:@"…%@", [sid substringFromIndex:sid.length - 8]];
    return sid.length > 0 ? sid : @"未命名会话";
}

@end

#pragma mark - IMFilesTextPage

@implementation IMFilesTextPage
@end

/// 规范化 workspace 相对路径：去首尾斜杠、折叠重复斜杠、丢掉 "." 段，根一律表示成 ""。
/// 为什么必须做：后端可能把根目录报成 "/" 或 "."，直接 `"/" + "/" + name` 会拼出
/// "//name" / "./name"，下一跳 workspaceFiles/list 会被 args 校验拒成
/// gateway/arguments-invalid——用户看到的现象就是「点进目录永远是空」。
static NSString *IMNormalizeWorkspacePath(NSString *path) {
    NSString *raw = path ?: @"";
    if (raw.length == 0) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *segment in [raw componentsSeparatedByString:@"/"]) {
        if (segment.length == 0 || [segment isEqualToString:@"."]) continue;
        if ([segment isEqualToString:@".."]) {   // 工作区相对路径不该出现，防御性吃掉
            if (parts.count > 0) [parts removeLastObject];
            continue;
        }
        [parts addObject:segment];
    }
    return [parts componentsJoinedByString:@"/"];
}

/// 在当前目录下拼一个子项路径：base 为空 → 直接返回 name（不能带前缀斜杠）。
static NSString *IMJoinWorkspacePath(NSString *base, NSString *name) {
    // 括号不能省：`name ?: @""` 整个才是 receiver；少了括号只有 @"" 被裁剪，
    // 名字里的前导斜杠会留下来（"//x" 会被 args 校验拒掉）。
    NSString *cleanName = [(name ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSString *normalizedBase = IMNormalizeWorkspacePath(base);
    if (cleanName.length == 0) return normalizedBase;
    if (normalizedBase.length == 0) return cleanName;
    return [normalizedBase stringByAppendingPathComponent:cleanName];
}

/// 真正发给主机的 `path`：**根目录必须发 "."，不能发 ""**。
/// 实测（imdsh/tools/dsh-rpc.mjs workspaceFiles/list）：
///   · path:""  → {"code":"gateway/bad-request","message":"path is required"}
///   · path:"." → 正常返回根目录列表，且回包里 path 是 ""
/// workspaceFiles/changes 更狠：path:"" → gateway/internal "file_path must be a non-empty string"。
/// 所以「规范化成空串」只用于本地拼接（面包屑 / dsh-resource 地址），发请求前要把空串换回 "."；
/// 否则每一次「列会话工作区根目录」都会被拒，而文件树永远是从根开始点进去的——
/// 用户看到的现象就是文件页整个是空的。
static NSString *IMRequestPathForWorkspacePath(NSString *path) {
    NSString *normalized = IMNormalizeWorkspacePath(path);
    return normalized.length > 0 ? normalized : @".";
}

#pragma mark - IMFilesService

@interface IMFilesService ()
@property (nonatomic, strong, nullable) IMDSHClient *cachedClient;
/// 「主机标识 + 设备 token」指纹：token 变了就说明重新配对过，必须重建客户端。
/// 只比 identifier 不够——重新配对时 identifier 不变，但旧 client 里揣着作废的 token。
@property (nonatomic, copy, nullable) NSString *cachedClientFingerprint;
@property (nonatomic, strong, nullable) id storeObserverToken;
/// 没选定作用域（没有会话可当工作区）时的本地错误。
- (NSError *)missingScopeError;
@end

@implementation IMFilesService

+ (instancetype)shared {
    static IMFilesService *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [IMFilesService new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 配对状态一变（重新配对/吊销/换主机），旧客户端里带的还是旧 token，
        // 必须断开并丢弃，否则会拿着一张作废的凭证继续连主机。
        __weak typeof(self) weakSelf = self;
        _storeObserverToken = [NSNotificationCenter.defaultCenter addObserverForName:IMServerStoreDidChangeNotification
                                                                            object:nil
                                                                             queue:NSOperationQueue.mainQueue
                                                                        usingBlock:^(NSNotification *note) {
            [weakSelf discardClientIfStale];
        }];
    }
    return self;
}

/// 主机标识 + 设备 token：token 变了就说明重新配对过。
- (NSString *)fingerprintForServer:(IMServer *)server {
    return [NSString stringWithFormat:@"%@|%@", server.identifier ?: @"", server.deviceToken ?: @""];
}

/// 只在「主机或 token 真的变了」时丢弃客户端。
/// 为什么不能一收到通知就丢：一次配对会连发好几条通知（persist + currentServer），
/// 无脑丢弃会把 UI 刚建好的新客户端当场拆掉，正在飞的请求全变错误态。
- (void)discardClientIfStale {
    if (self.cachedClient == nil) return;
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil || !server.hasToken) {
        [self discardClient];
        return;
    }
    if (![[self fingerprintForServer:server] isEqualToString:self.cachedClientFingerprint ?: @""]) {
        [self discardClient];
    }
}

- (void)discardClient {
    [self.cachedClient disconnect];
    self.cachedClient = nil;
    self.cachedClientFingerprint = nil;
}

- (BOOL)hasServer {
    return IMServerStore.shared.currentServer != nil;
}

- (BOOL)isPaired {
    IMServer *server = IMServerStore.shared.currentServer;
    return server != nil && server.hasToken;
}

- (IMDSHClient *)client {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil || !server.hasToken) {
        // 没配对就别建客户端：建了也只会在第一次请求时拿到 401。
        [self discardClient];
        return nil;
    }
    // 为什么缓存：文件页和预览页都要发请求，各自 new 一个客户端会各开一条 WS，
    // 主机上的 peer 是有限资源（protocol.md §4.4）。
    // 指纹里带上 token，重新配对后即使通知顺序错乱也不会用旧凭证继续连。
    NSString *fingerprint = [self fingerprintForServer:server];
    if (self.cachedClient == nil || ![self.cachedClientFingerprint isEqualToString:fingerprint]) {
        [self discardClient];
        self.cachedClient = [[IMDSHClient alloc] initWithServer:server];
        self.cachedClientFingerprint = fingerprint;
    }
    return self.cachedClient;
}

/// 没配对（或 token 被吊销）时所有入口都返回它，UI 据此显示「去设置」引导而不是网络错误。
- (NSError *)pairingError {
    NSString *message = self.hasServer ? @"这台主机还没配对" : @"还没连接主机";
    return [NSError errorWithDomain:IMFilesErrorDomain
                               code:IMFilesErrorCodeUnpaired
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// 没选定会话作用域时所有入口都返回它。为什么不直接发空 scope：主机一定回
/// gateway/lookup-failed（实测），UI 只会显示一句协议黑话，而且看起来像「空目录」。
- (NSError *)missingScopeError {
    return [NSError errorWithDomain:IMFilesErrorDomain
                               code:IMFilesErrorCodeNoScope
                           userInfo:@{NSLocalizedDescriptionKey: @"还没选定会话工作区"}];
}

#pragma mark 会话列表

- (void)loadSessionsWithCompletion:(IMFilesSessionsHandler)completion {
    if (completion == nil) return;
    IMDSHClient *client = self.client;
    if (client == nil) {
        completion(nil, [self pairingError]);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [client call:@"session/list" args:@{@"_request": @{}} completion:^(id value, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (error != nil) {
            completion(nil, error);
            return;
        }
        NSDictionary *json = IMDictOrNil(value);
        NSArray *items = [json[@"items"] isKindOfClass:NSArray.class] ? json[@"items"] : @[];

        NSMutableArray<IMFilesSession *> *all = [NSMutableArray array];
        NSMutableArray<IMFilesSession *> *withCwd = [NSMutableArray array];
        for (id raw in items) {
            NSDictionary *item = IMDictOrNil(raw);
            if (item == nil) continue;
            NSString *sessionId = IMStringOrNil(item[@"sessionId"]);
            if (sessionId.length == 0) continue;

            // 子代理会话（origin == "subagent"）不是人能打开的工作区作用域：
            // 列进去只会让用户选到一堆同名 cwd，文件树看起来「怎么都一样」。
            // 而且子代理会话的 sessionId 是不带 "session-" 前缀的裸 uuid，直接当
            // workspaceFileScopeId 发出去会被主机拒成 gateway/lookup-not-found（实测），
            // 所以带 parentSessionId 的也一并排除。
            NSString *origin = IMStringOrNil(item[@"origin"]);
            NSString *parentSessionId = IMStringOrNil(item[@"parentSessionId"]);
            if ([origin isEqualToString:@"subagent"] || parentSessionId.length > 0) continue;

            IMFilesSession *session = [IMFilesSession new];
            session.sessionId = sessionId;
            session.cwd = IMStringOrNil(item[@"cwd"]);
            session.updatedAt = IMDateFromFlexibleValue(item[@"updatedAt"]);

            NSDictionary *projections = IMDictOrNil(item[@"projections"]);
            NSDictionary *values = IMDictOrNil(projections[@"values"]);
            NSString *title = IMStringOrNil(values[@"title"]);
            if (title.length == 0) title = IMStringOrNil(item[@"title"]);
            session.title = title.length > 0 ? title : nil;

            [all addObject:session];
            if (session.cwd.length > 0) [withCwd addObject:session];
        }

        // 默认作用域优先「带 cwd 的普通会话」：没有 cwd 的会话后端解析不出工作区根，
        // 选它只会拿到空目录或报错。带 cwd 的为空时再退回全量，至少还有东西可选。
        completion(withCwd.count > 0 ? withCwd : all, nil);
    }];
}

#pragma mark 目录

- (void)listDirectory:(NSString *)path scopeId:(NSString *)scopeId completion:(IMFilesListingHandler)completion {
    if (completion == nil) return;
    IMDSHClient *client = self.client;
    if (client == nil) {
        completion(nil, [self pairingError]);
        return;
    }
    NSString *scope = scopeId ?: @"";
    // 空作用域发出去只会拿到 gateway/lookup-failed（实测），在这里就翻成人话。
    if (scope.length == 0) {
        completion(nil, [self missingScopeError]);
        return;
    }
    // 发出去之前就规范化：任何 "//x"、"./x"、"/x/" 都会被 args 校验毙掉。
    // 根目录要发 "."（发 "" 会被拒成 gateway/bad-request: path is required，实测）。
    NSString *target = IMRequestPathForWorkspacePath(path);
    // path 必须显式出现（省略会报 "path is required"，protocol.md §5.5）。
    NSDictionary *args = @{@"workspaceFileScopeId": scope, @"path": target};

    [client call:@"workspaceFiles/list" args:args completion:^(id value, NSError *error) {
        if (error != nil) {
            NSString *remoteCode = IMStringOrNil(error.userInfo[@"remoteCode"]);
            // 真机定位用：拼接一旦出错，最典型的表现就是「点进目录永远空」。
            if ([remoteCode isEqualToString:@"gateway/arguments-invalid"] ||
                [remoteCode isEqualToString:@"gateway/input-invalid"] ||
                [remoteCode isEqualToString:@"gateway/bad-request"]) {
                NSLog(@"[IMFiles] workspaceFiles/list 被拒 path=%@ scope=%@ code=%@", target, scope, remoteCode);
            }
            completion(nil, error);
            return;
        }
        NSDictionary *json = IMDictOrNil(value);
        if (json == nil) {
            completion(nil, [self badResponseError]);
            return;
        }
        IMFilesListing *listing = [IMFilesListing new];
        listing.path = IMNormalizeWorkspacePath(IMStringOrNil(json[@"path"]) ?: target);
        listing.truncated = [IMNumberOrNil(json[@"truncated"]) boolValue];

        NSArray *rawEntries = [json[@"entries"] isKindOfClass:NSArray.class] ? json[@"entries"] : @[];
        NSMutableArray<IMFilesEntry *> *entries = [NSMutableArray arrayWithCapacity:rawEntries.count];
        for (id raw in rawEntries) {
            NSDictionary *dict = IMDictOrNil(raw);
            NSString *name = IMStringOrNil(dict[@"name"]);
            if (name.length == 0) continue;

            IMFilesEntry *entry = [IMFilesEntry new];
            entry.name = name;
            // 统一走规范化拼接：根目录时报 "/" / "." / "" 都能拼出正确的相对路径。
            entry.path = IMJoinWorkspacePath(listing.path, name);

            NSString *type = IMStringOrNil(dict[@"type"]);
            if ([type isEqualToString:@"directory"]) {
                entry.type = IMFilesEntryTypeDirectory;
                entry.isDirectory = YES;
            } else if ([type isEqualToString:@"file"]) {
                entry.type = IMFilesEntryTypeFile;
            } else {
                entry.type = IMFilesEntryTypeOther;
            }

            NSNumber *size = IMNumberOrNil(dict[@"size"]);
            entry.hasSize = size != nil;
            entry.size = size.unsignedLongLongValue;
            entry.modifiedAt = IMEntryModifiedDate(dict);
            [entries addObject:entry];
        }

        // 文件夹在前，其余用自然序（中文、数字、大小写混排都能排对）。
        [entries sortUsingComparator:^NSComparisonResult(IMFilesEntry *a, IMFilesEntry *b) {
            if (a.isDirectory != b.isDirectory) return a.isDirectory ? NSOrderedAscending : NSOrderedDescending;
            return [a.name localizedStandardCompare:b.name];
        }];
        listing.entries = entries;
        completion(listing, nil);
    }];
}

#pragma mark stat / read

- (void)statPath:(NSString *)path scopeId:(NSString *)scopeId completion:(IMFilesStatHandler)completion {
    if (completion == nil) return;
    IMDSHClient *client = self.client;
    if (client == nil) {
        completion(NO, 0, nil, [self pairingError]);
        return;
    }
    NSDictionary *args = @{@"workspaceFileScopeId": scopeId ?: @"", @"path": IMRequestPathForWorkspacePath(path)};
    [client call:@"workspaceFiles/stat" args:args completion:^(id value, NSError *error) {
        if (error != nil) {
            completion(NO, 0, nil, error);
            return;
        }
        NSDictionary *json = IMDictOrNil(value);
        NSNumber *bytes = IMNumberOrNil(json[@"bytes"]);
        completion(bytes != nil, bytes.unsignedLongLongValue, IMStringOrNil(json[@"version"]), nil);
    }];
}

- (void)readTextPath:(NSString *)path
             scopeId:(NSString *)scopeId
              offset:(NSInteger)offset
               limit:(NSInteger)limit
          completion:(IMFilesTextHandler)completion {
    if (completion == nil) return;
    IMDSHClient *client = self.client;
    if (client == nil) {
        completion(nil, [self pairingError]);
        return;
    }
    NSInteger safeOffset = MAX(1, offset);
    NSInteger safeLimit = MIN(MAX(1, limit), 5000);   // 后端 maxLines 默认 5000
    NSDictionary *args = @{@"workspaceFileScopeId": scopeId ?: @"",
                           @"path": IMRequestPathForWorkspacePath(path),
                           @"range": @{@"offset": @(safeOffset), @"limit": @(safeLimit)}};

    [client call:@"workspaceFiles/read" args:args completion:^(id value, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }
        NSDictionary *json = IMDictOrNil(value);
        if (json == nil) {
            completion(nil, [self badResponseError]);
            return;
        }
        IMFilesTextPage *page = [IMFilesTextPage new];
        page.offset = [IMNumberOrNil(json[@"offset"]) integerValue];
        page.lines = [IMNumberOrNil(json[@"lines"]) integerValue];
        page.text = IMStringOrNil(json[@"text"]) ?: @"";
        page.eof = [IMNumberOrNil(json[@"eof"]) boolValue];
        NSNumber *bytes = IMNumberOrNil(json[@"bytes"]);
        page.hasTotalBytes = bytes != nil;
        page.totalBytes = bytes.unsignedLongLongValue;
        page.absolutePath = IMStringOrNil(json[@"absolutePath"]);
        page.version = IMStringOrNil(json[@"version"]);
        completion(page, nil);
    }];
}

- (void)readBytesPath:(NSString *)path scopeId:(NSString *)scopeId completion:(IMFilesBytesHandler)completion {
    if (completion == nil) return;
    IMDSHClient *client = self.client;
    if (client == nil) {
        completion(nil, nil, [self pairingError]);
        return;
    }
    // options 虽然可省，但字段集合校验下显式给一个空对象最稳（options 是声明过的字段）。
    NSDictionary *args = @{@"workspaceFileScopeId": scopeId ?: @"",
                           @"path": IMRequestPathForWorkspacePath(path),
                           @"options": @{}};

    [client call:@"workspaceFiles/readBytes" args:args completion:^(id value, NSError *error) {
        if (error != nil) {
            completion(nil, nil, error);
            return;
        }
        NSDictionary *json = IMDictOrNil(value);
        if (json == nil) {
            completion(nil, nil, [self badResponseError]);
            return;
        }
        NSData *data = nil;
        id raw = json[@"data"];
        if ([raw isKindOfClass:NSData.class]) {
            data = (NSData *)raw;                      // multipart 附件（IMDSHClient 已解出）
        } else if ([raw isKindOfClass:NSString.class]) {
            // 兜底：万一网关把字节退化成 base64 字符串。
            data = [[NSData alloc] initWithBase64EncodedString:(NSString *)raw
                                                      options:NSDataBase64DecodingIgnoreUnknownCharacters];
        } else if ([raw isKindOfClass:NSArray.class]) {
            // 再兜底：逐字节数字数组。
            NSMutableData *buffer = [NSMutableData data];
            for (id byte in (NSArray *)raw) {
                uint8_t value = (uint8_t)[IMNumberOrNil(byte) unsignedCharValue];
                [buffer appendBytes:&value length:1];
            }
            data = buffer;
        }
        NSMutableDictionary *meta = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"absolutePath", @"version", @"eof", @"offset", @"bytes"]) {
            if (json[key] != nil) meta[key] = json[key];
        }
        if (data == nil) {
            completion(nil, meta, [self badResponseError]);
            return;
        }
        completion(data, meta, nil);
    }];
}

#pragma mark 变动监听

- (void)watchPath:(NSString *)path
          scopeId:(NSString *)scopeId
         streamId:(NSString *)streamId
         onChange:(void (^)(void))onChange
          onError:(void (^)(NSError *))onError {
    IMDSHClient *client = self.client;
    if (client == nil || streamId.length == 0) return;
    NSDictionary *args = @{@"workspaceFileScopeId": scopeId ?: @"", @"path": IMRequestPathForWorkspacePath(path)};
    [client openStream:@"workspaceFiles/changes"
                  args:args
              streamId:streamId
               onFrame:^(NSString *sid, NSDictionary *value) {
        // 帧形状是 {kind:'ready'} / {kind:'change', change:{...}}；ready 不该触发刷新，
        // 否则每次订阅都会白刷一次列表。
        NSString *kind = IMStringOrNil(value[@"kind"]);
        if ([kind isEqualToString:@"ready"]) return;
        if (onChange) onChange();
    }
                 onEnd:nil
               onError:^(NSString *sid, NSError *error) {
        if (onError) onError(error);
    }];
}

- (void)stopWatching:(NSString *)streamId {
    if (streamId.length == 0) return;
    [self.client closeStream:streamId];
}

- (NSError *)badResponseError {
    return [NSError errorWithDomain:IMFilesErrorDomain
                               code:IMFilesErrorCodeBadResponse
                           userInfo:@{NSLocalizedDescriptionKey: @"主机返回的数据形状不对"}];
}

#pragma mark 错误文案

+ (NSString *)messageForError:(NSError *)error {
    if (error == nil) return @"未知错误";

    if ([error.domain isEqualToString:IMFilesErrorDomain]) {
        // 本地判定类错误：文案已写在 error 里（「这台主机还没配对」/「还没连接主机」）。
        switch (error.code) {
            case IMFilesErrorCodeUnpaired:
                return error.localizedDescription.length > 0 ? error.localizedDescription : @"这台主机还没配对";
            case IMFilesErrorCodeBadResponse: return @"主机返回的数据形状不对";
            case IMFilesErrorCodeNoScope:
                return error.localizedDescription.length > 0 ? error.localizedDescription : @"还没选定会话工作区";
            default: break;
        }
        return error.localizedDescription.length > 0 ? error.localizedDescription : @"文件页暂时不可用";
    }

    if ([error.domain isEqualToString:IMDSHClientErrorDomain]) {
        NSString *remoteCode = IMStringOrNil(error.userInfo[@"remoteCode"]);
        if (remoteCode.length > 0) {
            if ([remoteCode isEqualToString:@"workspace-file/not-found"]) return @"文件或目录不存在";
            if ([remoteCode isEqualToString:@"workspace-file/not-directory"]) return @"这不是一个目录";
            if ([remoteCode isEqualToString:@"workspace-file/not-regular-file"]) return @"这不是普通文件，无法预览";
            if ([remoteCode isEqualToString:@"workspace-file/outside-workspace"]) return @"路径在工作区之外";
            if ([remoteCode isEqualToString:@"workspace-file/too-large"]) return @"文件太大，超出主机允许的上限";
            if ([remoteCode isEqualToString:@"workspace-file/not-text"]) return @"这不是 UTF-8 文本";
            if ([remoteCode isEqualToString:@"workspace-file/watch-unsupported"]) return @"主机不支持目录变动监听";
            if ([remoteCode isEqualToString:@"gateway/arguments-invalid"] ||
                [remoteCode isEqualToString:@"gateway/input-invalid"] ||
                [remoteCode isEqualToString:@"gateway/bad-request"]) {
                return @"请求参数不被主机接受";
            }
            // 未知领域码：按协议文档 §9.2 的建议原样展示，别猜。
            return error.localizedDescription.length > 0 ? error.localizedDescription : @"主机拒绝了请求";
        }

        switch (error.code) {
            case 401: return @"授权失效，请在设置里重新配对";
            case 403: return @"主机拒绝了这次访问";
            case 404: return @"主机不认识这个接口";
            case 413: return @"请求体太大";
            case 500: return @"主机内部出错了";
            default: break;
        }
    }

    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorTimedOut: return @"主机响应超时";
            case NSURLErrorCannotFindHost:
            case NSURLErrorCannotConnectToHost:
            case NSURLErrorDNSLookupFailed: return @"连不上主机";
            case NSURLErrorNetworkConnectionLost: return @"网络连接中断";
            case NSURLErrorNotConnectedToInternet: return @"设备没有联网";
            case NSURLErrorCancelled: return @"请求已取消";
            default: return @"网络请求失败";
        }
    }

    return error.localizedDescription.length > 0 ? error.localizedDescription : @"未知错误";
}

+ (NSString *)detailForError:(NSError *)error {
    if ([error.domain isEqualToString:IMFilesErrorDomain] && error.code == IMFilesErrorCodeUnpaired) {
        return @"请在设置里重新配对后再浏览文件";
    }
    NSString *remoteCode = IMStringOrNil(error.userInfo[@"remoteCode"]);
    if ([remoteCode isEqualToString:@"gateway/lookup-failed"] ||
        [remoteCode isEqualToString:@"gateway/lookup-not-found"]) {
        return @"这个名字没能解析成会话工作区：顶部胶囊里换一个会话，或刷新会话列表再试。";
    }
    if ([remoteCode isEqualToString:@"gateway/bad-request"] ||
        [remoteCode isEqualToString:@"gateway/arguments-invalid"]) {
        return @"文件请求的参数被主机拒绝：多半是当前目录路径没带对，回工作区根目录（面包屑第一段）再点进来。";
    }
    if ([remoteCode isEqualToString:@"workspace-file/not-found"]) {
        return @"它可能刚被移动或删除，下拉刷新看看当前目录。";
    }
    if ([remoteCode isEqualToString:@"workspace-file/outside-workspace"]) {
        return @"工作区只能浏览会话根目录下的内容。";
    }
    if ([remoteCode isEqualToString:@"workspace-file/too-large"]) {
        return @"可以在电脑上打开这个文件，或换个小一点的文件看。";
    }
    if ([remoteCode isEqualToString:@"workspace-file/not-text"]) {
        return @"它可能含二进制内容，已按二进制方式预览。";
    }
    if (error.code == 404 && [error.domain isEqualToString:IMDSHClientErrorDomain]) {
        return @"主机的 DSH 版本可能过旧，不支持文件接口。";
    }
    if (error.code == 401 || error.code == 403) {
        return @"到「设置 → 主机」重新配对后即可继续。";
    }
    return nil;
}

+ (BOOL)isRetryableError:(NSError *)error {
    if ([error.domain isEqualToString:IMFilesErrorDomain] && error.code == IMFilesErrorCodeUnpaired) {
        return NO;   // 去设置配对才有用，重试没意义
    }
    NSString *remoteCode = IMStringOrNil(error.userInfo[@"remoteCode"]);
    if ([remoteCode isEqualToString:@"workspace-file/too-large"] ||
        [remoteCode isEqualToString:@"workspace-file/not-text"] ||
        [remoteCode isEqualToString:@"workspace-file/not-regular-file"]) {
        return NO;   // 重试也是同样的结果
    }
    return YES;
}

#pragma mark 路径

+ (NSString *)resourceAddressForScopeId:(NSString *)scopeId path:(NSString *)path {
    NSString *sid = scopeId ?: @"";
    NSString *relative = IMNormalizeWorkspacePath(path);
    if (relative.length == 0) return [NSString stringWithFormat:@"dsh-resource://file/session/%@", sid];
    return [NSString stringWithFormat:@"dsh-resource://file/session/%@/%@", sid, relative];
}

+ (NSArray<NSString *> *)pathComponentsForWorkspacePath:(NSString *)path {
    // 与发请求用的是同一套规范化，面包屑和实际请求的路径永远一致（否则面包屑会多出一段空段）。
    NSString *normalized = IMNormalizeWorkspacePath(path);
    return normalized.length > 0 ? [normalized componentsSeparatedByString:@"/"] : @[];
}

@end
