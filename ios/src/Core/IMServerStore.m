#import "IMServerStore.h"
#import "IMKeychain.h"
#import <UIKit/UIKit.h>

NSNotificationName const IMServerStoreDidChangeNotification = @"IMServerStoreDidChangeNotification";

static NSString *const IMServersDefaultsKey = @"imdsh.servers.v1";
static NSString *const IMCurrentServerDefaultsKey = @"imdsh.current-server.v1";
static NSString *const IMDeviceIdKeychainKey = @"imdsh.device-id";
static NSString *const IMDeviceNameDefaultsKey = @"imdsh.device-name";

#pragma mark - IMServer

@implementation IMServer

- (instancetype)initWithBaseURLString:(NSString *)baseURLString displayName:(NSString *)displayName {
    self = [super init];
    if (self) {
        _identifier = NSUUID.UUID.UUIDString;
        _baseURLString = [baseURLString copy];
        _displayName = [displayName copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    IMServer *copy = [[IMServer allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.displayName = self.displayName;
    copy.baseURLString = self.baseURLString;
    copy.deviceToken = self.deviceToken;
    copy.deviceName = self.deviceName;
    copy.pairingLabel = self.pairingLabel;
    copy.pairedAt = self.pairedAt;
    copy.lastConnectedAt = self.lastConnectedAt;
    return copy;
}

- (NSURL *)baseURL {
    NSString *trimmed = [self.baseURLString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([trimmed hasSuffix:@"/"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    if (trimmed.length == 0) return nil;
    if (![trimmed containsString:@"://"]) {
        trimmed = [@"http://" stringByAppendingString:trimmed];
    }
    return [NSURL URLWithString:trimmed];
}

- (BOOL)hasToken {
    return self.deviceToken.length > 0;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"identifier"] = self.identifier ?: NSUUID.UUID.UUIDString;
    dict[@"displayName"] = self.displayName ?: @"DSH";
    dict[@"baseURL"] = self.baseURLString ?: @"";
    if (self.deviceName) dict[@"deviceName"] = self.deviceName;
    if (self.pairingLabel) dict[@"pairingLabel"] = self.pairingLabel;
    if (self.pairedAt) dict[@"pairedAt"] = @([self.pairedAt timeIntervalSince1970]);
    if (self.lastConnectedAt) dict[@"lastConnectedAt"] = @([self.lastConnectedAt timeIntervalSince1970]);
    return dict;
}

+ (instancetype)serverWithDictionary:(NSDictionary *)dictionary {
    NSString *base = dictionary[@"baseURL"];
    if (![base isKindOfClass:NSString.class] || base.length == 0) return nil;
    NSString *name = dictionary[@"displayName"];
    IMServer *server = [[IMServer alloc] initWithBaseURLString:base
                                                  displayName:[name isKindOfClass:NSString.class] ? name : @"DSH"];
    NSString *identifier = dictionary[@"identifier"];
    if ([identifier isKindOfClass:NSString.class] && identifier.length > 0) {
        server.identifier = identifier;
    }
    NSString *deviceName = dictionary[@"deviceName"];
    if ([deviceName isKindOfClass:NSString.class]) server.deviceName = deviceName;
    NSString *pairingLabel = dictionary[@"pairingLabel"];
    if ([pairingLabel isKindOfClass:NSString.class]) server.pairingLabel = pairingLabel;
    NSNumber *pairedAt = dictionary[@"pairedAt"];
    if ([pairedAt isKindOfClass:NSNumber.class]) server.pairedAt = [NSDate dateWithTimeIntervalSince1970:pairedAt.doubleValue];
    NSNumber *lastConnectedAt = dictionary[@"lastConnectedAt"];
    if ([lastConnectedAt isKindOfClass:NSNumber.class]) server.lastConnectedAt = [NSDate dateWithTimeIntervalSince1970:lastConnectedAt.doubleValue];
    return server;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<IMServer %@ %@ token=%@>", self.displayName, self.baseURLString, self.hasToken ? @"yes" : @"no"];
}

@end

#pragma mark - IMServerStore

@interface IMServerStore ()
@property (nonatomic, strong) NSMutableArray<IMServer *> *mutableServers;
/// 同一轮 runloop 内只发一条变更通知（见 notifyChange）。
@property (nonatomic, assign) BOOL notificationScheduled;
@end

@implementation IMServerStore

+ (instancetype)shared {
    static IMServerStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [IMServerStore new];
        [shared reload];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableServers = [NSMutableArray array];
    }
    return self;
}

- (NSArray<IMServer *> *)servers {
    return [self.mutableServers copy];
}

- (void)reload {
    [self.mutableServers removeAllObjects];

    NSArray *raw = [NSUserDefaults.standardUserDefaults arrayForKey:IMServersDefaultsKey];
    for (NSDictionary *dict in raw) {
        if (![dict isKindOfClass:NSDictionary.class]) continue;
        IMServer *server = [IMServer serverWithDictionary:dict];
        if (server) {
            server.deviceToken = [self deviceTokenForServer:server];
            if (server.deviceToken.length == 0) server.deviceToken = nil;
            [self.mutableServers addObject:server];
        }
    }

    NSString *currentIdentifier = [NSUserDefaults.standardUserDefaults stringForKey:IMCurrentServerDefaultsKey];
    self.currentServer = currentIdentifier ? [self serverWithIdentifier:currentIdentifier] : self.mutableServers.firstObject;
    if (self.currentServer == nil) self.currentServer = self.mutableServers.firstObject;

    [self notifyChange];
}

- (void)persist {
    NSMutableArray *raw = [NSMutableArray array];
    for (IMServer *server in self.mutableServers) {
        [raw addObject:[server dictionaryRepresentation]];
    }
    [NSUserDefaults.standardUserDefaults setObject:raw forKey:IMServersDefaultsKey];
    if (self.currentServer.identifier.length > 0) {
        [NSUserDefaults.standardUserDefaults setObject:self.currentServer.identifier forKey:IMCurrentServerDefaultsKey];
    } else {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:IMCurrentServerDefaultsKey];
    }
    [self notifyChange];
}

- (void)notifyChange {
    // 一次配对会连着 persist + 切 currentServer，若每次直发，UI 会连收 3~4 条通知并整块重建。
    // 同一轮 runloop 内合并成一条。
    if (self.notificationScheduled) return;
    self.notificationScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.notificationScheduled = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:IMServerStoreDidChangeNotification object:nil];
    });
}

- (IMServer *)addServerWithBaseURLString:(NSString *)baseURLString displayName:(NSString *)displayName {
    IMServer *server = [[IMServer alloc] initWithBaseURLString:baseURLString displayName:displayName];
    [self.mutableServers addObject:server];
    if (self.currentServer == nil) self.currentServer = server;
    [self persist];
    return server;
}

- (void)updateServer:(IMServer *)server {
    NSUInteger index = [self.mutableServers indexOfObjectPassingTest:^BOOL(IMServer *candidate, NSUInteger idx, BOOL *stop) {
        return [candidate.identifier isEqualToString:server.identifier];
    }];
    if (index == NSNotFound) return;
    if (server.deviceToken.length > 0) {
        [self setDeviceToken:server.deviceToken forServer:server];
    }
    self.mutableServers[index] = server;
    [self persist];
}

- (void)removeServer:(IMServer *)server {
    NSIndexSet *indexes = [self.mutableServers indexesOfObjectsPassingTest:^BOOL(IMServer *candidate, NSUInteger idx, BOOL *stop) {
        return [candidate.identifier isEqualToString:server.identifier];
    }];
    [self.mutableServers removeObjectsAtIndexes:indexes];
    [IMKeychain removeKey:[self tokenKeyForIdentifier:server.identifier]];
    if ([self.currentServer.identifier isEqualToString:server.identifier]) {
        self.currentServer = self.mutableServers.firstObject;
    }
    [self persist];
}

- (IMServer *)serverWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0) return nil;
    for (IMServer *server in self.mutableServers) {
        if ([server.identifier isEqualToString:identifier]) return server;
    }
    return nil;
}

- (NSString *)tokenKeyForIdentifier:(NSString *)identifier {
    return [NSString stringWithFormat:@"imdsh.server.%@.token", identifier];
}

- (BOOL)setDeviceToken:(NSString *)token forServer:(IMServer *)server {
    NSString *key = [self tokenKeyForIdentifier:server.identifier];
    if (token.length > 0) {
        // Keychain 写失败只靠日志是查不出来的：这次运行照常能连，但重启后 token 就没了。
        BOOL stored = [IMKeychain setString:token forKey:key];
        server.deviceToken = token;
        if (!stored) {
            NSLog(@"[IMDSH] Keychain 写入失败（服务 %@）：令牌只在内存里，重启后需要重新配对", server.identifier);
        }
        return stored;
    }
    [IMKeychain removeKey:key];
    server.deviceToken = nil;
    return YES;
}

- (NSString *)deviceTokenForServer:(IMServer *)server {
    return [IMKeychain stringForKey:[self tokenKeyForIdentifier:server.identifier]];
}

@end

#pragma mark - IMDeviceIdentity

@implementation IMDeviceIdentity

+ (NSString *)deviceId {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *existing = [IMKeychain stringForKey:IMDeviceIdKeychainKey];
        if (existing.length > 0) {
            cached = existing;
        } else {
            NSString *fresh = NSUUID.UUID.UUIDString;
            [IMKeychain setString:fresh forKey:IMDeviceIdKeychainKey];
            cached = fresh;
        }
    });
    return cached ?: NSUUID.UUID.UUIDString;
}

+ (NSString *)defaultDeviceName {
    NSString *model = UIDevice.currentDevice.model ?: @"iOS";
    NSString *system = [NSString stringWithFormat:@"iOS %@", UIDevice.currentDevice.systemVersion ?: @""];
    return [NSString stringWithFormat:@"%@ · %@", model, system];
}

+ (NSString *)deviceName {
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:IMDeviceNameDefaultsKey];
    if (stored.length > 0) return stored;
    return [self defaultDeviceName];
}

+ (void)setDeviceName:(NSString *)name {
    if (name.length == 0) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:IMDeviceNameDefaultsKey];
    } else {
        [NSUserDefaults.standardUserDefaults setObject:name forKey:IMDeviceNameDefaultsKey];
    }
}

+ (NSString *)platform {
    return @"ios";
}

@end
