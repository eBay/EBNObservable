/****************************************************************************************************
	EBNObservable.h
	Observable
	
	Created by Chall Fry on 8/18/13.
    Copyright (c) 2013-2018 eBay Software Foundation.
	
*/

#import <objc/runtime.h>
#import "EBNObservation.h"
#import "NSSet+EBNObservable.h"

/**
	This macro makes it easier to make self the observer of the given keypath rooted at the given
	observed object. This macro tries to validate at compile time that:
			1. The key path is in fact a valid path from observedObj.
			2. The block doesn't directly access self or observedObj--either of which cause a retain loop.
	
	Note that the property trick doesn't work for properties that have custom getters--use the
	NoPropCheck variant in that case.
	
	DEBUG NOTE: An unfortuante side effect of this macro is that debug breakpoints don't work inside the 
	block, as LLDB can't set breakpoints inside macro expansions. If you need to set a breakpoint inside
	the callback block, it's best to use the plain method call instead.

	@param observedObj   The object at the root of the observation.
	@param keyPath       A '.' separated string describing a path to observe, where the path is a sequence of properties.
			Cannot be empty or nil. Can be a single property name.
	@param blockContents The contents of a block to be run in response to changes to the value in keyPath. Does not

	@return Returns a EBNObservation object describing the newly-created observation.
*/
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


/**
	This macro makes it easier to make self the observer of the given keypath rooted at the given
	observed object. This macro tries to validate at compile time that:
			1. The block doesn't directly access self or observedObj--either of which cause a retain loop.
	
	You should only use this method for cases where the ObserveProperty macro complains about your keyPath;
	a situation usually caused by non-property methods in the keypath. The keypath works in such a case, but
	can't be validated a compile time. The danger of using this method is that a future change to a property
	in the keypath won't be caught at compile time.

	@param observedObj   The object at the root of the observation.
	@param keyPath       A '.' separated string describing a path to observe, where the path is a sequence of properties.
						 Cannot be empty or nil.
	@param blockContents The contents of a block to be run in response to changes to the value in keyPath. Does not

	@return Returns a EBNObservation object describing the newly-created observation.
 */
#define ObservePropertyNoPropCheck(observedObj, keyPath, blockContents) \
({\
	EBNObservation *_blockInfo = NewObservationBlock(observedObj, blockContents);\
	[_blockInfo observe:EBNStringify(keyPath)];\
	_blockInfo; \
})

/**
	Meant to be used in concert with the Observe macro and the ObserveDebug function, with a syntax like this:
	
	Observe(ValidatePaths(observedObj, keypathList, ...) { blockContents });
	
	Note that there is no comma after the ValidatePaths macro.
	
	This macro, along with Observe, is designed for easy switching between 'safe' mode where the contents 
	of the observation block are checked for references to self, and 'debug' mode where breakpoints can be 
	set in the block contents.
	
	If the only keypaths you want to observe will not pass validation (for example, keypaths containing a '*'
	wildcard), you can leave the keypathList blank and add them later by saving the result of the Observe macro
	and calling - observe: on it.
	
	@param observedObj   	The object at the root of the observation.
	@param keypathList		A comma separated list of keypaths to observe. See description of ValidatePaths.
							May be empty, although you must add keypaths later to actually observe anything.

	@return Returns 4 comma-separated values, not meant for direct consumption. This macro is meant to be
	composed into either Observe or ObserveDebug.
*/
#define ValidatePaths(observedObj, ...) \
	( self ) , \
	( observedObj ) , \
({\
	__attribute__((unused)) __typeof__(observedObj) __internalObserved = observedObj;\
	EBNValidatePathsInternal(__VA_ARGS__)(__VA_ARGS__) \
	@[EBNStringifyArgs(__VA_ARGS__)(__VA_ARGS__)]; \
}), ^(__typeof__(self) blockSelf, __typeof__(observedObj) observed)

/**
	Meant to be used in concert with the Observe macro and the ObserveDebug function, with a syntax like this:

	Observe(ValidateObserverPaths(observerObj, observedObj, keypathList, ...) { blockContents });
	
	This is similar to ValidatePaths, but lets you declare that the observer object isn't self.

	Note that there is no comma after the ValidateObserverPaths macro.
	
	This macro, along with Observe, is designed for easy switching between 'safe' mode where the contents 
	of the observation block are checked for references to self, and 'debug' mode where breakpoints can be 
	set in the block contents.
	
	If the only keypaths you want to observe will not pass validation (for example, keypaths containing a '*'
	wildcard), you can leave the keypathList blank and add them later by saving the result of the Observe macro
	and calling - observe: on it.
	
	@param observerObj   	The object doing the observing.
	@param observedObj   	The object at the root of the observation.
	@param keypathList		A comma separated list of keypaths to observe. See description of ValidatePaths.
							May be empty, although you must add keypaths later to actually observe anything.

	@return Returns 4 comma-separated values, not meant for direct consumption. This macro is meant to be
	composed into either Observe or ObserveDebug.
*/
#define ValidateObserverPaths(observerObj, observedObj, ...) \
	( observerObj ) , \
	( observedObj ) , \
({\
	__attribute__((unused)) __typeof__(observedObj) __internalObserved = observedObj;\
	EBNValidatePathsInternal(__VA_ARGS__)(__VA_ARGS__) \
	@[EBNStringifyArgs(__VA_ARGS__)(__VA_ARGS__)]; \
}), ^(__typeof__(observerObj) observer, __typeof__(observedObj) observed)



/**
	Meant to be used in concert with ValidatePaths, with a syntax like this:
	
	Observe(ValidatePaths(observedObj, keypathList, ...) { blockContents });
	
	Note that there is no comma after the ValidatePaths macro.
	
	This macro is designed for easy switching between 'safe' mode where the contents of the observation block
	are checked for references to self, and 'debug' mode where breakpoints can be set in the block contents.
	
	To switch, change the name from "Observe" to "ObserveDebug". ObserveDebug is actually a function, defined in 
	EBNObservation.m.
	
	@param observedObj   	The object at the root of the observation.
	@param keypathList		A comma separated list of keypaths to observe. See description of ValidatePaths.
							May be empty, although you must add keypaths later to actually observe anything.
	@param blockContents 	The contents of a block to be run in response to changes to the value in keyPath. Does not

	@return Returns a EBNObservation object describing the newly-created observation.
*/
#define Observe(paramBundle) \
({\
	EBNINTERNAL_ArgumentExpander(paramBundle) \
	EBNValidateObservationBlock(__internalObserver, __internalObserved2, EBNINTERNAL_Indirector(EBNINTERNAL_ArgumentDestructor_ ## paramBundle)); \
	EBNObservation *__internalObservation = [[EBNObservation alloc] initForObserved:__internalObserved2 observer:__internalObserver \
			block:__internalBlock]; \
	[__internalObservation observeMultiple:__internalKeypathArray]; \
	__internalObservation; \
})

/**
	Validates the keypath strings in the argument list are valid keypaths when evaluated from rootObject.
	For a keypath of "a.b.c", rootObject must have a property of "a", which must in turn have a property "b".
	What it actually does internally is to declare unused variables for each keypath--that is it makes a variable
	equal to rootObject.a.b.c, and sees if it compiles.
*/
#define EBNValidatePaths(rootObject, ...) \
({ \
	__attribute__((unused)) __typeof__(rootObject) __internalObserved = rootObject; \
	EBNValidatePathsInternal(__VA_ARGS__)(__VA_ARGS__) \
	EBNStringifyArgs(__VA_ARGS__)(__VA_ARGS__); \
})

/**
	This macro wraps the stopTelling:aboutChangesTo: method, performing the same sort of checks on the 
	keypath that the ObserveProperty macro does. Only usable when 'self' is the observer, which is the common case.

	@param observedObj Object at the root of the observation--the object you passed in to ObserveProperty or
						one of the tell: methods
	@param keyPath     The keypath to stop observing.

	@return void
 */
#define StopObservingPath(observedObj, keyPath) \
({\
	__typeof__(observedObj) __internalObserved = observedObj; \
	if (0) \
	{ \
		__attribute__((unused)) __typeof__(__internalObserved.keyPath) _EBNNotUsed = __internalObserved.keyPath; \
	} \
	[__internalObserved stopTelling:self aboutChangesTo:EBNStringify(keyPath)]; \
})

/**
	This macro wraps the stopTellingAboutChanges: method. Only usable when 'self' is the observer, which is the common case.

	@param observedObj Object at the root of the observation--the object you passed in to ObserveProperty or
					   one of the tell: methods

	@return void
 */
#define StopObserving(observedObj) \
({\
	if ([observedObj isKindOfClass:[NSObject class]]) \
	{ \
		NSObject *__internalObserved = (NSObject *) observedObj; \
		[__internalObserved stopTellingAboutChanges:self]; \
	} \
})

/**
	A macro for debugging. Allows you to set a breakpoint on a property, and get notified when
	that property *of that object* gets set. Therefore, it works sort of like a watchpoint, but without the slowness.
	To use, add something like the following to your code:
	
		DebugBreakOnChange(object, @"propertyName")

	@param observedObj The object to observe.
	@param keyPath     A keypath.

	@return void
 */
#define DebugBreakOnChange(observedObj, keyPath) \
({\
	[observedObj debugBreakOnChange:keyPath line:__LINE__ file:__FILE__ func:__PRETTY_FUNCTION__]; \
})



#if defined(__cplusplus) || defined(c_plusplus)
	extern "C" {
#endif

@interface NSObject (EBNObservable)

/**
	Creates a new observation. Receiver should be the object being observed. In the common case where the caller
	is the observer (the object receiving notifications of changes), you should use the form [observedObject, tell:self ...].
	
	Remember that the callBlock won't get called until the end of the event in which a change occurred, multiple changes
	occurring in the same event get coalesced into one callback, and the callBlock always gets called on the main thread,
	even if the value of properties in the keypath were changed in a different thread. See documentation.

	@param observer  The object that should receive change notifications. Cannot be nil.
	@param keyPath   A period separated string of property names, specifying a series of properties starting from the receiver
	@param callBlock A block that gets called when the value changes.

	@return An EBNObservation object describing the created observation.
*/
- (nullable EBNObservation *) tell:(nonnull id) observer when:(nonnull NSString *) keyPath
		changes:(nonnull ObservationBlock) callBlock;

/**
	Creates a new observation. Receiver should be the object being observed. In the common case where the caller
	is the observer (the object receiving notifications of changes), you should use the form [observedObject, tell:self ...].
	
	In this variant, the callBlock will get call when the values in ANY of the key paths in the array change. Your callBlock
	is also not notified which value it was that triggered the call; due to coalescing, it's possible that multiple values 
	have changed.
	
	Remember that the callBlock won't get called until the end of the event in which a change occurred, multiple changes
	occurring in the same event get coalesced into one callback, and the callBlock always gets called on the main thread,
	even if the value of properties in the keypath were changed in a different thread. See documentation.


	@param observer  The object that should receive change notifications. Cannot be nil.
	@param propertyList  An array of keyPaths, where each key path is a period separated string of property names,
			specifying a series of properties starting from the receiver
	@param callBlock A block that gets called when the value changes.

	@return An EBNObservation object describing the created observation.
*/
- (nullable EBNObservation *) tell:(nonnull id) observer whenAny:(nonnull NSArray<NSString *> *) propertyList
		changes:(nonnull ObservationBlock) callBlock;

/**
	The receiver will iterate through all observations rooted on self, and remove any observations whose observer
	object is equal to observer.

	@param observer The object that registered as an observer in a tell: method
*/
- (void) stopTellingAboutChanges:(nonnull id) observer;

/**
	The receiver iterates through all observations rooted on self and active on the given keyPath, 
	removing any observations whose observer object is equal to observer.

	@param observer     The object that (presumably) registered as an observer in a tell: method.
	@param keyPath 		The keypath to remove observations from.
*/
- (void) stopTelling:(nonnull id) observer aboutChangesTo:(nonnull NSString *) keyPath;

/**
	Calls stopTelling:aboutChangesTo: for each item in the pathList array.

	@param observer The object that had been doing the observing
	@param pathList An array of keypath strings.
*/
- (void) stopTelling:(nonnull id) observer aboutChangesToArray:(nonnull NSArray<NSString *> *) pathList;

/**
	The receiver iterates through all observations rooted on self, and will remove any observations whose
	ObservationBlock is equal to block.

	@param block A block that (presumably) had been earlier passed into a tell: method on this object
*/
- (void) stopAllCallsTo:(nullable ObservationBlock) block;

/**
	Returns all properties currently being observed on the receiver, as an array of strings.

	@return an array of strings
 */
- (nullable NSArray<NSString *> *) allObservedProperties;

/**
	Returns how many observers there are for the given property

	@param propertyName A property of the receiver

	@return The number of observers of that property
 */
- (NSUInteger) numberOfObservers:(nonnull NSString *) propertyName;


/**
	Triggers observers, lazyloading evaluation, keypath updating, and other upkeep on the property at the
	END of the path	as if that property's setter had been called.
	
	If any value in the keyPath besides the last is nil, does nothing.
*/
- (void) ebn_manuallyTriggerObserversForPath:(nonnull NSString *) keyPath previousValue:(nullable id) prevValue;

/**
	Triggers observers, lazyloading evaluation, keypath updating, and other upkeep on the property at the
	END of the path	as if that property's setter had been called.
	
	If any value in the keyPath besides the last is nil, does nothing.
	
	Functionally, this method walks the values in the keypath to get to the terminal property, and then
	calls manuallyTriggerObserversForProperty: on that property.
*/
- (void) ebn_manuallyTriggerObserversForPath:(nonnull NSString *) keyPath previousValue:(nullable id) prevValue
		newValue:(nullable id) newValue;

/**
	For manually triggering observers. EBNObervable subclasses can use this if they
	have to set property ivars directly, but still want observers to get called.
	The observers still get called at the *end* of the event, not within this call.
	
	Call this method after the property value is updated. 
	
	You need to pass in the previous value to ensure that we can clean up keypaths that went through the old value
	of the object. This is only really relevant for properties with an object-type value, but really: just pass in
	the old value of the property.
	
	You do not need to call this inside of a custom setter method in order to get observations to happen
	in response to changes to the property being set.

	@param propertyName The property that changed value
	@param prevValue    The value the property had before the change.
 */
- (void) ebn_manuallyTriggerObserversForProperty:(nonnull NSString *) propertyName previousValue:(nullable id) prevValue;

/**
	For manually triggering observers. EBNObervable subclasses can use this if they
	have to set property ivars directly, but still want observers to get called.
	The observers still get called at the *end* of the event, not within this call.
	
	Call this method after the property value is updated. 
	
	You need to pass in the previous value to ensure that we can clean up keypaths that went through the old value
	of the object. This is only really relevant for properties with an object-type value, but really: just pass in
	the old value of the property.
	
	You do not need to call this inside of a custom setter method in order to get observations to happen
	in response to changes to the property being set.

	@param propertyName The property that changed value
	@param prevValue    The value the property had before the change.
 */
- (void) ebn_manuallyTriggerObserversForProperty:(nonnull NSString *) propertyName previousValue:(nullable id) prevValue
		newValue:(nullable id) newValue;

/**
	Attempts to get the actual base class for a given class, before runtime subclassing. This is a bug workaround
	for a case where Apple's KVO subclasses an Observable subclass. Generally you can use [self class] and
	get the baseclass, but if Apple's KVO subclasses our (or anyone else's) runtime subclass, KVO does the 
	wrong thing and returns its immediate super, not the 'base' class the object had before any runtime
	subclass hackery.
	
	The result is what [self class] should return for instances of this class, but doesn't in the case where 
	Apple's KVO subclasses an Observable subclass. 

	@return The base class--the class that's at the root of any runtime subclassing
 */
+ (nonnull Class) ebn_properBaseClass;

@end

@interface NSObject (EBNObservableDebugging)

/**
	Use this in the debugger: 
	
		po [<modelObject> debugShowAllObservers]

	@return A debug string with info about all observations active on the receiver.
*/
- (nonnull NSString *) debugShowAllObservers;

/**
	This can be used in the LLDB debugger to force a debug break when the value in the given keypath
	(rooted at the receiver) changes. Use:
	
		po [<modelObject> debugBreakOnChange:@"keypath"]
		
	This acts something like a watchpoint, only without the slowness. It differs from setting a breakpoint
	on the setter in that it is only tripped when the receiver changes state (or the value at the end of the keypath
	rooted at the receiver changes state). Other objects of the same class don't trigger the breakpoint.
	
	Also, if objects in the middle of the keypath change value while the program is running, the watchpoint 
	updates dynamically.
	
	This method can also be compiled into the program, but if the running program is not being debugged it 
	will not do anything, as the program would crash if it tried to cause a debugger break.

	@param keyPath A key path to observe

	@return A string describing what the method did. When used in lldb, this string will be printed to the console.
*/
- (nonnull NSString *) debugBreakOnChange:(nonnull NSString *) keyPath;

/**
	This can be used to cause a debugger break to occur when the value of the given keypath changes.
 
	This acts something like a watchpoint, only without the slowness. It differs from setting a breakpoint
	on the setter in that it is only tripped when the receiver changes state (or the value at the end of the keypath
	rooted at the receiver changes state). Other objects of the same class don't trigger the breakpoint.
	
	Also, if objects in the middle of the keypath change value while the program is running, the watchpoint 
	updates dynamically.
	
	This method can also be compiled into the program, but if the running program is not being debugged it 
	will not do anything, as the program would crash if it tried to cause a debugger break.
	
	The recommend way to use this method is via the macro that calls it. This will automatically fill in 
	the file and line number information:
	
		DebugBreakOnChange(<observedObject>, @"keypath");

	@param keyPath A key path to observe

	@return A string describing what the method did. When used in lldb, this string will be printed to the console.
*/
- (nonnull NSString *) debugBreakOnChange:(nonnull NSString *) keyPath line:(int) lineNum file:(nullable const char *) filePath
		func:(nullable const char *) func;

@end

/**
	A protocol that objects can implement to get notified when their properties get observed.
*/
@protocol EBNObserverNotificationProtocol

/**
	Lets an observed object know when one of its properties starts/stops being observed. 
	Not called when the number of observations changes (except when that number is to/from 0).
	
	This method will get called when the receiver is in the middle of a keypath (that is, the keypath that's
	being observed is rooted in some other object).

	@param propName        The name of the property whose observation state changed.
	@param isBeingObserved TRUE if the property is now being observed
*/
- (void) property:(nonnull NSString *) propName observationStateIs:(BOOL) isBeingObserved;

@end


/**
	Observers can implement this protocol to get notified if an object they're observing gets deallocated
	while they're observing it. 
	
	Example: Your ViewController observes a property of a model object with ObserveProperty(modelObject, @"SomeProperty"...).
	Later, modelObject is deallocated, which can happen while you're observing on it--observation does not retain
	the observed or observing objects, see docs. If your ViewController implements this protocol, you'll get notified of
	the deallocation.
*/
@protocol ObservedObjectDeallocProtocol <NSObject>

/**
	This method gets called from *inside* dealloc, and the object is probably partially destroyed!
	Do not attempt to look inside the passed-in object!

	@param object     The object that's being dealloc'ed. This will always be the root of a keypath for some
					  observation that you were doing at the time of dealloc.
	@param keypathStr The keypath for the observation
*/
@required
- (void) observedObjectHasBeenDealloced:(nonnull id) object endingObservation:(nonnull NSString *) keypathStr;

@end




#pragma mark - Insanity Hole

// Just don't look at the stuff below this line. You'll lose sanity. This stuff is used for validating that
// keypaths are valid property chains of their root objects, and isn't designed for direct use.
/*********************************************************************************************/

/**
	A macro that returns nothing.
	
	Used to erase the ValidatePaths() from the paramsBundle as part of the execute of the Observe macro,
	leaving only the observation block.

	Do not use.
*/
#define EBNINTERNAL_ArgumentExpander(observerObj, observedObj, keypathArray, block) \
	_Pragma("clang diagnostic push") \
	_Pragma("clang diagnostic ignored \"-Wshadow\"") \
	__typeof__(observerObj) __internalObserver = observerObj; \
	__typeof__(observedObj) __internalObserved2 = observedObj; \
	NSArray *__internalKeypathArray = keypathArray; \
	ObservationBlock __internalBlock = block; \
	_Pragma("clang diagnostic pop");

/**
	A macro that returns nothing.
	
	Used to erase the ValidatePaths() from the paramsBundle as part of the execute of the Observe macro,
	leaving only the observation block.
	
	Do not use.
*/
#define EBNINTERNAL_ArgumentDestructor_ValidatePaths(observedObj, ...)
#define EBNINTERNAL_ArgumentDestructor_ValidateObserverPaths(observedObj, ...)

/**
	An internal macro that returns its argument.
	
	Used for certain kinds of token-pasting operations, where we token-paste two names together to form a
	macro name, and then want to execute that macro.
	
	Do not use.
*/
#define EBNINTERNAL_Indirector(x) x


#define ValidatePath(pathName) \
	if (0) \
	{ \
		__attribute__((unused)) __typeof__(__internalObserved.pathName) _EBNNotUsed = __internalObserved.pathName; \
	}
	

	// This mess of macros is how we handle iterating the va_args that SyntheticProperty takes into
	// individual path calls. Each one checks the first path, and sends the rest to the n-1 version.
#define ValidatePath0(pathName)
#define ValidatePath1(pathName) ValidatePath(pathName)
#define ValidatePath2(pathName, ...) ValidatePath(pathName) ValidatePath1(__VA_ARGS__)
#define ValidatePath3(pathName, ...) ValidatePath(pathName) ValidatePath2(__VA_ARGS__)
#define ValidatePath4(pathName, ...) ValidatePath(pathName) ValidatePath3(__VA_ARGS__)
#define ValidatePath5(pathName, ...) ValidatePath(pathName) ValidatePath4(__VA_ARGS__)
#define ValidatePath6(pathName, ...) ValidatePath(pathName) ValidatePath5(__VA_ARGS__)
#define ValidatePath7(pathName, ...) ValidatePath(pathName) ValidatePath6(__VA_ARGS__)
#define ValidatePath8(pathName, ...) ValidatePath(pathName) ValidatePath7(__VA_ARGS__)
#define ValidatePath9(pathName, ...) ValidatePath(pathName) ValidatePath8(__VA_ARGS__)
#define ValidatePath10(pathName, ...) ValidatePath(pathName) ValidatePath9(__VA_ARGS__)
#define ValidatePath11(pathName, ...) ValidatePath(pathName) ValidatePath10(__VA_ARGS__)
#define ValidatePath12(pathName, ...) ValidatePath(pathName) ValidatePath11(__VA_ARGS__)
#define ValidatePath13(pathName, ...) _Pragma("GCC error \"The SyntheticProperty macro supports 12 dependent properties max. Use the syntheticProperty:dependsOn: methods instead.\"")

	// This is a trick to figure out which ValidatePath<#> to start with, based on
	// the number of arguments in varargs. Does not work with more then 12 arguments--
	// just use the syntheticProperty:dependsOnPaths: method in that case.
#define EBNValidatePathsInternal(...) EBNValidatePathsInternal_(,##__VA_ARGS__,13,12,11,10,9,8,7,6,5,4,3,2,1,0)
#define EBNValidatePathsInternal_(a,b,c,d,e,f,g,h,i,j,k,l,m,n,count,...) ValidatePath ## count



#define EBNStringifyArg(pathName) @#pathName
	
	// This mess of macros is how we handle iterating the va_args that SyntheticProperty takes into
	// individual path calls. Each one checks the first path, and sends the rest to the n-1 version.
#define EBNStringifyArgs0(pathName)
#define EBNStringifyArgs1(pathName) EBNStringifyArg(pathName)
#define EBNStringifyArgs2(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs1(__VA_ARGS__)
#define EBNStringifyArgs3(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs2(__VA_ARGS__)
#define EBNStringifyArgs4(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs3(__VA_ARGS__)
#define EBNStringifyArgs5(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs4(__VA_ARGS__)
#define EBNStringifyArgs6(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs5(__VA_ARGS__)
#define EBNStringifyArgs7(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs6(__VA_ARGS__)
#define EBNStringifyArgs8(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs7(__VA_ARGS__)
#define EBNStringifyArgs9(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs8(__VA_ARGS__)
#define EBNStringifyArgs10(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs9(__VA_ARGS__)
#define EBNStringifyArgs11(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs10(__VA_ARGS__)
#define EBNStringifyArgs12(pathName, ...) EBNStringifyArg(pathName), EBNStringifyArgs11(__VA_ARGS__)
#define EBNStringifyArgs13(pathName, ...) _Pragma("GCC error \"The SyntheticProperty macro supports 12 dependent properties max. Use the syntheticProperty:dependsOn: methods instead.\"")

	// This is a trick to figure out which EBNStringifyArgs<#> to start with, based on
	// the number of arguments in varargs. Does not work with more then 12 arguments.
#define EBNStringifyArgs(...) EBNStringifyArgs_(,##__VA_ARGS__,13,12,11,10,9,8,7,6,5,4,3,2,1,0)
#define EBNStringifyArgs_(a,b,c,d,e,f,g,h,i,j,k,l,m,n,count,...) EBNStringifyArgs ## count


#if defined(__cplusplus) || defined(c_plusplus)
	}
#endif

