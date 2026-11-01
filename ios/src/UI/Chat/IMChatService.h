//
//  IMChatService.h
//  IMDSH — 聊天域协议封装（session/list、page、follow、prompt、cancel、control）
//
//  为什么单独一层：端点参数形状的坑太多（_request 必填、control 的 args 必须是空对象、
//  子会话要换 address 形状），集中在这里处理一次，控制器只关心"数据回来了"。
//

#import <Foundation/Foundation.h>
#import "IMChatModels.h"
#import "IMImageAttachment.h"
#import "IMServerStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMChatListCompletion)(NSArray<IMSessionRow *> * _Nullable rows,
                                     NSString * _Nullable nextCursor,
                                     NSError * _Nullable error);
typedef void (^IMChatPageCompletion)(NSArray * _Nullable records,
                                     BOOL hasMore,
                                     NSInteger throughSeq,
                                     NSError * _Nullable error);
typedef void (^IMChatActionCompletion)(NSError * _Nullable error);
/// 全局投影流：一条 (sessionId, key, value)。
typedef void (^IMChatProjectionHandler)(NSString *sessionId, NSString *key, id value);

@interface IMChatService : NSObject

/// 用 IMServerStore.shared.currentServer 建客户端；未配对时所有调用直接回错误。
- (instancetype)init;

@property (nonatomic, readonly) BOOL isPaired;
@property (nonatomic, readonly, nullable) IMServer *server;

/// 连接状态（WebSocket）：断线重连提示用。
- (void)setConnectionHandler:(nullable void (^)(BOOL connected))handler;

#pragma mark 会话列表

/// 一次 session/list；nextCursor 为空表示没有更多页。
- (void)loadSessionsWithCursor:(nullable NSString *)cursor completion:(IMChatListCompletion)completion;

/// 订阅全机投影增量（session/control，args 必须是空对象）。
- (void)startControlStreamWithHandler:(IMChatProjectionHandler)handler;
- (void)stopControlStream;

#pragma mark 单个会话

/// 打开会话：先 snapshot，再 event / assistant-stream 帧。
- (void)openSession:(IMSessionRow *)row
        maxMessages:(NSInteger)maxMessages
         onSnapshot:(void (^)(NSDictionary *snapshot))onSnapshot
          onRecord:(void (^)(NSDictionary *record))onRecord
      onStreamFrame:(void (^)(NSDictionary *frame))onStreamFrame
              onEnd:(nullable void (^)(void))onEnd
            onError:(void (^)(NSError *error))onError;

- (void)closeSessionStream;

/// 向上翻页：throughSeq = 已持有最老 seq - 1。
- (void)loadOlderPageThroughSeq:(NSInteger)throughSeq
                    maxMessages:(NSInteger)maxMessages
                     completion:(IMChatPageCompletion)completion;

/// 发消息（mode = queue）。content 顺序：文本块在前，图片块按顺序跟在后面。
/// 只有图片没有文字时不发空的 text 块（空字符串块会被网关判成非法参数）。
- (void)sendPromptWithText:(nullable NSString *)text
                    images:(nullable NSArray<IMImageAttachment *> *)images
                 requestId:(NSString *)requestId
                completion:(IMChatActionCompletion)completion;

/// 停止当前回合。
- (void)cancelRunningTurnWithCompletion:(IMChatActionCompletion)completion;

/// 取历史图片 / 文件字节（session/attachment）；base64 已解回 NSData。
- (void)loadAttachmentWithId:(nullable NSString *)attachmentId
                   sessionId:(nullable NSString *)sessionId
                  completion:(void (^)(NSData * _Nullable data, NSString * _Nullable mediaType, NSError * _Nullable error))completion;

#pragma mark 错误判定

/// 401 / unauthorized：需要引导用户回去重新配对。
+ (BOOL)isUnauthorizedError:(nullable NSError *)error;
/// 人话错误文案。
+ (NSString *)messageForError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
