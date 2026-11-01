#import "IMPairingService.h"
#import "IMAPIClient.h"
#import "IMServerStore.h"

@implementation IMPairingService

#pragma mark - 地址 / 配对码规范化

+ (NSURL *)normalizeAddress:(NSString *)rawAddress {
    NSString *text = [rawAddress stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0) return nil;

    // 允许用户直接粘贴网关给的长链接：取 scheme://host[:port]，丢弃 path/query。
    if ([text containsString:@"?"]) {
        text = [text componentsSeparatedByString:@"?"].firstObject;
    }
    if (![text containsString:@"://"]) {
        text = [@"http://" stringByAppendingString:text];
    }
    while ([text hasSuffix:@"/"]) {
        text = [text substringToIndex:text.length - 1];
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:text];
    if (components.host.length == 0) return nil;
    components.path = @"";
    components.query = nil;
    components.fragment = nil;
    return components.URL;
}

+ (NSString *)normalizeCode:(NSString *)rawCode {
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < rawCode.length; i++) {
        unichar c = [rawCode characterAtIndex:i];
        if ([allowed characterIsMember:c]) {
            [digits appendFormat:@"%C", c];
        }
    }
    return digits.uppercaseString;
}

#pragma mark - 探测

+ (void)probeServerAtURL:(NSURL *)url completion:(IMProbeCompletion)completion {
    IMAPIClient *client = [[IMAPIClient alloc] initWithBaseURL:url deviceToken:nil];
    client.timeout = 8;
    [client GET:@"__webim/ping" query:nil completion:^(id json, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            if (completion) completion(NO, nil, error);
            return;
        }
        if (![json isKindOfClass:NSDictionary.class]) {
            NSError *bad = [NSError errorWithDomain:IMAPIErrorDomain code:IMAPIErrorCodeBadResponse
                                           userInfo:@{NSLocalizedDescriptionKey: @"这个地址返回的不是 dsh-webim 网关"}];
            if (completion) completion(NO, nil, bad);
            return;
        }
        NSString *version = nil;
        id candidate = json[@"version"] ?: json[@"instance"] ?: json[@"plugin"];
        if ([candidate isKindOfClass:NSString.class]) version = candidate;
        if ([candidate isKindOfClass:NSDictionary.class]) {
            id v = ((NSDictionary *)candidate)[@"version"];
            if ([v isKindOfClass:NSString.class]) version = v;
        }
        if (completion) completion(YES, version, nil);
    }];
}

#pragma mark - 兑换

+ (void)redeemCode:(NSString *)code
             atURL:(NSURL *)url
      displayName:(NSString *)displayName
        completion:(IMRedeemCompletion)completion {
    NSString *normalized = [self normalizeCode:code];
    if (normalized.length < 8) {
        NSError *error = [NSError errorWithDomain:IMAPIErrorDomain code:IMAPIErrorCodeBadResponse
                                         userInfo:@{NSLocalizedDescriptionKey: @"配对码看起来不完整"}];
        if (completion) completion(nil, error);
        return;
    }

    NSDictionary *body = @{
        @"code": normalized,
        @"deviceId": [IMDeviceIdentity deviceId],
        @"deviceName": [IMDeviceIdentity deviceName],
        // 服务端优先读 `name`，两个都发（彼此等价）。
        @"name": [IMDeviceIdentity deviceName],
        @"platform": [IMDeviceIdentity platform],
    };

    IMAPIClient *client = [[IMAPIClient alloc] initWithBaseURL:url deviceToken:nil];
    [client POST:@"__webim/pair/redeem" json:body completion:^(id json, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        NSDictionary *dict = [json isKindOfClass:NSDictionary.class] ? (NSDictionary *)json : @{};
        NSDictionary *device = [dict[@"device"] isKindOfClass:NSDictionary.class] ? dict[@"device"] : @{};
        // 网关把令牌放在顶层 deviceToken；也兼容嵌套 device.token 的写法。
        NSString *token = [dict[@"deviceToken"] isKindOfClass:NSString.class] ? dict[@"deviceToken"] : device[@"token"];
        if (![token isKindOfClass:NSString.class] || token.length == 0) {
            NSError *bad = [NSError errorWithDomain:IMAPIErrorDomain code:IMAPIErrorCodeBadResponse
                                           userInfo:@{NSLocalizedDescriptionKey: @"网关没有返回设备令牌"}];
            if (completion) completion(nil, bad);
            return;
        }

        NSString *name = displayName.length > 0 ? displayName : url.host;
        IMServer *server = [IMServerStore.shared addServerWithBaseURLString:url.absoluteString displayName:name];
        [IMServerStore.shared setDeviceToken:token forServer:server];
        server.deviceName = device[@"name"];
        server.pairedAt = [NSDate date];
        NSString *pairingLabel = dict[@"pairingLabel"];
        if ([pairingLabel isKindOfClass:NSString.class]) {
            server.pairingLabel = pairingLabel;
        } else if (normalized.length >= 4) {
            server.pairingLabel = [normalized substringFromIndex:normalized.length - 4];
        }
        [IMServerStore.shared updateServer:server];
        IMServerStore.shared.currentServer = server;
        [IMServerStore.shared updateServer:server];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(server, nil);
        });
    }];
}

#pragma mark - 设备管理

+ (void)listDevicesForServer:(IMServer *)server completion:(IMDeviceListCompletion)completion {
    IMAPIClient *client = [[IMAPIClient alloc] initWithBaseURL:server.baseURL deviceToken:server.deviceToken];
    [client GET:@"__webim/pair/devices" query:nil completion:^(id json, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSArray *devices = nil;
        if ([json isKindOfClass:NSDictionary.class]) {
            id value = ((NSDictionary *)json)[@"devices"];
            if ([value isKindOfClass:NSArray.class]) devices = value;
        } else if ([json isKindOfClass:NSArray.class]) {
            devices = json;
        }
        if (completion) completion(devices ?: @[], nil);
    }];
}

+ (void)fetchInventoryForServer:(IMServer *)server completion:(IMInventoryCompletion)completion {
    IMAPIClient *client = [[IMAPIClient alloc] initWithBaseURL:server.baseURL deviceToken:server.deviceToken];
    [client GET:@"__webim/pair/devices" query:nil completion:^(id json, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *dict = [json isKindOfClass:NSDictionary.class] ? (NSDictionary *)json : @{};
        if (completion) completion(dict, nil);
    }];
}

+ (void)createPairingCodeForServer:(IMServer *)server
                              days:(NSNumber *)days
                        completion:(IMPairCodeCompletion)completion {
    IMAPIClient *client = [[IMAPIClient alloc] initWithBaseURL:server.baseURL deviceToken:server.deviceToken];
    NSDictionary *body = days != nil ? @{@"days": days} : @{};
    [client POST:@"__webim/pair/code" json:body completion:^(id json, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *dict = [json isKindOfClass:NSDictionary.class] ? (NSDictionary *)json : @{};
        id code = dict[@"pairingCode"];
        if (![code isKindOfClass:NSDictionary.class]) {
            // 兼容只回 {ok, code:"..."} 的旧版本。
            NSString *flat = [dict[@"code"] isKindOfClass:NSString.class] ? dict[@"code"] : nil;
            if (flat.length == 0) {
                NSError *bad = [NSError errorWithDomain:IMAPIErrorDomain
                                                   code:IMAPIErrorCodeBadResponse
                                               userInfo:@{NSLocalizedDescriptionKey: @"网关没有返回配对码"}];
                if (completion) completion(nil, bad);
                return;
            }
            code = @{@"code": flat};
        }
        if (completion) completion(code, nil);
    }];
}

+ (void)revokeCode:(NSString *)code forServer:(IMServer *)server completion:(IMSimpleCompletion)completion {
    NSString *normalized = [self normalizeCode:code];
    IMAPIClient *client = [[IMAPIClient alloc] initWithBaseURL:server.baseURL deviceToken:server.deviceToken];
    [client POST:@"__webim/pair/revoke" json:@{@"code": normalized ?: @""} completion:^(id json, NSHTTPURLResponse *response, NSError *error) {
        if (completion) completion(error);
    }];
}

+ (void)revokeDeviceWithIdentifier:(NSString *)deviceIdentifier
                        forServer:(IMServer *)server
                       completion:(IMSimpleCompletion)completion {
    IMAPIClient *client = [[IMAPIClient alloc] initWithBaseURL:server.baseURL deviceToken:server.deviceToken];
    NSDictionary *body = @{@"deviceId": deviceIdentifier ?: @""};
    [client POST:@"__webim/pair/revoke" json:body completion:^(id json, NSHTTPURLResponse *response, NSError *error) {
        if (completion) completion(error);
    }];
}

@end
