//
//  files-IMFileKind.h
//  IMDSH — 文件域共用：按扩展名判类别、给出图标/配色/中文类别名与字节大小文案
//
//  为什么单独抽一层：文件列表、预览页、分享面板都要回答同一组问题
//  「这是什么文件、画哪个图标、用哪个颜色、有多大」。三处各写一份必然漂移，
//  所以统一放这里；颜色一律取 IMTheme 语义色，深浅色自动正确。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 文件类别。只区分「预览方式」需要的粒度，不做 MIME 大全。
typedef NS_ENUM(NSInteger, IMFileKind) {
    IMFileKindDirectory = 0,
    /// 纯文本 / 配置 / 数据（txt、json、yaml、csv…）
    IMFileKindText,
    /// 代码（可做着色）
    IMFileKindCode,
    /// Markdown
    IMFileKindMarkdown,
    /// 位图 / 矢量图（svg 走文本预览，见 IMFileKindLooksTextual 说明）
    IMFileKindImage,
    IMFileKindPDF,
    IMFileKindOffice,
    IMFileKindArchive,
    IMFileKindMedia,
    IMFileKindBinary,
    IMFileKindOther,
};

/// 由文件名（或路径）推类别；无扩展名时按常见文件名（Makefile/README…）判断。
FOUNDATION_EXPORT IMFileKind IMFileKindForName(NSString * _Nullable name);

/// SF Symbol 名（统一由 IMSymbol 上色）。
FOUNDATION_EXPORT NSString *IMFileKindSymbol(IMFileKind kind);

/// 图标主色（全部来自 IMTheme，深浅色都正确）。
FOUNDATION_EXPORT UIColor *IMFileKindColor(IMFileKind kind);

/// 中文类别名："文件夹" / "文本" / "PDF" / "Word 文档"…
FOUNDATION_EXPORT NSString *IMFileKindDisplayName(IMFileKind kind);

/// 是否走文本预览（svg 不算：UIImage 不支持 svg，退化成文本看源码更诚实）。
FOUNDATION_EXPORT BOOL IMFileKindLooksTextual(IMFileKind kind);

/// 字节数友好文案："—"（未知）/ "512 B" / "3.4 KB" / "12 MB"。
FOUNDATION_EXPORT NSString *IMFileSizeString(unsigned long long bytes, BOOL hasSize);

/// 扩展名（小写，不含点）；没有时返回空串。
FOUNDATION_EXPORT NSString *IMFileExtension(NSString * _Nullable name);

NS_ASSUME_NONNULL_END
