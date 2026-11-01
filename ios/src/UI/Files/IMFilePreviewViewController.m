//
//  IMFilePreviewViewController.m
//  IMDSH — 工作区文件预览页
//
//  设计取舍：
//   · 顶部玻璃条 + 元信息行 + 内容区三段式，和聊天/设置页同一套密度；
//   · 一切内容都先经过「骨架 → 成功 / 失败重试」状态机，慢网络下不会出现白屏；
//   · 文本走 workspaceFiles/read 的分页（协议本身就是按行分页，不是按字节），
//     一页 2000 行，超大文件（>2MB）先问一句再加载；
//   · 图片/PDF/Office 走 workspaceFiles/readBytes（multipart 回包，data 是 NSData）。
//

#import "IMFilePreviewViewController.h"

#import <QuickLook/QuickLook.h>
#import <ImageIO/ImageIO.h>

#import "IMTheme.h"
#import "IMGlass.h"
#import "IMFormatting.h"
#import "IMFilesService.h"
#import "IMServerStore.h"
#import "files-IMFileKind.h"
#import "files-IMFilesSkeletonView.h"

#pragma mark - 常量

/// 文本一页多少行。后端 maxLines 默认 5000，取 2000 保证单页回包不会被 2MB 字节上限拒。
static const NSInteger IMTextPageLines = 2000;
/// 超过这个大小先问一句（需求：>2MB 先确认再加载）。
static const unsigned long long IMLargeTextBytes = 2ULL * 1024ULL * 1024ULL;
/// 图片超过这个大小直接劝退，避免拿 30MB 的 RAW 把手机内存打满。
static const unsigned long long IMLargeImageBytes = 24ULL * 1024ULL * 1024ULL;
static NSString * const IMPreviewTempDirectoryName = @"IMFilesPreview";

typedef NS_ENUM(NSInteger, IMPreviewContentMode) {
    IMPreviewContentModeNone = 0,
    IMPreviewContentModeText,
    IMPreviewContentModeImage,
    IMPreviewContentModeQuickLook,
    /// 只展示元信息（不支持预览的类型、或读取失败但想看基本信息时）。
    IMPreviewContentModeInfo,
};

#pragma mark - 语法着色（轻量：注释/字符串/关键字/数字四类）

typedef NS_ENUM(NSInteger, IMCodeFamily) {
    IMCodeFamilyNone = 0,
    IMCodeFamilyCLike,      // // /* */
    IMCodeFamilyHash,       // #
    IMCodeFamilySQL,        // --
    IMCodeFamilyMarkdown,
    IMCodeFamilyJSON,
};

static IMCodeFamily IMCodeFamilyForExtension(NSString *ext) {
    static NSSet<NSString *> *cLike;
    static NSSet<NSString *> *hash;
    static NSSet<NSString *> *sql;
    static NSSet<NSString *> *json;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cLike = [NSSet setWithArray:@[@"js", @"mjs", @"cjs", @"ts", @"tsx", @"jsx", @"c", @"h",
                                      @"m", @"mm", @"cc", @"cpp", @"cxx", @"hpp", @"cs", @"java",
                                      @"kt", @"kts", @"swift", @"go", @"rs", @"php", @"css",
                                      @"scss", @"less", @"proto", @"graphql", @"gql", @"scala",
                                      @"dart", @"gradle", @"vue", @"svelte"]];
        hash = [NSSet setWithArray:@[@"py", @"rb", @"sh", @"bash", @"zsh", @"fish", @"yaml",
                                     @"yml", @"toml", @"ini", @"conf", @"cfg", @"properties",
                                     @"pl", @"r", @"ex", @"exs", @"ps1", @"dockerfile",
                                     @"gitignore", @"editorconfig", @"makefile"]];
        sql = [NSSet setWithArray:@[@"sql"]];
        json = [NSSet setWithArray:@[@"json", @"jsonc", @"json5", @"plist"]];
    });
    NSString *lower = ext.lowercaseString ?: @"";
    if ([json containsObject:lower]) return IMCodeFamilyJSON;
    if ([sql containsObject:lower]) return IMCodeFamilySQL;
    if ([hash containsObject:lower]) return IMCodeFamilyHash;
    if ([lower isEqualToString:@"md"] || [lower isEqualToString:@"markdown"] ||
        [lower isEqualToString:@"mdx"]) return IMCodeFamilyMarkdown;
    if ([cLike containsObject:lower]) return IMCodeFamilyCLike;
    return IMCodeFamilyNone;
}

/// 只对前 400KB 做正则扫描：再长的文件着色收益极低，扫描成本却是线性的。
static const NSUInteger IMSyntaxColoringByteLimit = 400 * 1024;

static NSArray<NSString *> *IMCodeKeywords(IMCodeFamily family) {
    switch (family) {
        case IMCodeFamilyCLike:
            return @[@"if", @"else", @"for", @"while", @"do", @"switch", @"case", @"break",
                     @"continue", @"return", @"function", @"class", @"struct", @"enum", @"const",
                     @"let", @"var", @"new", @"delete", @"try", @"catch", @"throw", @"import",
                     @"export", @"public", @"private", @"protected", @"static", @"void",
                     @"interface", @"extends", @"implements", @"async", @"await", @"func",
                     @"guard", @"def", @"end", @"nil", @"self", @"this", @"true", @"false",
                     @"null", @"undefined"];
        case IMCodeFamilyHash:
            return @[@"def", @"class", @"import", @"from", @"as", @"return", @"if", @"elif",
                     @"else", @"for", @"while", @"try", @"except", @"finally", @"with", @"lambda",
                     @"yield", @"None", @"True", @"False", @"and", @"or", @"not", @"in", @"is",
                     @"then", @"fi", @"do", @"done", @"function", @"local", @"export"];
        case IMCodeFamilySQL:
            return @[@"SELECT", @"FROM", @"WHERE", @"INSERT", @"UPDATE", @"DELETE", @"JOIN",
                     @"LEFT", @"RIGHT", @"INNER", @"OUTER", @"GROUP", @"ORDER", @"BY", @"HAVING",
                     @"LIMIT", @"OFFSET", @"CREATE", @"TABLE", @"INDEX", @"DROP", @"ALTER"];
        case IMCodeFamilyJSON:
        case IMCodeFamilyMarkdown:
        case IMCodeFamilyNone:
        default:
            return @[];
    }
}

static NSRegularExpression *IMRegex(NSString *pattern, NSRegularExpressionOptions options) {
    if (pattern.length == 0) return nil;
    return [NSRegularExpression regularExpressionWithPattern:pattern options:options error:NULL];
}

/// 把文本变成带轻量着色的富文本。刻意只用「注释 → 字符串 → 关键字/数字」三遍扫描，
/// 不做真正的词法分析：手机上看源码只要关键字/字符串能分辨就够了。
static NSAttributedString *IMCodeAttributedText(NSString *text, NSString *extension, CGFloat fontSize) {
    IMTheme *theme = IMTheme.shared;
    NSString *body = text.length > 0 ? text : @"";
    UIFont *font = [UIFont monospacedSystemFontOfSize:fontSize weight:UIFontWeightRegular];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByClipping;
    paragraph.lineSpacing = 1.0;
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:body attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: theme.labelPrimary,
        NSParagraphStyleAttributeName: paragraph,
    }];
    if (body.length == 0) return out;

    NSUInteger limit = MIN(body.length, IMSyntaxColoringByteLimit);
    NSRange window = NSMakeRange(0, limit);
    NSMutableIndexSet *claimed = [NSMutableIndexSet indexSet];
    IMCodeFamily family = IMCodeFamilyForExtension(extension);

    NSMutableArray<NSString *> *commentPatterns = [NSMutableArray array];
    if (family == IMCodeFamilyCLike) {
        [commentPatterns addObjectsFromArray:@[@"//[^\\n]*", @"/\\*[\\s\\S]*?\\*/"]];
    } else if (family == IMCodeFamilyHash) {
        [commentPatterns addObject:@"#[^\\n]*"];
    } else if (family == IMCodeFamilySQL) {
        [commentPatterns addObject:@"--[^\\n]*"];
    }

    for (NSString *pattern in commentPatterns) {
        NSRegularExpression *re = IMRegex(pattern, 0);
        [re enumerateMatchesInString:body options:0 range:window usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
            if (result.range.length == 0) return;
            [out addAttributes:@{NSForegroundColorAttributeName: theme.labelTertiary} range:result.range];
            [claimed addIndexesInRange:result.range];
        }];
    }

    // 字符串：`"…"` / `'…'`。模式用运行时拼装，避免在字面量里堆反斜杠——
    // 这段最容易写错，宁可多两行 NSString 也别猜转义。
    NSString *quote = @"\"";
    NSArray<NSString *> *stringPatterns = @[
        [NSString stringWithFormat:@"%@[^%@\\n]*%@", quote, quote, quote],
    ];
    if (family != IMCodeFamilyMarkdown && family != IMCodeFamilyJSON) {
        NSString *apostrophe = @"'";
        stringPatterns = [stringPatterns arrayByAddingObject:
            [NSString stringWithFormat:@"%@[^%@\\n]*%@", apostrophe, apostrophe, apostrophe]];
    }
    if (family == IMCodeFamilyMarkdown) {
        NSString *tick = @"`";
        stringPatterns = @[[NSString stringWithFormat:@"%@[^%@\\n]*%@", tick, tick, tick]];
    }

    for (NSString *pattern in stringPatterns) {
        NSRegularExpression *re = IMRegex(pattern, 0);
        [re enumerateMatchesInString:body options:0 range:window usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
            if (result.range.length == 0) return;
            [out addAttributes:@{NSForegroundColorAttributeName: theme.successColor} range:result.range];
            [claimed addIndexesInRange:result.range];
        }];
    }

    void (^apply)(NSString *, NSDictionary *, NSRegularExpressionOptions) =
        ^(NSString *pattern, NSDictionary *attrs, NSRegularExpressionOptions options) {
        NSRegularExpression *re = IMRegex(pattern, options);
        [re enumerateMatchesInString:body options:0 range:window usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
            if (result.range.length == 0) return;
            if ([claimed containsIndexesInRange:result.range]) return;
            [out addAttributes:attrs range:result.range];
        }];
    };

    if (family == IMCodeFamilyMarkdown) {
        // Markdown 只做两件事：标题行加粗上色、行内代码上色。
        apply(@"^#{1,6}[^\\n]*", @{NSForegroundColorAttributeName: theme.accentColor,
                                   NSFontAttributeName: [UIFont monospacedSystemFontOfSize:fontSize weight:UIFontWeightSemibold]},
              NSRegularExpressionAnchorsMatchLines);
        return out;
    }

    NSArray<NSString *> *keywords = IMCodeKeywords(family);
    if (keywords.count > 0) {
        NSMutableArray<NSString *> *escaped = [NSMutableArray arrayWithCapacity:keywords.count];
        for (NSString *word in keywords) {
            [escaped addObject:[NSRegularExpression escapedPatternForString:word]];
        }
        NSString *pattern = [NSString stringWithFormat:@"(?<![\\w$])(?:%@)(?![\\w$])", [escaped componentsJoinedByString:@"|"]];
        apply(pattern, @{NSForegroundColorAttributeName: theme.accentColor}, 0);
    }
    apply(@"\\b\\d+(?:\\.\\d+)?\\b", @{NSForegroundColorAttributeName: theme.warningColor}, 0);
    return out;
}


#pragma mark - 预览页

@interface IMFilePreviewViewController () <UIScrollViewDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate>

@property (nonatomic, copy) NSString *scopeId;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) unsigned long long declaredSize;
@property (nonatomic) BOOL hasDeclaredSize;
@property (nonatomic) BOOL placeholderMode;

@property (nonatomic) IMFileKind kind;
@property (nonatomic) IMPreviewContentMode contentMode;

@property (nonatomic) BOOL startedLoading;
/// 用户已经确认过「大文件也要加载」。
@property (nonatomic) BOOL largeLoadConfirmed;
/// 状态按钮点下去要做什么：`重试` / `仍然加载` / `按文本预览` / `去设置`。
/// 用 SEL 而不是靠文案猜，文案一改逻辑就错。
@property (nonatomic) SEL stateActionTarget;
/// 配对状态变更观察者（吊销/重新配对后要重判，并丢弃旧文件内容）。
@property (nonatomic, strong, nullable) id storeObserverToken;
/// 上次处理过的配对签名：一次配对会连发多条通知，签名没变就不重复拉。
@property (nonatomic, copy, nullable) NSString *lastPairingSignature;
@property (nonatomic, strong, nullable) NSError *lastError;

@property (nonatomic, strong) IMGlassBar *topBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) IMGlassButton *backButton;
@property (nonatomic, strong) IMGlassButton *textCopyButton;
@property (nonatomic, strong) IMGlassButton *shareButton;
@property (nonatomic, strong) IMGlassButton *moreButton;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) IMGlassBar *bottomBar;
@property (nonatomic, strong) UILabel *bottomLabel;
@property (nonatomic, strong) IMGlassButton *bottomActionButton;
@property (nonatomic, strong) NSLayoutConstraint *bottomBarBottomConstraint;

/// 状态视图
@property (nonatomic, strong) IMFilesSkeletonView *skeletonView;
@property (nonatomic, strong) UIView *stateView;
@property (nonatomic, strong) UIImageView *stateIconView;
@property (nonatomic, strong) UILabel *stateTitleLabel;
@property (nonatomic, strong) UILabel *stateDetailLabel;
@property (nonatomic, strong) IMGlassButton *stateActionButton;

/// 文本
@property (nonatomic, strong) UIScrollView *textScrollView;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSLayoutConstraint *textWrapConstraint;
@property (nonatomic, strong) NSLayoutConstraint *textWideConstraint;
@property (nonatomic, strong) NSMutableAttributedString *richText;
@property (nonatomic, strong) NSMutableString *plainText;
@property (nonatomic) BOOL wrapsLines;
@property (nonatomic) NSInteger loadedLines;
@property (nonatomic) BOOL hasMoreLines;
@property (nonatomic) BOOL hasTotalBytesInfo;

/// 图片
@property (nonatomic, strong) UIScrollView *imageScrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImage *loadedImage;

/// QuickLook / 其它 App 打开
@property (nonatomic, strong) QLPreviewController *quickLookController;
@property (nonatomic, strong, nullable) NSURL *temporaryFileURL;
@property (nonatomic, strong, nullable) UIDocumentInteractionController *documentController;

/// 元信息面板
@property (nonatomic, strong) UIView *infoPanel;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *infoValues;

@end

@implementation IMFilePreviewViewController

#pragma mark 初始化

+ (instancetype)placeholderController {
    IMFilePreviewViewController *controller = [[IMFilePreviewViewController alloc] initWithScopeId:@""
                                                                                             path:@""
                                                                                             name:@""
                                                                                             size:0
                                                                                          hasSize:NO];
    controller.placeholderMode = YES;
    return controller;
}

- (instancetype)initWithScopeId:(NSString *)scopeId
                           path:(NSString *)path
                           name:(NSString *)name
                           size:(unsigned long long)size
                        hasSize:(BOOL)hasSize {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _scopeId = [scopeId copy] ?: @"";
        _path = [path copy] ?: @"";
        _name = name.length > 0 ? [name copy] : (_path.lastPathComponent ?: @"文件");
        _declaredSize = size;
        _hasDeclaredSize = hasSize;
        _wrapsLines = YES;
        _kind = IMFileKindForName(_name);
        _infoValues = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    if (self.storeObserverToken != nil) {
        [NSNotificationCenter.defaultCenter removeObserver:self.storeObserverToken];
        self.storeObserverToken = nil;
    }
    [self.quickLookController willMoveToParentViewController:nil];
    [self.quickLookController.view removeFromSuperview];
    [self.quickLookController removeFromParentViewController];
    [self removeTemporaryFiles];
}

#pragma mark 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    IMTheme *theme = IMTheme.shared;
    self.view.backgroundColor = theme.backgroundBase;
    self.title = self.name;
    [self buildInterface];
    [self updateChromeForPlaceholder];

    // 设置里吊销/重新配对后，预览页可能还停在旧内容上（旧 token 已失效）：
    // 重判一次，未配对给引导，已配对就重新拉一遍。
    self.lastPairingSignature = [self pairingSignature];
    __weak typeof(self) weakSelf = self;
    self.storeObserverToken = [NSNotificationCenter.defaultCenter addObserverForName:IMServerStoreDidChangeNotification
                                                                             object:nil
                                                                              queue:NSOperationQueue.mainQueue
                                                                         usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self handleServerStoreChange];
    }];
}

/// 一次配对/吊销会连发多条通知，签名没变就不重复拉（否则会把正在进行的请求打断）。
- (void)handleServerStoreChange {
    NSString *signature = [self pairingSignature];
    if ([signature isEqualToString:self.lastPairingSignature ?: @""]) return;
    self.lastPairingSignature = signature;

    // 先扔旧客户端（旧 token），再按新状态重判；不依赖通知到达顺序。
    [IMFilesService.shared discardClient];
    self.startedLoading = YES;
    if (!IMFilesService.shared.isPaired) {
        [self clearContentView];
        [self removeTemporaryFiles];
        [self showUnpairedState];
        return;
    }
    [self beginLoad];
}

/// 配对状态指纹：主机标识 + 设备 token + 地址。
- (NSString *)pairingSignature {
    IMServer *server = IMServerStore.shared.currentServer;
    if (server == nil) return @"none";
    return [NSString stringWithFormat:@"%@|%@|%@",
            server.identifier ?: @"", server.deviceToken ?: @"", server.baseURLString ?: @""];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.startedLoading) {
        self.startedLoading = YES;
        [self beginLoad];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // 弹回列表时就把临时文件清掉：QuickLook 只在可见期间需要它。
    if (self.isMovingFromParentViewController) [self removeTemporaryFiles];
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

#pragma mark - 界面搭建

- (void)buildInterface {
    IMTheme *theme = IMTheme.shared;

    // ── 顶部玻璃条：返回 / 文件名 / 复制 / 分享 / 更多
    self.topBar = [[IMGlassBar alloc] initWithStyle:IMGlassStyleRegular];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topBar];

    self.backButton = [IMGlassButton iconButtonWithSystemImage:@"chevron.left" diameter:34];
    self.backButton.accessibilityLabel = @"返回";
    [self.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [IMTheme fontHeadline];
    self.titleLabel.textColor = theme.labelPrimary;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.titleLabel.text = self.name;
    [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.titleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.textCopyButton = [IMGlassButton iconButtonWithSystemImage:@"doc.on.doc" diameter:34];
    self.textCopyButton.accessibilityLabel = @"复制全文";
    [self.textCopyButton addTarget:self action:@selector(copyContent) forControlEvents:UIControlEventTouchUpInside];

    self.shareButton = [IMGlassButton iconButtonWithSystemImage:@"square.and.arrow.up" diameter:34];
    self.shareButton.accessibilityLabel = @"分享";
    [self.shareButton addTarget:self action:@selector(shareContent) forControlEvents:UIControlEventTouchUpInside];

    self.moreButton = [IMGlassButton iconButtonWithSystemImage:@"ellipsis" diameter:34];
    self.moreButton.accessibilityLabel = @"更多操作";

    [self.topBar.stackView addArrangedSubview:self.backButton];
    [self.topBar.stackView addArrangedSubview:self.titleLabel];
    [self.topBar.stackView addArrangedSubview:self.textCopyButton];
    [self.topBar.stackView addArrangedSubview:self.shareButton];
    [self.topBar.stackView addArrangedSubview:self.moreButton];

    // ── 元信息行（行数 / 大小 / 类型）
    self.metaLabel = [[UILabel alloc] init];
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.metaLabel.font = [IMTheme fontCaption];
    self.metaLabel.textColor = theme.labelTertiary;
    self.metaLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.view addSubview:self.metaLabel];

    // ── 内容容器
    self.contentContainer = [[UIView alloc] init];
    self.contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.contentContainer];

    // ── 底部玻璃条（加载更多 / 提示），默认隐藏
    self.bottomBar = [[IMGlassBar alloc] initWithStyle:IMGlassStyleRegular];
    self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBar.hidden = YES;
    [self.view addSubview:self.bottomBar];

    self.bottomLabel = [[UILabel alloc] init];
    self.bottomLabel.font = [IMTheme fontCaption];
    self.bottomLabel.textColor = theme.labelSecondary;
    [self.bottomLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.bottomActionButton = [IMGlassButton buttonWithTitle:@"继续加载" systemImage:@"arrow.down.circle" prominent:NO];
    [self.bottomActionButton addTarget:self action:@selector(loadMoreTextLines) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar.stackView addArrangedSubview:self.bottomLabel];
    [self.bottomBar.stackView addArrangedSubview:self.bottomActionButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.bottomBarBottomConstraint = [self.bottomBar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8];
    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],

        [self.metaLabel.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor constant:6],
        [self.metaLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.metaLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.contentContainer.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:8],
        [self.contentContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.contentContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.contentContainer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        self.bottomBarBottomConstraint,
    ]];

    [self buildSkeleton];
    [self buildStateView];
}

- (void)buildSkeleton {
    self.skeletonView = [[IMFilesSkeletonView alloc] init];
    self.skeletonView.translatesAutoresizingMaskIntoConstraints = NO;
    self.skeletonView.hidden = YES;
    [self.contentContainer addSubview:self.skeletonView];
    [NSLayoutConstraint activateConstraints:@[
        [self.skeletonView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor constant:20],
        [self.skeletonView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor constant:20],
        [self.skeletonView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor constant:-20],
    ]];
}

- (void)buildStateView {
    IMTheme *theme = IMTheme.shared;

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.hidden = YES;
    [self.contentContainer addSubview:container];

    self.stateIconView = [[UIImageView alloc] init];
    self.stateIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.stateIconView.tintColor = theme.labelTertiary;

    self.stateTitleLabel = [[UILabel alloc] init];
    self.stateTitleLabel.font = [IMTheme fontHeadline];
    self.stateTitleLabel.textColor = theme.labelPrimary;
    self.stateTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.stateTitleLabel.numberOfLines = 2;

    self.stateDetailLabel = [[UILabel alloc] init];
    self.stateDetailLabel.font = [IMTheme fontCallout];
    self.stateDetailLabel.textColor = theme.labelSecondary;
    self.stateDetailLabel.textAlignment = NSTextAlignmentCenter;
    self.stateDetailLabel.numberOfLines = 0;

    self.stateActionButton = [IMGlassButton buttonWithTitle:@"重试" systemImage:@"arrow.clockwise" prominent:YES];
    [self.stateActionButton addTarget:self action:@selector(stateActionTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.stateIconView, self.stateTitleLabel, self.stateDetailLabel, self.stateActionButton]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = theme.spacingM;
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [container.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [container.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [container.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [container.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],

        [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:-20],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:28],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-28],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:420],

        [self.stateIconView.widthAnchor constraintEqualToConstant:38],
        [self.stateIconView.heightAnchor constraintEqualToConstant:38],
    ]];

    self.stateView = container;
}

#pragma mark - 骨架/状态切换

- (void)showSkeletonWithCaption:(NSString *)caption {
    self.stateView.hidden = YES;
    self.skeletonView.hidden = NO;
    self.skeletonView.captionLabel.text = caption.length > 0 ? caption : @"正在读取…";
    [self.skeletonView startAnimating];
    self.contentContainer.hidden = NO;
}

- (void)hideSkeleton {
    [self.skeletonView stopAnimating];
    self.skeletonView.hidden = YES;
}

- (void)showStateIcon:(NSString *)symbol
                title:(NSString *)title
               detail:(nullable NSString *)detail
           actionText:(nullable NSString *)actionText
         actionTarget:(nullable SEL)action {
    [self hideSkeleton];
    IMTheme *theme = IMTheme.shared;

    self.stateIconView.image = IMSymbol(symbol, 30, UIImageSymbolWeightRegular);
    self.stateIconView.tintColor = theme.labelTertiary;
    self.stateTitleLabel.text = title;
    self.stateDetailLabel.text = detail ?: @"";
    self.stateDetailLabel.hidden = detail.length == 0;

    if (actionText.length > 0 && action != NULL) {
        self.stateActionTarget = action;
        self.stateActionButton.hidden = NO;
        [self.stateActionButton setButtonTitle:actionText systemImage:nil];
        self.stateActionButton.enabled = YES;
        self.stateActionButton.alpha = 1.0;
    } else {
        self.stateActionTarget = NULL;
        self.stateActionButton.hidden = YES;
    }
    self.stateView.hidden = NO;
    [self updateChromeVisibility];
}

/// 未配对（token 被吊销 / 主机被移除）：给「去设置」的引导，而不是一句 401。
- (void)showUnpairedState {
    [self showStateIcon:@"iphone.and.arrow.forward"
                  title:@"这台主机还没配对"
                 detail:@"请在设置里重新配对后再浏览文件"
             actionText:@"去设置"
           actionTarget:@selector(goToSettings)];
}

- (void)goToSettings {
    UITabBarController *tabs = self.tabBarController;
    if (tabs != nil && tabs.viewControllers.count > 2) {
        tabs.selectedIndex = 2;
        return;
    }
    IMShowToast(self.view, @"请到「设置」里重新配对这台主机");
}

- (void)clearContentView {
    for (UIView *subview in [self.contentContainer.subviews copy]) {
        if (subview == self.skeletonView || subview == self.stateView) continue;
        [subview removeFromSuperview];
    }
    self.textScrollView = nil;
    self.textView = nil;
    self.imageScrollView = nil;
    self.imageView = nil;
    self.infoPanel = nil;
    self.loadedImage = nil;
    [self removeQuickLookChild];
    self.contentMode = IMPreviewContentModeNone;
}

- (void)updateChromeVisibility {
    BOOL hasContent = (self.contentMode != IMPreviewContentModeNone) && self.stateView.hidden;
    self.textCopyButton.hidden = !(self.contentMode == IMPreviewContentModeText || self.contentMode == IMPreviewContentModeQuickLook);
    self.shareButton.hidden = !hasContent;
    self.moreButton.hidden = self.placeholderMode;
    if (self.navigationController == nil || self.navigationController.viewControllers.count <= 1) {
        self.backButton.hidden = YES;
    } else {
        self.backButton.hidden = NO;
    }
    [self buildMoreMenu];
}

- (void)updateChromeForPlaceholder {
    self.titleLabel.text = self.placeholderMode ? @"文件预览" : self.name;
    self.metaLabel.text = self.placeholderMode ? @"" : [self metaTextForCurrentKind];
    [self updateChromeVisibility];
}

- (NSString *)metaTextForCurrentKind {
    if (self.placeholderMode) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:IMFileKindDisplayName(self.kind)];
    if (self.loadedLines > 0) [parts addObject:[NSString stringWithFormat:@"共 %ld 行", (long)self.loadedLines]];
    if (self.hasDeclaredSize) [parts addObject:IMFileSizeString(self.declaredSize, YES)];
    if (self.path.length > 0) [parts addObject:self.path];
    return [parts componentsJoinedByString:@" · "];
}

#pragma mark - 加载入口

- (void)beginLoad {
    self.lastError = nil;
    self.hasMoreLines = NO;
    self.loadedLines = 0;
    self.hasTotalBytesInfo = NO;
    [self clearContentView];
    [self updateChromeForPlaceholder];
    self.bottomBar.hidden = YES;

    if (self.placeholderMode) {
        [self showStateIcon:@"doc.text.magnifyingglass"
                      title:@"选一个文件"
                     detail:@"在左边的目录里点开文件，就能在这里预览。"
                 actionText:nil
               actionTarget:NULL];
        return;
    }

    if (!IMFilesService.shared.hasServer) {
        [self showStateIcon:@"bolt.slash"
                      title:@"还没连接主机"
                     detail:@"先到「设置」里配对一台 DSH 主机，再来浏览文件。"
                 actionText:nil
               actionTarget:NULL];
        return;
    }

    if (!IMFilesService.shared.isPaired) {
        [self showUnpairedState];
        return;
    }

    [self showSkeletonWithCaption:[NSString stringWithFormat:@"正在读取 %@…", self.name]];

    NSString *ext = IMFileExtension(self.name);
    BOOL isSVG = [ext isEqualToString:@"svg"];

    if (self.kind == IMFileKindImage && !isSVG) {
        [self loadImage];
    } else if (IMFileKindLooksTextual(self.kind) || isSVG || self.kind == IMFileKindImage) {
        // svg 没有系统渲染器，退化成文本预览更诚实（需求里也允许）。
        [self loadTextPreflight];
    } else if (self.kind == IMFileKindBinary || self.kind == IMFileKindOther) {
        // 未知类型的常见情况是「没有扩展名的脚本/配置」：先试文本，失败再退二进制。
        [self loadTextPreflight];
    } else {
        [self loadBinary];
    }
}

#pragma mark 文本

- (void)loadTextPreflight {
    if (self.hasDeclaredSize) {
        [self decideTextLoadWithBytes:self.declaredSize hasBytes:YES];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [IMFilesService.shared statPath:self.path scopeId:self.scopeId completion:^(BOOL hasBytes, unsigned long long bytes, NSString *version, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (error != nil) {
            // stat 失败不代表文本读不出来（比如后端不报 size），直接试读一页。
            [self fetchTextPageAtOffset:1];
            return;
        }
        self.hasDeclaredSize = hasBytes;
        self.declaredSize = bytes;
        [self decideTextLoadWithBytes:bytes hasBytes:hasBytes];
    }];
}

- (void)decideTextLoadWithBytes:(unsigned long long)bytes hasBytes:(BOOL)hasBytes {
    if (hasBytes && bytes > IMLargeTextBytes && !self.largeLoadConfirmed) {
        [self hideSkeleton];
        NSString *sizeText = IMFileSizeString(bytes, YES);
        [self showStateIcon:@"exclamationmark.triangle"
                      title:@"文件比较大"
                     detail:[NSString stringWithFormat:@"%@，超过 2 MB。先加载前 %ld 行看看？", sizeText, (long)IMTextPageLines]
                 actionText:@"仍然加载"
               actionTarget:@selector(confirmLargeLoad)];
        return;
    }
    [self fetchTextPageAtOffset:1];
}

- (void)confirmLargeLoad {
    self.largeLoadConfirmed = YES;
    [self showSkeletonWithCaption:@"正在加载大文件…"];
    [self fetchTextPageAtOffset:1];
}

- (void)fetchTextPageAtOffset:(NSInteger)offset {
    if (offset <= 1) {
        self.richText = [[NSMutableAttributedString alloc] init];
        self.plainText = [NSMutableString string];
        self.loadedLines = 0;
    }
    [self showSkeletonWithCaption:offset <= 1 ? @"正在读取文本…" : @"正在加载后续内容…"];

    __weak typeof(self) weakSelf = self;
    [IMFilesService.shared readTextPath:self.path
                                scopeId:self.scopeId
                                 offset:offset
                                  limit:IMTextPageLines
                             completion:^(IMFilesTextPage *page, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (error != nil) {
            [self handleTextFailure:error offset:offset];
            return;
        }
        [self appendTextPage:page];
    }];
}

- (void)handleTextFailure:(NSError *)error offset:(NSInteger)offset {
    NSString *remoteCode = [error.userInfo[@"remoteCode"] isKindOfClass:NSString.class] ? error.userInfo[@"remoteCode"] : @"";
    BOOL looksBinary = [remoteCode isEqualToString:@"workspace-file/not-text"] ||
                       [remoteCode isEqualToString:@"workspace-file/not-regular-file"];
    if (looksBinary) {
        // 猜错了：按二进制走 QuickLook / 元信息。
        [self loadBinary];
        return;
    }
    self.lastError = error;
    if (offset > 1 && self.richText.length > 0) {
        // 后续页失败不该把已看到的内容清掉，只在底部条上提示。
        self.hasMoreLines = NO;
        self.bottomLabel.text = [IMFilesService messageForError:error];
        [self.bottomActionButton setButtonTitle:@"重试" systemImage:nil];
        self.bottomBar.hidden = NO;
        [self hideSkeleton];
        return;
    }
    [self showStateIcon:@"doc.questionmark"
                  title:[IMFilesService messageForError:error]
                 detail:[IMFilesService detailForError:error]
             actionText:[IMFilesService isRetryableError:error] ? @"重试" : nil
           actionTarget:@selector(retryTapped)];
}

- (void)appendTextPage:(IMFilesTextPage *)page {
    if (page.text.length > 0) {
        if (self.plainText.length > 0) [self.plainText appendString:@"\n"];
        [self.plainText appendString:page.text];
    }
    self.loadedLines += page.lines;
    self.hasMoreLines = !page.eof;
    if (page.hasTotalBytes) {
        self.hasTotalBytesInfo = YES;
        self.declaredSize = page.totalBytes;
        self.hasDeclaredSize = YES;
    }
    if (page.absolutePath.length > 0) self.infoValues[@"absolutePath"] = page.absolutePath;

    NSString *text = [self.plainText copy] ?: @"";
    NSString *ext = IMFileExtension(self.name);
    CGFloat fontSize = 12.5;

    // 着色是纯 CPU 活，2000 行也要几十毫秒，绝不能放主线程。
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSAttributedString *rendered = IMCodeAttributedText(text, ext, fontSize);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) return;
            if (self.richText == nil) self.richText = [[NSMutableAttributedString alloc] init];
            [self.richText setAttributedString:rendered];
            [self revealTextContent];
        });
    });
}

- (void)revealTextContent {
    if (self.textView == nil) {
        [self buildTextView];
    }
    self.textView.attributedText = self.richText;
    self.contentMode = IMPreviewContentModeText;
    [self hideSkeleton];
    self.stateView.hidden = YES;

    self.metaLabel.text = [self metaTextForCurrentKind];
    if (self.hasMoreLines) {
        self.bottomLabel.text = [NSString stringWithFormat:@"已显示 %ld 行，还有更多", (long)self.loadedLines];
        [self.bottomActionButton setButtonTitle:@"继续加载" systemImage:@"arrow.down.circle"];
        self.bottomBar.hidden = NO;
    } else {
        self.bottomBar.hidden = YES;
    }
    [self updateChromeVisibility];
    [self updateNoWrapWidthIfNeeded];
    [self.view setNeedsLayout];
}

- (void)buildTextView {
    if (self.textScrollView != nil) return;
    IMTheme *theme = IMTheme.shared;

    self.textScrollView = [[UIScrollView alloc] init];
    self.textScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textScrollView.backgroundColor = theme.codeBackgroundColor;
    self.textScrollView.alwaysBounceVertical = YES;
    self.textScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.textScrollView.delegate = self;
    [self.contentContainer addSubview:self.textScrollView];

    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.scrollEnabled = NO;            // 由外层 scrollView 统一滚动，才能做「不换行横滑」
    self.textView.backgroundColor = UIColor.clearColor;
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 12, 24, 12);
    self.textView.textContainer.lineFragmentPadding = 0;
    self.textView.dataDetectorTypes = UIDataDetectorTypeNone;
    [self.textScrollView addSubview:self.textView];

    self.textWrapConstraint = [self.textView.widthAnchor constraintEqualToAnchor:self.textScrollView.frameLayoutGuide.widthAnchor];
    self.textWideConstraint = [self.textView.widthAnchor constraintEqualToConstant:1000];
    self.textWideConstraint.active = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.textScrollView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [self.textScrollView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [self.textScrollView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [self.textScrollView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],

        [self.textView.topAnchor constraintEqualToAnchor:self.textScrollView.contentLayoutGuide.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.textScrollView.contentLayoutGuide.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.textScrollView.contentLayoutGuide.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.textScrollView.contentLayoutGuide.bottomAnchor],
        self.textWrapConstraint,
    ]];
    [self applyWrapMode];
}

/// 换行开关：换行时宽度跟随屏幕；不换行时文本容器放开、外滚视图横滑。
- (void)applyWrapMode {
    if (self.textView == nil) return;
    self.textView.textContainer.widthTracksTextView = self.wrapsLines;
    self.textScrollView.alwaysBounceHorizontal = !self.wrapsLines;
    self.textWrapConstraint.active = self.wrapsLines;
    self.textWideConstraint.active = !self.wrapsLines;
    if (self.wrapsLines) {
        [self.textScrollView setContentOffset:CGPointZero animated:NO];
    }
}

- (void)updateNoWrapWidthIfNeeded {
    if (self.wrapsLines || self.textView == nil || self.richText.length == 0) return;
    NSAttributedString *snapshot = [self.richText copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CGRect box = [snapshot boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                            context:nil];
        CGFloat width = ceil(box.size.width) + 32;   // 补上 textContainerInset 的左右各 12 + 余量
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil || self.textView == nil) return;
            CGFloat bounded = MIN(MAX(width, 320), 8000);
            self.textWideConstraint.constant = bounded;
            self.textView.textContainer.size = CGSizeMake(bounded, CGFLOAT_MAX);
            [self.view setNeedsLayout];
        });
    });
}

#pragma mark 图片

- (void)loadImage {
    if (self.hasDeclaredSize && self.declaredSize > IMLargeImageBytes) {
        [self showStateIcon:@"photo.badge.exclamationmark"
                      title:@"图片太大"
                     detail:[NSString stringWithFormat:@"%@，超过 24 MB，手机上解码会很吃力。", IMFileSizeString(self.declaredSize, YES)]
                 actionText:@"仍然加载"
               actionTarget:@selector(confirmLargeImage)];
        return;
    }
    [self fetchImageBytes];
}

- (void)confirmLargeImage {
    self.largeLoadConfirmed = YES;
    [self showSkeletonWithCaption:@"正在下载图片…"];
    [self fetchImageBytes];
}

- (void)fetchImageBytes {
    __weak typeof(self) weakSelf = self;
    [IMFilesService.shared readBytesPath:self.path scopeId:self.scopeId completion:^(NSData *data, NSDictionary *meta, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (error != nil) {
            self.lastError = error;
            [self showStateIcon:@"photo.badge.exclamationmark"
                          title:[IMFilesService messageForError:error]
                         detail:[IMFilesService detailForError:error]
                     actionText:[IMFilesService isRetryableError:error] ? @"重试" : nil
                   actionTarget:@selector(retryTapped)];
            return;
        }
        // 解码放在后台：手机上一次解码 8000px 的图能卡住主线程几百毫秒。
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            UIImage *image = [self decodeImageFromData:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf == nil) return;
                if (image == nil) {
                    strongSelf.lastError = nil;
                    [strongSelf showStateIcon:@"photo.badge.exclamationmark"
                                        title:@"看不了这张图"
                                       detail:@"主机的字节拿回来了，但系统解不出图像（可能是 svg 或损坏的文件）。"
                                   actionText:@"按文本预览"
                                 actionTarget:@selector(previewAsText)];
                    return;
                }
                strongSelf.declaredSize = data.length;
                strongSelf.hasDeclaredSize = YES;
                [strongSelf revealImage:image];
            });
        });
    }];
}

- (nullable UIImage *)decodeImageFromData:(NSData *)data {
    if (data.length == 0) return nil;
    UIImage *image = [UIImage imageWithData:data];
    if (image == nil) return nil;

    // GIF：把每一帧按 ImageIO 的延时拼成 animatedImage，系统自己播。
    if ([IMFileExtension(self.name) isEqualToString:@"gif"]) {
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (source != NULL) {
            size_t count = CGImageSourceGetCount(source);
            if (count > 1 && count <= 300) {
                NSMutableArray<UIImage *> *frames = [NSMutableArray arrayWithCapacity:count];
                NSTimeInterval total = 0.0;
                for (size_t index = 0; index < count; index++) {
                    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, index, NULL);
                    if (cgImage == NULL) continue;
                    UIImage *frame = [UIImage imageWithCGImage:cgImage];
                    CGImageRelease(cgImage);
                    if (frame) [frames addObject:frame];

                    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
                    NSDictionary *gif = properties[(NSString *)kCGImagePropertyGIFDictionary];
                    NSNumber *delay = gif[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?: gif[(NSString *)kCGImagePropertyGIFDelayTime];
                    total += delay.doubleValue > 0 ? delay.doubleValue : 0.1;
                }
                CFRelease(source);
                if (frames.count > 1) {
                    return [UIImage animatedImageWithImages:frames duration:MAX(total, 0.1)];
                }
                return image;
            }
            CFRelease(source);
        }
    }
    return image;
}

- (void)revealImage:(UIImage *)image {
    self.loadedImage = image;
    self.contentMode = IMPreviewContentModeImage;
    [self hideSkeleton];
    self.stateView.hidden = YES;

    if (self.imageScrollView == nil) {
        self.imageScrollView = [[UIScrollView alloc] init];
        self.imageScrollView.translatesAutoresizingMaskIntoConstraints = NO;
        self.imageScrollView.backgroundColor = IMTheme.shared.codeBackgroundColor;
        self.imageScrollView.delegate = self;
        self.imageScrollView.showsHorizontalScrollIndicator = NO;
        self.imageScrollView.showsVerticalScrollIndicator = NO;
        self.imageScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        self.imageScrollView.bouncesZoom = YES;
        self.imageScrollView.maximumZoomScale = 4.0;
        self.imageScrollView.minimumZoomScale = 1.0;
        [self.contentContainer addSubview:self.imageScrollView];

        self.imageView = [[UIImageView alloc] init];
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.imageView.userInteractionEnabled = YES;
        [self.imageScrollView addSubview:self.imageView];

        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleImageDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        [self.imageScrollView addGestureRecognizer:doubleTap];

        [NSLayoutConstraint activateConstraints:@[
            [self.imageScrollView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
            [self.imageScrollView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
            [self.imageScrollView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
            [self.imageScrollView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
        ]];
    }
    self.imageView.image = image;

    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithArray:@[IMFileKindDisplayName(self.kind)]];
    CGSize pixelSize = image.size;
    if (pixelSize.width > 0 && pixelSize.height > 0) {
        [parts insertObject:[NSString stringWithFormat:@"%.0f × %.0f", pixelSize.width * image.scale, pixelSize.height * image.scale] atIndex:0];
    }
    if (self.hasDeclaredSize) [parts addObject:IMFileSizeString(self.declaredSize, YES)];
    if (self.path.length > 0) [parts addObject:self.path];
    self.metaLabel.text = [parts componentsJoinedByString:@" · "];

    self.bottomBar.hidden = YES;
    [self updateChromeVisibility];
    [self.view setNeedsLayout];
    [self layoutImageForCurrentBounds];
}

- (void)handleImageDoubleTap:(UITapGestureRecognizer *)gesture {
    UIScrollView *scroll = self.imageScrollView;
    if (scroll == nil || self.imageView == nil) return;
    if (scroll.zoomScale > scroll.minimumZoomScale + 0.01) {
        [scroll setZoomScale:scroll.minimumZoomScale animated:YES];
        return;
    }
    CGPoint point = [gesture locationInView:self.imageView];
    CGFloat scale = MIN(scroll.maximumZoomScale, MAX(2.0, scroll.minimumZoomScale * 2.5));
    CGSize window = CGSizeMake(scroll.bounds.size.width / scale, scroll.bounds.size.height / scale);
    CGRect rect = CGRectMake(point.x - window.width / 2.0, point.y - window.height / 2.0, window.width, window.height);
    [scroll zoomToRect:rect animated:YES];
}

- (void)layoutImageForCurrentBounds {
    if (self.imageView == nil || self.loadedImage == nil) return;
    CGSize bounds = self.imageScrollView.bounds.size;
    CGSize imageSize = self.loadedImage.size;
    if (bounds.width < 1 || bounds.height < 1 || imageSize.width < 1 || imageSize.height < 1) return;

    // 只在未缩放时重排：放大状态下重排会把用户的缩放位置弹回去。
    if (self.imageScrollView.zoomScale > self.imageScrollView.minimumZoomScale + 0.01) return;

    CGFloat scale = MIN(bounds.width / imageSize.width, bounds.height / imageSize.height);
    scale = MIN(scale, 1.0);   // 小图保持 1:1，别放大成马赛克
    CGSize fitted = CGSizeMake(round(imageSize.width * scale), round(imageSize.height * scale));
    self.imageView.frame = CGRectMake(0, 0, fitted.width, fitted.height);
    self.imageScrollView.contentSize = fitted;
    CGFloat insetX = MAX(0, (bounds.width - fitted.width) / 2.0);
    CGFloat insetY = MAX(0, (bounds.height - fitted.height) / 2.0);
    self.imageScrollView.contentInset = UIEdgeInsetsMake(insetY, insetX, insetY, insetX);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutImageForCurrentBounds];
}

#pragma mark 二进制 / QuickLook

- (void)loadBinary {
    [self showSkeletonWithCaption:@"正在下载文件…"];
    __weak typeof(self) weakSelf = self;
    [IMFilesService.shared readBytesPath:self.path scopeId:self.scopeId completion:^(NSData *data, NSDictionary *meta, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        if (error != nil) {
            if ([error.userInfo[@"remoteCode"] isEqual:@"workspace-file/not-text"]) {
                self.lastError = error;
            }
            [self showStateIcon:@"doc.questionmark"
                          title:[IMFilesService messageForError:error]
                         detail:[IMFilesService detailForError:error]
                     actionText:[IMFilesService isRetryableError:error] ? @"重试" : nil
                   actionTarget:@selector(retryTapped)];
            return;
        }
        self.declaredSize = data.length;
        self.hasDeclaredSize = YES;
        NSURL *url = [self writeTemporaryFileWithData:data];
        if (url == nil) {
            [self showStateIcon:@"externaldrive.badge.xmark"
                          title:@"写不了临时文件"
                         detail:@"设备存储可能已满，或临时目录不可写。"
                     actionText:@"重试"
                   actionTarget:@selector(retryTapped)];
            return;
        }
        self.temporaryFileURL = url;
        self.infoValues[@"localPath"] = url.lastPathComponent;

        if ([QLPreviewController canPreviewItem:url]) {
            [self embedQuickLookForURL:url];
        } else {
            [self showInfoPanelWithNote:@"这个类型系统预览不了，可以交给别的 App 打开。"];
        }
    }];
}

- (void)embedQuickLookForURL:(NSURL *)url {
    [self hideSkeleton];
    self.stateView.hidden = YES;
    [self removeQuickLookChild];

    self.quickLookController = [[QLPreviewController alloc] init];
    self.quickLookController.dataSource = self;
    self.quickLookController.delegate = self;
    [self addChildViewController:self.quickLookController];
    UIView *qlView = self.quickLookController.view;
    qlView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:qlView];
    [NSLayoutConstraint activateConstraints:@[
        [qlView.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [qlView.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [qlView.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [qlView.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
    ]];
    [self.quickLookController didMoveToParentViewController:self];

    self.contentMode = IMPreviewContentModeQuickLook;
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithArray:@[IMFileKindDisplayName(self.kind)]];
    if (self.hasDeclaredSize) [parts addObject:IMFileSizeString(self.declaredSize, YES)];
    if (self.path.length > 0) [parts addObject:self.path];
    self.metaLabel.text = [parts componentsJoinedByString:@" · "];
    [self updateChromeVisibility];
}

- (void)removeQuickLookChild {
    if (self.quickLookController == nil) return;
    [self.quickLookController willMoveToParentViewController:nil];
    [self.quickLookController.view removeFromSuperview];
    [self.quickLookController removeFromParentViewController];
    self.quickLookController = nil;
}

- (void)previewAsText {
    self.largeLoadConfirmed = YES;
    [self showSkeletonWithCaption:@"正在按文本读取…"];
    [self fetchTextPageAtOffset:1];
}

#pragma mark 元信息面板

- (void)showInfoPanelWithNote:(NSString *)note {
    [self hideSkeleton];
    self.stateView.hidden = YES;
    [self clearOtherContentKeepingInfo];
    self.contentMode = IMPreviewContentModeInfo;

    IMTheme *theme = IMTheme.shared;
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.contentContainer addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = theme.spacingM;
    [scroll addSubview:stack];

    IMGlassView *card = [[IMGlassView alloc] initWithStyle:IMGlassStyleRegular];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.cornerRadius = theme.radiusCard;
    card.showsStroke = YES;
    [stack addArrangedSubview:card];

    UIStackView *rows = [[UIStackView alloc] init];
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = theme.spacingS;
    [card.contentView addSubview:rows];
    [NSLayoutConstraint activateConstraints:@[
        [rows.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:theme.spacingL],
        [rows.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:theme.spacingL],
        [rows.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-theme.spacingL],
        [rows.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor constant:-theme.spacingL],
    ]];

    [rows addArrangedSubview:[self infoRowWithTitle:@"名称" value:self.name]];
    [rows addArrangedSubview:[self infoRowWithTitle:@"类型" value:IMFileKindDisplayName(self.kind)]];
    [rows addArrangedSubview:[self infoRowWithTitle:@"大小" value:IMFileSizeString(self.declaredSize, self.hasDeclaredSize)]];
    if (self.path.length > 0) [rows addArrangedSubview:[self infoRowWithTitle:@"路径" value:self.path]];
    NSString *absolute = self.infoValues[@"absolutePath"];
    if (absolute.length > 0) [rows addArrangedSubview:[self infoRowWithTitle:@"主机绝对路径" value:absolute]];

    if (note.length > 0) {
        UILabel *noteLabel = [[UILabel alloc] init];
        noteLabel.text = note;
        noteLabel.font = [IMTheme fontFootnote];
        noteLabel.textColor = theme.labelTertiary;
        noteLabel.numberOfLines = 0;
        [stack addArrangedSubview:noteLabel];
    }

    UIStackView *actions = [[UIStackView alloc] init];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = theme.spacingS;
    if (self.temporaryFileURL != nil) {
        IMGlassButton *openButton = [IMGlassButton buttonWithTitle:@"用其它 App 打开" systemImage:@"arrow.up.forward.app" prominent:NO];
        [openButton addTarget:self action:@selector(openInOtherApp) forControlEvents:UIControlEventTouchUpInside];
        [actions addArrangedSubview:openButton];

        IMGlassButton *shareButton = [IMGlassButton buttonWithTitle:@"分享" systemImage:@"square.and.arrow.up" prominent:NO];
        [shareButton addTarget:self action:@selector(shareContent) forControlEvents:UIControlEventTouchUpInside];
        [actions addArrangedSubview:shareButton];
    } else {
        IMGlassButton *textButton = [IMGlassButton buttonWithTitle:@"按文本预览" systemImage:@"doc.text" prominent:NO];
        [textButton addTarget:self action:@selector(previewAsText) forControlEvents:UIControlEventTouchUpInside];
        [actions addArrangedSubview:textButton];
    }
    [stack addArrangedSubview:actions];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:theme.spacingL],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-theme.spacingXL],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:theme.spacingL],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-theme.spacingL],
    ]];
    self.infoPanel = scroll;

    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithArray:@[IMFileKindDisplayName(self.kind)]];
    if (self.hasDeclaredSize) [parts addObject:IMFileSizeString(self.declaredSize, YES)];
    if (self.path.length > 0) [parts addObject:self.path];
    self.metaLabel.text = [parts componentsJoinedByString:@" · "];
    [self updateChromeVisibility];
}

- (void)clearOtherContentKeepingInfo {
    for (UIView *subview in [self.contentContainer.subviews copy]) {
        if (subview == self.skeletonView || subview == self.stateView) continue;
        [subview removeFromSuperview];
    }
    self.textScrollView = nil;
    self.textView = nil;
    self.imageScrollView = nil;
    self.imageView = nil;
    [self removeQuickLookChild];
}

- (UIView *)infoRowWithTitle:(NSString *)title value:(NSString *)value {
    IMTheme *theme = IMTheme.shared;
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [IMTheme fontCaption];
    titleLabel.textColor = theme.labelTertiary;
    [titleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.text = value.length > 0 ? value : @"—";
    valueLabel.font = [IMTheme fontCallout];
    valueLabel.textColor = theme.labelPrimary;
    valueLabel.numberOfLines = 0;
    valueLabel.textAlignment = NSTextAlignmentRight;
    [valueLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, valueLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = theme.spacingM;
    row.alignment = UIStackViewAlignmentFirstBaseline;
    return row;
}

#pragma mark - 动作

- (void)goBack {
    if (self.navigationController != nil) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)retryTapped {
    [self beginLoad];
}

- (void)stateActionTapped {
    // 状态按钮的语义在 showStateIcon 里就定了（重试 / 仍然加载 / 按文本预览 / 去设置），
    // 这里直接执行，不靠按钮文案反推。
    SEL target = self.stateActionTarget;
    if (target == NULL) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self performSelector:target];
#pragma clang diagnostic pop
}

- (void)copyContent {
    NSString *text = nil;
    if (self.contentMode == IMPreviewContentModeText) {
        text = self.plainText.copy;
    } else if (self.temporaryFileURL != nil) {
        text = [[IMFilesService resourceAddressForScopeId:self.scopeId path:self.path] copy];
    }
    if (text.length == 0) {
        [self shareContent];
        return;
    }
    IMCopyText(text, self.view, self.contentMode == IMPreviewContentModeText ? @"已复制全文" : @"已复制文件地址");
}

- (void)shareContent {
    id item = nil;
    if (self.contentMode == IMPreviewContentModeText && self.plainText.length > 0) {
        item = self.plainText.copy;
    } else if (self.loadedImage != nil) {
        item = self.loadedImage;
    } else if (self.temporaryFileURL != nil) {
        item = self.temporaryFileURL;
    }
    if (item == nil) {
        IMCopyText([IMFilesService resourceAddressForScopeId:self.scopeId path:self.path], self.view, @"已复制文件地址");
        return;
    }

    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[item] applicationActivities:nil];
    // iPad 上 UIActivityViewController 是 popover，不设锚点会直接崩；
    // 锚到「当前可见的那个按钮」，都不可见时退回视图中心。
    UIView *anchor = nil;
    if (self.shareButton != nil && !self.shareButton.hidden) {
        anchor = self.shareButton;
    } else if (self.moreButton != nil && !self.moreButton.hidden) {
        anchor = self.moreButton;
    } else {
        anchor = self.view;
    }
    activity.popoverPresentationController.sourceView = anchor;
    activity.popoverPresentationController.sourceRect = (anchor == self.view)
        ? CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMinY(self.view.bounds) + 60, 1, 1)
        : anchor.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)openInOtherApp {
    if (self.temporaryFileURL == nil) return;
    self.documentController = [UIDocumentInteractionController interactionControllerWithURL:self.temporaryFileURL];
    self.documentController.name = self.name;
    [self.documentController presentOptionsMenuFromRect:self.view.bounds inView:self.view animated:YES];
}

- (void)saveImageToPhotoLibrary {
    if (self.loadedImage == nil) return;
    // Info.plist 已有 NSPhotoLibraryAddUsageDescription，直接存即可（缺这条会被 TCC 强杀）。
    UIImageWriteToSavedPhotosAlbum(self.loadedImage, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (error != nil) {
        IMShowToast(self.view, @"保存失败");
    } else {
        IMShowToast(self.view, @"已保存到相册");
    }
}

- (void)loadMoreTextLines {
    // 同一个按钮两种含义：正常是「继续加载」，上一页失败后变成「重试」。
    BOOL isRetry = [self.bottomActionButton.configuration.title isEqualToString:@"重试"];
    if (!isRetry && !self.hasMoreLines) return;
    [self fetchTextPageAtOffset:self.loadedLines + 1];
}

- (void)buildMoreMenu {
    IMTheme *theme = IMTheme.shared;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];

    __weak typeof(self) weakSelf = self;
    [items addObject:[UIAction actionWithTitle:@"复制全文" image:IMSymbol(@"doc.on.doc", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(__kindof UIAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self copyContent];
    }]];
    [items addObject:[UIAction actionWithTitle:@"分享" image:IMSymbol(@"square.and.arrow.up", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(__kindof UIAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self shareContent];
    }]];
    [items addObject:[UIAction actionWithTitle:@"重新加载" image:IMSymbol(@"arrow.clockwise", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(__kindof UIAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self beginLoad];
    }]];

    if (self.kind == IMFileKindImage && self.loadedImage != nil) {
        [items addObject:[UIAction actionWithTitle:@"存到相册" image:IMSymbol(@"square.and.arrow.down", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(__kindof UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            [self saveImageToPhotoLibrary];
        }]];
    }
    if (self.temporaryFileURL != nil) {
        [items addObject:[UIAction actionWithTitle:@"用其它 App 打开" image:IMSymbol(@"arrow.up.forward.app", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(__kindof UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            [self openInOtherApp];
        }]];
    }
    if (self.contentMode == IMPreviewContentModeText) {
        NSString *wrapTitle = self.wrapsLines ? @"不自动换行" : @"自动换行";
        UIImage *wrapImage = IMSymbol(self.wrapsLines ? @"arrow.left.and.right" : @"text.alignleft", 14, UIImageSymbolWeightRegular);
        [items addObject:[UIAction actionWithTitle:wrapTitle image:wrapImage identifier:nil handler:^(__kindof UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            self.wrapsLines = !self.wrapsLines;
            [self applyWrapMode];
            [self updateNoWrapWidthIfNeeded];
            [self buildMoreMenu];
        }]];
    }
    [items addObject:[UIAction actionWithTitle:@"复制文件地址" image:IMSymbol(@"link", 14, UIImageSymbolWeightRegular) identifier:nil handler:^(__kindof UIAction *action) {
        IMCopyText([IMFilesService resourceAddressForScopeId:self.scopeId path:self.path], self.view, @"已复制文件地址");
    }]];

    self.moreButton.menu = [UIMenu menuWithTitle:@"" children:items];
    self.moreButton.showsMenuAsPrimaryAction = YES;
    self.moreButton.tintColor = theme.labelPrimary;
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    if (scrollView == self.imageScrollView) return self.imageView;
    return nil;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    if (scrollView != self.imageScrollView) return;
    // 缩放后图片比视口小时重新居中。
    CGFloat insetX = MAX(0, (scrollView.bounds.size.width - scrollView.contentSize.width) / 2.0);
    CGFloat insetY = MAX(0, (scrollView.bounds.size.height - scrollView.contentSize.height) / 2.0);
    scrollView.contentInset = UIEdgeInsetsMake(insetY, insetX, insetY, insetX);
}

#pragma mark - QLPreviewControllerDataSource

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return self.temporaryFileURL != nil ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return self.temporaryFileURL;
}

#pragma mark - 临时文件

- (nullable NSURL *)writeTemporaryFileWithData:(NSData *)data {
    if (data.length == 0) {
        data = [NSData data];
    }
    // 同一次预览里可能写第二遍（重试、配对变更后重载）：旧目录先删掉，
    // 否则每次都会多出一个 <uuid> 目录堆在临时区里。
    [self removeTemporaryFiles];

    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:IMPreviewTempDirectoryName];
    NSFileManager *manager = NSFileManager.defaultManager;
    NSError *error = nil;
    if (![manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error]) {
        return nil;
    }
    // 崩溃/被系统杀掉时 dealloc 不会跑，靠这条兜底清理陈旧的 <uuid> 目录。
    [self sweepStaleTemporaryFoldersInRoot:root];

    NSString *folder = [root stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![manager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
        return nil;
    }
    NSString *safeName = self.name.length > 0 ? self.name : @"file";
    // 文件名里可能有 "/" 或 ":"（Windows 路径），换掉避免建目录失败。
    safeName = [safeName stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    safeName = [safeName stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    NSString *filePath = [folder stringByAppendingPathComponent:safeName];
    if (![data writeToFile:filePath options:NSDataWritingAtomic error:&error]) {
        // 写失败就把刚建的目录删掉，别留一个空壳。
        [manager removeItemAtPath:folder error:NULL];
        return nil;
    }
    return [NSURL fileURLWithPath:filePath];
}

/// 删掉 1 小时前的临时目录。只按「修改时间」判断：正在用的目录一定很新，不会被误删。
- (void)sweepStaleTemporaryFoldersInRoot:(NSString *)root {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSArray<NSString *> *children = [manager contentsOfDirectoryAtPath:root error:NULL];
    if (children.count == 0) return;

    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-3600];
    for (NSString *child in children) {
        NSString *path = [root stringByAppendingPathComponent:child];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        NSDate *modified = attributes[NSFileModificationDate];
        if (modified != nil && [modified compare:cutoff] == NSOrderedAscending) {
            [manager removeItemAtPath:path error:NULL];
        }
    }
}

- (void)removeTemporaryFiles {
    if (self.temporaryFileURL == nil) return;
    // QuickLook 还攥着这个 URL：先把子控制器摘掉再删文件，免得它去读一个已删除的路径。
    [self removeQuickLookChild];
    NSString *folder = self.temporaryFileURL.URLByDeletingLastPathComponent.path;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:IMPreviewTempDirectoryName];
    if (folder.length > 0 && [folder hasPrefix:root]) {
        [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
    }
    self.temporaryFileURL = nil;
}

@end
