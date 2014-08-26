/****************************************************************************************************
	EBNObservableInternal.h
	Observable
	
	Created by Chall Fry on 5/3/14.
    Copyright (c) 2013-2014 eBay Software Foundation.
	
	This header is intended for use only within EBNObservable and friends. 
	Client code shouldn't need it; this includes EBNObservable subclasses.
*/


#import "EBNObservable.h"

// The observedMethod dictionary has a NSMutableSet of these objects attached to each
// property being observed. This structure describes a single keypath that someone is
// observing. Each object in the observation path has this object in the dictionary for
// the property of that object being observed.
@interface EBNKeypathEntryInfo : NSObject
{
@public
	NSArray		 			*keyPath;
	EBNObservation			*blockInfo;
}
@end


@protocol EBNObservableProtocol <NSObject>

	// These methods add observer blocks to properties of an Observable
- (EBNObservation *) tell:(id) observer when:(NSString *) propertyName changes:(ObservationBlock) callBlock;
- (EBNObservation *) tell:(id) observer whenAny:(NSArray *) propertyList changes:(ObservationBlock) callBlock;

	// And these remove the observations
- (void) stopTellingAboutChanges:(id) observer;
- (void) stopTelling:(id) observer aboutChangesTo:(NSString *) propertyName;
- (void) stopTelling:(id) observer aboutChangesToArray:(NSArray *) propertyList;
- (void) stopAllCallsTo:(ObservationBlock) block;

	// Use this in the debugger: "po [<modelObject> debugShowAllObservers]"
- (NSString *) debugShowAllObservers;

	// Intended to be overridden by subclasses. Lets you know when you are being watched
- (void) property:(NSString *) propName observationStateIs:(BOOL) isBeingObserved;

	// Returns all properties currently being observed, as an array of strings.
- (NSArray *) allObservedProperties;

	// Returns how many observers there are for the given property
- (NSUInteger) numberOfObservers:(NSString *) propertyName;

- (id) valueForKeyEBN:(NSString *) key;

	// For manually triggering observers. EBNObervable subclasses can use this if they
	// have to set property ivars directly, but still want observers to get called.
	// The observers still get called at the *end* of the event, not within this call.
- (void) manuallyTriggerObserversForProperty:(NSString *) propertyName previousValue:(id) prevValue;

- (bool) createKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index;
- (bool) removeKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index;
- (bool) createKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
		forProperty:(NSString *) propName;
- (bool) removeKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
		forProperty:(NSString *) propName;

	// EBNObservation calls these internally, in its own calls to set up observations.
- (bool) observe:(NSString *) keyPathString using:(EBNObservation *) blockInfo;

	// The Execute methods in EBNObservation can cause reaping.
- (int) reapBlocks;

@end


@interface EBNObservable () <EBNObservableProtocol>
{
@public
	// observedMethods maps properties (specified by the setter method name, as a string) to
	// a NSMutableSet of blocks to be called when the property changes.
	NSMutableDictionary *observedMethods;
}

	// Don't call this unless you have a good reason.
+ (bool) swizzleImplementationForSetter:(NSString *) propName;
+ (SEL) selectorForPropertyGetter:(NSString *) propertyName;

@end

@interface EBNObservable (debugging) <EBNObservableProtocol>
@end

// This describes a single observation block. There is one of these for each observationBlock,
// and much of the coalescing that takes place is actually unioning sets of these objects.
// Note that this object does *not* know the keypath(s) that it's observing.
@interface EBNObservation ()
{

// @public doesn't mean public to you--just to EBNObservable.
@public
	EBNObservable * __weak 	weakObserved;
	id __weak 				weakObserver;
	ObservationBlock 		copiedBlock;
	ObservationBlockImmed	copiedImmedBlock;
}
@end


	// A private protocol, just for LazyLoader
@protocol EBNPropertyValidityProtocol <NSObject>
- (void) markPropertyValid:(NSString *) property;
@end




/****************************************************************************************************
	DEBUG_BREAKPOINT
	
	This is inline ASM code to programmatically break in the debugger at a specific point. Intended
	to be used with Apple's AmIBeingDebugged() method. Works on ARM and x86 processors, and their 64
	bit variants.
	
	DO NOT use this macro in your code to try debugging something. You'll forget, leave it there,
	and then your code will ship with a debugger break in it and will crash for no reason for your users.
	
	At some point, years from now, someone is going to have to have to extend this to a new target CPU type.
	Sorry.
*/
#if TARGET_CPU_ARM
	#define DEBUG_BREAKPOINT \
	({ \
		__asm__ __volatile__ ( \
				"mov r0, %0\n" \
				"mov r1, %1\n" \
				"mov r12, #37\n" \
				"svc 128\n" \
				: : "r" (getpid ()), "r" (SIGINT) : "r12", "r0", "r1", "cc"); \
	})
#elif TARGET_CPU_ARM64
	#define DEBUG_BREAKPOINT \
	({ \
		__asm__ __volatile__ ( \
				"mov x0, %0\n" \
				"mov x1, %1\n" \
				"mov x12, #37\n" \
				"svc 128\n" \
				: : "r" ((long) getpid ()), "r" ((long) SIGINT) : "x12", "x0", "x1", "cc"); \
	})
#elif TARGET_CPU_X86
	#define DEBUG_BREAKPOINT \
	({ \
		__asm__ __volatile__ ( \
				"pushl %0\n" \
				"pushl %1\n" \
				"push $0\n" \
				"movl %2, %%eax\n" \
				"int $0x80\n" \
				"add $12, %%esp" \
				: : "g" (SIGINT), "g" (getpid ()), "n" (37) : "eax", "cc"); \
	})
#elif TARGET_CPU_X86_64
	#define DEBUG_BREAKPOINT \
	({ \
		__asm__ __volatile__ ( \
				"int $3" \
				: : : "cc"); \
	})
#else
	// Can't break. Unknown cpu target.
	#define DEBUG_BREAKPOINT
#endif


