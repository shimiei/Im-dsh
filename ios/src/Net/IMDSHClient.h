//
//  IMDSHClient.h
//  IMDSH — DSH Harness 客户端（unary RPC + WebSocket 流）
//
//  协议事实（已对真实网关实测，见 imdsh/docs/protocol-notes/probe-rpc.mjs）：
//   · unary:  POST {base}/api/{endpoint}
//             body  {"type":"client-request","rpcId":"<uuid>","method":"<endpoint>","payload":{"args":{...}}}
//             回复  {"type":"server-response","rpcId":"<uuid>","result":{"ok":true,"value":...}}
//                   或 {"type":"server-response","rpcId":"<uuid>","result":{"ok":false,"error":{...}}}
//   · stream: WS {ws(s)base}/api/remote.mux（Cookie 鉴权）
//             发送 {"type":"open","streamId":"<id>","endpoint":"<endpoint>","payload":{"args":{...}}}
//             接收 {"type":"item","streamId":"<id>","value":{...}}
//                  {"type":"error","streamId":"<id>","error":{...}}
//             关闭 {"type":"close","streamId":"<id>"}
//   · 鉴权：请求带 webim 网关的 device Cookie（`webim_device`），网关自行铸造 dsh-auth-* 并转发。
//

#import <Foundation/Foundation.h>
#import "IMServerStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMRPCCompletion)(id _Nullable value, NSError * _Nullable error);
typedef void (^IMStreamFrameHandler)(NSString *streamId, NSDictionary *value);
typedef void (^IMStreamErrorHandler)(NSString *streamId, NSError *error);
typedef void (^IMStreamEndHandler)(NSString *streamId);
typedef void (^IMConnectionStateHandler)(BOOL connected);

FOUNDATION_EXPORT NSString *const IMDSHClientErrorDomain;

@interface IMDSHClient : NSObject

- (instancetype)initWithServer:(IMServer *)server;

@property (nonatomic, strong, readonly) IMServer *server;
/// WebSocket 是否已就绪。流会在就绪后自动补发订阅。
@property (nonatomic, readonly) BOOL streamConnected;

/// unary 调用。args 直接给协议里的 args 对象（例如 session/list 传 @{@"_request": @{}}）。
- (void)call:(NSString *)endpoint args:(nullable NSDictionary *)args completion:(IMRPCCompletion)completion;

/// 订阅一个流式端点（session/follow、session/control、workspaceFiles/changes…）。
/// 同一个 streamId 重复订阅时，内部会先发 `cancel` 再 `open`（同一 socket 上重复 open 会
/// 被服务端以 1008 关闭整条连接，见 docs/protocol.md §5）。
- (void)openStream:(NSString *)endpoint
               args:(NSDictionary *)args
           streamId:(NSString *)streamId
            onFrame:(IMStreamFrameHandler)onFrame
            onError:(IMStreamErrorHandler)onError;

/// 带「流结束」回调的版本：服务端下发 `end` 帧时触发（会话结束、监听被撤销等）。
- (void)openStream:(NSString *)endpoint
               args:(NSDictionary *)args
           streamId:(NSString *)streamId
            onFrame:(IMStreamFrameHandler)onFrame
              onEnd:(nullable IMStreamEndHandler)onEnd
            onError:(IMStreamErrorHandler)onError;

- (void)closeStream:(NSString *)streamId;
- (void)closeAllStreams;

/// 建立 / 断开 mux 连接（openStream 首次调用会自动连接）。
- (void)connect;
- (void)disconnect;

/// 连接状态变化（仅 UI 用，回调在主线程）。
- (void)setStateHandler:(nullable IMConnectionStateHandler)handler;

@end

NS_ASSUME_NONNULL_END
