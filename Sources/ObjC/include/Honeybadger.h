#pragma once


#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN


@interface Honeybadger : NSObject

- (id) init NS_UNAVAILABLE;

// CONFIG ------------------------------------------------------------------

+ (void) configureWithAPIKey:(NSString*)apiKey
NS_SWIFT_NAME(configure(apiKey:));

+ (void) configureWithAPIKey:(NSString*)apiKey fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(configure(apiKey:fingerprint:));

+ (void) configureWithAPIKey:(NSString*)apiKey environment:(NSString*)environment
NS_SWIFT_NAME(configure(apiKey:environment:));

+ (void) configureWithAPIKey:(NSString*)apiKey environment:(NSString*)environment fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(configure(apiKey:environment:fingerprint:));

// NOTIFY ------------------------------------------------------------------

+ (void) notifyWithString:(NSString*)errorString
NS_SWIFT_NAME(notify(errorString:));

+ (void) notifyWithString:(NSString*)errorString errorClass:(NSString*)errorClass
NS_SWIFT_NAME(notify(errorString:errorClass:));

+ (void) notifyWithString:(NSString*)errorString context:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(notify(errorString:context:));

+ (void) notifyWithString:(NSString*)errorString errorClass:(NSString*)errorClass context:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(notify(errorString:errorClass:context:));

+ (void) notifyWithError:(NSError*)error
NS_SWIFT_NAME(notify(error:));

+ (void) notifyWithError:(NSError*)error errorClass:(NSString*)errorClass
NS_SWIFT_NAME(notify(error:errorClass:));

+ (void) notifyWithError:(NSError*)error errorClass:(NSString*)errorClass context:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(notify(error:errorClass:context:));

// CONTEXT -----------------------------------------------------------------

+ (void) setContext:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(setContext(context:));

+ (void) resetContext:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(resetContext(context:));

@end


NS_ASSUME_NONNULL_END
