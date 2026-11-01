//
//  IMImagePreviewViewController.m
//  IMDSH — 图片全屏预览
//

#import "IMImagePreviewViewController.h"
#import "IMTheme.h"
#import "IMGlass.h"
#import "IMAttachmentImageStore.h"

@interface IMImagePreviewViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) IMAttachmentRef *attachment;
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, strong, nullable) UIImage *placeholderImage;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation IMImagePreviewViewController

- (instancetype)initWithPlaceholderImage:(UIImage *)image
                              attachment:(IMAttachmentRef *)attachment
                               sessionId:(NSString *)sessionId {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _attachment = attachment;
        _sessionId = [sessionId copy] ?: @"";
        _placeholderImage = image;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.modalPresentationStyle = UIModalPresentationFullScreen;

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.delegate = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 4.0;
    self.scrollView.bouncesZoom = YES;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.backgroundColor = UIColor.blackColor;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    self.imageView = [[UIImageView alloc] init];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.image = self.placeholderImage;
    [self.contentView addSubview:self.imageView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = UIColor.whiteColor;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setImage:IMSymbol(@"xmark", 16, UIImageSymbolWeightBold) forState:UIControlStateNormal];
    closeButton.tintColor = UIColor.whiteColor;
    closeButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    closeButton.layer.cornerRadius = 18;
    [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
        [self.contentView.heightAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.heightAnchor],

        [self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [closeButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [closeButton.widthAnchor constraintEqualToConstant:36],
        [closeButton.heightAnchor constraintEqualToConstant:36],
    ]];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:doubleTap];

    [self loadFullImage];
}

- (void)loadFullImage {
    if (self.attachment.attachmentId.length == 0 || self.sessionId.length == 0) return;
    UIImage *cached = [IMAttachmentImageStore.shared cachedImageForAttachmentId:self.attachment.attachmentId];
    if (cached != nil) {
        self.imageView.image = cached;
        return;
    }
    if (self.imageView.image == nil) [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [IMAttachmentImageStore.shared imageForAttachment:self.attachment sessionId:self.sessionId completion:^(UIImage *image) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        [self.spinner stopAnimating];
        // 拉原图失败就留在缩略图上，不提示、不打断。
        if (image != nil) self.imageView.image = image;
    }];
}

#pragma mark - 交互

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (self.scrollView.zoomScale > self.scrollView.minimumZoomScale + 0.01) {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
        return;
    }
    CGPoint point = [recognizer locationInView:self.contentView];
    CGFloat target = MIN(self.scrollView.maximumZoomScale, 2.5);
    CGFloat width = self.scrollView.bounds.size.width / target;
    CGFloat height = self.scrollView.bounds.size.height / target;
    CGRect zoomRect = CGRectMake(point.x - width / 2, point.y - height / 2, width, height);
    [self.scrollView zoomToRect:zoomRect animated:YES];
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.contentView;
}

@end
