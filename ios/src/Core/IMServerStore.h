//
//  IMServerStore.h
//  IMDSH — 多机管理（一台设备可保存多台 DSH 主机）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const IMServerStoreDidChangeNotification;

/// 一台已配对（或待配对）的 DSH 主机。
@interface IMServer : NSObject <NSCopying>

@property (nonatomic, copy) NSString *identifier;      // 本地 UUID
@property (nonatomic, copy) NSString *displayName;     // 用户可见名称
@property (nonatomic, copy) NSString *baseURLString;   // https://host[:port]
@property (nonatomic, copy, nullable) NSString *deviceToken; // Keychain 镜像（内存态）
@property (nonatomic, copy, nullable) NSString *deviceName;  // 服务端记录的设备名
@property (nonatomic, copy, nullable) NSString *pairingLabel; // 绑定用的配对码尾号，仅作展示
@property (nonatomic, strong, nullable) NSDate *pairedAt;
@property (nonatomic, strong, nullable) NSDate *lastConnectedAt;
@property (nonatomic, readonly) BOOL hasToken;

- (instancetype)initWithBaseURLString:(NSString *)baseURLString displayName:(NSString *)displayName;

/// 归一化后的 NSURL（无尾部斜杠）。
@property (nonatomic, readonly, nullable) NSURL *baseURL;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)serverWithDictionary:(NSDictionary *)dictionary;

@end

@interface IMServerStore : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, copy) NSArray<IMServer *> *servers;
@property (nonatomic, strong, nullable) IMServer *currentServer;

- (void)reload;
- (IMServer *)addServerWithBaseURLString:(NSString *)baseURLString displayName:(NSString *)displayName;
- (void)updateServer:(IMServer *)server;
- (void)removeServer:(IMServer *)server;
- (nullable IMServer *)serverWithIdentifier:(NSString *)identifier;

/// 设备 token 单独存 Keychain，避免出现在 plist/备份里。
/// 写设备令牌。返回 NO 表示 Keychain 写入失败（本次运行内存里仍可用，但重启后会丢），
/// 调用方应把这件事告诉用户，而不是静默当成成功。
- (BOOL)setDeviceToken:(nullable NSString *)token forServer:(IMServer *)server;
- (nullable NSString *)deviceTokenForServer:(IMServer *)server;

@end

/// 本机身份：deviceId 稳定（Keychain），名称可改。
@interface IMDeviceIdentity : NSObject

+ (NSString *)deviceId;
+ (NSString *)deviceName;
+ (void)setDeviceName:(NSString *)name;
+ (NSString *)platform;
/// 形如 "iPhone · iOS 27.2"
+ (NSString *)defaultDeviceName;

@end

NS_ASSUME_NONNULL_END
