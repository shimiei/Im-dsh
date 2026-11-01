//
//  IMMarkdownRenderer.m
//  IMDSH — 手写 Markdown 解析
//

#import "IMMarkdownRenderer.h"
#import "IMTheme.h"

@implementation IMMarkdownNode
@end

#pragma mark - 字体与段落工具

static UIFont *IMFontWithTraits(UIFont *base, BOOL bold, BOOL italic) {
    if (!bold && !italic) return base;
    UIFontDescriptor *descriptor = base.fontDescriptor;
    UIFontDescriptorSymbolicTraits traits = descriptor.symbolicTraits;
    if (bold) traits |= UIFontDescriptorTraitBold;
    if (italic) traits |= UIFontDescriptorTraitItalic;
    UIFontDescriptor *derived = [descriptor fontDescriptorWithSymbolicTraits:traits];
    UIFont *font = derived ? [UIFont fontWithDescriptor:derived size:base.pointSize] : nil;
    return font ?: base;
}

static NSParagraphStyle *IMParagraphStyle(CGFloat before, CGFloat after, CGFloat headIndent, CGFloat firstLineIndent) {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineHeightMultiple = [IMTheme bodyLineHeightMultiple];
    style.paragraphSpacingBefore = before;
    style.paragraphSpacing = after;
    style.headIndent = headIndent;
    style.firstLineHeadIndent = firstLineIndent;
    style.lineBreakMode = NSLineBreakByWordWrapping;
    return style;
}

static NSDictionary<NSAttributedStringKey, id> *IMBaseAttributes(void) {
    return @{
        NSFontAttributeName: [IMTheme fontBody],
        NSForegroundColorAttributeName: IMTheme.shared.labelPrimary,
        NSParagraphStyleAttributeName: IMParagraphStyle(0, 6, 0, 0),
    };
}

static NSDictionary<NSAttributedStringKey, id> *IMHeadingAttributes(NSInteger level) {
    static const CGFloat sizes[6] = {22, 19.5, 17.5, 16, 15, 14};
    CGFloat size = sizes[MIN(MAX(level, 1), 6) - 1];
    UIFont *font = [UIFont systemFontOfSize:size weight:level <= 2 ? UIFontWeightBold : UIFontWeightSemibold];
    return @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: IMTheme.shared.labelPrimary,
        NSParagraphStyleAttributeName: IMParagraphStyle(level <= 2 ? 10 : 8, 4, 0, 0),
    };
}

#pragma mark - 行内解析

static void IMAppendInline(NSMutableAttributedString *out, NSString *text, NSDictionary<NSAttributedStringKey, id> *attributes);

static void IMFlushRun(NSMutableAttributedString *out, NSMutableString *buffer, NSDictionary<NSAttributedStringKey, id> *attributes) {
    if (buffer.length == 0) return;
    [out appendAttributedString:[[NSAttributedString alloc] initWithString:buffer attributes:attributes]];
    [buffer setString:@""];
}

static BOOL IMIsWordCharacter(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

static void IMAppendInline(NSMutableAttributedString *out, NSString *text, NSDictionary<NSAttributedStringKey, id> *attributes) {
    if (text.length == 0) return;
    NSMutableString *buffer = [NSMutableString string];
    NSUInteger index = 0;
    NSUInteger length = text.length;

    while (index < length) {
        unichar c = [text characterAtIndex:index];

        // 反斜杠转义：\* \_ \` \[ 等按字面输出
        if (c == '\\' && index + 1 < length) {
            [buffer appendFormat:@"%C", [text characterAtIndex:index + 1]];
            index += 2;
            continue;
        }

        // 行内代码
        if (c == '`') {
            NSRange close = [text rangeOfString:@"`" options:0 range:NSMakeRange(index + 1, length - index - 1)];
            if (close.location != NSNotFound) {
                NSString *code = [text substringWithRange:NSMakeRange(index + 1, close.location - index - 1)];
                IMFlushRun(out, buffer, attributes);
                NSMutableDictionary *codeAttributes = [attributes mutableCopy];
                UIFont *base = attributes[NSFontAttributeName] ?: [IMTheme fontBody];
                codeAttributes[NSFontAttributeName] = [UIFont monospacedSystemFontOfSize:base.pointSize - 0.5 weight:UIFontWeightRegular];
                codeAttributes[NSBackgroundColorAttributeName] = IMTheme.shared.inlineCodeBackgroundColor;
                codeAttributes[NSForegroundColorAttributeName] = IMTheme.shared.labelPrimary;
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:code attributes:codeAttributes]];
                index = close.location + 1;
                continue;
            }
        }

        // 粗体 / 删除线 / 斜体
        NSString *delimiter = nil;
        BOOL bold = NO;
        BOOL italic = NO;
        BOOL strike = NO;
        if (index + 1 < length) {
            unichar next = [text characterAtIndex:index + 1];
            if ((c == '*' && next == '*') || (c == '_' && next == '_')) {
                delimiter = [text substringWithRange:NSMakeRange(index, 2)];
                bold = YES;
            } else if (c == '~' && next == '~') {
                delimiter = [text substringWithRange:NSMakeRange(index, 2)];
                strike = YES;
            }
        }
        if (delimiter.length == 0 && (c == '*' || c == '_')) {
            // 保留 snake_case / 2*3 这类普通字符：下划线只在词边界当强调标记。
            BOOL boundary = (index == 0) || !IMIsWordCharacter([text characterAtIndex:index - 1]);
            if (c == '*' || boundary) {
                delimiter = [text substringWithRange:NSMakeRange(index, 1)];
                italic = YES;
            }
        }
        if (delimiter.length > 0) {
            NSUInteger from = index + delimiter.length;
            NSRange newline = [text rangeOfString:@"\n" options:0 range:NSMakeRange(from, length - from)];
            NSUInteger lineEnd = newline.location == NSNotFound ? length : newline.location;
            if (lineEnd > from) {
                NSRange close = [text rangeOfString:delimiter options:0 range:NSMakeRange(from, lineEnd - from)];
                if (close.location != NSNotFound && close.location > from) {
                    NSString *inner = [text substringWithRange:NSMakeRange(from, close.location - from)];
                    IMFlushRun(out, buffer, attributes);
                    NSMutableDictionary *innerAttributes = [attributes mutableCopy];
                    UIFont *base = attributes[NSFontAttributeName] ?: [IMTheme fontBody];
                    if (bold || italic) innerAttributes[NSFontAttributeName] = IMFontWithTraits(base, bold, italic);
                    if (strike) innerAttributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
                    IMAppendInline(out, inner, innerAttributes);
                    index = close.location + delimiter.length;
                    continue;
                }
            }
        }

        // 链接 [label](url)
        if (c == '[') {
            NSRange closeBracket = [text rangeOfString:@"]" options:0 range:NSMakeRange(index + 1, length - index - 1)];
            if (closeBracket.location != NSNotFound && closeBracket.location + 1 < length
                && [text characterAtIndex:closeBracket.location + 1] == '(') {
                NSUInteger urlStart = closeBracket.location + 2;
                NSRange closeParen = [text rangeOfString:@")" options:0 range:NSMakeRange(urlStart, length - urlStart)];
                if (closeParen.location != NSNotFound) {
                    NSString *label = [text substringWithRange:NSMakeRange(index + 1, closeBracket.location - index - 1)];
                    NSString *urlText = [text substringWithRange:NSMakeRange(urlStart, closeParen.location - urlStart)];
                    IMFlushRun(out, buffer, attributes);
                    NSMutableDictionary *linkAttributes = [attributes mutableCopy];
                    linkAttributes[NSForegroundColorAttributeName] = IMTheme.shared.accentColor;
                    NSURL *url = [NSURL URLWithString:urlText];
                    linkAttributes[NSLinkAttributeName] = url ?: urlText;
                    [out appendAttributedString:[[NSAttributedString alloc] initWithString:label.length > 0 ? label : urlText
                                                                                attributes:linkAttributes]];
                    index = closeParen.location + 1;
                    continue;
                }
            }
        }

        [buffer appendFormat:@"%C", c];
        index += 1;
    }

    IMFlushRun(out, buffer, attributes);
}

static void IMAppendParagraph(NSMutableAttributedString *out, NSAttributedString *paragraph) {
    if (paragraph.length == 0) return;
    if (out.length > 0) {
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{
            NSParagraphStyleAttributeName: IMParagraphStyle(0, 0, 0, 0),
        }]];
    }
    [out appendAttributedString:paragraph];
}

#pragma mark - 表格（等宽对齐）

/// 终端式显示宽度：CJK / 全角字符占两格，才能和等宽字体对齐。
static NSUInteger IMDisplayWidth(NSString *text) {
    NSUInteger width = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        BOOL wide = (c >= 0x1100 && c <= 0x115F)
            || (c >= 0x2E80 && c <= 0xA4CF)
            || (c >= 0xAC00 && c <= 0xD7A3)
            || (c >= 0xF900 && c <= 0xFAFF)
            || (c >= 0xFE30 && c <= 0xFE4F)
            || (c >= 0xFF00 && c <= 0xFF60)
            || (c >= 0xFFE0 && c <= 0xFFE6);
        width += wide ? 2 : 1;
    }
    return width;
}

static NSString *IMPaddedCell(NSString *cell, NSUInteger width) {
    NSUInteger current = IMDisplayWidth(cell);
    if (current >= width) return cell;
    return [cell stringByAppendingString:[@"" stringByPaddingToLength:(width - current) withString:@" " startingAtIndex:0]];
}

static NSArray<NSString *> *IMTableCellSplit(NSString *line) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([trimmed hasPrefix:@"|"]) trimmed = [trimmed substringFromIndex:1];
    if ([trimmed hasSuffix:@"|"]) trimmed = [trimmed substringToIndex:trimmed.length - 1];
    NSMutableArray<NSString *> *cells = [NSMutableArray array];
    for (NSString *cell in [trimmed componentsSeparatedByString:@"|"]) {
        [cells addObject:[cell stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
    }
    return cells;
}

static BOOL IMIsTableSeparator(NSString *line) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (trimmed.length < 3) return NO;
    if (![trimmed containsString:@"-"]) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"|-: "];
    NSCharacterSet *invalid = allowed.invertedSet;
    return [trimmed rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

#pragma mark - Renderer

@implementation IMMarkdownRenderer

+ (NSAttributedString *)attributedPlainText:(NSString *)text {
    NSString *content = text.length > 0 ? text : @" ";
    NSMutableAttributedString *output = [[NSMutableAttributedString alloc] initWithString:content attributes:IMBaseAttributes()];
    return output;
}

+ (NSAttributedString *)attributedCode:(NSString *)code {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineHeightMultiple = 1.25;
    style.paragraphSpacing = 0;
    style.lineBreakMode = NSLineBreakByClipping;
    return [[NSAttributedString alloc] initWithString:code.length > 0 ? code : @" " attributes:@{
        NSFontAttributeName: [IMTheme fontMonoBody],
        NSForegroundColorAttributeName: IMTheme.shared.labelPrimary,
        NSParagraphStyleAttributeName: style,
    }];
}

+ (NSArray<IMMarkdownNode *> *)parseMarkdown:(NSString *)markdown {
    NSMutableArray<IMMarkdownNode *> *nodes = [NSMutableArray array];
    if (![markdown isKindOfClass:NSString.class] || markdown.length == 0) return nodes;

    NSString *normalized = [markdown stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];

    __block NSMutableAttributedString *currentText = [NSMutableAttributedString new];
    __block NSMutableArray<NSString *> *plainParagraph = [NSMutableArray array];

    void (^flushPlain)(void) = ^{
        if (plainParagraph.count == 0) return;
        NSString *joined = [plainParagraph componentsJoinedByString:@" "];
        [plainParagraph removeAllObjects];
        NSMutableAttributedString *paragraph = [NSMutableAttributedString new];
        IMAppendInline(paragraph, joined, IMBaseAttributes());
        IMAppendParagraph(currentText, paragraph);
    };

    void (^flushText)(void) = ^{
        flushPlain();
        if (currentText.length == 0) return;
        IMMarkdownNode *node = [IMMarkdownNode new];
        node.type = IMMarkdownNodeTypeText;
        node.attributedText = [currentText copy];
        [nodes addObject:node];
        currentText = [NSMutableAttributedString new];
    };

    NSUInteger index = 0;
    while (index < lines.count) {
        NSString *line = lines[index];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

        // 围栏代码块
        if ([trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"]) {
            NSString *fence = [trimmed substringToIndex:3];
            NSString *language = [[trimmed substringFromIndex:3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            flushText();
            NSMutableArray<NSString *> *codeLines = [NSMutableArray array];
            index += 1;
            while (index < lines.count) {
                NSString *candidate = [lines[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if ([candidate hasPrefix:fence]) { index += 1; break; }
                [codeLines addObject:lines[index]];
                index += 1;
            }
            IMMarkdownNode *node = [IMMarkdownNode new];
            node.type = IMMarkdownNodeTypeCode;
            node.rawText = [codeLines componentsJoinedByString:@"\n"];
            node.language = language.length > 0 ? language : nil;
            [nodes addObject:node];
            continue;
        }

        // 分割线
        BOOL isRule = NO;
        if (trimmed.length >= 3) {
            NSString *stripped = [trimmed stringByReplacingOccurrencesOfString:@" " withString:@""];
            if (stripped.length >= 3) {
                unichar first = [stripped characterAtIndex:0];
                if (first == '-' || first == '*' || first == '_') {
                    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:[NSString stringWithFormat:@"%C", first]];
                    isRule = [stripped rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
                }
            }
        }
        if (isRule) {
            flushText();
            IMMarkdownNode *node = [IMMarkdownNode new];
            node.type = IMMarkdownNodeTypeRule;
            [nodes addObject:node];
            index += 1;
            continue;
        }

        // 表格
        if ([line containsString:@"|"] && index + 1 < lines.count && IMIsTableSeparator(lines[index + 1])) {
            flushText();
            NSMutableArray<NSArray<NSString *> *> *collected = [NSMutableArray array];
            [collected addObject:IMTableCellSplit(line)];
            index += 2;   // 跳过表头与分隔行
            while (index < lines.count) {
                NSString *candidate = [lines[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if (candidate.length == 0 || ![candidate containsString:@"|"]) break;
                [collected addObject:IMTableCellSplit(lines[index])];
                index += 1;
            }
            NSArray<NSArray<NSString *> *> *rows = collected;

            NSUInteger columnCount = 0;
            for (NSArray<NSString *> *row in rows) columnCount = MAX(columnCount, row.count);
            NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
            for (NSUInteger column = 0; column < columnCount; column++) {
                NSUInteger width = 1;
                for (NSArray<NSString *> *row in rows) {
                    if (column < row.count) width = MAX(width, IMDisplayWidth(row[column]));
                }
                [widths addObject:@(width)];
            }

            NSMutableArray<NSString *> *output = [NSMutableArray array];
            for (NSUInteger rowIndex = 0; rowIndex < rows.count; rowIndex++) {
                NSArray<NSString *> *row = rows[rowIndex];
                NSMutableArray<NSString *> *cells = [NSMutableArray array];
                for (NSUInteger column = 0; column < columnCount; column++) {
                    NSString *cell = column < row.count ? row[column] : @"";
                    [cells addObject:IMPaddedCell(cell, widths[column].unsignedIntegerValue)];
                }
                [output addObject:[cells componentsJoinedByString:@"  "]];
                if (rowIndex == 0) {
                    NSMutableArray<NSString *> *separators = [NSMutableArray array];
                    for (NSNumber *width in widths) {
                        [separators addObject:[@"" stringByPaddingToLength:width.unsignedIntegerValue withString:@"─" startingAtIndex:0]];
                    }
                    [output addObject:[separators componentsJoinedByString:@"  "]];
                }
            }

            IMMarkdownNode *node = [IMMarkdownNode new];
            node.type = IMMarkdownNodeTypeCode;
            node.rawText = [output componentsJoinedByString:@"\n"];
            node.language = @"表格";
            [nodes addObject:node];
            continue;
        }

        // 标题
        if ([trimmed hasPrefix:@"#"]) {
            NSUInteger level = 0;
            while (level < trimmed.length && level < 6 && [trimmed characterAtIndex:level] == '#') level += 1;
            BOOL hasSpace = level < trimmed.length && ([trimmed characterAtIndex:level] == ' ' || [trimmed characterAtIndex:level] == '\t');
            if (level > 0 && hasSpace) {
                NSString *content = [[trimmed substringFromIndex:level] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                flushPlain();
                NSMutableAttributedString *paragraph = [NSMutableAttributedString new];
                IMAppendInline(paragraph, content, IMHeadingAttributes((NSInteger)level));
                IMAppendParagraph(currentText, paragraph);
                index += 1;
                continue;
            }
        }

        // 引用
        if ([trimmed hasPrefix:@">"]) {
            flushPlain();
            NSString *content = [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSMutableDictionary *attributes = [IMBaseAttributes() mutableCopy];
            attributes[NSForegroundColorAttributeName] = IMTheme.shared.labelSecondary;
            attributes[NSParagraphStyleAttributeName] = IMParagraphStyle(2, 3, 16, 16);
            NSMutableAttributedString *paragraph = [NSMutableAttributedString new];
            [paragraph appendAttributedString:[[NSAttributedString alloc] initWithString:@"▍ " attributes:@{
                NSFontAttributeName: [IMTheme fontBody],
                NSForegroundColorAttributeName: IMTheme.shared.labelDimmed,
                NSParagraphStyleAttributeName: attributes[NSParagraphStyleAttributeName],
            }]];
            IMAppendInline(paragraph, content, attributes);
            IMAppendParagraph(currentText, paragraph);
            index += 1;
            continue;
        }

        // 列表项（含一层嵌套）
        {
            NSUInteger leadingSpaces = 0;
            while (leadingSpaces < line.length) {
                unichar c = [line characterAtIndex:leadingSpaces];
                if (c == ' ' || c == '\t') leadingSpaces += (c == '\t' ? 2 : 1);
                else break;
            }
            NSUInteger markerStart = 0;
            NSUInteger scan = 0;
            while (scan < line.length && ([line characterAtIndex:scan] == ' ' || [line characterAtIndex:scan] == '\t')) scan += 1;
            markerStart = scan;

            NSString *marker = nil;
            NSUInteger contentStart = NSNotFound;
            BOOL ordered = NO;
            NSUInteger markerWidth = 0;

            if (markerStart < line.length) {
                unichar c = [line characterAtIndex:markerStart];
                if (c == '-' || c == '*' || c == '+') {
                    NSUInteger after = markerStart + 1;
                    if (after < line.length && ([line characterAtIndex:after] == ' ' || [line characterAtIndex:after] == '\t')) {
                        marker = @"•";
                        contentStart = after + 1;
                        markerWidth = IMDisplayWidth(marker);
                    }
                } else if (c >= '0' && c <= '9') {
                    NSUInteger digitsEnd = markerStart;
                    while (digitsEnd < line.length) {
                        unichar d = [line characterAtIndex:digitsEnd];
                        if (d < '0' || d > '9') break;
                        digitsEnd += 1;
                    }
                    if (digitsEnd < line.length) {
                        unichar punct = [line characterAtIndex:digitsEnd];
                        BOOL punctuation = (punct == '.' || punct == ')');
                        NSUInteger after = digitsEnd + 1;
                        if (punctuation && after < line.length && [line characterAtIndex:after] == ' ') {
                            marker = [line substringWithRange:NSMakeRange(markerStart, digitsEnd - markerStart + 1)];
                            contentStart = after + 1;
                            ordered = YES;
                            markerWidth = IMDisplayWidth(marker);
                        }
                    }
                }
            }

            if (marker.length > 0 && contentStart != NSNotFound && contentStart <= line.length) {
                flushPlain();
                NSString *content = [line substringFromIndex:contentStart];
                NSUInteger indent = leadingSpaces >= 2 ? 1 : 0;
                CGFloat baseIndent = 2 + indent * 18;
                CGFloat headIndent = baseIndent + MAX(16, markerWidth + 6);
                NSMutableDictionary *attributes = [IMBaseAttributes() mutableCopy];
                attributes[NSParagraphStyleAttributeName] = IMParagraphStyle(1, 3, headIndent, baseIndent);

                NSMutableAttributedString *paragraph = [NSMutableAttributedString new];
                NSMutableDictionary *markerAttributes = [attributes mutableCopy];
                markerAttributes[NSForegroundColorAttributeName] = ordered ? IMTheme.shared.labelSecondary : IMTheme.shared.accentColor;
                [paragraph appendAttributedString:[[NSAttributedString alloc] initWithString:[marker stringByAppendingString:@"\t"]
                                                                                  attributes:markerAttributes]];
                IMAppendInline(paragraph, content, attributes);
                IMAppendParagraph(currentText, paragraph);
                index += 1;
                continue;
            }
        }

        // 普通段落
        if (trimmed.length == 0) {
            flushPlain();
            index += 1;
            continue;
        }
        if ([plainParagraph.lastObject hasSuffix:@"  "] || [plainParagraph.lastObject hasSuffix:@"\\"]) {
            // markdown 硬换行：显式拼一个换行符进去
            NSString *previous = [plainParagraph.lastObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            plainParagraph[plainParagraph.count - 1] = [[previous stringByAppendingString:@"\\\n"] mutableCopy];
        }
        [plainParagraph addObject:trimmed];
        index += 1;
    }

    flushText();
    return nodes;
}

@end
