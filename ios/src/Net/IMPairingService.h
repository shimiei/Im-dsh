//
//  IMPairingService.h
//  IMDSH — 配对流程（地址 + 配对码 → 长效 device token）
//
//  服务端契约见 imdsh/docs/pairing-api.md（由 dsh-webim 的 lib/pairing.js 提供）：
//    POST /__webim/pair/redeem  {code, deviceId, deviceName, platform}
//      → 200 {ok:true, device:{token,id,name}, server:{version,...}}
//      → 4xx {ok:false, error:{code,message}}
//    GET  /__webim/pair/devices  （需已配对）→ {ok:true, devices:[...]}
//    POST /__webim/pair/revoke   {id}
//    GET  /__webim/ping          → 网关自述（连通性/版本探测）
//

#import <Foundation/Foundation.h>
#import "IMServerStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMProbeCompletion)(BOOL reachable, NSString * _Nullable version, NSError * _Nullable error);
typedef void (^IMRedeemCompletion)(IMServer * _Nullable server, NSError * _Nullable error);
typedef void (^IMDeviceListCompletion)(NSArray<NSDictionary *> * _Nullable devices, NSError * _Nullable error);
typedef void (^IMInventoryCompletion)(NSDictionary * _Nullable inventory, NSError * _Nullable error);
typedef void (^IMPairCodeCompletion)(NSDictionary * _Nullable pairingCode, NSError * _Nullable error);
typedef void (^IMSimpleCompletion)(NSError * _Nullable error);

@interface IMPairingService : NSObject

/// 探测地址是否是活的 dsh-webim 网关（能拿到 /__webim/ping 且结构对）。
+ (void)probeServerAtURL:(NSURL *)url completion:(IMProbeCompletion)completion;

/// 用配对码兑换：成功后自动在 IMServerStore 中建好记录、写入 Keychain token，并设为当前服务器。
+ (void)redeemCode:(NSString *)code
             atURL:(NSURL *)url
      displayName:(nullable NSString *)displayName
        completion:(IMRedeemCompletion)completion;

/// 已配对设备列表（管理用）。
+ (void)listDevicesForServer:(IMServer *)server completion:(IMDeviceListCompletion)completion;

/// 配对清单：一次拿到 `{pairDays, devices[], pairingCodes[]}` 原始字典。
/// 设置页要同时展示设备与配对码时用这个，别为一个 GET 打两次。
+ (void)fetchInventoryForServer:(IMServer *)server completion:(IMInventoryCompletion)completion;

/// 在主机上生成一张新配对码。days 传 nil 用主机默认（30 天），@0 表示永久。
/// 成功时回调的是一个 pairingCode 字典：code / createdAt / expiresAt / expiresInDays /
/// permanent / expired / redeemed / deviceIdPrefix / revoked。
+ (void)createPairingCodeForServer:(IMServer *)server
                              days:(nullable NSNumber *)days
                        completion:(IMPairCodeCompletion)completion;

/// 吊销未使用的配对码（传码字符串，连字符可有可无）。
+ (void)revokeCode:(NSString *)code forServer:(IMServer *)server completion:(IMSimpleCompletion)completion;

/// 吊销某台设备（传服务端返回的 id）。
+ (void)revokeDeviceWithIdentifier:(NSString *)deviceIdentifier
                        forServer:(IMServer *)server
                       completion:(IMSimpleCompletion)completion;

/// 规范化用户输入的地址：去空格、补 scheme、去尾部斜杠。
+ (nullable NSURL *)normalizeAddress:(NSString *)rawAddress;
/// 规范化配对码：去空格/连字符、转大写。
+ (NSString *)normalizeCode:(NSString *)rawCode;

@end

NS_ASSUME_NONNULL_END
