#pragma once


#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN


@interface Honeybadger : NSObject

- (id) init NS_UNAVAILABLE;

+ (void) configureWithAPIKey:(NSString*)apiKey
NS_SWIFT_NAME(configureWith(apiKey:));

+ (void) notifyWithString:(NSString*)errorString
NS_SWIFT_NAME(notifyWithString(errorString:));

+ (void) notifyWithString:(NSString*)errorString additionalData:(NSDictionary*)data
NS_SWIFT_NAME(notifyWithString(errorString:additionalData:));

+ (void) notifyWithError:(NSError*)error
NS_SWIFT_NAME(notifyWithError(error:));

+ (void) notifyWithError:(NSError*)error additionalData:(NSDictionary*)data
NS_SWIFT_NAME(notifyWithError(error:additionalData:));

+ (void) setContext:(NSDictionary*)context
NS_SWIFT_NAME(setContext(context:));

+ (void) resetContext:(NSDictionary*)context
NS_SWIFT_NAME(resetContext(context:));

@end


NS_ASSUME_NONNULL_END
