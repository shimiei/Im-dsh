//
//  IMMarkdownRenderer.h
//  IMDSH — 手写 Markdown 解析：把 Markdown 文本折成可直接渲染的节点
//
//  不能引库（任务约束），所以只实现 DSH 输出里真实出现的子集：
//  标题、粗体/斜体/删除线、行内代码、围栏代码块、有序/无序列表（一层嵌套）、
//  引用、链接、分割线、表格（等宽对齐后当代码块画）。
//
//  产出两类节点：
//   · Text  —— 一个 NSAttributedString，内部按段落各自带 paragraphStyle（标题/列表/引用都靠它区分，
//              这样一条消息只需要一个 UITextView，省掉几十个 subview）；
//   · Code  —— 原始文本 + 语言标签，交给代码块视图做横向滚动与复制；
//   · Rule  —— 分割线。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMMarkdownNodeType) {
    IMMarkdownNodeTypeText = 0,
    IMMarkdownNodeTypeCode,
    IMMarkdownNodeTypeRule,
};

@interface IMMarkdownNode : NSObject

@property (nonatomic, assign) IMMarkdownNodeType type;
/// Text 节点的富文本（多段落）。
@property (nonatomic, strong, nullable) NSAttributedString *attributedText;
/// Code 节点的原始文本（不做任何转义处理）。
@property (nonatomic, copy, nullable) NSString *rawText;
/// Code 节点的语言标签；表格会写 "表格"。
@property (nonatomic, copy, nullable) NSString *language;

@end

@interface IMMarkdownRenderer : NSObject

/// 解析 Markdown。纯计算、不碰 UI 状态，可以放心丢到后台队列。
+ (NSArray<IMMarkdownNode *> *)parseMarkdown:(nullable NSString *)markdown;

/// 纯文本（用户消息这类）：保留换行，不解释任何 Markdown 语法。
+ (NSAttributedString *)attributedPlainText:(nullable NSString *)text;

/// 代码块里渲染用的等宽富文本（语法高亮不做，只保证颜色与行高正确）。
+ (NSAttributedString *)attributedCode:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
