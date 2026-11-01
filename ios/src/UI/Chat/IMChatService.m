//
//  IMChatService.m
//  IMDSH — 聊天域协议封装
//

#import "IMChatService.h"
#import "IMDSHClient.h"
#import "IMAPIClient.h"
#import "IMCrashReporter.h"

static NSString *const IMChatServiceErrorDomain = @"IMChatServiceErrorDomain";

#pragma mark - 共享客户端
// 列表页要 session/control、聊天页要 session/follow，两者必须复用同一条 mux 连接：
// 多个 IMDSHClient 会各开一条 WebSocket，既浪费又会把 streamId 空间搞乱。

static IMDSHClient *gSharedClient;
static NSString *gSharedClientKey;

static NSMutableDictionary<NSString *, IMConnectionStateHandler> *IMStateHandlerMap(void) {
    static NSMutableDictionary<NSString *, IMConnectionStateHandler> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = [NSMutableDictionary dictionary];
    });
    return map;
}

static void IMInstallStateDispatcher(void) {
    if (gSharedClient == nil) return;
    [gSharedClient setStateHandler:^(BOOL connected) {
        for (IMConnectionStateHandler handler in IMStateHandlerMap().allValues) {
            handler(connected);
        }
    }];
}

@interface IMChatService ()
@property (nonatomic, copy, nullable) NSString *handlerKey;
/// 本实例的短 UUID：streamId 前缀，避免不同页面的订阅互相顶掉。
@property (nonatomic, copy) NSString *streamInstanceId;
@property (nonatomic, copy, nullable) NSString *controlStreamId;
@property (nonatomic, copy, nullable) NSString *followStreamId;
@property (nonatomic, strong, nullable) IMSessionRow *currentRow;
@end

@implementation IMChatService

- (instancetype)init {
    self = [super init];
    if (self) {
        _handlerKey = NSUUID.UUID.UUIDString;
        _streamInstanceId = [[NSUUID.UUID.UUIDString substringToIndex:8] lowercaseString];
    }
    return self;
}

- (void)dealloc {
    if (_handlerKey != nil) [IMStateHandlerMap() removeObjectForKey:_handlerKey];
}

+ (IMDSHClient *)sharedClient {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil || !server.hasToken) {
        gSharedClient = nil;
        gSharedClientKey = nil;
        return nil;
    }
    // 换主机 / 重新配对后必须换客户端，否则还在用旧 token 连着旧地址。
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", server.identifier, server.baseURLString, server.deviceToken ?: @""];
    if (gSharedClient != nil && [gSharedClientKey isEqualToString:key]) return gSharedClient;

    if (gSharedClient != nil) {
        [gSharedClient closeAllStreams];
        [gSharedClient disconnect];
    }
    gSharedClient = [[IMDSHClient alloc] initWithServer:server];
    gSharedClientKey = key;
    IMInstallStateDispatcher();
    return gSharedClient;
}

- (IMDSHClient *)client {
    return [IMChatService sharedClient];
}

- (IMServer *)server {
    return IMServerStore.shared.currentServer;
}

- (BOOL)isPaired {
    return [IMChatService sharedClient] != nil;
}

- (void)setConnectionHandler:(void (^)(BOOL))handler {
    if (self.handlerKey.length == 0) self.handlerKey = NSUUID.UUID.UUIDString;
    if (handler == nil) {
        [IMStateHandlerMap() removeObjectForKey:self.handlerKey];
        return;
    }
    IMStateHandlerMap()[self.handlerKey] = [handler copy];
    IMInstallStateDispatcher();
}

#pragma mark - 错误

static NSError *IMChatNotPairedError(void) {
    return [NSError errorWithDomain:IMChatServiceErrorDomain
                               code:-1
                           userInfo:@{NSLocalizedDescriptionKey: @"还没有配对的主机，请到设置页完成配对"}];
}

+ (BOOL)isUnauthorizedError:(NSError *)error {
    if (error == nil) return NO;
    if (error.code == IMAPIErrorCodeUnauthorized) return YES;
    NSNumber *status = error.userInfo[IMAPIErrorHTTPStatusKey];
    if ([status integerValue] == 401) return YES;
    NSString *remote = error.userInfo[IMAPIErrorRemoteCodeKey];
    if ([remote isKindOfClass:NSString.class] && [remote.lowercaseString containsString:@"unauthorized"]) return YES;
    return NO;
}

+ (NSString *)messageForError:(NSError *)error {
    if (error == nil) return @"";
    if ([error.domain isEqualToString:IMChatServiceErrorDomain]) return error.localizedDescription;
    return [IMAPIClient localizedMessageForError:error];
}

/// 子会话必须换 address 形状，否则服务端回 session/agent-busy。
static NSDictionary *IMAddressForRow(IMSessionRow *row) {
    if (row.isSubagent && row.parentSessionId.length > 0) {
        return @{
            @"kind": @"subagent",
            @"parentSessionId": row.parentSessionId,
            @"childSessionId": row.sessionId,
            @"mode": @"unknown",
        };
    }
    return @{@"kind": @"session", @"sessionId": row.sessionId};
}

#pragma mark - 会话列表

- (void)loadSessionsWithCursor:(NSString *)cursor completion:(IMChatListCompletion)completion {
    if (self.client == nil) {
        if (completion) completion(nil, nil, IMChatNotPairedError());
        return;
    }
    NSMutableDictionary *request = [NSMutableDictionary dictionary];
    if (cursor.length > 0) request[@"cursor"] = cursor;

    [self.client call:@"session/list" args:@{@"_request": request} completion:^(id value, NSError *error) {
        if (error != nil) {
            if (completion) completion(nil, nil, error);
            return;
        }
        NSMutableArray<IMSessionRow *> *rows = [NSMutableArray array];
        NSString *nextCursor = nil;
        NSUInteger rawCount = 0;
        NSUInteger skippedSubagents = 0;
        NSDate *startedAt = [NSDate date];
        if ([value isKindOfClass:NSDictionary.class]) {
            id items = ((NSDictionary *)value)[@"items"];
            if ([items isKindOfClass:NSArray.class]) {
                rawCount = [(NSArray *)items count];
                for (id raw in (NSArray *)items) {
                    IMSessionRow *row = [IMSessionRow rowWithDictionary:raw];
                    if (row == nil) continue;
                    // 子代理子会话不进列表：桌面端也是在任务卡里就地展开，不给独立入口。
                    // 主机的 items 把两者混在一起（实测 475 条里 382 条是 subagent，单次响应 4.9 MB），
                    // 不过滤的话列表会被子会话淹没，而且每条都要参与后续的 O(n) 扫描。
                    if (row.isSubagent) {
                        skippedSubagents += 1;
                        continue;
                    }
                    [rows addObject:row];
                }
            }
            // 契约里 cursor 是可选字段：有就接，没有就一次到底。
            id candidate = ((NSDictionary *)value)[@"cursor"];
            if (![candidate isKindOfClass:NSString.class]) candidate = ((NSDictionary *)value)[@"nextCursor"];
            if ([candidate isKindOfClass:NSString.class] && [(NSString *)candidate length] > 0) nextCursor = candidate;
        }
        [IMCrashReporter log:@"session/list: 原始 %lu 条，入列 %lu 条，跳过子代理 %lu 条，耗时 %.0f ms",
                        (unsigned long)rawCount,
                        (unsigned long)rows.count,
                        (unsigned long)skippedSubagents,
                        -[startedAt timeIntervalSinceNow] * 1000.0];
        if (completion) completion(rows, nextCursor, nil);
    }];
}

- (void)startControlStreamWithHandler:(IMChatProjectionHandler)handler {
    if (self.client == nil) return;
    [self stopControlStream];

    // streamId 必须带实例标识：同一条 mux 连接上重复 id 会顶掉旧订阅（客户端内部先 cancel 再 open），
    // 列表页与详情页各自订阅 control 时会互相踢掉，被踢的那条永远收不到 baseline。
    NSString *streamId = [NSString stringWithFormat:@"control-%@", self.streamInstanceId];
    self.controlStreamId = streamId;
    __weak typeof(self) weakSelf = self;
    [self.client openStream:@"session/control"
                       args:@{}
                   streamId:streamId
                    onFrame:^(NSString *sid, NSDictionary *value) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil || handler == nil) return;
        NSString *type = value[@"type"];
        if ([type isEqual:@"projection"]) {
            NSString *sessionId = value[@"sessionId"];
            NSString *key = value[@"key"];
            if ([sessionId isKindOfClass:NSString.class] && [key isKindOfClass:NSString.class]) {
                handler(sessionId, key, value[@"value"]);
            }
            return;
        }
        if ([type isEqual:@"baseline"]) {
            id inner = value[@"value"];
            if (![inner isKindOfClass:NSDictionary.class]) return;
            id projections = ((NSDictionary *)inner)[@"projections"];
            if (![projections isKindOfClass:NSDictionary.class]) return;
            for (NSString *sessionId in (NSDictionary *)projections) {
                id block = ((NSDictionary *)projections)[sessionId];
                if (![block isKindOfClass:NSDictionary.class]) continue;
                id values = ((NSDictionary *)block)[@"values"];
                if (![values isKindOfClass:NSDictionary.class]) continue;
                for (NSString *key in (NSDictionary *)values) {
                    handler(sessionId, key, ((NSDictionary *)values)[key]);
                }
            }
        }
    }
                    onError:^(NSString *sid, NSError *error) {
        // 单条流的错误由连接层统一重连处理，这里不打扰 UI。
    }];
}

- (void)stopControlStream {
    if (self.controlStreamId.length == 0) return;
    [self.client closeStream:self.controlStreamId];
    self.controlStreamId = nil;
}

#pragma mark - 单个会话

- (void)openSession:(IMSessionRow *)row
        maxMessages:(NSInteger)maxMessages
         onSnapshot:(void (^)(NSDictionary *))onSnapshot
           onRecord:(void (^)(NSDictionary *))onRecord
      onStreamFrame:(void (^)(NSDictionary *))onStreamFrame
              onEnd:(void (^)(void))onEnd
            onError:(void (^)(NSError *))onError {
    if (self.client == nil) {
        if (onError) onError(IMChatNotPairedError());
        return;
    }
    self.currentRow = row;
    // 同一会话可能被两个页面同时打开（iPad 双列 + 旋转重建）：streamId 带实例标识，
    // 后开者不会顶掉前一个，各自 closeStream 也只关自己那条。
    NSString *streamId = [NSString stringWithFormat:@"follow-%@-%@", self.streamInstanceId, row.sessionId];
    self.followStreamId = streamId;

    NSDictionary *args = @{
        @"request": @{
            @"address": IMAddressForRow(row),
            @"maxMessages": @(MAX(1, maxMessages)),
            @"assistantStream": @YES,   // 契约里是 const true：要打字机效果必须显式带上
        },
    };

    [self.client openStream:@"session/follow"
                       args:args
                   streamId:streamId
                    onFrame:^(NSString *sid, NSDictionary *value) {
        NSString *type = value[@"type"];
        if ([type isEqual:@"snapshot"]) {
            if (onSnapshot) onSnapshot(value);
            return;
        }
        if ([type isEqual:@"event"]) {
            if (onRecord) onRecord(value);
            return;
        }
        if ([type isEqual:@"assistant-stream"]) {
            id frame = value[@"frame"];
            if ([frame isKindOfClass:NSDictionary.class] && onStreamFrame) onStreamFrame(frame);
        }
    }
                      onEnd:^(NSString *sid) {
        if (onEnd) onEnd();
    }
                    onError:^(NSString *sid, NSError *error) {
        if (onError) onError(error);
    }];
}

- (void)closeSessionStream {
    if (self.followStreamId.length == 0) return;
    [self.client closeStream:self.followStreamId];
    self.followStreamId = nil;
}

- (void)loadOlderPageThroughSeq:(NSInteger)throughSeq
                    maxMessages:(NSInteger)maxMessages
                     completion:(IMChatPageCompletion)completion {
    if (self.client == nil || self.currentRow == nil) {
        if (completion) completion(nil, NO, throughSeq, IMChatNotPairedError());
        return;
    }
    NSDictionary *args = @{
        @"request": @{
            @"address": IMAddressForRow(self.currentRow),
            @"throughSeq": @(MAX(0, throughSeq)),
            @"maxMessages": @(MAX(1, maxMessages)),
        },
    };
    [self.client call:@"session/page" args:args completion:^(id value, NSError *error) {
        if (error != nil) {
            if (completion) completion(nil, NO, throughSeq, error);
            return;
        }
        NSArray *records = nil;
        BOOL hasMore = NO;
        if ([value isKindOfClass:NSDictionary.class]) {
            id rawRecords = ((NSDictionary *)value)[@"records"];
            if ([rawRecords isKindOfClass:NSArray.class]) records = rawRecords;
            // hasMore 可能是 null：NSNull 上发 boolValue 会抛 unrecognized selector。
            id rawHasMore = ((NSDictionary *)value)[@"hasMore"];
            hasMore = [rawHasMore isKindOfClass:NSNumber.class] ? [(NSNumber *)rawHasMore boolValue] : NO;
        }
        if (completion) completion(records, hasMore, throughSeq, nil);
    }];
}

/// prompt 被网关判参数非法时，把实际发出的 args 摘要打出来（base64 截断），只在错误分支调用。
static void IMChatLogPromptRejection(NSDictionary *args, NSError *error);

- (void)sendPromptWithText:(NSString *)text
                    images:(NSArray<IMImageAttachment *> *)images
                 requestId:(NSString *)requestId
                completion:(IMChatActionCompletion)completion {
    if (self.client == nil || self.currentRow == nil) {
        if (completion) completion(IMChatNotPairedError());
        return;
    }

    NSMutableArray *content = [NSMutableArray array];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // 纯图片消息不发空 text 块：网关对空字符串 text 块是判非法的。
    if (trimmed.length > 0) {
        [content addObject:@{@"type": @"text", @"text": text}];
    }
    // 张数/体积上限由会话的 imageLimits 决定，界面层已经校验过，这里只负责拼块。
    for (IMImageAttachment *attachment in images) {
        if (attachment.base64Data.length == 0) continue;
        [content addObject:@{
            @"type": @"image",
            @"mediaType": attachment.mediaType ?: @"image/jpeg",
            @"data": attachment.base64Data,
            @"name": attachment.name ?: @"image.jpg",
        }];
    }
    if (content.count == 0) {
        if (completion) completion(nil);
        return;
    }

    NSTimeZone *zone = NSTimeZone.localTimeZone;
    NSDictionary *args = @{
        @"request": @{
            @"requestId": requestId.length > 0 ? requestId : NSUUID.UUID.UUIDString,
            @"sessionId": self.currentRow.sessionId,
            @"mode": @"queue",
            @"content": content,
            @"clientTimeZone": zone.name ?: @"UTC",
        },
    };
    [self.client call:@"session/prompt" args:args completion:^(id value, NSError *error) {
        if (error != nil) IMChatLogPromptRejection(args, error);
        if (completion) completion(error);
    }];
}

/// prompt 被网关判参数非法时，把实际发出的 args 摘要打出来（base64 截断），只在错误分支调用。
static void IMChatLogPromptRejection(NSDictionary *args, NSError *error) {
    NSString *code = error.userInfo[IMAPIErrorRemoteCodeKey];
    if (![code isKindOfClass:NSString.class]) return;
    if (![code isEqualToString:@"gateway/arguments-invalid"]) return;

    NSDictionary *request = args[@"request"];
    NSMutableDictionary *redacted = [NSMutableDictionary dictionary];
    for (NSString *key in request) {
        id value = request[key];
        if (![key isEqualToString:@"content"] || ![value isKindOfClass:NSArray.class]) {
            redacted[key] = value;
            continue;
        }
        NSMutableArray *blocks = [NSMutableArray array];
        for (NSDictionary *block in (NSArray *)value) {
            if (![block isKindOfClass:NSDictionary.class]) continue;
            NSMutableDictionary *copy = [block mutableCopy];
            if ([copy[@"type"] isEqualToString:@"image"] && [copy[@"data"] isKindOfClass:NSString.class]) {
                copy[@"data"] = [NSString stringWithFormat:@"…<%lu bytes>", (unsigned long)[copy[@"data"] length]];
            }
            [blocks addObject:copy];
        }
        redacted[@"content"] = blocks;
    }

    NSData *json = [NSJSONSerialization isValidJSONObject:redacted]
        ? [NSJSONSerialization dataWithJSONObject:redacted options:0 error:NULL]
        : nil;
    NSString *text = json != nil ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : redacted.description;
    NSLog(@"[imdsh][session/prompt] 被拒绝 code=%@ args=%@", code, text);
}

- (void)loadAttachmentWithId:(NSString *)attachmentId
                   sessionId:(NSString *)sessionId
                  completion:(void (^)(NSData *, NSString *, NSError *))completion {
    if (attachmentId.length == 0 || sessionId.length == 0) {
        if (completion) completion(nil, nil, IMChatNotPairedError());
        return;
    }
    if (self.client == nil) {
        if (completion) completion(nil, nil, IMChatNotPairedError());
        return;
    }

    NSDictionary *args = @{@"request": @{@"sessionId": sessionId, @"attachmentId": attachmentId}};
    [self.client call:@"session/attachment" args:args completion:^(id value, NSError *error) {
        if (error != nil || ![value isKindOfClass:NSDictionary.class]) {
            if (completion) completion(nil, nil, error);
            return;
        }
        NSDictionary *result = value;
        NSString *mediaType = nil;
        id attachment = result[@"attachment"];
        if ([attachment isKindOfClass:NSDictionary.class]) {
            id type = ((NSDictionary *)attachment)[@"mediaType"];
            if ([type isKindOfClass:NSString.class]) mediaType = type;
        }

        id payload = result[@"data"];
        NSData *bytes = nil;
        if ([payload isKindOfClass:NSData.class]) {
            // 二进制端点会走 multipart 回包，客户端已封成 {__multipart:YES, data:NSData}。
            bytes = payload;
        } else if ([payload isKindOfClass:NSString.class] && [(NSString *)payload length] > 0) {
            bytes = [[NSData alloc] initWithBase64EncodedString:payload options:NSDataBase64DecodingIgnoreUnknownCharacters];
        }
        if (completion) completion(bytes, mediaType, bytes.length > 0 ? nil : error);
    }];
}

- (void)cancelRunningTurnWithCompletion:(IMChatActionCompletion)completion {
    if (self.client == nil || self.currentRow == nil) {
        if (completion) completion(IMChatNotPairedError());
        return;
    }
    NSDictionary *args = @{@"request": @{@"sessionId": self.currentRow.sessionId}};
    [self.client call:@"session/cancel" args:args completion:^(id value, NSError *error) {
        if (completion) completion(error);
    }];
}

@end
