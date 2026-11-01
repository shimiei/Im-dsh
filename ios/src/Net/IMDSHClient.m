#import "IMDSHClient.h"

NSString *const IMDSHClientErrorDomain = @"IMDSHClientErrorDomain";

typedef NS_ENUM(NSInteger, IMDSHClientErrorCode) {
    IMDSHClientErrorNotConnected = -1,
    IMDSHClientErrorBadResponse = -2,
    IMDSHClientErrorRemote = -3,
    IMDSHClientErrorTransport = -4,
};

static const NSTimeInterval IMDSHUnaryTimeout = 45.0;
static const NSInteger IMDSHMaxReconnectAttempts = 12;

#pragma mark - 订阅

@interface IMStreamSubscription : NSObject
@property (nonatomic, copy) NSString *endpoint;
@property (nonatomic, copy) NSDictionary *args;
@property (nonatomic, copy) IMStreamFrameHandler onFrame;
@property (nonatomic, copy, nullable) IMStreamEndHandler onEnd;
@property (nonatomic, copy) IMStreamErrorHandler onError;
@end

@implementation IMStreamSubscription
@end

#pragma mark - 客户端

@interface IMDSHClient ()
@property (nonatomic, strong) IMServer *server;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionWebSocketTask *socket;
@property (nonatomic, strong) NSMutableDictionary<NSString *, IMStreamSubscription *> *streams;
@property (nonatomic, copy, nullable) IMConnectionStateHandler stateHandler;
@property (nonatomic, assign) NSInteger retryAttempt;
@property (nonatomic, assign) BOOL wantsConnection;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) BOOL pingScheduled;
@end

@implementation IMDSHClient

- (instancetype)initWithServer:(IMServer *)server {
    self = [super init];
    if (self) {
        _server = server;
        _streams = [NSMutableDictionary dictionary];
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = IMDSHUnaryTimeout;
        config.HTTPShouldSetCookies = NO;
        config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)dealloc {
    [self.socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway reason:nil];
}

- (BOOL)streamConnected {
    @synchronized (self) {
        return self.connected;
    }
}

#pragma mark - unary

- (void)call:(NSString *)endpoint args:(NSDictionary *)args completion:(IMRPCCompletion)completion {
    if (self.server.baseURL == nil) {
        if (completion) completion(nil, [self errorWithCode:IMDSHClientErrorTransport message:@"没有配置服务器"]);
        return;
    }

    NSString *rpcId = NSUUID.UUID.UUIDString;
    NSDictionary *body = @{
        @"type": @"client-request",
        @"rpcId": rpcId,
        @"method": endpoint,
        @"payload": @{@"args": args ?: @{}},
    };

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self.server.baseURL URLByAppendingPathComponent:[NSString stringWithFormat:@"api/%@", endpoint]]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = IMDSHUnaryTimeout;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [self authorizeRequest:request];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self deliver:completion value:nil error:error];
            return;
        }
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (http.statusCode == 401 || http.statusCode == 403) {
            [self deliver:completion value:nil error:[self errorWithCode:http.statusCode
                                                                 message:@"授权失效，请在设置里重新配对"]];
            return;
        }
        if (http.statusCode >= 400) {
            [self deliver:completion value:nil error:[self errorWithCode:http.statusCode
                                                                 message:[NSString stringWithFormat:@"网关返回 HTTP %ld", (long)http.statusCode]]];
            return;
        }

        NSString *contentType = http.MIMEType ?: @"";
        if ([contentType containsString:@"multipart/form-data"]) {
            // 二进制响应（文件字节）：抽出 metadata 与第一个 part 的 payload。
            id parsed = [self parseMultipart:data contentType:http.MIMEType];
            if ([parsed isKindOfClass:NSDictionary.class]) {
                NSDictionary *envelope = parsed[@"metadata"];
                if ([envelope isKindOfClass:NSDictionary.class] && [envelope[@"result"] isKindOfClass:NSDictionary.class]) {
                    NSDictionary *result = envelope[@"result"];
                    if ([result[@"ok"] boolValue]) {
                        NSMutableDictionary *value = [NSMutableDictionary dictionary];
                        id meta = result[@"value"];
                        if ([meta isKindOfClass:NSDictionary.class]) [value addEntriesFromDictionary:meta];
                        value[@"__multipart"] = @YES;
                        if (parsed[@"data"]) value[@"data"] = parsed[@"data"];
                        [self deliver:completion value:value error:nil];
                        return;
                    }
                    [self deliver:completion value:nil error:[self remoteErrorFromResult:result]];
                    return;
                }
            }
            [self deliver:completion value:nil error:[self errorWithCode:IMDSHClientErrorBadResponse message:@"二进制响应无法解析"]];
            return;
        }

        id json = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:NULL] : nil;
        if (![json isKindOfClass:NSDictionary.class]) {
            [self deliver:completion value:nil error:[self errorWithCode:IMDSHClientErrorBadResponse message:@"网关返回的不是 JSON"]];
            return;
        }
        NSDictionary *result = ((NSDictionary *)json)[@"result"];
        if (![result isKindOfClass:NSDictionary.class]) {
            [self deliver:completion value:nil error:[self errorWithCode:IMDSHClientErrorBadResponse message:@"响应缺少 result"]];
            return;
        }
        if ([result[@"ok"] boolValue]) {
            [self deliver:completion value:result[@"value"] error:nil];
        } else {
            [self deliver:completion value:nil error:[self remoteErrorFromResult:result]];
        }
    }];
    [task resume];
}

- (void)deliver:(IMRPCCompletion)completion value:(id)value error:(NSError *)error {
    if (completion == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(value, error);
    });
}

- (void)authorizeRequest:(NSMutableURLRequest *)request {
    NSString *token = self.server.deviceToken;
    if (token.length == 0) return;
    [request setValue:[NSString stringWithFormat:@"webim_device=%@", token] forHTTPHeaderField:@"Cookie"];
    [request setValue:token forHTTPHeaderField:@"X-IMDSH-Device"];
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:IMDSHClientErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"未知错误"}];
}

- (NSError *)remoteErrorFromResult:(NSDictionary *)result {
    NSDictionary *error = [result[@"error"] isKindOfClass:NSDictionary.class] ? result[@"error"] : @{};
    NSString *code = [error[@"code"] isKindOfClass:NSString.class] ? error[@"code"] : @"unknown";
    NSString *message = [error[@"message"] isKindOfClass:NSString.class] ? error[@"message"] : @"调用失败";
    return [NSError errorWithDomain:IMDSHClientErrorDomain
                               code:IMDSHClientErrorRemote
                           userInfo:@{NSLocalizedDescriptionKey: message,
                                      @"remoteCode": code,
                                      @"remoteDetails": error[@"details"] ?: @{}}];
}

#pragma mark - multipart

- (NSDictionary *)parseMultipart:(NSData *)data contentType:(NSString *)contentType {
    if (data.length == 0) return nil;
    NSString *boundary = nil;
    for (NSString *part in [contentType componentsSeparatedByString:@";"]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([trimmed.lowercaseString hasPrefix:@"boundary="]) {
            boundary = [trimmed substringFromIndex:@"boundary=".length];
            boundary = [boundary stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        }
    }
    if (boundary.length == 0) return nil;

    NSString *haystack = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSDictionary *metadata = nil;
    NSData *fileData = nil;

    // 以 "\r\n--boundary" 切分；首个 chunk 是前导。
    NSString *delimiter = [NSString stringWithFormat:@"--%@", boundary];
    NSArray<NSString *> *chunks = [haystack componentsSeparatedByString:delimiter];
    for (NSString *chunk in chunks) {
        NSRange headerBreak = [chunk rangeOfString:@"\r\n\r\n"];
        if (headerBreak.location == NSNotFound) continue;
        NSString *headers = [chunk substringToIndex:headerBreak.location];
        NSString *body = [chunk substringFromIndex:NSMaxRange(headerBreak)];
        if ([body hasSuffix:@"\r\n"]) body = [body substringToIndex:body.length - 2];

        if ([headers containsString:@"name=\"metadata\""]) {
            NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
            if (bodyData) metadata = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:NULL];
        } else if (fileData == nil && [headers.lowercaseString containsString:@"filename="]) {
            // 二进制 part 不能用 UTF-8 解码重建，只能按原始字节重新定位。
            fileData = [self rawPartData:data headersContaining:@"filename="];
        }
    }
    if (metadata == nil) return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"metadata"] = metadata;
    if (fileData) out[@"data"] = fileData;
    return out;
}

/// 直接从原始字节里截取第一个带文件名的 part 的内容（避免编码往返损坏二进制）。
- (NSData *)rawPartData:(NSData *)data headersContaining:(NSString *)needle {
    NSData *needleData = [needle dataUsingEncoding:NSUTF8StringEncoding];
    NSRange hit = [data rangeOfData:needleData options:0 range:NSMakeRange(0, data.length)];
    if (hit.location == NSNotFound) return nil;
    NSData *blankLine = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange after = NSMakeRange(hit.location, data.length - hit.location);
    NSRange blank = [data rangeOfData:blankLine options:0 range:after];
    if (blank.location == NSNotFound) return nil;
    NSUInteger start = NSMaxRange(blank);
    NSData *terminator = [@"\r\n--" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange end = [data rangeOfData:terminator options:0 range:NSMakeRange(start, data.length - start)];
    if (end.location == NSNotFound) return nil;
    return [data subdataWithRange:NSMakeRange(start, end.location - start)];
}

#pragma mark - 流

- (void)openStream:(NSString *)endpoint
              args:(NSDictionary *)args
          streamId:(NSString *)streamId
           onFrame:(IMStreamFrameHandler)onFrame
           onError:(IMStreamErrorHandler)onError {
    [self openStream:endpoint args:args streamId:streamId onFrame:onFrame onEnd:nil onError:onError];
}

- (void)openStream:(NSString *)endpoint
              args:(NSDictionary *)args
          streamId:(NSString *)streamId
           onFrame:(IMStreamFrameHandler)onFrame
             onEnd:(IMStreamEndHandler)onEnd
           onError:(IMStreamErrorHandler)onError {
    IMStreamSubscription *subscription = [IMStreamSubscription new];
    subscription.endpoint = endpoint;
    subscription.args = args ?: @{};
    subscription.onFrame = onFrame;
    subscription.onEnd = onEnd;
    subscription.onError = onError;

    // streams 会被 socket 回调队列与主线程同时读写（帧解析 vs UI 进出会话），必须加锁。
    BOOL existed = NO;
    BOOL connected = NO;
    @synchronized (self) {
        existed = self.streams[streamId] != nil;
        self.streams[streamId] = subscription;
        connected = self.connected;
    }

    if (!connected) {
        [self connect];
        return;
    }
    if (existed) {
        // 同一 socket 上重复 open 会被服务端 1008 掐掉整条连接：先 cancel，再把 open 推到下一个 runloop。
        [self sendJSON:@{@"type": @"cancel", @"streamId": streamId}];
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) return;
            BOOL stillCurrent = NO;
            @synchronized (self) {
                stillCurrent = (self.streams[streamId] == subscription);
            }
            if (!stillCurrent) return;
            [self sendOpenForStreamId:streamId subscription:subscription];
        });
        return;
    }
    [self sendOpenForStreamId:streamId subscription:subscription];
}

- (void)closeStream:(NSString *)streamId {
    if (streamId.length == 0) return;
    BOOL connected = NO;
    @synchronized (self) {
        [self.streams removeObjectForKey:streamId];
        connected = self.connected;
    }
    if (connected) {
        [self sendJSON:@{@"type": @"cancel", @"streamId": streamId}];
    }
}

- (void)closeAllStreams {
    NSArray<NSString *> *all = nil;
    @synchronized (self) {
        all = self.streams.allKeys;
    }
    for (NSString *streamId in all) {
        [self closeStream:streamId];
    }
}

- (void)sendOpenForStreamId:(NSString *)streamId subscription:(IMStreamSubscription *)subscription {
    NSDictionary *frame = @{
        @"type": @"open",
        @"streamId": streamId,
        @"endpoint": subscription.endpoint,
        @"payload": @{@"args": subscription.args},
    };
    [self sendJSON:frame];
}

- (void)sendJSON:(NSDictionary *)frame {
    if (self.socket == nil) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:frame options:0 error:NULL];
    if (data == nil) return;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text.length == 0) return;
    [self.socket sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:text]
           completionHandler:^(NSError *error) {
        if (error) {
            NSLog(@"[IMDSH] ws send failed: %@", error);
        }
    }];
}

#pragma mark - 连接管理

- (void)connect {
    self.wantsConnection = YES;
    if (self.socket != nil) return;
    NSURL *base = self.server.baseURL;
    if (base == nil) return;

    NSURLComponents *components = [NSURLComponents componentsWithURL:base resolvingAgainstBaseURL:NO];
    components.scheme = [components.scheme isEqualToString:@"https"] ? @"wss" : @"ws";
    components.path = @"/api/remote.mux";
    components.query = nil;
    NSURL *url = components.URL;
    if (url == nil) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [self authorizeRequest:request];

    NSURLSessionWebSocketTask *socket = [self.session webSocketTaskWithRequest:request];
    socket.maximumMessageSize = 16 * 1024 * 1024;
    self.socket = socket;
    [socket resume];

    self.retryAttempt = 0;   // 连上了就把退避计数清零，否则累计 12 次断线会永久放弃重连
    [self setConnected:YES];

    // resume 后立刻发 open 是安全的：URLSession 会缓冲到握手完成。
    NSDictionary<NSString *, IMStreamSubscription *> *snapshot = nil;
    @synchronized (self) {
        snapshot = [self.streams copy];
    }
    [snapshot enumerateKeysAndObjectsUsingBlock:^(NSString *streamId, IMStreamSubscription *subscription, BOOL *stop) {
        [self sendOpenForStreamId:streamId subscription:subscription];
    }];
    [self receiveNext];
    [self schedulePing];
}

- (void)disconnect {
    self.wantsConnection = NO;
    [self tearDownSocket];
}

- (void)tearDownSocket {
    self.pingScheduled = NO;
    NSURLSessionWebSocketTask *socket = self.socket;
    self.socket = nil;
    [socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
    [self setConnected:NO];
}

- (void)setConnected:(BOOL)connected {
    BOOL changed = NO;
    @synchronized (self) {
        if (_connected != connected) {
            _connected = connected;
            changed = YES;
        }
    }
    if (!changed) return;
    IMConnectionStateHandler handler = self.stateHandler;
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(connected);
        });
    }
}

- (void)setStateHandler:(IMConnectionStateHandler)handler {
    _stateHandler = [handler copy];
}

- (void)schedulePing {
    if (!self.wantsConnection) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil || self.socket == nil || !self.wantsConnection) return;
        [self.socket sendPingWithPongReceiveHandler:^(NSError *error) {
            if (error) {
                [weakSelf handleFailure:error];
                return;
            }
            [weakSelf schedulePing];
        }];
    });
}

- (void)receiveNext {
    NSURLSessionWebSocketTask *socket = self.socket;
    if (socket == nil) return;
    __weak typeof(self) weakSelf = self;
    [socket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (error) {
            [self handleFailure:error];
            return;
        }
        NSString *text = nil;
        if (message.type == NSURLSessionWebSocketMessageTypeString) {
            text = message.string;
        } else if (message.data) {
            text = [[NSString alloc] initWithData:message.data encoding:NSUTF8StringEncoding];
        }
        if (text.length > 0) {
            [self handleFrameText:text];
        }
        if (self.socket != nil) {
            [self receiveNext];
        }
    }];
}

- (void)handleFrameText:(NSString *)text {
    id json = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    if (![json isKindOfClass:NSDictionary.class]) return;
    NSDictionary *frame = (NSDictionary *)json;
    NSString *type = frame[@"type"];
    NSString *streamId = [frame[@"streamId"] isKindOfClass:NSString.class] ? frame[@"streamId"] : @"";
    if (streamId.length == 0) return;
    IMStreamSubscription *subscription = nil;
    @synchronized (self) {
        subscription = self.streams[streamId];
    }
    if (subscription == nil) return;

    if ([type isEqualToString:@"item"]) {
        id value = frame[@"value"];
        if ([value isKindOfClass:NSDictionary.class] && subscription.onFrame) {
            IMStreamFrameHandler handler = subscription.onFrame;
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(streamId, (NSDictionary *)value);
            });
        }
    } else if ([type isEqualToString:@"end"]) {
        // 服务端主动结束这条逻辑流（会话收尾、订阅被撤销）。订阅本身由调用方决定是否重开。
        IMStreamEndHandler handler = subscription.onEnd;
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(streamId);
            });
        }
    } else if ([type isEqualToString:@"error"]) {
        NSDictionary *error = [frame[@"error"] isKindOfClass:NSDictionary.class] ? frame[@"error"] : @{};
        NSString *message = [error[@"message"] isKindOfClass:NSString.class] ? error[@"message"] : @"流式订阅失败";
        NSError *nsError = [self errorWithCode:IMDSHClientErrorRemote message:message];
        if (subscription.onError) {
            IMStreamErrorHandler handler = subscription.onError;
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(streamId, nsError);
            });
        }
    }
}

- (void)handleFailure:(NSError *)error {
    BOOL shouldRetry = self.wantsConnection;
    [self tearDownSocket];
    if (!shouldRetry) return;
    if (self.retryAttempt >= IMDSHMaxReconnectAttempts) {
        NSLog(@"[IMDSH] giving up reconnect after %ld attempts", (long)self.retryAttempt);
        return;
    }
    self.retryAttempt += 1;
    NSTimeInterval delay = MIN(30.0, pow(2.0, MIN(self.retryAttempt, 5)));
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil || !self.wantsConnection) return;
        [self connect];
    });
}

@end
