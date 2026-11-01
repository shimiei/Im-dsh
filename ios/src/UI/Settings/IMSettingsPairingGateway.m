//
//  IMSettingsPairingGateway.m
//  IMDSH — 设置域的配对管理适配层
//

#import "IMSettingsPairingGateway.h"
#import "IMAPIClient.h"
#import "IMPairingService.h"
#import "IMFormatting.h"

NSString *const IMSettingsPairingErrorDomain = @"IMSettingsPairingErrorDomain";

static NSError *IMSettingsPairingError(IMSettingsPairingErrorCode code, NSString *message) {
    return [NSError errorWithDomain:IMSettingsPairingErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

/// 服务端字段可能是 NSNumber / NSString / 缺失，统一按「有值才取」处理。
static NSString *IMStringValue(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return nil;
}

static BOOL IMBoolValue(id value) {
    return [value isKindOfClass:NSNumber.class] && [(NSNumber *)value boolValue];
}

static NSString *IMFormatPairCode(NSString *plain) {
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    for (NSUInteger index = 0; index < plain.length; index += 4) {
        NSUInteger length = MIN((NSUInteger)4, plain.length - index);
        [groups addObject:[plain substringWithRange:NSMakeRange(index, length)]];
    }
    return [groups componentsJoinedByString:@"-"];
}

/// 剩余天数：优先用服务端算好的天数，其次按到期时间推算，都没有就 -1（UI 不编造）。
static NSInteger IMRemainingDays(id inDays, NSDate *expiresAt) {
    if ([inDays isKindOfClass:NSNumber.class]) return [(NSNumber *)inDays integerValue];
    if (expiresAt != nil) return MAX(0, (NSInteger)ceil([expiresAt timeIntervalSinceNow] / 86400.0));
    return -1;
}

#pragma mark - IMPairingDevice

@implementation IMPairingDevice

+ (instancetype)deviceWithDictionary:(NSDictionary *)dictionary currentDeviceId:(NSString *)deviceId {
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;

    NSString *identifier = IMStringValue(dictionary[@"deviceId"]) ?: IMStringValue(dictionary[@"id"]);
    if (identifier.length == 0) return nil;

    IMPairingDevice *device = [[IMPairingDevice alloc] init];
    device.deviceIdentifier = identifier;
    NSString *prefix = IMStringValue(dictionary[@"deviceIdPrefix"]);
    device.shortIdentifier = prefix.length > 0
        ? prefix
        : (identifier.length > 8 ? [identifier substringToIndex:8] : identifier);
    device.name = IMStringValue(dictionary[@"name"]) ?: @"";
    device.platformText = IMStringValue(dictionary[@"platform"]) ?: @"";
    device.platformDisplayName = [IMSettingsPairingGateway platformDisplayNameForText:device.platformText];
    device.pairedAt = IMDateFromFlexibleValue(dictionary[@"createdAt"]) ?: IMDateFromFlexibleValue(dictionary[@"pairedAt"]);
    device.lastSeenAt = IMDateFromFlexibleValue(dictionary[@"lastSeenAt"]);
    device.revoked = IMBoolValue(dictionary[@"revoked"]);
    device.currentDevice = deviceId.length > 0 && [identifier isEqualToString:deviceId];
    return device;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<IMPairingDevice %@ %@%@>", self.shortIdentifier, self.name,
            self.currentDevice ? @" (current)" : @""];
}

@end

#pragma mark - IMPairingCode

@implementation IMPairingCode

+ (instancetype)codeWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;

    // 网关/Net 可能把码放在顶层 code，也可能再包一层 pairingCode；两种都收。
    NSDictionary *payload = dictionary;
    id nested = dictionary[@"pairingCode"];
    if ([nested isKindOfClass:NSDictionary.class]) payload = nested;
    else if ([nested isKindOfClass:NSString.class]) payload = @{@"code": nested};

    NSString *raw = IMStringValue(dictionary[@"code"]);
    if (raw.length == 0) raw = IMStringValue(payload[@"code"]);
    if (raw.length == 0 && [dictionary[@"record"] isKindOfClass:NSDictionary.class]) {
        NSDictionary *record = dictionary[@"record"];
        raw = IMStringValue(record[@"code"]) ?: IMStringValue(record[@"pairingCode"]);
    }
    if (raw.length == 0) return nil;

    IMPairingCode *code = [[IMPairingCode alloc] init];
    code.plainCode = [IMPairingService normalizeCode:raw];
    if (code.plainCode.length == 0) return nil;
    code.displayCode = IMFormatPairCode(code.plainCode);

    NSDate *expiresAt = IMDateFromFlexibleValue(payload[@"expiresAt"]);
    if (expiresAt == nil) expiresAt = IMDateFromFlexibleValue(dictionary[@"expiresAt"]);
    code.expiresAt = expiresAt;

    id inDays = payload[@"expiresInDays"] ?: dictionary[@"expiresInDays"];
    // 契约用 expiresAt == 0 表示永久，同时给 permanent = true、expiresInDays = 0。
    if (expiresAt == nil && (IMBoolValue(payload[@"permanent"]) || IMBoolValue(dictionary[@"permanent"])
                             || ([inDays isKindOfClass:NSNumber.class] && [inDays integerValue] == 0))) {
        code.neverExpires = YES;
        code.remainingDays = -1;
        return code;
    }

    code.neverExpires = NO;
    code.remainingDays = IMRemainingDays(inDays, expiresAt);
    return code;
}

@end

#pragma mark - IMPairingCodeRecord

@implementation IMPairingCodeRecord

+ (instancetype)recordWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;

    NSDictionary *payload = dictionary;
    id nested = dictionary[@"pairingCode"];
    if ([nested isKindOfClass:NSDictionary.class]) payload = nested;

    NSString *raw = IMStringValue(payload[@"code"]) ?: IMStringValue(dictionary[@"code"]);
    if (raw.length == 0) return nil;

    IMPairingCodeRecord *record = [[IMPairingCodeRecord alloc] init];
    record.plainCode = [IMPairingService normalizeCode:raw];
    if (record.plainCode.length == 0) return nil;
    record.displayCode = IMFormatPairCode(record.plainCode);

    record.createdAt = IMDateFromFlexibleValue(payload[@"createdAt"]);
    record.expiresAt = IMDateFromFlexibleValue(payload[@"expiresAt"]);
    record.revoked = IMBoolValue(payload[@"revoked"]);
    record.expired = IMBoolValue(payload[@"expired"]);
    record.redeemedDevicePrefix = IMStringValue(payload[@"deviceIdPrefix"]);
    if (record.redeemedDevicePrefix.length == 0) record.redeemedDevicePrefix = nil;

    id inDays = payload[@"expiresInDays"];
    BOOL permanent = IMBoolValue(payload[@"permanent"]);
    record.neverExpires = permanent || (record.expiresAt == nil && [inDays isKindOfClass:NSNumber.class] && [inDays integerValue] == 0);
    record.remainingDays = record.neverExpires ? -1 : IMRemainingDays(inDays, record.expiresAt);

    // 服务端可能来不及打 expired 标记（本机时钟/缓存），本地再判一次到期。
    BOOL timeExpired = record.expiresAt != nil && [record.expiresAt timeIntervalSinceNow] <= 0;
    BOOL redeemed = IMBoolValue(payload[@"redeemed"]) || record.redeemedDevicePrefix.length > 0;

    if (record.revoked) {
        record.state = IMPairingCodeStateDead;
    } else if (redeemed) {
        record.state = IMPairingCodeStateRedeemed;   // 已兑换的码本来就不能再用，语义上比「过期」更准
    } else if (record.expired || timeExpired) {
        record.state = IMPairingCodeStateDead;
    } else {
        record.state = IMPairingCodeStateUnused;
    }
    return record;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<IMPairingCodeRecord %@ state=%ld>", self.displayCode, (long)self.state];
}

@end

#pragma mark - IMSettingsPairingGateway

@implementation IMSettingsPairingGateway

+ (void)fetchInventoryForServer:(IMServer *)server completion:(IMSettingsInventoryCompletion)completion {
    if (server == nil) {
        if (completion) completion(nil, nil, IMSettingsPairingError(IMSettingsPairingErrorCodeMissingToken, @"还没有添加主机"));
        return;
    }
    if (server.deviceToken.length == 0) {
        if (completion) completion(nil, nil, IMSettingsPairingError(IMSettingsPairingErrorCodeMissingToken, @"这台主机还没完成配对"));
        return;
    }

    // 一次 GET 拿到 {pairDays, devices[], pairingCodes[]}：Net 层负责 HTTP 与错误语义，
    // 本层只做字典 → 模型（脏数据一律跳过，不越界、不崩）。
    [IMPairingService fetchInventoryForServer:server completion:^(NSDictionary *inventory, NSError *error) {
        if (error) {
            if (completion) completion(nil, nil, error);
            return;
        }
        if (![inventory isKindOfClass:NSDictionary.class]) {
            if (completion) completion(nil, nil, IMSettingsPairingError(IMSettingsPairingErrorCodeBadResponse,
                                                                        @"主机返回的数据看不懂"));
            return;
        }

        NSDictionary *dict = inventory;
        NSString *currentDeviceId = [IMDeviceIdentity deviceId];

        NSMutableArray<IMPairingDevice *> *devices = [NSMutableArray array];
        id rawDevices = dict[@"devices"];
        if ([rawDevices isKindOfClass:NSArray.class]) {
            for (id raw in (NSArray *)rawDevices) {
                if (![raw isKindOfClass:NSDictionary.class]) continue;   // 脏数据直接跳过，不崩
                IMPairingDevice *device = [IMPairingDevice deviceWithDictionary:raw currentDeviceId:currentDeviceId];
                if (device) [devices addObject:device];
            }
        }
        // 自己永远排最前：吊销/核对身份时最常看的就是这一行。
        [devices sortUsingComparator:^NSComparisonResult(IMPairingDevice *lhs, IMPairingDevice *rhs) {
            if (lhs.currentDevice != rhs.currentDevice) return lhs.currentDevice ? NSOrderedAscending : NSOrderedDescending;
            NSDate *left = lhs.lastSeenAt ?: lhs.pairedAt ?: NSDate.distantPast;
            NSDate *right = rhs.lastSeenAt ?: rhs.pairedAt ?: NSDate.distantPast;
            return [right compare:left];
        }];

        NSMutableArray<IMPairingCodeRecord *> *codes = [NSMutableArray array];
        id rawCodes = dict[@"pairingCodes"];
        if ([rawCodes isKindOfClass:NSArray.class]) {
            for (id raw in (NSArray *)rawCodes) {
                if (![raw isKindOfClass:NSDictionary.class]) continue;
                IMPairingCodeRecord *record = [IMPairingCodeRecord recordWithDictionary:raw];
                if (record) [codes addObject:record];
            }
        }
        [codes sortUsingComparator:^NSComparisonResult(IMPairingCodeRecord *lhs, IMPairingCodeRecord *rhs) {
            NSDate *left = lhs.createdAt ?: NSDate.distantPast;
            NSDate *right = rhs.createdAt ?: NSDate.distantPast;
            return [right compare:left];
        }];

        if (completion) completion(devices, codes, nil);
    }];
}

+ (void)listDevicesForServer:(IMServer *)server
                  completion:(void (^)(NSArray<IMPairingDevice *> * _Nullable, NSError * _Nullable))completion {
    [self fetchInventoryForServer:server completion:^(NSArray<IMPairingDevice *> *devices, NSArray<IMPairingCodeRecord *> *codes, NSError *error) {
        if (completion) completion(devices, error);
    }];
}

+ (void)revokeDevice:(IMPairingDevice *)device
           forServer:(IMServer *)server
          completion:(IMSimpleCompletion)completion {
    if (device.deviceIdentifier.length == 0) {
        if (completion) completion(IMSettingsPairingError(IMSettingsPairingErrorCodeBadResponse, @"设备缺少标识，无法吊销"));
        return;
    }
    [IMPairingService revokeDeviceWithIdentifier:device.deviceIdentifier forServer:server completion:completion];
}

+ (void)revokeCode:(IMPairingCodeRecord *)record
         forServer:(IMServer *)server
        completion:(IMSimpleCompletion)completion {
    if (record.plainCode.length == 0) {
        if (completion) completion(IMSettingsPairingError(IMSettingsPairingErrorCodeBadResponse, @"配对码为空，无法吊销"));
        return;
    }
    [IMPairingService revokeCode:record.plainCode forServer:server completion:completion];
}

+ (void)createPairingCodeForServer:(IMServer *)server
                              days:(NSNumber *)days
                        completion:(void (^)(IMPairingCode * _Nullable, NSError * _Nullable))completion {
    if (server.baseURL == nil) {
        if (completion) completion(nil, IMSettingsPairingError(IMSettingsPairingErrorCodeBadResponse, @"主机地址无效"));
        return;
    }
    if (server.deviceToken.length == 0) {
        // 先在本侧拦一下：比让请求撞 401 更快，文案也更具体。
        if (completion) completion(nil, IMSettingsPairingError(IMSettingsPairingErrorCodeMissingToken, @"这台主机还没完成配对"));
        return;
    }

    [IMPairingService createPairingCodeForServer:server days:days completion:^(NSDictionary *pairingCode, NSError *error) {
        if (error) {
            NSInteger status = [error.userInfo[IMAPIErrorHTTPStatusKey] integerValue];
            // 旧网关没有这个路由（404）或不允许该方法（405）：这是「功能不存在」，不是错误。
            if (status == 404 || status == 405) {
                if (completion) completion(nil, IMSettingsPairingError(IMSettingsPairingErrorCodeUnavailable,
                                                                       @"这台主机的网关版本不支持生成配对码"));
                return;
            }
            if (completion) completion(nil, error);
            return;
        }

        IMPairingCode *code = pairingCode != nil ? [IMPairingCode codeWithDictionary:pairingCode] : nil;
        if (code == nil) {
            if (completion) completion(nil, IMSettingsPairingError(IMSettingsPairingErrorCodeBadResponse,
                                                                    @"网关返回的数据里没有配对码"));
            return;
        }
        if (completion) completion(code, nil);
    }];
}

+ (NSString *)messageForError:(NSError *)error {
    if (error == nil) return @"";
    if ([error.domain isEqualToString:IMSettingsPairingErrorDomain]) {
        return error.localizedDescription;
    }
    return [IMAPIClient localizedMessageForError:error];
}

+ (BOOL)isUnavailableError:(NSError *)error {
    if (error == nil) return NO;
    if ([error.domain isEqualToString:IMSettingsPairingErrorDomain]) {
        return error.code == IMSettingsPairingErrorCodeUnavailable;
    }
    NSInteger status = [error.userInfo[IMAPIErrorHTTPStatusKey] integerValue];
    return status == 404 || status == 405;
}

+ (NSString *)platformDisplayNameForText:(NSString *)platform {
    NSString *text = [platform.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (text.length == 0) return @"未知平台";
    if ([text isEqualToString:@"ios"] || [text isEqualToString:@"iphoneos"] || [text isEqualToString:@"ipados"]) return @"iOS";
    if ([text isEqualToString:@"macos"] || [text isEqualToString:@"osx"] || [text isEqualToString:@"darwin"]) return @"macOS";
    if ([text isEqualToString:@"android"]) return @"Android";
    if ([text isEqualToString:@"windows"]) return @"Windows";
    if ([text isEqualToString:@"linux"]) return @"Linux";
    if ([text isEqualToString:@"web"]) return @"Web";
    return platform;   // 不认识的平台原样展示，避免瞎翻译
}

@end
