//
//  files-IMFilesSkeletonView.m
//  IMDSH — 文件域共用：加载骨架
//

#import "files-IMFilesSkeletonView.h"
#import "IMTheme.h"

@interface IMFilesSkeletonView ()
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIStackView *barStack;
@end

@implementation IMFilesSkeletonView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        IMTheme *theme = IMTheme.shared;

        _barStack = [[UIStackView alloc] init];
        _barStack.translatesAutoresizingMaskIntoConstraints = NO;
        _barStack.axis = UILayoutConstraintAxisVertical;
        _barStack.spacing = theme.spacingM;
        [self addSubview:_barStack];

        // 宽度比例故意参差，看着像真实内容而不是一堆等长色块。
        NSArray<NSNumber *> *ratios = @[@0.86, @0.62, @0.94, @0.48, @0.78, @0.55, @0.9, @0.7];
        for (NSNumber *ratio in ratios) {
            UIView *bar = [[UIView alloc] init];
            bar.translatesAutoresizingMaskIntoConstraints = NO;
            bar.backgroundColor = theme.backgroundLayer3;
            bar.layer.cornerRadius = 5;
            bar.layer.cornerCurve = kCACornerCurveContinuous;
            [bar.heightAnchor constraintEqualToConstant:10].active = YES;
            [_barStack addArrangedSubview:bar];
            [bar.widthAnchor constraintEqualToAnchor:_barStack.widthAnchor multiplier:ratio.doubleValue].active = YES;
        }

        _captionLabel = [[UILabel alloc] init];
        _captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _captionLabel.font = [IMTheme fontFootnote];
        _captionLabel.textColor = theme.labelTertiary;
        _captionLabel.text = @"正在读取…";
        [self addSubview:_captionLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_barStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
            [_barStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_barStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_captionLabel.topAnchor constraintEqualToAnchor:_barStack.bottomAnchor constant:20],
            [_captionLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_captionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
            [_captionLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)startAnimating {
    [self.layer removeAllAnimations];
    self.alpha = 1.0;
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.85
                          delay:0
                        options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse | UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        weakSelf.alpha = 0.5;
    } completion:nil];
}

- (void)stopAnimating {
    [self.layer removeAllAnimations];
    self.alpha = 1.0;
}

@end
