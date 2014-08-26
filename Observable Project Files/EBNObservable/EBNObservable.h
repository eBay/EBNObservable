/****************************************************************************************************
	EBNObservable.h
	Observable
	
	Created by Chall Fry on 8/18/13.
    Copyright (c) 2013-2014 eBay Software Foundation.
	
*/

#import <objc/runtime.h>
#import "EBNObservation.h"

	// This macro makes it easier to make self the observer of the given keypath rooted at the given
	// observed object. This macro tries to validate at compile time that:
	//		1. The key path is in fact a valid path from observedObj.
	//		2. The block doesn't directly access self or observedObj--either of which cause a retain loop.
	//
	// Note that the property trick doesn't work for properties that have custom getters--use the
	// NoPropCheck variant in that case.
#define ObserveProperty(observedObj, keyPath, blockContents) \
({\
	__typeof__(observedObj) __internalObserved = observedObj; \
	if (0) \
	{ \
		__attribute__((unused)) __typeof__(__internalObserved.keyPath) _EBNNotUsed = __internalObserved.keyPath; \
	} \
	EBNObservation *_blockInfo = NewObservationBlock(__internalObserved, blockContents); \
	[_blockInfo observe:EBNStringify(keyPath)]; \
	_blockInfo; \
})

	// Similar to above, but it doesn't perform the compile time checks on the keyPath. Useful for when
	// the above macro fails on a keyPath you know is valid.
#define ObservePropertyNoPropCheck(observedObj, keyPath, blockContents) \
({\
	EBNObservation *_blockInfo = NewObservationBlock(observedObj, blockContents);\
	[_blockInfo observe:EBNStringify(keyPath)];\
	_blockInfo; \
})

	// These macros wrap the stopTelling: calls, and do the same sort of property checks as
	// the ObserveProperty macros. Only usable when 'self' is the observer, which is the common case.
#define StopObservingPath(observedObj, keyPath) \
({\
	__typeof__(observedObj) __internalObserved = observedObj; \
	if (0) \
	{ \
		__attribute__((unused)) __typeof__(__internalObserved.keyPath) _EBNNotUsed = __internalObserved.keyPath; \
	} \
	[__internalObserved stopTelling:self aboutChangesTo:EBNStringify(keyPath)]; \
})

#define StopObserving(observedObj) \
({\
	__typeof__(observedObj) __internalObserved = observedObj; \
	[__internalObserved stopTellingAboutChanges:self]; \
})


	// A macro for debugging. Allows you to set a breakpoint on a property, and get notified when
	// that property gets set. Therefore, it works sort of like a watchpoint, but without the slowness.
	// To use, type "po DebugBreakOnChange(object, @"propertyName")" in the debugger, or
	// add a DebugBreakOnChange() to your code.
#define DebugBreakOnChange(observedObj, keyPath) \
({\
	[observedObj debugBreakOnChange:keyPath line:__LINE__ file:__FILE__ func:__PRETTY_FUNCTION__]; \
})



#if defined(__cplusplus) || defined(c_plusplus)
	extern "C" {
#endif


@interface EBNObservable : NSObject

- (id) init __attribute__((objc_designated_initializer));

	// These methods add observer blocks to properties of an Observable
- (EBNObservation *) tell:(id) observer when:(NSString *) propertyName changes:(ObservationBlock) callBlock;
- (EBNObservation *) tell:(id) observer whenAny:(NSArray *) propertyList changes:(ObservationBlock) callBlock;

	// And these remove the observations
- (void) stopTellingAboutChanges:(id) observer;
- (void) stopTelling:(id) observer aboutChangesTo:(NSString *) propertyName;
- (void) stopTelling:(id) observer aboutChangesToArray:(NSArray *) propertyList;
- (void) stopAllCallsTo:(ObservationBlock) block;

// Methods for subclasess

	// Intended to be overridden by subclasses. Lets you know when you are being watched
- (void) property:(NSString *) propName observationStateIs:(BOOL) isBeingObserved;

	// Returns all properties currently being observed, as an array of strings.
- (NSArray *) allObservedProperties;

	// Returns how many observers there are for the given property
- (NSUInteger) numberOfObservers:(NSString *) propertyName;

	// For manually triggering observers. EBNObervable subclasses can use this if they
	// have to set property ivars directly, but still want observers to get called.
	// The observers still get called at the *end* of the event, not within this call.
- (void) manuallyTriggerObserversForProperty:(NSString *) propertyName previousValue:(id) prevValue;
- (void) manuallyTriggerObserversForProperty:(NSString *) propertyName previousValue:(id) prevValue newValue:(id) newValue;

@end


@interface EBNObservable (Debugging)

	// Use this in the debugger: "po [<modelObject> debugShowAllObservers]"
- (NSString *) debugShowAllObservers;

- (NSString *) debugBreakOnChange:(NSString *) keyPath;
- (NSString *) debugBreakOnChange:(NSString *) keyPath line:(int) lineNum file:(const char *) filePath
		func:(const char *) func;

@end


	// Observers can implmenent this, but it's not required.
@protocol ObservedObjectDeallocProtocol <NSObject>

@required
	// This method gets called from *inside* dealloc, and the object is probably partially destroyed!
	// Do not attempt to look inside the passed-in object!
- (void) observedObjectHasBeenDealloced:(id) object endingObservation:(NSString *) keypathStr;
@end



#if defined(__cplusplus) || defined(c_plusplus)
	}
#endif
