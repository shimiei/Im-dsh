#import "IMKeychain.h"
#import <Security/Security.h>

static NSString *const IMKeychainService = @"com.imdsh.app";

@implementation IMKeychain

+ (NSMutableDictionary *)baseQueryForKey:(NSString *)key {
    return [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: IMKeychainService,
        (__bridge id)kSecAttrAccount: key,
    } mutableCopy];
}

+ (BOOL)setString:(NSString *)value forKey:(NSString *)key {
    if (key.length == 0) return NO;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSMutableDictionary *query = [self baseQueryForKey:key];

    NSDictionary *attributes = @{
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    };

    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        [query addEntriesFromDictionary:attributes];
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    return status == errSecSuccess;
}

+ (nullable NSString *)stringForKey:(NSString *)key {
    if (key.length == 0) return nil;
    NSMutableDictionary *query = [self baseQueryForKey:key];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)removeKey:(NSString *)key {
    if (key.length == 0) return NO;
    NSMutableDictionary *query = [self baseQueryForKey:key];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}

+ (BOOL)containsKey:(NSString *)key {
    return [self stringForKey:key] != nil;
}

@end
