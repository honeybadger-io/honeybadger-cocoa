#pragma once


#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN


@interface Honeybadger : NSObject

- (id) init NS_UNAVAILABLE;

+ (void) configureWithAPIKey:(NSString*)apiKey
NS_SWIFT_NAME(configure(apiKey:));

+ (void) notifyWithString:(NSString*)errorString
NS_SWIFT_NAME(notify(errorString:));

+ (void) notifyWithString:(NSString*)errorString context:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(notify(errorString:context:));

+ (void) notifyWithError:(NSError*)error
NS_SWIFT_NAME(notify(error:));

+ (void) notifyWithError:(NSError*)error context:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(notify(error:context:));

+ (void) setContext:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(setContext(context:));

+ (void) resetContext:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(resetContext(context:));

@end


NS_ASSUME_NONNULL_END
