//
//  IMKeychain.h
//  IMDSH — 极简 Keychain 封装（设备 token / 设备身份不落 UserDefaults）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMKeychain : NSObject

+ (BOOL)setString:(NSString *)value forKey:(NSString *)key;
+ (nullable NSString *)stringForKey:(NSString *)key;
+ (BOOL)removeKey:(NSString *)key;
+ (BOOL)containsKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
