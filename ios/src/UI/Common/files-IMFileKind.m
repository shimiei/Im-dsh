//
//  files-IMFileKind.m
//  IMDSH — 文件域共用：类型识别 / 图标 / 配色 / 大小文案
//

#import "files-IMFileKind.h"
#import "IMTheme.h"

#pragma mark - 扩展名表

/// 命中即用；表里没有的再走文件名/无扩展名规则。
static NSDictionary<NSString *, NSNumber *> *IMFileKindExtensionTable(void) {
    static NSDictionary<NSString *, NSNumber *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, NSNumber *> *map = [NSMutableDictionary dictionary];
        void (^put)(NSArray<NSString *> *, IMFileKind) = ^(NSArray<NSString *> *exts, IMFileKind kind) {
            for (NSString *ext in exts) map[ext] = @(kind);
        };

        put(@[@"md", @"markdown", @"mdx", @"mdc"], IMFileKindMarkdown);

        put(@[@"txt", @"text", @"log", @"csv", @"tsv", @"env", @"gitignore",
              @"editorconfig", @"npmrc", @"babelrc"], IMFileKindText);
        put(@[@"json", @"jsonc", @"json5", @"yaml", @"yml", @"toml", @"ini", @"conf",
              @"cfg", @"xml", @"plist", @"properties", @"lock", @"csv"], IMFileKindText);

        put(@[@"js", @"mjs", @"cjs", @"ts", @"tsx", @"jsx", @"py", @"rb", @"go", @"rs",
              @"java", @"kt", @"kts", @"swift", @"c", @"h", @"m", @"mm", @"cc", @"cpp",
              @"cxx", @"hpp", @"cs", @"php", @"sh", @"bash", @"zsh", @"fish", @"ps1",
              @"sql", @"css", @"scss", @"sass", @"less", @"html", @"htm", @"vue",
              @"svelte", @"gradle", @"lua", @"dart", @"ex", @"exs", @"pl", @"r",
              @"scala", @"clj", @"vim", @"proto", @"graphql", @"gql", @"patch", @"diff"],
          IMFileKindCode);

        // svg 也列在这里，但 IMFileKindLooksTextual 会把它排除：本机没有 svg 渲染器，
        // 与其显示一个空图，不如当源码给用户看。
        put(@[@"png", @"jpg", @"jpeg", @"gif", @"webp", @"heic", @"heif", @"bmp",
              @"tiff", @"tif", @"ico", @"svg"], IMFileKindImage);

        put(@[@"pdf"], IMFileKindPDF);
        put(@[@"doc", @"docx", @"xls", @"xlsx", @"ppt", @"pptx", @"rtf", @"pages",
              @"numbers", @"key", @"odt", @"ods", @"odp"], IMFileKindOffice);
        put(@[@"zip", @"tar", @"gz", @"tgz", @"bz2", @"xz", @"7z", @"rar", @"jar",
              @"whl", @"war"], IMFileKindArchive);
        put(@[@"mp3", @"wav", @"m4a", @"flac", @"ogg", @"aac", @"mp4", @"mov", @"m4v",
              @"avi", @"mkv", @"webm", @"flv", @"wmv"], IMFileKindMedia);

        table = map;
    });
    return table;
}

/// 常见无扩展名文件：都当代码/文本看，比显示「未知」有用。
static BOOL IMFileNameIsPlainText(NSString *lowerName) {
    static NSSet<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[@"makefile", @"dockerfile", @"rakefile", @"gemfile",
                                      @"procfile", @"license", @"licence", @"readme",
                                      @"changelog", @"authors", @"notice", @"todo"]];
    });
    if ([names containsObject:lowerName]) return YES;
    // "readme.md" 走扩展名；"README" 这种裸文件名走上面；".gitignore" 走下面。
    return NO;
}

NSString *IMFileExtension(NSString *name) {
    if (name.length == 0) return @"";
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *last = trimmed.lastPathComponent;
    NSString *ext = last.pathExtension.lowercaseString;
    return ext ?: @"";
}

IMFileKind IMFileKindForName(NSString *name) {
    if (name.length == 0) return IMFileKindOther;

    NSString *lowerName = name.lastPathComponent.lowercaseString;
    NSString *ext = IMFileExtension(lowerName);

    if (ext.length > 0) {
        NSNumber *hit = IMFileKindExtensionTable()[ext];
        if (hit != nil) return (IMFileKind)hit.integerValue;
        return IMFileKindBinary;   // 有扩展名但不在表里：按二进制保守处理
    }

    if ([lowerName hasPrefix:@"."]) return IMFileKindText;   // .gitignore / .env
    if (IMFileNameIsPlainText(lowerName)) return IMFileKindCode;
    return IMFileKindOther;
}

BOOL IMFileKindLooksTextual(IMFileKind kind) {
    switch (kind) {
        case IMFileKindText:
        case IMFileKindCode:
        case IMFileKindMarkdown:
            return YES;
        case IMFileKindImage: {
            return NO;   // svg 在调用处单独判断（见下）
        }
        default:
            return NO;
    }
}

NSString *IMFileKindSymbol(IMFileKind kind) {
    switch (kind) {
        case IMFileKindDirectory: return @"folder.fill";
        case IMFileKindText:      return @"doc.text";
        case IMFileKindCode:      return @"chevron.left.forwardslash.chevron.right";
        case IMFileKindMarkdown:  return @"doc.richtext";
        case IMFileKindImage:     return @"photo";
        case IMFileKindPDF:       return @"doc.viewfinder";
        case IMFileKindOffice:    return @"tablecells";
        case IMFileKindArchive:   return @"archivebox";
        case IMFileKindMedia:     return @"play.rectangle";
        case IMFileKindBinary:    return @"shippingbox";
        case IMFileKindOther:
        default:                  return @"doc";
    }
}

UIColor *IMFileKindColor(IMFileKind kind) {
    IMTheme *theme = IMTheme.shared;
    switch (kind) {
        case IMFileKindDirectory: return theme.accentColor;
        case IMFileKindText:      return theme.labelSecondary;
        case IMFileKindCode:      return theme.accentColor;
        case IMFileKindMarkdown:  return theme.successColor;
        case IMFileKindImage:     return theme.successColor;
        case IMFileKindPDF:       return theme.dangerColor;
        case IMFileKindOffice:    return theme.warningColor;
        case IMFileKindArchive:   return theme.warningColor;
        case IMFileKindMedia:     return theme.accentColor;
        case IMFileKindBinary:    return theme.labelTertiary;
        case IMFileKindOther:
        default:                  return theme.labelTertiary;
    }
}

NSString *IMFileKindDisplayName(IMFileKind kind) {
    switch (kind) {
        case IMFileKindDirectory: return @"文件夹";
        case IMFileKindText:      return @"文本";
        case IMFileKindCode:      return @"代码";
        case IMFileKindMarkdown:  return @"Markdown";
        case IMFileKindImage:     return @"图片";
        case IMFileKindPDF:       return @"PDF";
        case IMFileKindOffice:    return @"Office 文档";
        case IMFileKindArchive:   return @"压缩包";
        case IMFileKindMedia:     return @"音视频";
        case IMFileKindBinary:    return @"二进制";
        case IMFileKindOther:
        default:                  return @"未知类型";
    }
}

NSString *IMFileSizeString(unsigned long long bytes, BOOL hasSize) {
    if (!hasSize) return @"—";
    if (bytes < 1024ULL) return [NSString stringWithFormat:@"%llu B", bytes];

    double value = (double)bytes;
    static NSString * const units[] = { @"KB", @"MB", @"GB", @"TB" };
    NSUInteger unit = 0;
    value /= 1024.0;
    while (value >= 1024.0 && unit < 3) {
        value /= 1024.0;
        unit += 1;
    }
    // 10 以下保留一位小数（1.4 MB），以上取整（42 MB）——手机上一眼能读的密度。
    if (value < 10.0) return [NSString stringWithFormat:@"%.1f %@", value, units[unit]];
    return [NSString stringWithFormat:@"%.0f %@", value, units[unit]];
}
