//
//  files-IMFilesSkeletonView.h
//  IMDSH — 文件域共用：加载骨架（几条圆角占位条 + 一句说明）
//
//  为什么不用 UIActivityIndicatorView 了事：文件读取动辄几百毫秒到几秒，
//  骨架条能让用户看出「这一屏会有内容」，比转圈更不焦虑，也不会有布局跳动。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMFilesSkeletonView : UIView

/// 骨架下方那句说明（"正在读取 main.m…"）。
@property (nonatomic, strong, readonly) UILabel *captionLabel;

- (void)startAnimating;
- (void)stopAnimating;

@end

NS_ASSUME_NONNULL_END
