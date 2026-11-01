#import "IMAPIClient.h"

NSString *const IMAPIErrorDomain = @"IMAPIErrorDomain";
NSString *const IMAPIErrorRemoteCodeKey = @"IMAPIErrorRemoteCodeKey";
NSString *const IMAPIErrorHTTPStatusKey = @"IMAPIErrorHTTPStatusKey";

@implementation IMAPIClient

- (instancetype)initWithBaseURL:(NSURL *)baseURL deviceToken:(NSString *)deviceToken {
    self = [super init];
    if (self) {
        _baseURL = baseURL;
        _deviceToken = [deviceToken copy];
        _timeout = 20.0;
    }
    return self;
}

- (void)GET:(NSString *)path query:(NSDictionary<NSString *, NSString *> *)query completion:(IMAPICompletion)completion {
    NSURLComponents *components = [NSURLComponents componentsWithURL:[self.baseURL URLByAppendingPathComponent:path]
                                            resolvingAgainstBaseURL:NO];
    if (query.count > 0) {
        NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
        [query enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [items addObject:[NSURLQueryItem queryItemWithName:key value:value]];
        }];
        components.queryItems = items;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    request.HTTPMethod = @"GET";
    [self sendRequest:request completion:completion];
}

- (void)POST:(NSString *)path json:(id)json completion:(IMAPICompletion)completion {
    NSURL *url = [self.baseURL URLByAppendingPathComponent:path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (json != nil) {
        NSError *serializationError = nil;
        NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:&serializationError];
        if (body == nil) {
            if (completion) completion(nil, nil, serializationError);
            return;
        }
        request.HTTPBody = body;
    }
    [self sendRequest:request completion:completion];
}

- (void)sendRequest:(NSMutableURLRequest *)request completion:(IMAPICompletion)completion {
    request.timeoutInterval = self.timeout;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"IMDSH-iOS" forHTTPHeaderField:@"X-IMDSH-Client"];
    if (self.deviceToken.length > 0) {
        [request setValue:[NSString stringWithFormat:@"webim_device=%@", self.deviceToken] forHTTPHeaderField:@"Cookie"];
        [request setValue:self.deviceToken forHTTPHeaderField:@"X-IMDSH-Device"];
    }

    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = self.timeout;
    config.HTTPShouldSetCookies = NO;
    config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(nil, (NSHTTPURLResponse *)response, error);
                return;
            }
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            id json = nil;
            if (data.length > 0) {
                json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:NULL];
            }

            if (http.statusCode >= 200 && http.statusCode < 300) {
                if (completion) completion(json, http, nil);
                return;
            }

            NSError *apiError = [self errorForStatus:http.statusCode json:json];
            if (completion) completion(json, http, apiError);
        });
    }];
    [task resume];
}

- (NSError *)errorForStatus:(NSInteger)status json:(id)json {
    NSString *remoteCode = nil;
    NSString *remoteMessage = nil;
    if ([json isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)json;
        id error = dict[@"error"];
        if ([error isKindOfClass:NSDictionary.class]) {
            remoteCode = error[@"code"];
            remoteMessage = error[@"message"];
        } else if ([error isKindOfClass:NSString.class]) {
            remoteMessage = error;
        }
        if (remoteMessage.length == 0) {
            id message = dict[@"message"];
            if ([message isKindOfClass:NSString.class]) remoteMessage = message;
        }
        if (remoteCode.length == 0) {
            id code = dict[@"code"];
            if ([code isKindOfClass:NSString.class]) remoteCode = code;
        }
    }

    NSInteger code = IMAPIErrorCodeRemote;
    switch (status) {
        case 401: code = IMAPIErrorCodeUnauthorized; break;
        case 403: code = IMAPIErrorCodeForbidden; break;
        case 404: code = IMAPIErrorCodeNotFound; break;
        case 409: code = IMAPIErrorCodeConflict; break;
        case 429: code = IMAPIErrorCodeRateLimited; break;
        default:
            if (status >= 500) code = IMAPIErrorCodeServer;
            break;
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = remoteMessage.length > 0 ? remoteMessage : [NSString stringWithFormat:@"HTTP %ld", (long)status];
    info[IMAPIErrorHTTPStatusKey] = @(status);
    if (remoteCode.length > 0) info[IMAPIErrorRemoteCodeKey] = remoteCode;
    return [NSError errorWithDomain:IMAPIErrorDomain code:code userInfo:info];
}

+ (NSString *)localizedMessageForError:(NSError *)error {
    if (error == nil) return @"";
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorCannotConnectToHost: return @"连不上这台主机，确认地址与端口，以及 DSH 的远程接入是否已开启";
            case NSURLErrorTimedOut: return @"请求超时，网络不稳或主机没响应";
            case NSURLErrorNotConnectedToInternet: return @"设备没有联网";
            case NSURLErrorCannotFindHost: return @"域名解析失败，检查地址是否写对";
            case NSURLErrorSecureConnectionFailed:
            case NSURLErrorServerCertificateUntrusted: return @"TLS 证书不被信任";
            default: return error.localizedDescription ?: @"网络错误";
        }
    }
    NSString *remote = error.userInfo[IMAPIErrorRemoteCodeKey];
    if ([remote isEqualToString:@"code-already-bound"]) {
        return @"这个配对码已经绑定到另一台设备了，请在这台主机上重新生成";
    }
    if ([remote isEqualToString:@"code-expired"]) return @"配对码已过期，请重新生成";
    if ([remote isEqualToString:@"code-invalid"]) return @"配对码不对，注意区分容易混淆的字符";
    if ([remote isEqualToString:@"rate-limited"]) return @"尝试太频繁，稍后再试";
    if (error.code == IMAPIErrorCodeUnauthorized) return @"授权失效，请重新配对";
    return error.localizedDescription ?: @"未知错误";
}

@end
