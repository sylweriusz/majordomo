#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift cannot catch Objective-C exceptions, yet some Apple APIs (notably
/// AVAudioEngine) report failures by raising them. An exception that unwinds
/// through a Swift async frame skips the concurrency runtime's cleanup and
/// leaves the thread's executor-tracking state dangling, so the next
/// `MainActor.assumeIsolated` on that thread segfaults.
@interface MJDObjCException : NSObject

/// Runs `block`. An NSException raised inside is returned as an NSError
/// (domain = exception name, description = reason) instead of propagating.
+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
