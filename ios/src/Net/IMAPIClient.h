//
//  IMAPIClient.h
//  IMDSH — 面向 dsh-webim 网关的 HTTP 客户端
//
//  所有请求都带 device token（Cookie `webim_device` + 头 `X-IMDSH-Device`），
//  网关校验通过后自行铸造 DSH 的 dsh-auth-* Cookie，App 侧不保存任何 DSH 凭据。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const IMAPIErrorDomain;

typedef NS_ENUM(NSInteger, IMAPIErrorCode) {
    IMAPIErrorCodeTransport = -1,
    IMAPIErrorCodeUnauthorized = 401,
    IMAPIErrorCodeForbidden = 403,
    IMAPIErrorCodeNotFound = 404,
    IMAPIErrorCodeConflict = 409,
    IMAPIErrorCodeRateLimited = 429,
    IMAPIErrorCodeServer = 500,
    /// 网关返回了 ok:false，附带 code/message。
    IMAPIErrorCodeRemote = -100,
    /// 响应不是预期的 JSON 形状。
    IMAPIErrorCodeBadResponse = -101,
};

/// 服务器返回的结构化错误。
FOUNDATION_EXPORT NSString *const IMAPIErrorRemoteCodeKey;
FOUNDATION_EXPORT NSString *const IMAPIErrorHTTPStatusKey;

@interface IMAPIClient : NSObject

- (instancetype)initWithBaseURL:(NSURL *)baseURL deviceToken:(nullable NSString *)deviceToken NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) NSURL *baseURL;
@property (nonatomic, copy, nullable) NSString *deviceToken;
/// 默认 20 秒。
@property (nonatomic, assign) NSTimeInterval timeout;

typedef void (^IMAPICompletion)(id _Nullable json, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error);

- (void)GET:(NSString *)path query:(nullable NSDictionary<NSString *, NSString *> *)query completion:(IMAPICompletion)completion;
- (void)POST:(NSString *)path json:(nullable id)json completion:(IMAPICompletion)completion;

/// 便捷：把 NSError 转成人话（面板上直接用）。
+ (NSString *)localizedMessageForError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
