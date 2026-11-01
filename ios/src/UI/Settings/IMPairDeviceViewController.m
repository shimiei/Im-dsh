//
//  IMPairDeviceViewController.m
//  IMDSH — 生成配对码
//

#import "IMPairDeviceViewController.h"
#import "IMSettingsCardView.h"
#import "IMSettingsRowView.h"
#import "IMSettingsPairingGateway.h"
#import "IMFormatting.h"

#import "IMTheme.h"
#import "IMGlass.h"
#import "IMServerStore.h"

@interface IMPairDeviceViewController ()
@property (nonatomic, strong) IMServer *server;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) NSLayoutConstraint *maxContentWidthConstraint;

@property (nonatomic, strong, nullable) IMSettingsCardView *codeCard;
@property (nonatomic, strong, nullable) IMPairingCode *code;
@property (nonatomic, strong, nullable) NSError *loadError;
@property (nonatomic, assign) BOOL loading;
/// 网关没有这个接口时的降级态（不是「错误」，是「不可用」）。
@property (nonatomic, assign) BOOL unavailable;
@property (nonatomic, copy, nullable) NSString *unavailableReason;
@end

@implementation IMPairDeviceViewController

#pragma mark - 构造

- (instancetype)initWithServer:(IMServer *)server {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _server = server;
    }
    return self;
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"配对码";
    self.view.backgroundColor = IMTheme.shared.backgroundBase;
    [self buildHierarchy];
    [self buildContent];
    [self requestNewCode];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat maxWidth = [IMTheme.shared maxContentWidthForSize:self.view.bounds.size];
    if (fabs(self.maxContentWidthConstraint.constant - maxWidth) > 0.5) {
        self.maxContentWidthConstraint.constant = maxWidth;
    }
}

#pragma mark - 骨架

- (void)buildHierarchy {
    IMTheme *theme = IMTheme.shared;

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = theme.spacingL;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.contentStack];

    NSLayoutConstraint *fillWidth = [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor
                                                                                  constant:-(theme.spacingL * 2)];
    fillWidth.priority = (UILayoutPriority)999;
    self.maxContentWidthConstraint = [self.contentStack.widthAnchor constraintLessThanOrEqualToConstant:[theme maxContentWidthForSize:self.view.bounds.size]];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:theme.spacingL],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-(theme.spacingXL + theme.spacingL)],
        [self.contentStack.centerXAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.centerXAnchor],

        fillWidth,
        self.maxContentWidthConstraint,
    ]];
}

#pragma mark - 内容

- (void)buildContent {
    IMStackRemoveAllArrangedSubviews(self.contentStack);

    IMSettingsCardView *introCard = [[IMSettingsCardView alloc] initWithTitle:@"怎么用"];
    introCard.contentInsets = UIEdgeInsetsMake(IMTheme.shared.spacingL, IMTheme.shared.spacingL,
                                               IMTheme.shared.spacingL, IMTheme.shared.spacingL);
    [introCard addView:[self paragraphView:@"在另一台设备上打开 IMDSH，填入主机地址和这枚配对码即可完成配对。"
                                     text2:@"一码一机：每枚码只能绑定一台设备，用过即失效；未使用的码可以在主机上随时吊销。"]];
    [self.contentStack addArrangedSubview:introCard];

    self.codeCard = [[IMSettingsCardView alloc] initWithTitle:@"配对码"];
    self.codeCard.contentInsets = UIEdgeInsetsMake(IMTheme.shared.spacingL, IMTheme.shared.spacingL,
                                                   IMTheme.shared.spacingL, IMTheme.shared.spacingL);
    [self.contentStack addArrangedSubview:self.codeCard];
    [self rebuildCodeCard];

    IMSettingsCardView *hostCard = [[IMSettingsCardView alloc] initWithTitle:@"主机"];
    IMSettingsRowView *hostRow = [IMSettingsRowView rowWithTitle:self.server.displayName systemImage:@"server.rack"];
    hostRow.subtitle = self.server.baseURLString;
    hostRow.valueText = self.server.hasToken ? @"已配对" : @"令牌缺失";
    hostRow.valueColor = self.server.hasToken ? IMTheme.shared.successColor : IMTheme.shared.warningColor;
    hostRow.copyableText = self.server.baseURLString;
    [hostCard addRow:hostRow];
    [hostCard setFooterText:@"这枚码由当前主机签发；请在主机运行期间使用。"];
    [self.contentStack addArrangedSubview:hostCard];
}

- (UIView *)paragraphView:(NSString *)text text2:(nullable NSString *)text2 {
    IMTheme *theme = IMTheme.shared;

    UILabel *main = [[UILabel alloc] init];
    main.text = text;
    main.font = [IMTheme fontBody];
    main.textColor = theme.labelPrimary;
    main.numberOfLines = 0;

    UILabel *secondary = [[UILabel alloc] init];
    secondary.text = text2;
    secondary.font = [IMTheme fontFootnote];
    secondary.textColor = theme.labelTertiary;
    secondary.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[main, secondary]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = theme.spacingS;
    stack.alignment = UIStackViewAlignmentFill;
    return stack;
}

#pragma mark - 配对码卡片

- (void)rebuildCodeCard {
    IMSettingsCardView *card = self.codeCard;
    if (card == nil) return;

    [card clearContent];
    IMTheme *theme = IMTheme.shared;
    __weak typeof(self) weakSelf = self;

    if (self.loading) {
        UIStackView *row = [self loadingRow:@"正在生成配对码…"];
        [card addView:row];
        [card setFooterText:@"配对码由主机现场签发，通常一秒内完成。"];
        return;
    }

    if (self.unavailable) {
        UILabel *title = [[UILabel alloc] init];
        title.text = @"这台主机暂不支持生成配对码";
        title.font = [IMTheme fontHeadline];
        title.textColor = theme.labelPrimary;
        title.numberOfLines = 0;

        UILabel *detail = [[UILabel alloc] init];
        detail.text = self.unavailableReason ?: @"请在电脑上的 DSH 设置 → 远程接入 → 设备配对 里生成配对码，再回到本机「添加主机」输入。";
        detail.font = [IMTheme fontFootnote];
        detail.textColor = theme.labelSecondary;
        detail.numberOfLines = 0;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail]];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = theme.spacingS;
        stack.alignment = UIStackViewAlignmentFill;
        [card addView:stack];

        IMSettingsRowView *hintRow = [IMSettingsRowView rowWithTitle:@"在主机上生成配对码" systemImage:@"desktopcomputer"];
        hintRow.subtitle = @"DSH → 设置 → 远程接入 → 设备配对";
        hintRow.verticalPadding = theme.spacingS;
        [card addRow:hintRow];
        [card setFooterText:nil];
        return;
    }

    if (self.loadError != nil && self.code == nil) {
        UILabel *title = [[UILabel alloc] init];
        title.text = @"没能生成配对码";
        title.font = [IMTheme fontHeadline];
        title.textColor = theme.labelPrimary;

        UILabel *detail = [[UILabel alloc] init];
        detail.text = [IMSettingsPairingGateway messageForError:self.loadError];
        detail.font = [IMTheme fontFootnote];
        detail.textColor = theme.labelSecondary;
        detail.numberOfLines = 0;

        IMGlassButton *retry = [IMGlassButton buttonWithTitle:@"重试" systemImage:@"arrow.clockwise" prominent:NO];
        retry.translatesAutoresizingMaskIntoConstraints = NO;
        [retry addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            [weakSelf requestNewCode];
        }] forControlEvents:UIControlEventTouchUpInside];
        UIView *buttonRow = [self containerAligningLeading:retry];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail, buttonRow]];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = theme.spacingM;
        stack.alignment = UIStackViewAlignmentFill;
        [card addView:stack];
        [card setFooterText:@"仍然失败的话，可以在主机本机设置页生成配对码再输入。"];
        return;
    }

    IMPairingCode *code = self.code;
    if (code == nil) {
        [card addView:[self paragraphView:@"还没有配对码。" text2:@"点下面的按钮生成一枚。"]];
        return;
    }

    // 大字 + 等宽：读码时要一个个字符核对，字号和字距都得给足。
    UILabel *codeLabel = [[UILabel alloc] init];
    codeLabel.font = [UIFont monospacedSystemFontOfSize:29 weight:UIFontWeightSemibold];
    codeLabel.textColor = theme.labelPrimary;
    codeLabel.textAlignment = NSTextAlignmentCenter;
    codeLabel.adjustsFontSizeToFitWidth = YES;
    codeLabel.minimumScaleFactor = 0.6;
    codeLabel.numberOfLines = 1;
    codeLabel.userInteractionEnabled = YES;
    codeLabel.attributedText = [[NSAttributedString alloc] initWithString:code.displayCode
                                                              attributes:@{NSKernAttributeName: @(2.0)}];
    [codeLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyCode)]];

    UILabel *expiryLabel = [[UILabel alloc] init];
    expiryLabel.font = [IMTheme fontFootnote];
    expiryLabel.textColor = theme.labelTertiary;
    expiryLabel.textAlignment = NSTextAlignmentCenter;
    expiryLabel.numberOfLines = 0;
    expiryLabel.text = [self expiryDescriptionForCode:code];

    IMGlassButton *copyButton = [IMGlassButton buttonWithTitle:@"复制配对码" systemImage:@"doc.on.doc" prominent:YES];
    copyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [copyButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [weakSelf copyCode];
    }] forControlEvents:UIControlEventTouchUpInside];

    IMGlassButton *regenerateButton = [IMGlassButton buttonWithTitle:@"重新生成" systemImage:@"arrow.clockwise" prominent:NO];
    regenerateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [regenerateButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [weakSelf requestNewCode];
    }] forControlEvents:UIControlEventTouchUpInside];

    // 末尾放一个弹性占位，让两个玻璃按钮保持自身尺寸，而不是被拉伸铺满一行。
    UIView *buttonSpacer = [[UIView alloc] init];
    [buttonSpacer setContentHuggingPriority:(UILayoutPriority)1 forAxis:UILayoutConstraintAxisHorizontal];
    [buttonSpacer setContentCompressionResistancePriority:(UILayoutPriority)1 forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *buttonRow = [[UIStackView alloc] initWithArrangedSubviews:@[copyButton, regenerateButton, buttonSpacer]];
    buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
    buttonRow.axis = UILayoutConstraintAxisHorizontal;
    buttonRow.spacing = theme.spacingS;
    buttonRow.alignment = UIStackViewAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[codeLabel, expiryLabel, buttonRow]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = theme.spacingM;
    stack.alignment = UIStackViewAlignmentFill;
    [stack setCustomSpacing:theme.spacingS afterView:codeLabel];
    [stack setCustomSpacing:theme.spacingL afterView:expiryLabel];
    [card addView:stack];

    [card setFooterText:@"点按配对码即可复制。之前生成的未使用码不会自动失效，可在主机上一并吊销。"];
}

- (NSString *)expiryDescriptionForCode:(IMPairingCode *)code {
    if (code.neverExpires) return @"长期有效，直到在主机上吊销";
    if (code.expiresAt != nil) {
        NSString *when = IMShortDateTimeString(code.expiresAt);
        if (code.remainingDays >= 0) {
            return [NSString stringWithFormat:@"有效期 %ld 天 · %@ 到期", (long)code.remainingDays, when];
        }
        return [NSString stringWithFormat:@"%@ 到期", when];
    }
    if (code.remainingDays >= 0) {
        return [NSString stringWithFormat:@"有效期 %ld 天", (long)code.remainingDays];
    }
    return @"有效期由主机设置决定";
}

- (UIStackView *)loadingRow:(NSString *)text {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];

    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [IMTheme fontBody];
    label.textColor = IMTheme.shared.labelSecondary;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[spinner, label]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = IMTheme.shared.spacingS;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

- (UIView *)containerAligningLeading:(UIView *)view {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:container.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [view.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor],
    ]];
    return container;
}

#pragma mark - 数据

- (void)requestNewCode {
    if (!self.server.hasToken) {
        self.loading = NO;
        self.unavailable = YES;
        self.unavailableReason = @"这台主机还没有完成配对，无法签发新的配对码。先在主机上生成一枚码并完成本机配对。";
        [self refreshCodeCardAnimated:YES];
        return;
    }

    self.loading = YES;
    self.loadError = nil;
    [self refreshCodeCardAnimated:YES];

    __weak typeof(self) weakSelf = self;
    [IMSettingsPairingGateway createPairingCodeForServer:self.server days:nil completion:^(IMPairingCode *code, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;

        strongSelf.loading = NO;
        if (error != nil) {
            strongSelf.code = nil;
            strongSelf.loadError = error;
            strongSelf.unavailable = [IMSettingsPairingGateway isUnavailableError:error];
            if (strongSelf.unavailable) {
                strongSelf.unavailableReason = @"这台主机的网关版本不支持在手机上生成配对码。请在电脑上的 DSH 设置 → 远程接入 → 设备配对 里生成，再回到本机「添加主机」输入。";
            }
            [strongSelf refreshCodeCardAnimated:YES];
            return;
        }

        strongSelf.unavailable = NO;
        strongSelf.unavailableReason = nil;
        strongSelf.code = code;
        [strongSelf refreshCodeCardAnimated:YES];
    }];
}

- (void)refreshCodeCardAnimated:(BOOL)animated {
    if (animated && self.codeCard != nil) {
        [UIView transitionWithView:self.codeCard
                          duration:0.2
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ [self rebuildCodeCard]; }
                        completion:nil];
    } else {
        [self rebuildCodeCard];
    }
}

#pragma mark - 动作

- (void)copyCode {
    if (self.code.plainCode.length == 0) return;
    // 复制不带分隔符的纯码：粘贴到别的输入框里不会因为连字符被拒。
    IMCopyText(self.code.plainCode, self.view, @"配对码已复制");
}

@end

