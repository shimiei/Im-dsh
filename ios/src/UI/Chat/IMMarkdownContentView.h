//
//  IMMarkdownContentView.h
//  IMDSH — Markdown 渲染视图（文本 / 代码块 / 分割线）
//
//  为什么自己拼视图而不是一个 UITextView 画到底：代码块要横向滚动 + 复制按钮 +
//  长块折叠，这些用纯富文本做不到；文本段落仍然走单个 UITextView，保证链接可点、可选中。
//

#import <UIKit/UIKit.h>
#import "IMMarkdownRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@class IMMarkdownContentView;

@protocol IMMarkdownContentViewDelegate <NSObject>
@optional
/// 点了 Markdown 里的链接。
- (void)markdownContentView:(IMMarkdownContentView *)view didTapLink:(NSURL *)url;
/// 代码块展开/收起导致自身高度变化（外层需要重算行高）。
- (void)markdownContentViewDidChangeHeight:(IMMarkdownContentView *)view;
@end

@interface IMMarkdownContentView : UIView

@property (nonatomic, weak, nullable) id<IMMarkdownContentViewDelegate> delegate;

/// 直接给节点（调用方已经解析好的情况）。
- (void)renderNodes:(NSArray<IMMarkdownNode *> *)nodes;
/// 给 Markdown 文本：内部后台解析、主线程渲染，同一文本命中缓存不重复解析。
- (void)renderMarkdownText:(nullable NSString *)markdown;
/// 流式输出专用：已完成的段落走 Markdown 解析（按段落缓存），未完成的尾行按纯文本渲染，
/// 避免每个 delta 都拿全文当 key 整篇重解析。
- (void)renderStreamingMarkdown:(nullable NSString *)markdown;
/// 给纯文本（用户消息）：保留换行，按正文样式渲染。
- (void)renderPlainText:(nullable NSString *)text;
/// 收起所有代码块的展开态（cell 复用时调用）。
- (void)resetExpansion;

@end

NS_ASSUME_NONNULL_END
