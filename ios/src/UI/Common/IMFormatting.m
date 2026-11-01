//
//  IMFormatting.m
//  IMDSH — 时间格式化 / 容错解析 / 轻提示等小工具
//

#import "IMFormatting.h"
#import "IMTheme.h"
#import "IMGlass.h"

#pragma mark - 时间

static NSISO8601DateFormatter *IMISO8601Formatter(BOOL fractionalSeconds) {
    static NSISO8601DateFormatter *plain;
    static NSISO8601DateFormatter *fractional;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = [[NSISO8601DateFormatter alloc] init];
        plain.formatOptions = NSISO8601DateFormatWithInternetDateTime;

        fractional = [[NSISO8601DateFormatter alloc] init];
        fractional.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    return fractionalSeconds ? fractional : plain;
}

/// 服务端偶尔给 "2026-03-01 14:03:00" 这种无时区的串，按本地时区读。
static NSDate *IMDateFromLooseString(NSString *text) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return [formatter dateFromString:text];
}

NSDate *IMDateFromFlexibleValue(id value) {
    if (value == nil || value == NSNull.null) return nil;

    if ([value isKindOfClass:NSNumber.class]) {
        double number = [value doubleValue];
        if (number <= 0) return nil;                       // 0 = 未设置 / 永不过期，交由调用方判断
        // 毫秒时间戳量级约 1.7e12，秒级约 1.7e9：用 1e11 分界足够安全。
        double seconds = number > 1e11 ? number / 1000.0 : number;
        return [NSDate dateWithTimeIntervalSince1970:seconds];
    }

    if ([value isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length == 0) return nil;
        NSDate *date = [IMISO8601Formatter(NO) dateFromString:text];
        if (date == nil) date = [IMISO8601Formatter(YES) dateFromString:text];
        if (date == nil) date = IMDateFromLooseString(text);
        if (date == nil) {
            // 有些网关把时间戳当字符串发（"1772000000000"）。
            BOOL allDigits = text.length > 0;
            for (NSUInteger i = 0; i < text.length && allDigits; i++) {
                unichar c = [text characterAtIndex:i];
                if (c < '0' || c > '9') allDigits = NO;
            }
            if (allDigits) return IMDateFromFlexibleValue(@(text.doubleValue));
        }
        return date;
    }

    return nil;
}

static NSString *IMClockString(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"];
        formatter.dateFormat = @"HH:mm";
    });
    return [formatter stringFromDate:date];
}

NSDate *IMDateFromFlexibleValue(id value);

NSString *IMShortDateTimeString(NSDate *date) {
    if (date == nil) return @"—";
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    });
    return [formatter stringFromDate:date];
}

NSString *IMRelativeTimeString(NSDate *date) {
    if (date == nil) return @"—";

    NSTimeInterval interval = [date timeIntervalSinceNow];
    if (interval > 0) return @"刚刚";                       // 时钟偏差导致的「未来」按刚刚处理

    NSTimeInterval ago = -interval;
    if (ago < 60) return @"刚刚";
    if (ago < 3600) return [NSString stringWithFormat:@"%ld 分钟前", (long)(ago / 60)];

    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) return [NSString stringWithFormat:@"今天 %@", IMClockString(date)];
    if ([calendar isDateInYesterday:date]) return [NSString stringWithFormat:@"昨天 %@", IMClockString(date)];
    if (ago < 7 * 24 * 3600) {
        static NSDateFormatter *weekday;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            weekday = [[NSDateFormatter alloc] init];
            weekday.locale = [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"];
            weekday.dateFormat = @"EEEE HH:mm";
        });
        return [weekday stringFromDate:date];
    }

    static NSDateFormatter *sameYear;
    static NSDateFormatter *otherYear;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sameYear = [[NSDateFormatter alloc] init];
        sameYear.locale = [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"];
        sameYear.dateFormat = @"M月d日";

        otherYear = [[NSDateFormatter alloc] init];
        otherYear.locale = [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"];
        otherYear.dateFormat = @"yyyy年M月d日";
    });

    NSInteger year = [calendar component:NSCalendarUnitYear fromDate:date];
    NSInteger currentYear = [calendar component:NSCalendarUnitYear fromDate:NSDate.date];
    return [year == currentYear ? sameYear : otherYear stringFromDate:date];
}

#pragma mark - 复制 / 轻提示

static const NSInteger IMToastTag = 0x494D5447; // 'IMTG'

static void im_showToast(UIView *hostView, NSString *text) {
    UIView *container = hostView.window ?: hostView;
    if (container == nil || text.length == 0) return;

    [container viewWithTag:IMToastTag].hidden = YES;
    [[container viewWithTag:IMToastTag] removeFromSuperview];

    IMGlassView *toast = [[IMGlassView alloc] initWithStyle:IMGlassStyleRegular];
    toast.tag = IMToastTag;
    toast.cornerRadius = IMTheme.shared.radiusPill;
    toast.showsStroke = NO;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.userInteractionEnabled = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [IMTheme fontCallout];
    label.textColor = IMTheme.shared.labelPrimary;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [toast.contentView addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:toast.contentView.topAnchor constant:10],
        [label.bottomAnchor constraintEqualToAnchor:toast.contentView.bottomAnchor constant:-10],
        [label.leadingAnchor constraintEqualToAnchor:toast.contentView.leadingAnchor constant:18],
        [label.trailingAnchor constraintEqualToAnchor:toast.contentView.trailingAnchor constant:-18],
        [toast.widthAnchor constraintLessThanOrEqualToConstant:320],
    ]];

    [container addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.bottomAnchor constant:-28],
        [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:24],
        [toast.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-24],
    ]];

    toast.alpha = 0.0;
    toast.transform = CGAffineTransformMakeScale(0.94, 0.94);
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        toast.alpha = 1.0;
        toast.transform = CGAffineTransformIdentity;
    } completion:nil];

    __weak IMGlassView *weakToast = toast;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        IMGlassView *strongToast = weakToast;
        if (strongToast == nil) return;
        [UIView animateWithDuration:0.24 animations:^{
            strongToast.alpha = 0.0;
        } completion:^(BOOL finished) {
            [strongToast removeFromSuperview];
        }];
    });
}

void IMShowToast(UIView *hostView, NSString *message) {
    im_showToast(hostView, message);
}

void IMCopyText(NSString *text, UIView *hostView, NSString *message) {
    if (text.length == 0) return;
    UIPasteboard.generalPasteboard.string = text;
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    im_showToast(hostView, message.length > 0 ? message : @"已复制");
}

void IMStackRemoveAllArrangedSubviews(UIStackView *stack) {
    NSArray<UIView *> *existing = [stack.arrangedSubviews copy];
    for (UIView *view in existing) {
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}
