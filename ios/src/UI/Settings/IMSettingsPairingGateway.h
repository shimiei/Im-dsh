//
//  IMSettingsPairingGateway.h
//  IMDSH — 设置域的配对管理适配层
//
//  职责：把网关的原始 JSON（设备表 / 配对码）翻译成 UI 能直接吃的模型。
//  HTTP 一律走 Net 层（IMPairingService / IMAPIClient），本层不重复实现协议。
//
//  契约（lib/gateway.js + lib/pairing.js）：
//    GET  __webim/pair/devices → {ok, pairDays, devices:[{deviceId, deviceIdPrefix,
//                                name, platform, createdAt, lastSeenAt, revoked, revokedAt}],
//                                pairingCodes:[{code, createdAt, expiresAt(ms, 0=永久),
//                                expiresInDays, permanent, expired, redeemed, deviceIdPrefix,
//                                revoked, revokedAt}]}
//    POST __webim/pair/code    → {ok, pairDays, pairingCode:{...}}      （Net 已封装）
//    POST __webim/pair/revoke  → {ok}  body {deviceId} 或 {code}        （Net 已封装）
//    错误统一 {ok:false, code:"rate-limited"|"code-invalid"|...}，HTTP 状态即语义。
//

#import <Foundation/Foundation.h>
#import "IMServerStore.h"
#import "IMPairingService.h"

NS_ASSUME_NONNULL_BEGIN

/// 本层自有的错误（无法从 HTTP 层直接表达的那几种状态）。
FOUNDATION_EXPORT NSString *const IMSettingsPairingErrorDomain;
typedef NS_ENUM(NSInteger, IMSettingsPairingErrorCode) {
    /// 网关没有这个接口（旧版本）：UI 应降级为「不可用」，而不是报红色错误。
    IMSettingsPairingErrorCodeUnavailable = -201,
    /// 还没有设备令牌，无法调用需要授权的接口。
    IMSettingsPairingErrorCodeMissingToken = -202,
    /// 响应缺少关键字段。
    IMSettingsPairingErrorCodeBadResponse = -203,
};

#pragma mark - 服务端设备表

/// 服务端设备表里的一台设备（只保留 UI 需要的字段，全部做了类型校验）。
@interface IMPairingDevice : NSObject

@property (nonatomic, copy) NSString *deviceIdentifier;          // 服务端主键 deviceId
@property (nonatomic, copy) NSString *shortIdentifier;           // 前 8 位，列表里给人看
@property (nonatomic, copy) NSString *name;                      // 可能为空串
@property (nonatomic, copy) NSString *platformText;              // 原始 platform，如 "ios"
@property (nonatomic, copy) NSString *platformDisplayName;       // "iOS"
@property (nonatomic, strong, nullable) NSDate *pairedAt;
@property (nonatomic, strong, nullable) NSDate *lastSeenAt;
/// 与 IMDeviceIdentity.deviceId 相同 → 就是当前这台设备。
@property (nonatomic, assign) BOOL currentDevice;
@property (nonatomic, assign) BOOL revoked;

+ (nullable instancetype)deviceWithDictionary:(NSDictionary *)dictionary
                              currentDeviceId:(nullable NSString *)deviceId;
@end

#pragma mark - 配对码

/// 刚生成的那一枚码（用于大字展示给用户抄录）。
@interface IMPairingCode : NSObject

@property (nonatomic, copy) NSString *plainCode;                 // 无分隔符，便于复制/比对
@property (nonatomic, copy) NSString *displayCode;               // XXXX-XXXX-XXXX
@property (nonatomic, assign) BOOL neverExpires;
@property (nonatomic, strong, nullable) NSDate *expiresAt;
/// 剩余天数；-1 表示服务端没给且无法推算。
@property (nonatomic, assign) NSInteger remainingDays;

+ (nullable instancetype)codeWithDictionary:(NSDictionary *)dictionary;
@end

typedef NS_ENUM(NSInteger, IMPairingCodeState) {
    /// 还没被任何设备用过，可以拿去配对。
    IMPairingCodeStateUnused = 0,
    /// 已经被某台设备兑换。
    IMPairingCodeStateRedeemed,
    /// 已过期或被吊销，不再可用。
    IMPairingCodeStateDead,
};

/// 配对码列表里的一条记录。状态判定顺序：吊销 > 已兑换 > 过期 > 可用。
@interface IMPairingCodeRecord : NSObject

@property (nonatomic, copy) NSString *plainCode;
@property (nonatomic, copy) NSString *displayCode;
@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *expiresAt;
@property (nonatomic, assign) BOOL neverExpires;
@property (nonatomic, assign) NSInteger remainingDays;           // -1 未知
@property (nonatomic, assign) IMPairingCodeState state;
/// 已兑换时，使用它的那台设备的 id 前缀（服务端只回前 8 位）。
@property (nonatomic, copy, nullable) NSString *redeemedDevicePrefix;
@property (nonatomic, assign) BOOL revoked;
@property (nonatomic, assign) BOOL expired;

+ (nullable instancetype)recordWithDictionary:(NSDictionary *)dictionary;
@end

#pragma mark - 适配层

typedef void (^IMSettingsInventoryCompletion)(NSArray<IMPairingDevice *> * _Nullable devices,
                                              NSArray<IMPairingCodeRecord *> * _Nullable codes,
                                              NSError * _Nullable error);

@interface IMSettingsPairingGateway : NSObject

/// 一次请求拿到「设备表 + 配对码表」。两个数组都按 UI 需要排好序：
/// 设备（当前设备第一，其余按最后活跃倒序）、配对码（按创建时间倒序）。
+ (void)fetchInventoryForServer:(IMServer *)server completion:(IMSettingsInventoryCompletion)completion;

/// 只要设备表时的便捷入口（等价于 fetchInventoryForServer:，丢弃配对码）。
+ (void)listDevicesForServer:(IMServer *)server
                  completion:(void (^)(NSArray<IMPairingDevice *> * _Nullable devices,
                                       NSError * _Nullable error))completion;

/// 吊销一台设备（直通 IMPairingService，body 为 {deviceId}）。
+ (void)revokeDevice:(IMPairingDevice *)device
           forServer:(IMServer *)server
          completion:(IMSimpleCompletion)completion;

/// 吊销一枚还没用过的配对码（直通 IMPairingService，body 为 {code}）。
+ (void)revokeCode:(IMPairingCodeRecord *)record
         forServer:(IMServer *)server
        completion:(IMSimpleCompletion)completion;

/// 生成一枚新配对码（直通 IMPairingService）。days 传 nil 用主机默认有效期；@0 = 永久。
+ (void)createPairingCodeForServer:(IMServer *)server
                              days:(nullable NSNumber *)days
                        completion:(void (^)(IMPairingCode * _Nullable code,
                                             NSError * _Nullable error))completion;

/// 错误 → 简体中文说明（含本层自有错误的特判，其余交给 IMAPIClient）。
+ (NSString *)messageForError:(nullable NSError *)error;

/// 该错误是否表示「这台主机不支持此功能」，UI 据此走灰度降级。
+ (BOOL)isUnavailableError:(nullable NSError *)error;

/// platform 字段 → 展示名（"ios" → "iOS"）。
+ (NSString *)platformDisplayNameForText:(nullable NSString *)platform;

@end

NS_ASSUME_NONNULL_END
