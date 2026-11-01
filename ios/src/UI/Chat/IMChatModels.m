//
//  IMChatModels.m
//  IMDSH — 会话/消息数据模型 + 事件折叠
//

#import "IMChatModels.h"
#import "IMFormatting.h"

#pragma mark - 小工具

/// NSNotFound（NSIntegerMax）直接强转成 NSInteger 后不会变成 -1，会让调用方的 `index < 0` 判断失效。
static inline NSInteger IMIndexResult(NSUInteger index) {
    return index == NSNotFound ? -1 : (NSInteger)index;
}

#pragma mark - JSON 取值（NSNull / 类型漂移一律降级，绝不把消息发给 id）

/// 协议里的数字字段偶尔会是 null 或字符串，直接发 integerValue/doubleValue/boolValue
/// 会以 unrecognized selector 崩在折叠里（表现就是「点开任何会话必崩」，列表页因为走
/// IMSessionRow 的全量类型检查反而正常）。
static inline NSInteger IMIntegerValue(id value) {
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value integerValue];
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value integerValue];
    return 0;
}

static inline double IMDoubleValue(id value) {
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value doubleValue];
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value doubleValue];
    return 0;
}

static inline BOOL IMBoolValue(id value) {
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value boolValue];
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value boolValue];
    return NO;
}

/// 只接受真正的 NSString：callId / name / status / type 这些字段可能是 NSNull 或数字。
static inline NSString *IMStringValue(id value) {
    return [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
}

NSString *IMTokenCountString(NSInteger tokens) {
    if (tokens <= 0) return @"0";
    if (tokens < 1000) return [NSString stringWithFormat:@"%ld", (long)tokens];
    if (tokens < 1000000) {
        double k = tokens / 1000.0;
        return k < 10 ? [NSString stringWithFormat:@"%.1fk", k] : [NSString stringWithFormat:@"%.0fk", k];
    }
    return [NSString stringWithFormat:@"%.1fM", tokens / 1000000.0];
}

NSString *IMPrettyJSONString(NSString *raw) {
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return @"";
    // 只有看起来像 JSON 容器才解析，避免每次调用都白跑一次序列化。
    unichar first = [trimmed characterAtIndex:0];
    if (first != '{' && first != '[') return raw;

    NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) return raw;
    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (object == nil || error != nil) return raw;
    if (![NSJSONSerialization isValidJSONObject:object]) return raw;

    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted;
    if (@available(iOS 13.0, *)) options |= NSJSONWritingWithoutEscapingSlashes;
    NSData *pretty = [NSJSONSerialization dataWithJSONObject:object options:options error:&error];
    if (pretty == nil) return raw;
    NSString *text = [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding];
    return text.length > 0 ? text : raw;
}

/// 压成一行并截断（折叠态只需要一眼能看懂的摘要）。
static NSString *IMOneLineSummary(NSString *text, NSUInteger limit) {
    NSMutableString *line = [text mutableCopy];
    [line replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, line.length)];
    [line replaceOccurrencesOfString:@"\r" withString:@" " options:0 range:NSMakeRange(0, line.length)];
    while ([line containsString:@"  "]) {
        [line replaceOccurrencesOfString:@"  " withString:@" " options:0 range:NSMakeRange(0, line.length)];
    }
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length <= limit) return trimmed;
    return [[trimmed substringToIndex:limit] stringByAppendingString:@"…"];
}

#pragma mark - IMSessionRow

@implementation IMSessionRow

+ (instancetype)rowWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    id sessionId = dictionary[@"sessionId"];
    if (![sessionId isKindOfClass:NSString.class] || [(NSString *)sessionId length] == 0) return nil;

    IMSessionRow *row = [IMSessionRow new];
    row.sessionId = sessionId;

    id parent = dictionary[@"parentSessionId"];
    if ([parent isKindOfClass:NSString.class]) row.parentSessionId = parent;

    id cwd = dictionary[@"cwd"];
    if ([cwd isKindOfClass:NSString.class]) row.cwd = cwd;

    // updatedAt 是毫秒时间戳；IMDateFromFlexibleValue 会按量级自动区分秒/毫秒。
    row.updatedAt = [IMDateFromFlexibleValue(dictionary[@"updatedAt"]) timeIntervalSince1970];
    row.running = IMBoolValue(dictionary[@"running"]);
    row.blank = IMBoolValue(dictionary[@"blank"]);
    row.isSubagent = [dictionary[@"origin"] isEqual:@"subagent"];

    id projections = dictionary[@"projections"];
    id values = [projections isKindOfClass:NSDictionary.class] ? projections[@"values"] : nil;
    if ([values isKindOfClass:NSDictionary.class]) {
        id title = values[@"title"];
        if ([title isKindOfClass:NSString.class]) row.title = title;

        id usage = values[@"tokenUsage"];
        if ([usage isKindOfClass:NSDictionary.class]) {
            NSInteger input = IMIntegerValue(usage[@"uncachedInputTokens"]);
            NSInteger output = IMIntegerValue(usage[@"outputTokens"]);
            row.tokenCount = input + output;
        }
    }
    return row;
}

- (NSString *)displayTitle {
    NSString *title = [self.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (title.length > 0) return title;

    NSString *cwd = self.cwd;
    if (cwd.length > 0) {
        // Windows 主机给的是反斜杠路径，两种分隔符都要认。
        NSString *tail = [cwd stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"]];
        NSRange slash = [tail rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"] options:NSBackwardsSearch];
        if (slash.location != NSNotFound) tail = [tail substringFromIndex:NSMaxRange(slash)];
        if (tail.length > 0) return tail;
    }

    return self.sessionId.length > 8 ? [self.sessionId substringToIndex:8] : self.sessionId;
}

- (BOOL)isEmptySession {
    return self.blank && [self.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0;
}

@end

#pragma mark - IMToolCallEntry

@implementation IMToolCallEntry

- (instancetype)init {
    self = [super init];
    if (self) {
        _callId = @"";
        _name = @"tool";
        _argumentsText = [NSMutableString string];
        _resultText = [NSMutableString string];
        _state = IMToolCallStateRunning;
    }
    return self;
}

- (NSString *)argumentsSummary {
    NSString *raw = self.argumentsText;
    if (raw.length == 0) return @"";

    // 参数是流式拼出来的 JSON 字符串，中途可能不完整：能解析就取关键字段，解析不了压成一行。
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)object;
        for (NSString *key in @[@"command", @"path", @"file_path", @"pattern", @"query", @"url", @"description", @"prompt", @"name", @"content"]) {
            id value = dict[key];
            if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) {
                return IMOneLineSummary(value, 120);
            }
        }
        NSArray *keys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
        if (keys.count > 0) {
            NSString *firstKey = keys.firstObject;
            id value = dict[firstKey];
            if ([value isKindOfClass:NSString.class]) {
                return IMOneLineSummary([NSString stringWithFormat:@"%@: %@", firstKey, value], 120);
            }
            return firstKey;
        }
    }
    return IMOneLineSummary(raw, 120);
}

@end

#pragma mark - IMTodoEntry

@implementation IMAttachmentRef

+ (instancetype)refWithBlock:(NSDictionary *)block {
    if (![block isKindOfClass:NSDictionary.class]) return nil;
    id attachment = block[@"attachment"];
    if (![attachment isKindOfClass:NSDictionary.class]) return nil;

    NSString *attachmentId = ((NSDictionary *)attachment)[@"attachmentId"];
    if (![attachmentId isKindOfClass:NSString.class] || attachmentId.length == 0) return nil;

    IMAttachmentRef *ref = [[IMAttachmentRef alloc] init];
    ref.attachmentId = attachmentId;
    id name = ((NSDictionary *)attachment)[@"name"];
    if ([name isKindOfClass:NSString.class]) ref.name = name;
    id mediaType = ((NSDictionary *)attachment)[@"mediaType"];
    if ([mediaType isKindOfClass:NSString.class]) {
        ref.mediaType = mediaType;
        ref.isImage = [mediaType hasPrefix:@"image/"];
    }
    NSString *blockType = IMStringValue(block[@"type"]);
    if ([blockType isEqualToString:@"image"]) ref.isImage = YES;
    return ref;
}

- (NSString *)displayName {
    if (self.name.length > 0) return self.name;
    return self.isImage ? @"图片" : @"文件";
}

@end

@implementation IMTodoEntry

+ (instancetype)entryWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    id content = dictionary[@"content"];
    if (![content isKindOfClass:NSString.class]) return nil;
    IMTodoEntry *entry = [IMTodoEntry new];
    entry.content = content;
    NSString *status = IMStringValue(dictionary[@"status"]);
    if ([status isEqualToString:@"completed"]) entry.status = IMTodoStatusCompleted;
    else if ([status isEqualToString:@"in_progress"]) entry.status = IMTodoStatusInProgress;
    else entry.status = IMTodoStatusPending;
    return entry;
}

@end

#pragma mark - IMMessageItem

@implementation IMMessageItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _text = [NSMutableString string];
        _reasoning = [NSMutableString string];
        _toolCalls = [NSMutableArray array];
        _attachments = [NSMutableArray array];
    }
    return self;
}

- (BOOL)isEmptyContent {
    return self.text.length == 0
        && self.reasoning.length == 0
        && self.toolCalls.count == 0
        && self.todos.count == 0
        && self.attachments.count == 0
        && self.notice.length == 0;
}

@end

#pragma mark - IMChatTranscript

@interface IMChatTranscript ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *events;
@property (nonatomic, strong, readwrite, nullable) IMMessageItem *streamingItem;
/// 流式 end 帧表示"已落盘"，等下一个 assistant/message 事件到达时把占位气泡换掉。
@property (nonatomic, assign) BOOL awaitingCommit;
@property (nonatomic, assign) NSInteger commitTurn;
@property (nonatomic, assign) NSInteger commitStep;
@end

@implementation IMChatTranscript

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
        _events = [NSMutableArray array];
    }
    return self;
}

#pragma mark 记录摄入

/// record 与裸 event 两种形状都接受（session/page、session/follow 的 records 是前者）。
static NSDictionary *IMEventFromRecord(NSDictionary *record) {
    if (![record isKindOfClass:NSDictionary.class]) return nil;
    id type = record[@"type"];
    if ([type isKindOfClass:NSString.class] && [type isEqualToString:@"event"]) {
        id event = record[@"event"];
        return [event isKindOfClass:NSDictionary.class] ? event : nil;
    }
    if ([record[@"seq"] isKindOfClass:NSNumber.class] && [type isKindOfClass:NSString.class]) return record;
    return nil;
}

/// 按 seq 去重并保持升序；返回 YES 表示真的插入了新事件。
- (BOOL)insertEvent:(NSDictionary *)event {
    if (![event isKindOfClass:NSDictionary.class]) return NO;   // insertObject:nil 会直接抛异常
    NSInteger seq = IMIntegerValue(event[@"seq"]);
    NSUInteger insertAt = self.events.count;
    for (NSUInteger i = 0; i < self.events.count; i++) {
        NSInteger existing = IMIntegerValue(self.events[i][@"seq"]);
        if (existing == seq) return NO;
        if (existing > seq) { insertAt = i; break; }
    }
    [self.events insertObject:event atIndex:insertAt];
    return YES;
}

- (void)resetWithRecords:(NSArray *)records {
    [self.events removeAllObjects];
    [self.items removeAllObjects];
    self.streamingItem = nil;
    self.awaitingCommit = NO;
    for (id record in records) {
        NSDictionary *event = IMEventFromRecord(record);
        if (event) [self insertEvent:event];
    }
    [self fold];
}

- (void)prependRecords:(NSArray *)records {
    BOOL changed = NO;
    for (id record in records) {
        NSDictionary *event = IMEventFromRecord(record);
        if (event && [self insertEvent:event]) changed = YES;
    }
    if (changed) [self fold];
}

- (BOOL)appendRecord:(NSDictionary *)record {
    NSDictionary *event = IMEventFromRecord(record);
    if (event == nil) return NO;

    NSString *type = event[@"type"];
    if ([type isKindOfClass:NSString.class]) {
        if (self.awaitingCommit && [type isEqualToString:@"assistant/message"]) {
            // 落盘事件到了：占位气泡换成折叠出来的正式消息。
            id rawData = event[@"data"];
            NSDictionary *data = [rawData isKindOfClass:NSDictionary.class] ? rawData : @{};
            NSInteger turn = IMIntegerValue(data[@"turn"]);
            NSInteger step = IMIntegerValue(data[@"step"]);
            if (turn == self.commitTurn && step == self.commitStep) {
                self.streamingItem = nil;
                self.awaitingCommit = NO;
            }
        }
        if ([type isEqualToString:@"turn/end"]) self.running = NO;
        if ([type isEqualToString:@"turn/start"]) self.running = YES;
    }

    if (![self insertEvent:event]) return NO;
    [self fold];
    return YES;
}

- (BOOL)hasSeqGapAtEvent:(NSDictionary *)event {
    NSDictionary *raw = IMEventFromRecord(event);
    if (raw == nil) return NO;
    NSInteger seq = IMIntegerValue(raw[@"seq"]);
    NSInteger newest = self.newestSeq;
    return newest > 0 && seq > newest + 1;
}

- (NSInteger)oldestSeq {
    if (self.events.count == 0) return 0;
    return IMIntegerValue(self.events.firstObject[@"seq"]);
}

- (NSInteger)newestSeq {
    if (self.events.count == 0) return 0;
    return IMIntegerValue(self.events.lastObject[@"seq"]);
}

- (NSInteger)indexOfStreamingItem {
    if (self.streamingItem == nil) return -1;
    return IMIndexResult([self.items indexOfObjectIdenticalTo:self.streamingItem]);
}

- (NSInteger)indexOfItem:(IMMessageItem *)item {
    if (item == nil) return -1;
    return IMIndexResult([self.items indexOfObjectIdenticalTo:item]);
}

#pragma mark 折叠

/// 注意签名收的是 id：调用方直接把 JSON 里的 block[@"id"] / data[@"callId"] 递进来，
/// 声明成 NSString * 只是掩盖了问题——字段是 NSNull 时 `callId.length` 会当场崩。
static IMToolCallEntry *IMEnsureToolCall(IMMessageItem *item, NSMutableDictionary<NSString *, IMToolCallEntry *> *index, id callIdValue, id nameValue) {
    NSString *callId = IMStringValue(callIdValue);
    NSString *name = IMStringValue(nameValue);
    NSString *key = callId.length > 0 ? callId : [NSString stringWithFormat:@"anon-%lu", (unsigned long)item.toolCalls.count];
    IMToolCallEntry *entry = index[key];
    if (entry) {
        if (entry.name.length == 0 && name.length > 0) entry.name = name;
        return entry;
    }
    entry = [IMToolCallEntry new];
    entry.callId = key;
    entry.name = name.length > 0 ? name : @"tool";
    index[key] = entry;
    [item.toolCalls addObject:entry];
    return entry;
}

static void IMAppendText(NSMutableString *target, NSString *text, NSString *separator) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) return;
    if (target.length > 0 && separator.length > 0) [target appendString:separator];
    [target appendString:text];
}

static NSTimeInterval IMReasoningSecondsFromStream(id stream) {
    if (![stream isKindOfClass:NSArray.class]) return 0;
    for (NSDictionary *record in (NSArray *)stream) {
        if (![record isKindOfClass:NSDictionary.class]) continue;
        if (![record[@"type"] isEqual:@"reasoning-chunks"]) continue;
        id deltas = record[@"dt"];
        if (![deltas isKindOfClass:NSArray.class]) continue;
        double total = 0;
        for (id delta in (NSArray *)deltas) total += IMDoubleValue(delta);
        if (total > 0) return total / 1000.0;   // dt 单位是毫秒
    }
    return 0;
}

- (void)fold {
    NSMutableDictionary<NSNumber *, IMMessageItem *> *carry = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *expandedCarry = [NSMutableDictionary dictionary];
    for (IMMessageItem *old in self.items) {
        if (old.streaming) continue;
        if (old.seq > 0) carry[@(old.seq)] = old;
        for (IMToolCallEntry *entry in old.toolCalls) {
            if (entry.callId.length > 0) expandedCarry[entry.callId] = @(entry.expanded);
        }
    }

    NSMutableArray<IMMessageItem *> *out = [NSMutableArray array];
    NSMutableDictionary<NSString *, IMToolCallEntry *> *toolIndex = [NSMutableDictionary dictionary];
    IMMessageItem *lastAssistant = nil;

    for (NSDictionary *event in self.events) {
        NSString *type = event[@"type"];
        id rawData = event[@"data"];
        NSDictionary *data = [rawData isKindOfClass:NSDictionary.class] ? rawData : @{};
        NSInteger seq = IMIntegerValue(event[@"seq"]);
        NSTimeInterval time = IMDoubleValue(event[@"time"]) / 1000.0;

        if (![type isKindOfClass:NSString.class]) continue;

        if ([type isEqualToString:@"user/message"]) {
            IMMessageItem *item = [IMMessageItem new];
            item.kind = IMMessageItemKindUser;
            item.seq = seq;
            item.time = time;
            id content = data[@"content"];
            if ([content isKindOfClass:NSArray.class]) {
                for (NSDictionary *block in (NSArray *)content) {
                    if (![block isKindOfClass:NSDictionary.class]) continue;
                    NSString *blockType = IMStringValue(block[@"type"]);
                    if ([blockType isEqualToString:@"text"]) {
                        IMAppendText(item.text, block[@"text"], @"\n");
                    } else if ([blockType isEqualToString:@"image"]) {
                        IMAttachmentRef *ref = [IMAttachmentRef refWithBlock:block];
                        if (ref != nil) {
                            ref.isImage = YES;
                            [item.attachments addObject:ref];
                        }
                    } else if ([blockType isEqualToString:@"file"]) {
                        IMAttachmentRef *ref = [IMAttachmentRef refWithBlock:block];
                        if (ref != nil) [item.attachments addObject:ref];
                    }
                }
            }
            if (!item.isEmptyContent) [out addObject:item];
            lastAssistant = nil;
            continue;
        }

        if ([type isEqualToString:@"assistant/message"]) {
            IMMessageItem *item = [IMMessageItem new];
            item.kind = IMMessageItemKindAssistant;
            item.seq = seq;
            item.time = time;
            item.turn = IMIntegerValue(data[@"turn"]);
            item.step = IMIntegerValue(data[@"step"]);
            if (IMBoolValue(data[@"interrupted"])) {
                item.notice = @"这一轮被中断";
                item.noticeIsError = NO;
            }

            id message = data[@"message"];
            id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
            if ([content isKindOfClass:NSArray.class]) {
                for (NSDictionary *block in (NSArray *)content) {
                    if (![block isKindOfClass:NSDictionary.class]) continue;
                    NSString *blockType = IMStringValue(block[@"type"]);
                    if ([blockType isEqualToString:@"text"]) {
                        IMAppendText(item.text, block[@"text"], @"\n\n");
                    } else if ([blockType isEqualToString:@"reasoning"]) {
                        IMAppendText(item.reasoning, block[@"text"], @"\n\n");
                    } else if ([blockType isEqualToString:@"tool-call"]) {
                        IMToolCallEntry *entry = IMEnsureToolCall(item, toolIndex, block[@"id"], block[@"name"]);
                        NSString *arguments = block[@"arguments"];
                        if ([arguments isKindOfClass:NSString.class] && arguments.length > 0) {
                            [entry.argumentsText setString:arguments];   // 落盘参数是完整的，直接覆盖流式碎片
                        }
                    }
                }
            }

            item.reasoningSeconds = IMReasoningSecondsFromStream(data[@"stream"]);
            id usage = data[@"usage"];
            if ([usage isKindOfClass:NSDictionary.class]) self.tokenUsage = usage;

            if (!item.isEmptyContent) {
                [out addObject:item];
                lastAssistant = item;
            }
            continue;
        }

        if ([type isEqualToString:@"tool/call"]) {
            if (lastAssistant == nil) {
                lastAssistant = [IMMessageItem new];
                lastAssistant.kind = IMMessageItemKindAssistant;
                lastAssistant.seq = seq;
                lastAssistant.time = time;
                [out addObject:lastAssistant];
            }
            IMToolCallEntry *entry = IMEnsureToolCall(lastAssistant, toolIndex, data[@"callId"], data[@"name"]);
            NSString *arguments = data[@"arguments"];
            if ([arguments isKindOfClass:NSString.class] && arguments.length > 0 && entry.argumentsText.length == 0) {
                [entry.argumentsText setString:arguments];
            }
            continue;
        }

        if ([type isEqualToString:@"tool/result"]) {
            id message = data[@"message"];
            NSString *callId = [message isKindOfClass:NSDictionary.class] ? IMStringValue(((NSDictionary *)message)[@"toolCallId"]) : nil;
            IMToolCallEntry *entry = callId.length > 0 ? toolIndex[callId] : nil;
            if (entry == nil) {
                if (lastAssistant == nil) {
                    lastAssistant = [IMMessageItem new];
                    lastAssistant.kind = IMMessageItemKindAssistant;
                    lastAssistant.seq = seq;
                    lastAssistant.time = time;
                    [out addObject:lastAssistant];
                }
                entry = IMEnsureToolCall(lastAssistant, toolIndex, callId, @"tool");
            }

            NSMutableString *result = [NSMutableString string];
            id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
            if ([content isKindOfClass:NSArray.class]) {
                for (NSDictionary *block in (NSArray *)content) {
                    if (![block isKindOfClass:NSDictionary.class]) continue;
                    if ([block[@"type"] isEqual:@"text"]) IMAppendText(result, block[@"text"], @"\n");
                }
            }
            if (result.length > 0) [entry.resultText setString:result];

            BOOL failed = ([message isKindOfClass:NSDictionary.class] && IMBoolValue(((NSDictionary *)message)[@"isError"]))
                || [data[@"error"] isKindOfClass:NSDictionary.class];
            entry.state = failed ? IMToolCallStateFailed : IMToolCallStateSucceeded;
            continue;
        }

        if ([type isEqualToString:@"todo/write"]) {
            id rawTodos = data[@"todos"];
            NSMutableArray<IMTodoEntry *> *todos = [NSMutableArray array];
            if ([rawTodos isKindOfClass:NSArray.class]) {
                for (id raw in (NSArray *)rawTodos) {
                    IMTodoEntry *entry = [IMTodoEntry entryWithDictionary:raw];
                    if (entry) [todos addObject:entry];
                }
            }
            if (todos.count == 0) continue;

            // todo/write 是整值替换：紧邻的上一条待办卡片就地更新，避免刷出一堆历史清单。
            IMMessageItem *last = out.lastObject;
            if (last.kind == IMMessageItemKindTodo) {
                last.todos = todos;
            } else {
                IMMessageItem *item = [IMMessageItem new];
                item.kind = IMMessageItemKindTodo;
                item.seq = seq;
                item.time = time;
                item.todos = todos;
                [out addObject:item];
            }
            continue;
        }

        // 其余事件（step/*、team/*、job/*、session/title…）都是旁路事件，不进对话流。
    }

    // 带上一次折叠的展开态：重折不该让用户刚展开的卡片自己收回去。
    for (IMMessageItem *item in out) {
        IMMessageItem *previous = carry[@(item.seq)];
        if (previous) {
            item.reasoningExpanded = previous.reasoningExpanded;
            item.todosExpanded = previous.todosExpanded;
        }
        for (IMToolCallEntry *entry in item.toolCalls) {
            NSNumber *expanded = expandedCarry[entry.callId];
            if (expanded != nil) entry.expanded = expanded.boolValue;
        }
    }

    [self.items setArray:out];
    if (self.streamingItem != nil) [self.items addObject:self.streamingItem];
}

#pragma mark 流式增量

- (BOOL)applyAssistantStreamFrame:(NSDictionary *)frame {
    if (![frame isKindOfClass:NSDictionary.class]) return NO;
    NSString *frameType = frame[@"type"];
    if (![frameType isKindOfClass:NSString.class]) return NO;

    if ([frameType isEqualToString:@"start"]) {
        IMMessageItem *item = [IMMessageItem new];
        item.kind = IMMessageItemKindAssistant;
        item.streaming = YES;
        item.attemptId = IMStringValue(frame[@"attemptId"]);
        item.turn = IMIntegerValue(frame[@"turn"]);
        item.step = IMIntegerValue(frame[@"step"]);
        item.time = NSDate.date.timeIntervalSince1970;
        self.streamingItem = item;
        self.awaitingCommit = NO;
        self.running = YES;
        [self.items addObject:item];
        return YES;
    }

    if ([frameType isEqualToString:@"chunk"]) {
        id rawChunk = frame[@"chunk"];
        if (![rawChunk isKindOfClass:NSDictionary.class]) return NO;
        NSDictionary *chunk = rawChunk;
        NSString *chunkType = chunk[@"type"];
        if (![chunkType isKindOfClass:NSString.class]) return NO;

        IMMessageItem *item = self.streamingItem;
        if (item == nil) {
            // 漏了 start 帧（例如中途订阅）：补一个占位，保证增量不丢。
            item = [IMMessageItem new];
            item.kind = IMMessageItemKindAssistant;
            item.streaming = YES;
            item.attemptId = IMStringValue(frame[@"attemptId"]);
            item.time = NSDate.date.timeIntervalSince1970;
            self.streamingItem = item;
            [self.items addObject:item];
        }

        double chunkTime = IMDoubleValue(frame[@"time"]) / 1000.0;

        if ([chunkType isEqualToString:@"text-delta"]) {
            NSString *text = chunk[@"text"];
            if (![text isKindOfClass:NSString.class]) return NO;
            if (item.reasoningInProgress) {
                item.reasoningInProgress = NO;
                if (item.reasoningSeconds <= 0 && chunkTime > item.time) item.reasoningSeconds = MAX(1.0, chunkTime - item.time);
            }
            [item.text appendString:text];
            return YES;
        }

        if ([chunkType isEqualToString:@"reasoning-delta"]) {
            NSString *text = chunk[@"text"];
            if (![text isKindOfClass:NSString.class]) return NO;
            if (item.reasoning.length == 0 && chunkTime > 0) item.time = chunkTime;   // 以思考起点为计时起点
            item.reasoningInProgress = YES;
            [item.reasoning appendString:text];
            return YES;
        }

        if ([chunkType isEqualToString:@"tool-call-delta"]) {
            NSString *callId = chunk[@"id"];
            if (![callId isKindOfClass:NSString.class]) callId = @"";
            IMToolCallEntry *entry = nil;
            for (IMToolCallEntry *candidate in item.toolCalls) {
                if ([candidate.callId isEqualToString:callId]) { entry = candidate; break; }
            }
            if (entry == nil) {
                entry = [IMToolCallEntry new];
                entry.callId = callId.length > 0 ? callId : [NSString stringWithFormat:@"stream-%lu", (unsigned long)item.toolCalls.count];
                [item.toolCalls addObject:entry];
            }
            NSString *name = chunk[@"name"];
            if ([name isKindOfClass:NSString.class] && name.length > 0) entry.name = name;
            NSString *delta = chunk[@"argumentsDelta"];
            if ([delta isKindOfClass:NSString.class]) [entry.argumentsText appendString:delta];
            if (item.reasoningInProgress) {
                item.reasoningInProgress = NO;
                if (item.reasoningSeconds <= 0 && chunkTime > item.time) item.reasoningSeconds = MAX(1.0, chunkTime - item.time);
            }
            return YES;
        }

        if ([chunkType isEqualToString:@"usage"]) {
            id usage = chunk[@"usage"];
            if ([usage isKindOfClass:NSDictionary.class]) self.tokenUsage = usage;
            return NO;
        }

        // block-start / block-end / finish 交给落盘事件处理。
        return NO;
    }

    if ([frameType isEqualToString:@"end"]) {
        IMMessageItem *item = self.streamingItem;
        id rawOutcome = frame[@"outcome"];
        NSString *kind = [rawOutcome isKindOfClass:NSDictionary.class] ? ((NSDictionary *)rawOutcome)[@"kind"] : nil;
        item.streaming = NO;
        item.reasoningInProgress = NO;
        if ([kind isEqualToString:@"committed"]) {
            self.awaitingCommit = YES;
            self.commitTurn = item.turn;
            self.commitStep = item.step;
        } else if ([kind isEqualToString:@"abandoned"]) {
            item.notice = @"生成已中断";
            item.noticeIsError = NO;
        }
        return YES;
    }

    return NO;
}

@end
