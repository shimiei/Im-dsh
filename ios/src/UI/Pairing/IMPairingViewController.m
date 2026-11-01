#import "IMPairingViewController.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMPairingService.h"
#import "IMAPIClient.h"

@interface IMPairingViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) IMGlassView *formCard;
@property (nonatomic, strong) UITextField *addressField;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) IMGlassButton *connectButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation IMPairingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IMDSH";
    self.view.backgroundColor = IMTheme.shared.backgroundBase;
    [self buildInterface];
}

- (void)buildInterface {
    IMTheme *theme = IMTheme.shared;

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = theme.spacingL;
    [self.scrollView addSubview:self.contentStack];

    // 标题区
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"连接到你的 DSH";
    titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    titleLabel.textColor = theme.labelPrimary;
    titleLabel.numberOfLines = 0;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = @"在电脑上打开 DeepSeek Harness → 设置 → 远程接入 → 设备配对，生成一次性配对码。";
    subtitleLabel.font = [IMTheme fontCallout];
    subtitleLabel.textColor = theme.labelSecondary;
    subtitleLabel.numberOfLines = 0;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = theme.spacingS;
    [self.contentStack addArrangedSubview:header];
    [self.contentStack setCustomSpacing:theme.spacingXL afterView:header];

    // 表单卡片
    self.formCard = [[IMGlassView alloc] initWithStyle:IMGlassStyleRegular];
    self.formCard.showsStroke = YES;
    self.formCard.cornerRadius = theme.radiusCard;
    [self.contentStack addArrangedSubview:self.formCard];

    UIStackView *form = [[UIStackView alloc] init];
    form.translatesAutoresizingMaskIntoConstraints = NO;
    form.axis = UILayoutConstraintAxisVertical;
    form.spacing = theme.spacingM;
    [self.formCard.contentView addSubview:form];
    [NSLayoutConstraint activateConstraints:@[
        [form.topAnchor constraintEqualToAnchor:self.formCard.contentView.topAnchor constant:theme.spacingL],
        [form.leadingAnchor constraintEqualToAnchor:self.formCard.contentView.leadingAnchor constant:theme.spacingL],
        [form.trailingAnchor constraintEqualToAnchor:self.formCard.contentView.trailingAnchor constant:-theme.spacingL],
        [form.bottomAnchor constraintEqualToAnchor:self.formCard.contentView.bottomAnchor constant:-theme.spacingL],
    ]];

    [form addArrangedSubview:[self fieldLabel:@"服务器地址"]];
    self.addressField = [self textFieldWithPlaceholder:@"192.168.1.20:3081" keyboard:UIKeyboardTypeURL];
    self.addressField.textContentType = nil;
    self.addressField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.addressField.autocorrectionType = UITextAutocorrectionTypeNo;
    [form addArrangedSubview:self.addressField];

    [form addArrangedSubview:[self fieldLabel:@"配对码"]];
    self.codeField = [self textFieldWithPlaceholder:@"XXXX-XXXX-XXXX" keyboard:UIKeyboardTypeASCIICapable];
    self.codeField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.codeField.autocorrectionType = UITextAutocorrectionTypeNo;
    [form addArrangedSubview:self.codeField];

    self.connectButton = [IMGlassButton buttonWithTitle:@"开始配对" systemImage:@"link" prominent:YES];
    [self.connectButton addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventTouchUpInside];
    [form addArrangedSubview:self.connectButton];
    [self.connectButton.heightAnchor constraintGreaterThanOrEqualToConstant:46].active = YES;

    UIStackView *statusRow = [[UIStackView alloc] init];
    statusRow.axis = UILayoutConstraintAxisHorizontal;
    statusRow.spacing = theme.spacingS;
    statusRow.alignment = UIStackViewAlignmentCenter;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    [statusRow addArrangedSubview:self.spinner];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [IMTheme fontFootnote];
    self.statusLabel.textColor = theme.labelSecondary;
    self.statusLabel.numberOfLines = 0;
    [statusRow addArrangedSubview:self.statusLabel];

    [self.contentStack addArrangedSubview:statusRow];

    UILabel *hint = [[UILabel alloc] init];
    hint.text = @"配对码一码一机、长期有效，可在 DSH 设置页随时吊销。同一台电脑可以配给多台设备，各自的码互不影响。";
    hint.font = [IMTheme fontFootnote];
    hint.textColor = theme.labelTertiary;
    hint.numberOfLines = 0;
    [self.contentStack addArrangedSubview:hint];

    UILayoutGuide *margins = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:margins.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:theme.spacingXL],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-theme.spacingXL],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:theme.spacingL],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-theme.spacingL],
    ]];
}

- (UILabel *)fieldLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [IMTheme fontCaption];
    label.textColor = IMTheme.shared.labelTertiary;
    return label;
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder keyboard:(UIKeyboardType)keyboard {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.keyboardType = keyboard;
    field.font = [IMTheme fontBody];
    field.textColor = IMTheme.shared.labelPrimary;
    field.backgroundColor = IMTheme.shared.backgroundLayer2;
    field.layer.cornerRadius = IMTheme.shared.radiusMedium;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    field.leftViewMode = UITextFieldViewModeAlways;
    field.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    field.rightViewMode = UITextFieldViewModeAlways;
    field.delegate = self;
    field.returnKeyType = UIReturnKeyNext;
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:46].active = YES;
    return field;
}

#pragma mark - 动作

- (void)setStatus:(NSString *)text color:(UIColor *)color busy:(BOOL)busy {
    self.statusLabel.text = text;
    self.statusLabel.textColor = color ?: IMTheme.shared.labelSecondary;
    if (busy) {
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
    }
}

- (void)connectTapped {
    NSURL *url = [IMPairingService normalizeAddress:self.addressField.text ?: @""];
    if (url == nil) {
        [self setStatus:@"地址看起来不对，示例：192.168.1.20:3081" color:IMTheme.shared.dangerColor busy:NO];
        return;
    }
    NSString *code = [IMPairingService normalizeCode:self.codeField.text ?: @""];
    if (code.length < 8) {
        [self setStatus:@"配对码不完整" color:IMTheme.shared.dangerColor busy:NO];
        return;
    }

    // 回车连按会绕过按钮禁用并发发起两次 redeem：第二次必然拿到 code-already-bound，
    // 把「配对成功」覆盖成红色错误，还会 dismiss 两次。用按钮态当并发锁。
    if (!self.connectButton.enabled) return;
    self.connectButton.enabled = NO;
    [self setStatus:@"正在探测主机…" color:IMTheme.shared.labelSecondary busy:YES];

    __weak typeof(self) weakSelf = self;
    [IMPairingService probeServerAtURL:url completion:^(BOOL reachable, NSString *version, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (!reachable) {
            self.connectButton.enabled = YES;
            [self setStatus:[IMAPIClient localizedMessageForError:error] color:IMTheme.shared.dangerColor busy:NO];
            return;
        }
        [self setStatus:@"主机已找到，正在配对…" color:IMTheme.shared.labelSecondary busy:YES];
        [IMPairingService redeemCode:code atURL:url displayName:nil completion:^(IMServer *server, NSError *error2) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.connectButton.enabled = YES;
            if (error2 || server == nil) {
                [strongSelf setStatus:[IMAPIClient localizedMessageForError:error2] color:IMTheme.shared.dangerColor busy:NO];
                return;
            }
            [strongSelf setStatus:@"配对成功" color:IMTheme.shared.successColor busy:NO];
            if (strongSelf.onPaired) strongSelf.onPaired();
            [strongSelf dismissViewControllerAnimated:YES completion:nil];
        }];
    }];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.addressField) {
        [self.codeField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
        [self connectTapped];
    }
    return YES;
}

@end
