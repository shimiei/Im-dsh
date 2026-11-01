//
//  IMChatModels.h
//  IMDSH — 会话/消息数据模型 + 事件折叠（把 follow、page 的 record 折成可渲染列表）
//
//  为什么单独一层：协议里一个「回合」是 assistant/message + tool/call + tool/result
//  等多条事件拼出来的，UI 不该自己啃事件流；折叠规则（按 callId 去重、todo 整值替换、
//  流式增量合并）集中在这里，聊天页只负责画。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 会话列表行

/// 会话列表的一行（session/list 的 item 落地形态）。
@interface IMSessionRow : NSObject

@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy, nullable) NSString *parentSessionId;
@property (nonatomic, copy, nullable) NSString *cwd;
/// 取自 projections.values.title，可能为 nil。
@property (nonatomic, copy, nullable) NSString *title;
/// 毫秒时间戳的秒值（0 = 未知）。
@property (nonatomic, assign) NSTimeInterval updatedAt;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL blank;
/// origin == "subagent"
@property (nonatomic, assign) BOOL isSubagent;
/// projections.values.tokenUsage 的总量，0 = 未知。
@property (nonatomic, assign) NSInteger tokenCount;

+ (nullable instancetype)rowWithDictionary:(NSDictionary *)dictionary;
/// 标题回退链：projections.title → cwd 尾段 → sessionId 前 8 位。
- (NSString *)displayTitle;
/// 标题为空、且没跑过任何内容（空白会话）。
- (BOOL)isEmptySession;
/// 项目维度：主机给的 cwd 原值（空串表示未知项目）。
@property (nonatomic, copy, readonly) NSString *projectKey;
/// 项目显示名：cwd 尾段（如 dsh-webim）；未知时为「未指定项目」。
@property (nonatomic, copy, readonly) NSString *projectName;

@end

#pragma mark - 会话分组

/// 按项目（cwd）聚合出来的一组会话。列表页用它做「可折叠的项目分组」。
@interface IMSessionGroup : NSObject

@property (nonatomic, copy, readonly) NSString *projectKey;
@property (nonatomic, copy, readonly) NSString *projectName;
@property (nonatomic, strong, readonly) NSMutableArray<IMSessionRow *> *rows;
/// 分组是否收起。
@property (nonatomic, assign) BOOL collapsed;
/// 组内最新一条的更新时间，用于组间排序。
@property (nonatomic, assign, readonly) NSTimeInterval latestUpdate;

/// 按项目分组：组内 updatedAt 倒序，组间按最新时间倒序。
+ (NSArray<IMSessionGroup *> *)groupsFromRows:(NSArray<IMSessionRow *> *)rows;

@end

#pragma mark - 工具调用

typedef NS_ENUM(NSInteger, IMToolCallState) {
    IMToolCallStateRunning = 0,
    IMToolCallStateSucceeded,
    IMToolCallStateFailed,
};

/// 一次工具调用（合并 assistant/message 的 tool-call 块、tool/call 事件、tool/result 事件）。
@interface IMToolCallEntry : NSObject

@property (nonatomic, copy) NSString *callId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableString *argumentsText;
@property (nonatomic, strong) NSMutableString *resultText;
@property (nonatomic, assign) IMToolCallState state;
@property (nonatomic, assign) BOOL expanded;

/// 折叠态用的一行摘要（取参数里最有信息量的字段）。
- (NSString *)argumentsSummary;
/// 展开态用的美化 JSON（由工具卡后台算好写回，避免主线程解析）。
@property (nonatomic, copy, nullable) NSString *prettyArguments;
@property (nonatomic, copy, nullable) NSString *prettyResult;

@end

#pragma mark - 待办

typedef NS_ENUM(NSInteger, IMTodoStatus) {
    IMTodoStatusPending = 0,
    IMTodoStatusInProgress,
    IMTodoStatusCompleted,
};

@interface IMTodoEntry : NSObject
@property (nonatomic, copy) NSString *content;
@property (nonatomic, assign) IMTodoStatus status;
+ (nullable instancetype)entryWithDictionary:(NSDictionary *)dictionary;
@end

#pragma mark - 附件引用

/// 历史消息里的图片 / 文件引用（不含字节；要缩略图得用 session/attachment 去取）。
@interface IMAttachmentRef : NSObject

@property (nonatomic, copy) NSString *attachmentId;
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic, assign) BOOL isImage;
/// 可读名字：name → 按类型兜底。
@property (nonatomic, readonly) NSString *displayName;

/// 从 content block（{type:'image'|'file', attachment:{...}}）解析；没有 attachmentId 返回 nil。
+ (nullable instancetype)refWithBlock:(NSDictionary *)block;

@end

#pragma mark - 消息

typedef NS_ENUM(NSInteger, IMMessageItemKind) {
    IMMessageItemKindUser = 0,
    IMMessageItemKindAssistant,
    IMMessageItemKindTodo,
    /// 灰底提示条（错误 / 中断 / 状态）。
    IMMessageItemKindNotice,
};

/// 聊天流里的一条可渲染项。
@interface IMMessageItem : NSObject

@property (nonatomic, assign) IMMessageItemKind kind;
/// 该项首事件的 seq（折叠时用于保留展开态）。
@property (nonatomic, assign) NSInteger seq;
/// 秒级时间戳。
@property (nonatomic, assign) NSTimeInterval time;

@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, strong) NSMutableString *reasoning;
/// 思考耗时（秒），0 = 未知。
@property (nonatomic, assign) NSTimeInterval reasoningSeconds;
@property (nonatomic, assign) BOOL reasoningExpanded;
@property (nonatomic, assign) BOOL reasoningInProgress;

@property (nonatomic, strong) NSMutableArray<IMToolCallEntry *> *toolCalls;

@property (nonatomic, strong, nullable) NSArray<IMTodoEntry *> *todos;
@property (nonatomic, assign) BOOL todosExpanded;

@property (nonatomic, copy, nullable) NSString *notice;
@property (nonatomic, assign) BOOL noticeIsError;

/// 是否仍在流式输出（决定是否显示光标 / 打字机）。
@property (nonatomic, assign) BOOL streaming;
@property (nonatomic, copy, nullable) NSString *attemptId;
@property (nonatomic, assign) NSInteger turn;
@property (nonatomic, assign) NSInteger step;

/// 用户消息里的附件（图片 / 文件引用）。
@property (nonatomic, strong) NSMutableArray<IMAttachmentRef *> *attachments;

- (BOOL)isEmptyContent;

@end

#pragma mark - 折叠器

/// 把 session/page、session/follow 的 record 与 assistant-stream 增量折成 items。
@interface IMChatTranscript : NSObject

@property (nonatomic, strong, readonly) NSMutableArray<IMMessageItem *> *items;
/// 正在流式输出、尚未落盘的那一条（独立于 items，折叠时自动接在末尾）。
@property (nonatomic, strong, nullable, readonly) IMMessageItem *streamingItem;
/// 最近一次 assistant/message 的 token 用量。
@property (nonatomic, strong, nullable) NSDictionary *tokenUsage;
/// 服务端报的 running 状态（prompt 接受 / turn 结束后本地推算）。
@property (nonatomic, assign) BOOL running;

/// 打开会话（或重新对齐）时整体替换。
- (void)resetWithRecords:(nullable NSArray *)records;
/// 向上翻页：插入更老的历史（内部按 seq 去重后重折）。
- (void)prependRecords:(nullable NSArray *)records;
/// 实时事件；返回 YES 表示界面需要刷新。
- (BOOL)appendRecord:(nullable NSDictionary *)record;
/// assistant-stream 帧；返回 YES 表示有可见变化（需要重绘流式气泡）。
- (BOOL)applyAssistantStreamFrame:(nullable NSDictionary *)frame;

/// 已持有最老的 seq（0 = 空）。
@property (nonatomic, readonly) NSInteger oldestSeq;
@property (nonatomic, readonly) NSInteger newestSeq;
/// 收到的最后一个 seq 与期望值之间是否跳号（跳号要重开流修 gap）。
- (BOOL)hasSeqGapAtEvent:(nullable NSDictionary *)event;

/// 流式气泡在 items 里的下标（-1 = 没有）。
- (NSInteger)indexOfStreamingItem;
/// 该 item 在 items 里的下标（-1 = 不存在）。
- (NSInteger)indexOfItem:(IMMessageItem *)item;

@end

/// 把可能是 JSON 的字符串美化成缩进文本；解析失败原样返回。
FOUNDATION_EXPORT NSString *IMPrettyJSONString(NSString *raw);
/// token 数字的人话版本：1234 → "1.2k"。
FOUNDATION_EXPORT NSString *IMTokenCountString(NSInteger tokens);

NS_ASSUME_NONNULL_END
