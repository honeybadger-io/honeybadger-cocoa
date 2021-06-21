#pragma once


#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN


@interface Honeybadger : NSObject

- (id) init NS_UNAVAILABLE;

+ (void) configureWithAPIKey:(NSString*)apiKey
NS_SWIFT_NAME(configure(apiKey:));

+ (void) notifyWithString:(NSString*)errorString
NS_SWIFT_NAME(notify(errorString:));

+ (void) notifyWithString:(NSString*)errorString additionalData:(NSDictionary<NSString*, NSString*>*)data
NS_SWIFT_NAME(notify(errorString:additionalData:));

+ (void) notifyWithError:(NSError*)error
NS_SWIFT_NAME(notify(error:));

+ (void) notifyWithError:(NSError*)error additionalData:(NSDictionary<NSString*, NSString*>*)data
NS_SWIFT_NAME(notify(error:additionalData:));

+ (void) setContext:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(setContext(context:));

+ (void) resetContext:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(resetContext(context:));

@end


NS_ASSUME_NONNULL_END
