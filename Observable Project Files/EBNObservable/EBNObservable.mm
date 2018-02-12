/****************************************************************************************************
	Observable.mm
	Observable

	Created by Chall Fry on 8/18/13.
    Copyright (c) 2013-2018 eBay Software Foundation.
*/

#import <sys/sysctl.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIGeometry.h>
#import <CoreGraphics/CGGeometry.h>

#import "EBNObservableInternal.h"


// EBNWrapValue is a set of very simple, overloaded functions that take values of C-native types that can be
// 'wrapped' into Objective C objects, usually NSNumber or NSValue. There's also a passthrough for values
// that are already of object type. This is used in a couple of places internally.
static inline id EBNWrapValue(const bool value) 			{ return [NSNumber numberWithBool:value]; }
static inline id EBNWrapValue(const char value) 			{ return [NSNumber numberWithChar:value]; }
static inline id EBNWrapValue(const double value) 			{ return [NSNumber numberWithDouble:value]; }
static inline id EBNWrapValue(const float value) 			{ return [NSNumber numberWithFloat:value]; }
static inline id EBNWrapValue(const int value) 				{ return [NSNumber numberWithInt:value]; }
static inline id EBNWrapValue(const long value) 			{ return [NSNumber numberWithLong:value]; }
static inline id EBNWrapValue(const long long value) 		{ return [NSNumber numberWithLongLong:value]; }
static inline id EBNWrapValue(const short value) 			{ return [NSNumber numberWithShort:value]; }
static inline id EBNWrapValue(const unsigned char value) 	{ return [NSNumber numberWithUnsignedChar:value]; }
static inline id EBNWrapValue(const unsigned int value) 	{ return [NSNumber numberWithUnsignedInt:value]; }
static inline id EBNWrapValue(const unsigned long value) 	{ return [NSNumber numberWithUnsignedLong:value]; }
static inline id EBNWrapValue(const unsigned long long value) { return [NSNumber numberWithUnsignedLongLong:value]; }
static inline id EBNWrapValue(const unsigned short value) 	{ return [NSNumber numberWithUnsignedShort:value]; }
static inline id EBNWrapValue(const void * value) 			{ return [NSValue valueWithPointer:value]; }
static inline id EBNWrapValue(const id value) 				{ return value; }
static inline id EBNWrapValue(const NSRange value)			{ return [NSValue valueWithRange:value]; }
static inline id EBNWrapValue(const CGPoint value)			{ return [NSValue valueWithCGPoint:value]; }
static inline id EBNWrapValue(const CGRect value)			{ return [NSValue valueWithCGRect:value]; }
static inline id EBNWrapValue(const CGSize value)			{ return [NSValue valueWithCGSize:value]; }
static inline id EBNWrapValue(const UIEdgeInsets value)		{ return [NSValue valueWithUIEdgeInsets:value]; }


/****************************************************************************************************
	getAndWrapProperty
	
	This C++ template function calls the given Objective-C getter method and then, if necessary,
	wraps the result into an Objective-C object. Used by ebn_valueForKey in order to help make a 
	valueForKey: method that throws fewer exceptions than Apple's.
*/
template<typename T> id getAndWrapProperty(id self, Method getterMethod, SEL getterSEL)
{
	T (*getterImplementation)(id, SEL) = (T (*)(id, SEL)) method_getImplementation(getterMethod);
	T getterResult = getterImplementation(self, getterSEL);
	id wrappedResult = EBNWrapValue(getterResult);
	return wrappedResult;
}

// When we create a shadowed subclass we'll add these functions as methods of the new subclass
static void EBNOverrideDeallocForClass(Class shadowClass);
static void ebn_shadowed_dealloc(__unsafe_unretained NSObject *self, SEL _cmd);
static Class ebn_shadowed_ClassForCoder(id self, SEL _cmd);

// This very special function gets template expanded into each type of property we know how to override.
// This creates a function for bool properties, one for int properties, one for Obj-C objects, etc.
template<typename T> void overrideSetterMethod(NSString *propName, Method setter, Method getter,
		EBNShadowedClassInfo *classInfo);

// This is the function that gets installed in the run loop to call all the observer blocks that have been scheduled.
extern "C"
{
	void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);
}

BOOL EBNComparePropertyAtIndex(NSInteger index, EBNKeypathEntryInfo *info, NSString *propName, id prevObject, id curObject);
template<typename T> inline BOOL EBNComparePropertyEquality(NSString *propName,
		NSInteger index, EBNKeypathEntryInfo *info, id prevObject, id curObject);


	// Keeping track of delayed blocks
NSMutableSet					*EBN_ObserverBlocksToRunAfterThisEvent;
NSMutableSet					*EBN_ObserverBlocksBeingDrained;
NSMutableArray					*EBN_ObservedObjectKeepAlive;
NSMutableArray 					*EBN_ObservedObjectBeingDrainedKeepAlive;

	// Shadow classes--private subclasses that we create to implement overriding setter methods
	// This dictionary holds EBNShadowedClassInfo objects, and is keyed with Class objects
NSMapTable						*EBNBaseClassToShadowInfoTable;

	// Not used for anything other than as a @synchronize token. Currently is a pointer alias to
	// EBN_ObserverBlocksToRunAfterThisEvent, but that could change.
NSMutableSet					*EBNObservableSynchronizationToken;

	// Returned by ebn_ValueForKey: when the receiver doesn't contain a property matching key.
NSObject						*EBN_InvalidPropertyKey;

#pragma mark -
/**
	EBNShadowedClassInfo is also pretty much just a data struct; but it has a convenience initializer.
	The purpose of these objects is to record the association between a class in the app (the 'base' class) 
	and a runtime-created subclass (the 'shadow' class), as well as all the methods we've overridden in the
	shadow class.
*/
@implementation EBNShadowedClassInfo

- (instancetype) initWithBaseClass:(Class) baseClass shadowClass:(Class) newShadowClass
{
	if (self = [super init])
	{
		_baseClass = baseClass;
		_shadowClass = newShadowClass;
		_getters = [[NSMutableOrderedSet alloc] init];
		_setters = [[NSMutableSet alloc] init];
		_validPropertyBitfieldSize = NSNotFound;		
	}
	return self;
}
@end

#pragma mark -
@implementation NSObject (EBNObservable)

#pragma mark Public API

/****************************************************************************************************
	tell:when:changes:
	
	Sets up KVO. When the given property is modified (specifically, its setter method is called),
	the given block will be called before the end of the current event on the main thread's runloop.
*/
- (EBNObservation *) tell:(id) observer when:(NSString *) keyPathString changes:(ObservationBlock) callBlock
{
	EBNObservation *blockInfo = [[EBNObservation alloc] initForObserved:self
			observer:observer block:callBlock] ;
	
	[self ebn_observe:keyPathString using:blockInfo];
	
	return blockInfo;
}

/****************************************************************************************************
	tell:whenAny:changes:
	
	Sets up KVO for a bunch of properties at once. A change to any property in the list will 
	cause the given block to be called. Multiple changes to properties during the processing
	of a single event in the main thread's runloop will be coalesced.
	
	The callBlock is always called on the main thread, at the end of event processing. Note that 
	changes to properties on another thread aren't guaranteed to be coalesced, but probably 
	will be.
*/
- (EBNObservation *) tell:(id) observer whenAny:(NSArray *) propertyList changes:(ObservationBlock) callBlock
{
	EBAssertContainerIsSolelyKindOfClass(propertyList, [NSString class]);
	
	EBNObservation *blockInfo = [[EBNObservation alloc] initForObserved:self
			observer:observer block:callBlock] ;

	for (NSString *keyPathString in propertyList)
	{
		[self ebn_observe:keyPathString using:blockInfo];
	}
	
	return blockInfo;
}

/****************************************************************************************************
	stopTelling:aboutChangesTo:
	
	Deregisters all observations that match the criteria:
		- Observed object matches receiver
		- Observer object matches observer parameter
		- keyPath being observed matches keypath parameter
	
	Usually this is one observation block, as this method is usally the 'remove one KVO observation' call.
	But there can be multiple blocks registered by the same observer to view the same keypath, and 
	deregistering observations is ALWAYS done by searching for observations that match criteria.
*/
- (void) stopTelling:(id) observer aboutChangesTo:(NSString *) keyPathStr
{
	NSArray *keyPath = [keyPathStr componentsSeparatedByString:@"."];
	NSString *propName = keyPath[0];
	NSMutableSet *entriesToRemove = [[NSMutableSet alloc] init];
	
	// Look for the case where we're removing 'object-following' array elements. This case
	// doesn't yet work well. Although we track the original array element that was observed and can find the
	// observation even if it has changed position in the array, this will match any observation that started
	// at that index. For example: Repeatedly insert an object into an array at index 0 and then create an observation
	// on it at "array.0". Array elements 0...n will then all have observations on them, with their original
	// observation keypath set to "array.0" but their current path equal to their current array position.
	// Calling this method to stop observing on "array.0" will remove all of those observations.
	for (NSString *pathEntry in keyPath)
	{
		if (isdigit([pathEntry characterAtIndex:0]))
		{
			EBLogContext(kLoggingContextOther, @"Ending observation on array elements where the observation is "
					@"referenced by the keypath doesn't work very well. Perhaps you should use one of the other stopTelling: "
					@"methods instead.");
		}
	}
	
	// Find all the entries to be removed
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (observedKeysDict)
	{
		@synchronized(observedKeysDict)
		{
			NSMutableArray *observations = observedKeysDict[propName];
			for (EBNKeypathEntryInfo *entry in observations)
			{
				if (entry->_blockInfo->_weakObserver_forComparisonOnly == observer &&
						entry->_keyPathIndex == 0 &&
						!entry->_blockInfo.isForLazyLoader &&
						[keyPath isEqualToArray:entry->_keyPath])
				{
					// We've found the right entry. Add it to the list to be removed.
					[entriesToRemove addObject:entry];
				}
			}
		}
	}
	
	// And then remove them
	for (EBNKeypathEntryInfo *entry in entriesToRemove)
	{
		[entry ebn_updateKeypathAtIndex:0 from:self to:nil];
	}
}

/****************************************************************************************************
	stopTelling:aboutChangesToArray:
	
	The companion method for tell:whenAny:changes:. Deregisters multiple observations at once.
	
	Deregisters all observations that match the criteria:
		- Observed object matches receiver
		- Observer object matches observer parameter
		- keyPath being observed matches any member of the propertyList parameter
	
	Deregistering observations is ALWAYS done by searching for observations that match criteria, and all
	observations that match the given criteria will be removed.
*/
- (void) stopTelling:(id) observer aboutChangesToArray:(NSArray *) keypathList
{
	for (NSString *keypath in keypathList)
	{
		[self stopTelling:observer aboutChangesTo:keypath];
	}
}

/****************************************************************************************************
	stopTellingAboutChanges:
	
	Deregisters all observations that match the criteria:
		- Observed object matches receiver
		- Observer object matches observer parameter
		
	This removes all observations for the observed-observer pair, no matter the keypath.
	
	Deregistering observations is ALWAYS done by searching for observations that match criteria, and all
	observations that match the given criteria will be removed.
*/
- (void) stopTellingAboutChanges:(id) observer
{
	int removedBlockCount = 0;
	NSMutableSet *entriesToRemove = [[NSMutableSet alloc] init];

	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (observedKeysDict)
	{
		@synchronized(observedKeysDict)
		{
			for (NSString *propertyKey in [observedKeysDict allKeys])
			{
				NSMutableArray *observers = observedKeysDict[propertyKey];
				
				for (EBNKeypathEntryInfo *entryInfo in observers)
				{
					// We're only looking for the blocks for which this is the observed object.
					if (entryInfo->_blockInfo->_weakObserver_forComparisonOnly == observer &&
							entryInfo->_keyPathIndex == 0 &&
							!entryInfo->_blockInfo.isForLazyLoader)
					{
						[entriesToRemove addObject:entryInfo];
						++removedBlockCount;
					}
				}
			}
		}
	}

	for (EBNKeypathEntryInfo *entryInfo in entriesToRemove)
	{
		[entryInfo ebn_updateKeypathAtIndex:0 from:self to:nil];
	}

	// Show warnings for odd results
	if (removedBlockCount == 0)
	{
		EBLogContext(kLoggingContextOther, @"When removing all observer blocks where %@ is observing %@: "
				@"Couldn't find any matching observer block. Were we not observering this?",
				[observer class], [self class]);
	}
}

/****************************************************************************************************
	stopAllCallsTo:
	
	If you saved your observationBlock when you registered, you can use this method to
	remove all KVO notifications that would call that block.

	Deregisters all observations that match the criteria:
		- Observed object matches receiver
		- ObservationBlock matches parameter
	
	Deregistering observations is ALWAYS done by searching for observations that match criteria, and all
	observations that match the given criteria will be removed.
	
	Must be sent to the same object that you sent the "tell:" method to when you set up the observation,
	but matches any keypath. That is, this won't remove an observation whose keypath goes through or
	ends at this object, only ones that start at this object.
*/
- (void) stopAllCallsTo:(ObservationBlock) stopBlock
{
	if (!stopBlock)
		return;

	int removedBlockCount = 0;
	NSMutableSet *entriesToRemove = [[NSMutableSet alloc] init];

	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (observedKeysDict)
	{
		@synchronized(observedKeysDict)
		{
			for (NSString *propertyKey in [observedKeysDict allKeys])
			{
				NSMutableArray *observers = observedKeysDict[propertyKey];
				
				for (EBNKeypathEntryInfo *entryInfo in observers)
				{
					// Match on the entries where the block that gets run is the indicated block
					if (entryInfo->_blockInfo->_copiedBlock == stopBlock && entryInfo->_keyPathIndex == 0)
					{
						[entriesToRemove addObject:entryInfo];
						++removedBlockCount;
					}
				}
			}
		}
	}
	
	for (EBNKeypathEntryInfo *entryInfo in entriesToRemove)
	{
		[entryInfo ebn_updateKeypathAtIndex:0 from:self to:nil];
	}

	// Show warnings for odd results
	if (removedBlockCount == 0)
	{
		EBLogContext(kLoggingContextOther, @"When stopping all cases where %@ calls observer block %p: "
				@"Couldn't find any matching observer block. Were we not observering this?",
				[self debugDescription], stopBlock);
	}
}

/****************************************************************************************************
	EBNProperBaseClass
 
	Usually, calling [self class] will return the base class, however if Apple's KVO makes a subclass
	of our runtime subclass, Apple's KVO will override [self class] in their subclass so that it returns
	the superclass of the class they created, which would be our runtime subclass in this instance.
	
	Visually, showing the inheritance hierarchy where this can happen:
	
		NSObject
		EBNSomeDataManager
		EBNSomeDataManager_EBNShadowClass					Observable makes this class at runtime
		NSKVONotifying_EBNSomeDataManager_EBNShadowClass	Then, Apple's KVO makes this class at runtime
 
 	Apple's KVO overrides -class in NSKVONotifying_EBNSomeDataManager_EBNShadowClass, but that override
	will return EBNSomeDataManager_EBNShadowClass as the object's class, not EBNSomeDataManager.
	
	So, if this is an issue for you, call EBNProperBaseClass instead, and you'll get EBNSomeDataManager,
	the 'correct' result.
	
	See prepareToObserveProperty:, where this class method gets overridden for Observable shadow classes,
	and will return the proper base class.
*/
+ (Class) ebn_properBaseClass
{
	return self;
}

#pragma mark Somewhat Protected

/****************************************************************************************************
	ebn_manuallyTriggerObserversForPath:previousValue:
	
	Triggers observers, lazyloading evaluation, keypath updating, and other upkeep on the property at the
	END of the path	as if that property's setter had been called.
	
	If any value in the keyPath besides the last is nil, does nothing.
	
	Functionally, this method walks the values in the keypath to get to the terminal property, and then
	calls manuallyTriggerObserversForProperty: on that property.
*/
- (void) ebn_manuallyTriggerObserversForPath:(NSString *) keyPath previousValue:(id) prevValue
{
	NSArray *keyPathArray = [keyPath componentsSeparatedByString:@"."];
	NSObject<EBNObservable_Custom_Selectors> *object = (NSObject<EBNObservable_Custom_Selectors> *) self;
	
	if (keyPathArray.count == 0)
	{
		return;
	}
	else if (keyPathArray.count > 1)
	{
		for (int index = 0; index < keyPathArray.count - 1; ++index)
		{
			object = [object ebn_valueForKey:keyPathArray[index]];
			if (!object)
				return;
		}
	}
	[object ebn_manuallyTriggerObserversForProperty:[keyPathArray lastObject] previousValue:prevValue];
}

/****************************************************************************************************
	ebn_manuallyTriggerObserversForProperty:previousValue:
	
	Triggers observers, lazyloading evaluation, keypath updating, and other upkeep on the given property,
	as if the property's setter had been called. 
	
	This method attempts to strike a performance balance, minimizing both the cost of scheduling excess
	observations when the property value didn't change, and minimizing cases where we evalute the underlying 
	property in order to check to see whether the value changed.
	
	Therefore, you should only call this method when you're reasonably sure the value changed, but actually
	testing against the new value isn't necessary.
	
	For external callers, this method is useful if a observed object needs to use direct ivar access yet 
	still wants to trigger observers.
*/
- (void) ebn_manuallyTriggerObserversForProperty:(NSString *) propertyName previousValue:(id) prevValue
{
	NSMutableArray *observers = nil;
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (observedKeysDict)
	{
		@synchronized(observedKeysDict)
		{
			observers = [observedKeysDict[propertyName] mutableCopy];
			NSMutableArray *splatObservers = observedKeysDict[@"*"];
			if (observers && splatObservers)
				[observers addObjectsFromArray:splatObservers];
			else if (splatObservers && !observers)
				observers = [splatObservers copy];				
		}
	}
	
	// If nobody's observing, nothing to do
	if (!observers)
		return;
	
	// Execute all the LazyLoader blocks; this handles chained lazy properties--that is, cases where
	// one lazy property depends on another lazy property. We should do this before calling
	// immediate blocks, so that an immed block that references a lazy property will force a recompute.
	
	size_t numLazyLoaderBlocks = 0;
	BOOL reapBlocksAfter = NO;
	for (EBNKeypathEntryInfo *entry in observers)
	{
		EBNObservation *blockInfo = entry->_blockInfo;

		if (blockInfo.isForLazyLoader)
		{
			if (![blockInfo executeWithPreviousValue:prevValue])
				reapBlocksAfter = YES;
			++numLazyLoaderBlocks;
		}
	}
	
	// If there were blocks that couldn't be run because their observing or observed object has gone away,
	// it's time to reap dead observations.
	if (reapBlocksAfter)
		[self ebn_reapBlocks];
	
	// If that was all the blocks, we're done. Return before we go eval the new value
	if (observers.count == numLazyLoaderBlocks)
		return;
	
	// If there's observations on the property it's almost always better to eval the new value
	// so we can optimize by not calling observers if the value didn't change
	id newValue = [self ebn_valueForKey:propertyName];
	
	// No need to do anything if the values are the same. Note when debugging: For properties that
	// box into a NSInteger or NSValue, this won't get hit because the pointers don't match. That's by design.
	// This catches object-type properties that didn't change.
	if (newValue == prevValue)
		return;
	
	[self ebn_manuallyTriggerObserversForProperty:propertyName previousValue:prevValue newValue:newValue
			copiedObserverTable:observers];
}

/****************************************************************************************************
	ebn_manuallyTriggerObserversForPath:previousValue:newValue:
	
	Triggers observers, lazyloading evaluation, keypath updating, and other upkeep on the property at the
	END of the path	as if that property's setter had been called.
	
	If any value in the keyPath besides the last is nil, does nothing.
	
	Functionally, this method walks the values in the keypath to get to the terminal property, and then
	calls manuallyTriggerObserversForProperty: on that property.
*/
- (void) ebn_manuallyTriggerObserversForPath:(NSString *) keyPath previousValue:(id) prevValue newValue:(id) newValue
{
	NSArray *keyPathArray = [keyPath componentsSeparatedByString:@"."];
	NSObject<EBNObservable_Custom_Selectors> *object = (NSObject<EBNObservable_Custom_Selectors> *) self;
	
	if (keyPathArray.count == 0)
	{
		return;
	}
	else if (keyPathArray.count > 1)
	{
		for (int index = 0; index < keyPathArray.count - 1; ++index)
		{
			object = [object ebn_valueForKey:keyPathArray[index]];
			if (!object)
				return;
		}
	}
	[object ebn_manuallyTriggerObserversForProperty:[keyPathArray lastObject] previousValue:prevValue newValue:newValue];
}

/****************************************************************************************************
	ebn_manuallyTriggerObserversForProperty:previousValue:newValue:
	
	Triggers observers on the given property, as if the setter for the property had been called.
	
	This method takes the new value of the property as a parameter, and exits early if the value didn't
	change. It's better to use this method in cases where you already have the new value for the property.
	However, don't eval the property to get the new value just so you can call this method.
	
	Unlike the other ebn_manuallyTriggerObserversForProperty:, this method evaluates whether the value
	actually changed first, and only runs lazyloader blocks (invalidating lazy properties whose value
	depends on this property) if the value actually changed.

	This method is used by the collection classes, including the case where the special "*" key
	changes. External callers should use this method as well when they have the new property value in hand.
*/
- (void) ebn_manuallyTriggerObserversForProperty:(NSString *) propertyName previousValue:(id) prevValue
		newValue:(id) newValue
{
	// Don't test for 'isEqual' here--keypaths need to be updated whenever the pointers are different
	if (newValue != prevValue || [propertyName isEqualToString:@"*"])
	{
		NSMutableArray *observers = nil;
		NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
		if (observedKeysDict)
		{
			@synchronized(observedKeysDict)
			{
				observers = [observedKeysDict[propertyName] mutableCopy];
				if (![propertyName isEqualToString:@"*"])
				{
					NSMutableArray *splatObservers = observedKeysDict[@"*"];
					if (observers && splatObservers)
						[observers addObjectsFromArray:splatObservers];
					else if (splatObservers && !observers)
						observers = [splatObservers copy];
				}
			}
		}
		
		// If nobody's observing, we're done.
		if (!observers)
			return;
		
		// Execute all the LazyLoader blocks; this handles chained lazy properties--that is, cases where
		// one lazy property depends on another lazy property. We should do this before calling
		// immediate blocks, so that an immed block that references a lazy property will force a recompute.
		
		size_t numLazyLoaderBlocks = 0;
		for (EBNKeypathEntryInfo *entry in observers)
		{
			EBNObservation *blockInfo = entry->_blockInfo;

			if (blockInfo.isForLazyLoader)
			{
				[blockInfo executeWithPreviousValue:prevValue];
				++numLazyLoaderBlocks;
			}
		}
		
		[self ebn_manuallyTriggerObserversForProperty:propertyName previousValue:prevValue newValue:newValue
				copiedObserverTable:observers];
	}
}

/****************************************************************************************************
	ebn_manuallyTriggerObserversForProperty:previousValue:newValue:copiedObserverTable:
	
	Internal method to trigger observers. Takes a COPY of the observer table (because @sync).
	The caller should check that the previous and new values aren't equal (using ==) and not call
	this method if they are, but should not check isEqual: (because of how keypath updating works).
	
	This method is private; don't call it directly.
*/
- (void) ebn_manuallyTriggerObserversForProperty:(NSString *)propertyName previousValue:(id)prevValue
		newValue:(id)newValue copiedObserverTable:(NSMutableArray *) observers
{	
	BOOL reapBlocksAfter = NO;

	// Go through all the observations, update any keypaths that need it.
	// If we update a keypath, we'll need to evaluate the property value to get the new value
	for (EBNKeypathEntryInfo *entry in observers)
	{
		// Update the keypath to go through the new object; this also tells us if any endpoint of the keypath
		// changed value
		if ([entry ebn_updateNextKeypathEntryFrom:prevValue to:newValue])
		{
			EBNObservation *blockInfo = entry->_blockInfo;
			
			// We already went through all the lazyloader blocks
			if (blockInfo.isForLazyLoader)
				continue;
		
			// Make sure the observed object still exists before calling/scheduling blocks
			if (![blockInfo executeWithPreviousValue:prevValue])
				reapBlocksAfter = YES;
		}
	}
	
	if (reapBlocksAfter)
		[self ebn_reapBlocks];
}

/****************************************************************************************************
	numberOfObservers:
	
	Returns the number of observers for the given property.
*/
- (NSUInteger) numberOfObservers:(NSString *) propertyName
{
	NSUInteger numObservers = 0;
	
	// Clean out any observation blocks that are inactive because their observer went away.
	// We don't want to count them.
	[self ebn_reapBlocks];
	
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (observedKeysDict)
	{
		@synchronized(observedKeysDict)
		{
			NSMutableArray *observers = observedKeysDict[propertyName];
			NSMutableArray *splatObservers = observedKeysDict[@"*"];
			numObservers = observers.count + splatObservers.count;
		}
	}
	
	return numObservers;
}

/****************************************************************************************************
	allObservedProperties
	
	Returns all the properties currently being observed, as a set of strings. This includes
	properties being observed because a keypath rooted at some other object runs through (or ends at)
	this object.
*/
- (NSSet *) allObservedProperties
{
	[self ebn_reapBlocks];
	
	NSMutableSet *properties = nil;
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (observedKeysDict)
	{
		@synchronized(observedKeysDict)
		{
			properties = [NSMutableSet setWithArray:[observedKeysDict allKeys]];
		}
	}
	
	return properties;
}

/****************************************************************************************************
	ebn_allProperties
	
	Returns all the properties of self, as an array of strings. Includes properties declared in
	superclasses; properties redefined in subclasses only count once.
*/
- (NSSet *) ebn_allProperties
{
	Class curClass = [self class];
	NSMutableSet *propertySet = [[NSMutableSet alloc] init];

	// copyPropertyList only gives us properties about the current class--not its superclasses.
	// So, walk up the class tree, from the current class to NSObject.
	while (curClass && curClass != [NSObject class])
	{
		unsigned int propCount;
		objc_property_t *properties = class_copyPropertyList(curClass, &propCount);
		if (properties)
		{
			for (int propIndex = 0; propIndex < propCount; ++propIndex)
			{
				// Get the name of all the properties, add them to the set. We use a set
				// to deduplicate properties re-declared in subclasses.
				NSString *propString = @(property_getName(properties[propIndex]));
				if (propString)
				{
					[propertySet addObject:propString];
				}
			}
		
			free(properties);
		}
		
		curClass = [curClass superclass];
	}
	
	return [propertySet copy];
}

#pragma mark Private

/****************************************************************************************************
	load
	
	Because static initialization is so great.
	
	Sets up a global set of blocks to be run on the main runloop, and creates a run loop observer
	to iterate the set.
*/
+ (void) load
{
	static CFRunLoopObserverRef runLoopObserver = NULL;
	
	// The dispatch_once is probably not necessary, as load is guaranteed to be called
	// exactly once, and the base init is guaranteed to be called before subclass inits
	// (therefore before subclasses can access the wrapper block queue).
	static dispatch_once_t once;
	dispatch_once(&once,
	^{
		// Set up our set of blocks to run at the end of each event
		EBN_ObserverBlocksToRunAfterThisEvent = [[NSMutableSet alloc] init];
		runLoopObserver = CFRunLoopObserverCreate(NULL, kCFRunLoopBeforeWaiting, YES, 0,
				EBN_RunLoopObserverCallBack, NULL);
		CFRunLoopAddObserver(CFRunLoopGetMain(), runLoopObserver, kCFRunLoopCommonModes);
		
		// EBN_ObserverBlocksToRunAfterThisEvent is created at initialization time, is
		// never dealloc'ed, and is private to EBNObservable. This makes it a good candidate to use
		// for our @synchronize token.
		EBNObservableSynchronizationToken = EBN_ObserverBlocksToRunAfterThisEvent;
		
		// And, this is our set of objects to keep from getting dealloc'ed until we can
		// send their observer messages.
		EBN_ObservedObjectKeepAlive = [[NSMutableArray alloc] init];

		// This dictionary contains EBNShadowedClassInfo objects, mapping parent classes
		// (the observed classes) to the objects with info about the shadow class.
		EBNBaseClassToShadowInfoTable = [NSMapTable mapTableWithKeyOptions:NSMapTableObjectPointerPersonality 
				valueOptions:NSMapTableStrongMemory];
		
		// Create a permanent object to be the invalid key object
		EBN_InvalidPropertyKey = [[NSObject alloc] init];
	});
}

/****************************************************************************************************
	ebn_observedKeysDict:
	
	This gets the observed methods dict out of an associated object, creating it if necessary.
	
	The caller of this method must be inside a @synchronized() block--keyed off the result of this
	method--while accessing the dictionary.
	
	That is, you need to do this:
			
			NSMutableDictionary *dict = [self ebn_observedKeysDict:YES];
			@synchronized(dict)
			{
				... use dict in here
			}
*/
- (NSMutableDictionary *) ebn_observedKeysDict:(BOOL) createIfNil
{
	NSMutableDictionary *observedMethods = objc_getAssociatedObject(self, @selector(ebn_observedKeysDict:));
	if (!observedMethods && createIfNil)
	{
		@synchronized(EBNObservableSynchronizationToken)
		{
			// Recheck for non-nil inside the sync
			observedMethods = objc_getAssociatedObject(self, @selector(ebn_observedKeysDict:));
			if (!observedMethods)
			{
				// Okay, it really doesn't exist, so set it up while inside the sync
				observedMethods = [[NSMutableDictionary alloc] init];
				objc_setAssociatedObject(self, @selector(ebn_observedKeysDict:), observedMethods,
						OBJC_ASSOCIATION_RETAIN);
			}
		}
	}
	return observedMethods;
}

/****************************************************************************************************
	ebn_valueForKey:
	
	Cocoa collection classes implement valueForKey: to perform operations on each object in the colleciton.
	They also don't allow observing for sets and arrays. Since we do, we need a valueForKey: variant
	that allows you to pass a key string into a collection and get back the corresponding object
	from the collection. 
	
	That is, [observableArray ebn_valueForKey:@"4"] will give you object 4 in the array, just like array[4].
	
	The Observable collection classes override this method.
*/
- (id) ebn_valueForKey:(NSString *)key
{
	id result = nil;

	// valueForKey is inside an exception handler because some property types aren't KVC-compliant
	// and throw NSUnknownKeyException when it appears the actual problem is that KVC can't box up the type,
	// as opposed to being unable to find a getter method or ivar. ebn_valueForKey is private to Observable
	// and doesn't care about these exceptions.
	@try
	{
		// Get the method selector for the getter on this property
		Class realClass = object_getClass(self);
		SEL getterSelector = ebn_selectorForPropertyGetter(realClass, key);
		if (getterSelector)
		{
			Method getterMethod = class_getInstanceMethod(realClass, getterSelector);
			if (getterMethod)
			{
				char typeOfGetter[32];
				method_getReturnType(getterMethod, typeOfGetter, 32);

				switch (typeOfGetter[0])
				{
				case _C_CHR:
					result = getAndWrapProperty<char>(self, getterMethod, getterSelector);
				break;
				case _C_UCHR:
					result = getAndWrapProperty<unsigned char>(self, getterMethod, getterSelector);
				break;
				case _C_SHT:
					result = getAndWrapProperty<short>(self, getterMethod, getterSelector);
				break;
				case _C_USHT:
					result = getAndWrapProperty<unsigned short>(self, getterMethod, getterSelector);
				break;
				case _C_INT:
					result = getAndWrapProperty<int>(self, getterMethod, getterSelector);
				break;
				case _C_UINT:
					result = getAndWrapProperty<unsigned int>(self, getterMethod, getterSelector);
				break;
				case _C_LNG:
					result = getAndWrapProperty<long>(self, getterMethod, getterSelector);
				break;
				case _C_ULNG:
					result = getAndWrapProperty<unsigned long>(self, getterMethod, getterSelector);
				break;
				case _C_LNG_LNG:
					result = getAndWrapProperty<long long>(self, getterMethod, getterSelector);
				break;
				case _C_ULNG_LNG:
					result = getAndWrapProperty<unsigned long long>(self, getterMethod, getterSelector);
				break;
				case _C_FLT:
					result = getAndWrapProperty<float>(self, getterMethod, getterSelector);
				break;
				case _C_DBL:
					result = getAndWrapProperty<double>(self, getterMethod, getterSelector);
				break;
				case _C_BFLD:
					// Pretty sure this can't happen, as bitfields can't be top-level and are only found inside structs/unions
					EBAssert(false, @"Observable does not have a way to override the setter for %@.", key);
				break;
				case _C_BOOL:
					result = getAndWrapProperty<bool>(self, getterMethod, getterSelector);
				break;
				case _C_PTR:
				case _C_CHARPTR:
				case _C_ATOM:		// Apparently never generated? Only docs I can find say treat same as charptr
				case _C_ARY_B:
					result = getAndWrapProperty<void *>(self, getterMethod, getterSelector);
				break;
				
				case _C_ID:
					result = getAndWrapProperty<id>(self, getterMethod, getterSelector);
				break;
				case _C_CLASS:
					result = getAndWrapProperty<Class>(self, getterMethod, getterSelector);
				break;
				case _C_SEL:
					result = getAndWrapProperty<SEL>(self, getterMethod, getterSelector);
				break;

				case _C_STRUCT_B:
					if (!strncmp(typeOfGetter, @encode(NSRange), 32))
						result = getAndWrapProperty<NSRange>(self, getterMethod, getterSelector);
					else if (!strncmp(typeOfGetter, @encode(CGPoint), 32))
						result = getAndWrapProperty<CGPoint>(self, getterMethod, getterSelector);
					else if (!strncmp(typeOfGetter, @encode(CGRect), 32))
						result = getAndWrapProperty<CGRect>(self, getterMethod, getterSelector);
					else if (!strncmp(typeOfGetter, @encode(CGSize), 32))
						result = getAndWrapProperty<CGSize>(self, getterMethod, getterSelector);
					else if (!strncmp(typeOfGetter, @encode(UIEdgeInsets), 32))
						result = getAndWrapProperty<UIEdgeInsets>(self, getterMethod, getterSelector);
					else
						EBAssert(false, @"Observable does not have a way to override the setter for %@.", key);
				break;
						
				default:
					result = [self valueForKey:key];
				break;
				}
			}
			else
			{
				result = [self valueForKey:key];
			}
		}
		else
		{
			// We'd do this here, except it almost never works.
			// result = [self valueForKey:key];
			result = nil;
		}
	}
	@catch (NSException *exception)
	{
		// Swallow unknown key exceptions (and warn), rethrow all others
		if ([exception.name isEqualToString:@"NSUnknownKeyException"])
		{
			EBLogContext(kLoggingContextOther, @"Performance Warning: valueForKey threw an NSUnknownKeyException.");
		}
		else
		{
			@throw exception;
		}
	}
	
	return result;
}

/****************************************************************************************************
	ebn_compareKeypathValues:atIndex:from:to:
    
    Compares the values of the given key in both fromObj and toObj. Handles wildcards.
*/
+ (BOOL) ebn_compareKeypathValues:(EBNKeypathEntryInfo *) info atIndex:(NSInteger) index from:(id) fromObj to:(id) toObj
{
	BOOL result = NO;
	
	NSString *propName = info->_keyPath[index];
	if ([propName isEqualToString:@"*"])
	{
		// Might be better to use [observedKeysDict allKeys] for the from case
		NSSet *fromPropertySet = [fromObj ebn_allProperties];
		NSSet *toPropertySet = [toObj ebn_allProperties];
		NSSet *allProps = fromPropertySet;
		if (!allProps)
			allProps = toPropertySet;
		else
			allProps = [fromPropertySet setByAddingObjectsFromSet:toPropertySet];
			
		for (NSString *propertyString in allProps)
		{
			result |= EBNComparePropertyAtIndex(index, info, propertyString, fromObj, toObj);
		}
	}
	else
	{
		result = EBNComparePropertyAtIndex(index, info, propName, fromObj, toObj);
	}

	return result;
}


/****************************************************************************************************
	ebn_observe:using:
	
	Sets up an observation.
*/
- (BOOL) ebn_observe:(NSString *) keyPathString using:(EBNObservation *) blockInfo
{
	// Create our keypath entry
	EBNKeypathEntryInfo	*entryInfo = [[EBNKeypathEntryInfo alloc] init];
	entryInfo->_blockInfo = blockInfo;
	entryInfo->_keyPath = [keyPathString componentsSeparatedByString:@"."];
	entryInfo->_keyPathIndex = 0;
	
	return [entryInfo ebn_updateKeypathAtIndex:0 from:nil to:self];
}

/****************************************************************************************************
	ebn_addEntry:forProperty:
    
    
*/
- (void) ebn_addEntry:(EBNKeypathEntryInfo *) entryInfo forProperty:(NSString *) propName
{
	BOOL tableWasEmpty = NO;
	
	if ([propName isEqualToString:@"*"])
	{
		for (NSString *expandedPropString in [self ebn_allProperties])
		{
			[self ebn_swizzleImplementationForSetter:expandedPropString];
		}
	}
	else
	{
		// Check that this class is set up to observe the given property. That is, check that we've
		// swizzled the setter.
		if (![self ebn_swizzleImplementationForSetter:propName])
		{
			// If an object in the middle of a keypath doesn't have a property matching the next key or otherwise
			// can't be set up to observe, it's okay, as this object might get replaced later with one that can.
			// (Adding keypath optionals will improve this somewhat). But, if item 0 in the path can't find the
			// first property, we're boned so assert on it.
			if (entryInfo->_keyPathIndex == 0)
			{
				// This code *should* assert here, to force callers to fix their observations. However, this
				// currently fails a bunch of unit tests because a bunch of Unit Test settings objects created
				// for dependency injection don't have all the properties of the real objects.
				EBLogContext(kLoggingContextOther, @"The root object of the observation can't observe the first "
					@"property in the keypath. This observation will never work.");
			}
//			EBAssert(entryInfo->_keyPathIndex != 0, @"The root object of the observation can't observe the first "
//					@"property in the keypath. This observation will never work.");

			return;
		}
	}

	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:YES];
	@synchronized(observedKeysDict)
	{
		// Get the array of blocks to invoke when a particular setter is called.
		NSMutableArray *observers = observedKeysDict[propName];
	
		// If the array doesn't exist, create it and add it to the method dict.
		if (!observers)
		{
			observers = [[NSMutableArray alloc] init];
			observedKeysDict[propName] = observers;
			tableWasEmpty = true;
		}
		
		// Add the entry to the list of things this property is observing
		[observers addObject:entryInfo];
	}
			
	// If the table had been empty, but now isn't, this means the given property
	// is now being observed (and wasn't before now). Inform ourselves.
	if (tableWasEmpty && [self respondsToSelector:@selector(property:observationStateIs:)])
	{
		NSObject <EBNObserverNotificationProtocol> *target = (NSObject<EBNObserverNotificationProtocol> *) self;
		[target property:propName observationStateIs:TRUE];
	}
}

/****************************************************************************************************
	ebn_removeEntry:forProperty:atIndex:
    
    
*/
- (EBNKeypathEntryInfo *) ebn_removeEntry:(EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) pathIndex
		forProperty:(NSString *) propName
{
	BOOL observerTableRemoved = NO;
	EBNKeypathEntryInfo *removedEntry = nil;

	// Remove the entry from the observer table for the given property.
	// If the entry is in the table multiple times, be sure to only remove one instance.
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	@synchronized(observedKeysDict)
	{
		// Important that here we use propName and not look inside entryInfo to pull the property
		// from the keypath.
		NSMutableArray *observers = observedKeysDict[propName];
		for (int index = 0; index < observers.count; ++index)
		{
			EBNKeypathEntryInfo *indexedEntry = observers[index];
			if (indexedEntry->_blockInfo == entryInfo->_blockInfo &&
					indexedEntry->_keyPathIndex == pathIndex &&
					[indexedEntry->_keyPath isEqualToArray:entryInfo->_keyPath])
			{
				removedEntry = indexedEntry;
				[observers removeObjectAtIndex:index];
				break;
			}
		}
				
		if (observers && ![observers count])
		{
			[observedKeysDict removeObjectForKey:propName];
			observerTableRemoved = true;
		}
	}
		
	// If nobody is observing this property anymore, inform ourselves
	if (observerTableRemoved && [self respondsToSelector:@selector(property:observationStateIs:)])
	{
		NSObject <EBNObserverNotificationProtocol> *target = (NSObject<EBNObserverNotificationProtocol> *) self;
		[target property:propName observationStateIs:FALSE];
	}
	
	return removedEntry;
}

/****************************************************************************************************
	ebn_reapBlocks

	Checks every registered block in this object, removing blocks whose observer has been deallocated.
	This method will tell other Observable objects to remove entries for keypaths where their observing
	object has been deallocated.
	
	It's useful to remember that this method checks every observation whose keypath touches self at 
	any point in the keypath. Some of the blocks we check could be rooted in self; others not.
	
	Rember that the lifetime of an observer block should be until either the observed or observing
	object goes away (or it's explicitly removed). However, since there isn't a notifying zeroing 
	weak pointer, we do this to clean up.
	
	Returns the number of blocks that got reaped.
*/
- (int) ebn_reapBlocks
{
	int removedBlockCount = 0;
	NSMutableSet *entriesToRemove = [[NSMutableSet alloc] init];

	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (observedKeysDict)
	{
		@synchronized(observedKeysDict)
		{
			for (NSString *propertyKey in [observedKeysDict allKeys])
			{
				NSMutableArray *observers = observedKeysDict[propertyKey];
				for (EBNKeypathEntryInfo *entry in observers)
				{
					if (!entry->_blockInfo->_weakObserver)
					{
						[entriesToRemove addObject:entry];
					}
				}
			}
		}
	}
		
	for (EBNKeypathEntryInfo *entry in entriesToRemove)
	{
		if ([entry ebn_removeObservation])
			++removedBlockCount;
	}

	return removedBlockCount;
}

/****************************************************************************************************
	ebn_prepareObjectForObservation
	
	This returns the class where we should add/replace getter and setter methods in order to 
	implement observation.
	
	This class should be a runtime-created subclass of the given class. It could be a class created
	by Apple's KVO, or one created by us.
	
	Also, very important terminology for this method:
	
		baseClass	<-  The 'visible to Cocoa' class of this object, or what this was before anyone
						isa-swizzled it.
		actualClass	<-  The actual runtime type of self. Might be same as baseClass; not always.
		shadowClass <-  The runtime-created subclass where Observable is doing its method swizzling.
						Same as actualClass when actualClass is an Apple KVO subclass.
						
	Pass nil for propertyName if you're observing a non-property key ("*", array indexes, dictionary keys, etc.)
	
	Caller is required to @synchronize(EBNBaseClassToShadowInfoTable) before calling this function, and keep
	the sync while using the result.
*/
- (EBNShadowedClassInfo *) ebn_prepareObjectForObservation
{
	Class actualClass = object_getClass(self);
	EBNShadowedClassInfo *info = nil;
	
		// 1. Is this object already shadowed?
	if (class_respondsToSelector(actualClass, @selector(ebn_shadowClassInfo)))
	{
		// Note that this also catches the case where someone else has subclassed our shadow class.
		info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
	}
	else
	{
		// Do not make shadow classes for tagged pointers. Because that is not going to work at all.
		uintptr_t value = (uintptr_t)(__bridge void *) self;
		if (value & 0xF)
			return nil;

		// Get the shadowed subclass to setClass to for instances of this base class. Make the
		// shadowed subclass if necessary.
		Class baseClass = [self class];
		info = [actualClass ebn_createShadowedSubclass:baseClass actualClass:actualClass
				additionalOverrides:NO];
		
		// Objects that Apple's KVO has already subclassed need to be handled specially.
		if (info && !info->_isAppleKVOClass)
		{
			// In this case we have to make the object be the shadow class
			object_setClass(self, info->_shadowClass);
		}
	}
	
	return info;
}

/****************************************************************************************************
	ebn_createShadowedSubclass:actualClass:additionalOverrides:
	
	Very important for this method:
	
		baseClass	<-  The 'visible to Cocoa' class of this object, or what this was before anyone
						isa-swizzled it.
		actualClass	<-  The actual runtime type of self. Might be same as baseClass; not always.
		shadowClass <-  The runtime-created subclass where Observable is doing its method swizzling.
						Same as curClass when curClass is an Apple KVO subclass.

	Caller is required to @synchronize(EBNBaseClassToShadowInfoTable) before calling this function, and keep
	the sync while using the result.
	
	Caller should have already checked for the case where actualClass is *already* shadowed, wherein either
	actualClass is a class we created at runtime OR a subclass of one of our runtime-created classes.
	
	AdditionalOverrides can be set to TRUE in the case where we know we haven't allocated any objects of the 
	base class as yet. The additional overrides change the shadowing strategy so that all objects of this class
	will be created as shadowed classes, and instances of the base class won't ever exist. The side effect is that,
	due to the shadowed object containing additional ivars, we cannot isa-swizzle base class objects to be 
	shadowed objects--but we won't ever need to.
*/
+ (EBNShadowedClassInfo *) ebn_createShadowedSubclass:(Class) baseClass actualClass:(Class) actualClass
		additionalOverrides:(BOOL) additionalOverrides
{
	// Do we have a shadow class for this actual object class already?
	EBNShadowedClassInfo *info = [EBNBaseClassToShadowInfoTable objectForKey:actualClass];
	
	// If this object is subclassed by Apple's KVO, we can't subclass their subclass.
	// Apple's code becomes unhappy, apparently. So instead we'll method swizzle methods in
	// Apple's KVO subclass.
	if (!info)
	{
		// This test checks to see if the [self class] is overridden to return the superclass.
		if (baseClass == class_getSuperclass(actualClass))
		{
			info = [[EBNShadowedClassInfo alloc] initWithBaseClass:baseClass shadowClass:actualClass];
			info->_isAppleKVOClass = true;
			EBNOverrideDeallocForClass(actualClass);
			
			// Add a custom method that returns our info object
			EBNShadowedClassInfo *(^customClassInfoMethod)(NSObject *) = ^EBNShadowedClassInfo *(NSObject *)
			{
				return info;
			};
			IMP infoMethodImplementation = imp_implementationWithBlock(customClassInfoMethod);
			class_addMethod(actualClass, @selector(ebn_shadowClassInfo), infoMethodImplementation, "@@:");

			// This makes the Apple KVO subclass be both the base and the subclass in the table.
			// Future lookups against this class will get found the table lookup, above.
			[EBNBaseClassToShadowInfoTable setObject:info forKey:actualClass];
		}
	}

	// If we don't have an info object by this point, we'll need to make a new class.
	if (!info)
	{
		// Do not make shadow classes for CF objects that are toll-free bridged.
		NSString *className = NSStringFromClass(actualClass);
		if ([className hasPrefix:@"NSCF"] || [className hasPrefix:@"__NSCF"])
		{
			// So, you stopped at this. Most likely it is because someone set a toll-free bridged
			// CF object as a NS property value, and someone else observed on it. This doesn't work, and won't work.
			// You'll just submit a bug report about it, but the level of hacking required to make this work
			// is incompatible with App Store apps.
			EBLogContext(kLoggingContextOther, @"Properties of toll-free bridged CoreFoundation objects can't be observed.");
			return nil;
		}
	
		// Have to make a new class
		static NSString *shadowClassSuffix = @"_EBNShadowClass";
		NSString *shadowClassName = [NSString stringWithFormat:@"%@%@", className, shadowClassSuffix];
		Class shadowClass = objc_allocateClassPair(actualClass, [shadowClassName UTF8String], 0);
		if (!shadowClass)
		{
			// In some odd cases (such as multiple classes with the same name in your codebase) allocate
			// class pair will fail. In that case try to find the proper shadow class to use.
		//	shadowClass = objc_getClass([shadowClassName UTF8String]);
		//	info = EBNShadowedClassToInfoTable[shadowClass];
		}
		else
		{
			// The new class gets several method overrides.
			//	1. - class; returns what [self class] returned before swizzling
			// 	2. - classForCoder; same idea
			//  3. - dealloc; We override dealloc to clean up observations.
			//  4. - ebn_shadowClassInfo; This is a custom method that returns our shadow class info object
			//  5. + ebn_properBaseClass; This is a custom class method that returns the base class
			//
			// Note that we don't override respondsToSelector:, meaning that NSObject's resondsToSelector:
			// will return NO for selector ebn_shadowClassInfo. This is intentional.
			info = [[EBNShadowedClassInfo alloc] initWithBaseClass:baseClass shadowClass:shadowClass];
			
			// Override -class (the instance method, not the class method).
			Class (^overrideTheMethodNamedClass)(NSObject *) = ^Class (NSObject *)
			{
				return baseClass;
			};
			Method classforClassInstanceMethod = class_getInstanceMethod(actualClass, @selector(class));
			IMP classMethodImplementation = imp_implementationWithBlock(overrideTheMethodNamedClass);
			class_addMethod(shadowClass, @selector(class), classMethodImplementation,
					method_getTypeEncoding(classforClassInstanceMethod));

			// Override classForCoder to return the parent class; this keeps us from encoding the
			// shadowed class with NSCoder
			Method classForCoder = class_getInstanceMethod(actualClass, @selector(classForCoder));
			class_addMethod(shadowClass, @selector(classForCoder), (IMP) ebn_shadowed_ClassForCoder,
					method_getTypeEncoding(classForCoder));
			
			// Override dealloc
			EBNOverrideDeallocForClass(shadowClass);
			
			// Add a custom method that returns our info object
			EBNShadowedClassInfo *(^customClassInfoMethod)(NSObject *) = ^EBNShadowedClassInfo *(NSObject *)
			{
				return info;
			};
			IMP infoMethodImplementation = imp_implementationWithBlock(customClassInfoMethod);
			class_addMethod(shadowClass, @selector(ebn_shadowClassInfo), infoMethodImplementation, "@@:");

			// Add a custom method that returns the proper base class
			// Remember, the base class is not necessarily our direct superclass.
			Class (^properBaseClass_Override)(NSObject *) = ^Class (NSObject *)
			{
				return baseClass;
			};
			classMethodImplementation = imp_implementationWithBlock(properBaseClass_Override);
			class_addMethod(object_getClass(shadowClass), @selector(ebn_properBaseClass),
					classMethodImplementation, "#@:");
			
			if (additionalOverrides)
			{
				[self ebn_installAdditionalOverrides:info actualClass:actualClass];
			}
			else
			{
				// Register the new class if we're not doing additional overrides.
				info->_allocHasHappened = YES;
				objc_registerClassPair(info->_shadowClass);
			}
					
			// Add our new class to the table; other objects of the same actual class will get isa-swizzled
			// to this subclass when first observed upon
			[EBNBaseClassToShadowInfoTable setObject:info forKey:actualClass];
		}
	}

	return info;
}

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	This is a wrapper for ebn_swizzleImplementationForSetter:info: found below. This method first checks
	that the property exists in the class, and if so, isa-swizzles the object to be an Observable sub-class
	if necessary, and sets up a wrapper method around the setter. 
	
	We want this method to be efficient, so that it can be called on every observation, and will quickly
	return if all the required shadow class creation, isa-swizzling, and setter method wrapping is already done.
	
	Returns NO if for any reason the object couldn't be set up for observation on the given property.
*/
- (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName
{
	// If this class doesn't have the given property, we want to bail out before we isa-swizzle the object. 
	if (!class_getProperty(object_getClass(self), [propName UTF8String]))
		return NO;

	@synchronized (EBNBaseClassToShadowInfoTable)
	{
		EBNShadowedClassInfo *info = [self ebn_prepareObjectForObservation];
		if (!info)
			return NO;

		// Attempt to add a wrapper method to the shadow class that wraps this setter method
		if (![info->_shadowClass ebn_swizzleImplementationForSetter:propName info:info])
			return NO;
	}

	return YES;
}

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:info:
	
	Swizzles the implemention of the setter method of the given property. The swizzled implementation
	calls through to the original implementation and then processes observer blocks.
	
	The bulk of this method is a switch statement that switches on the type of the property (parsed
	from the string returned by method_getArgumentType()) and calls a templatized C++ function
	called overrideSetterMethod<>() to create a new method and swizzle it in.
	
	Returns YES if we were able to swizzle the setter method. 
*/
+ (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName info:(EBNShadowedClassInfo *) info
{
	Class classToModify;

	@synchronized (EBNBaseClassToShadowInfoTable)
	{
		// Check to see if the setter has been overridden in this class.
		if ([info->_setters containsObject:propName])
		{
			// Already swizzled. We're done.
			return YES;
		}
		
		// We add the setter to the array even if this method ends up failing and unable to swizzle.
		// This prevents us from repeatedly attempting a swizzle that won't work.
		[info->_setters addObject:propName];
		classToModify = info->_shadowClass;
	}
	
	// If the setter isn't found, we can't swizzle, but there's no need to panic.
	// This is what will happen for readonly properties in a keypath.
	SEL setterSelector = ebn_selectorForPropertySetter(classToModify, propName);
	if (!setterSelector)
	{
		// If this property is non-constant and has no setter (for example a synthetic property that
		// calculates its value in the getter), and is being observed, it'll either need to be
		// lazyloaded, or it needs to make use of manual update triggering. But if it's constant,
		// it can be observed through just fine.
		return YES;
	}
		
	// For the setter we'll need the method definition, so we can get the argument type
	// As with the selector, this could be nil (in this case it means that some other class
	// defines the setter method, but the property is readonly in this class).
	Method setterMethod = class_getInstanceMethod(classToModify, setterSelector);
	if (!setterMethod)
		return NO;
	
	// We need to have the getter in order to swizzle, as our swizzled replacement will
	// need to call it. For keypath properties, we need to use the getter
	// to figure out what object to move to next; for endpoint properties, we use the getter
	// to determine if the value actually changes when the setter is called.
	SEL getterSelector = ebn_selectorForPropertyGetter(classToModify, propName);
	EBAssert(getterSelector, @"Couldn't find getter method for property %@ in class %@", propName, classToModify);
	if (!getterSelector)
	{
		// Not finding the getter is actually worse than not finding the setter, as it likely indicates
		// a getter selector exists but wasn't found.
		return NO;
	}
	
	// Get the getter method.
	Method getterMethod = class_getInstanceMethod(classToModify, getterSelector);
	EBAssert(getterMethod, @"Could not find getter method. Make sure class %@ has a method named %@.",
			classToModify, NSStringFromSelector(getterSelector));
	if (!getterMethod)
		return NO;
		
	char typeOfSetter[32];
	method_getArgumentType(setterMethod, 2, typeOfSetter, 32);

	// Types defined in runtime.h
	switch (typeOfSetter[0])
	{
	case _C_CHR:
		overrideSetterMethod<char>(propName, setterMethod, getterMethod, info);
	break;
	case _C_UCHR:
		overrideSetterMethod<unsigned char>(propName, setterMethod, getterMethod, info);
	break;
	case _C_SHT:
		overrideSetterMethod<short>(propName, setterMethod, getterMethod, info);
	break;
	case _C_USHT:
		overrideSetterMethod<unsigned short>(propName, setterMethod, getterMethod, info);
	break;
	case _C_INT:
		overrideSetterMethod<int>(propName, setterMethod, getterMethod, info);
	break;
	case _C_UINT:
		overrideSetterMethod<unsigned int>(propName, setterMethod, getterMethod, info);
	break;
	case _C_LNG:
		overrideSetterMethod<long>(propName, setterMethod, getterMethod, info);
	break;
	case _C_ULNG:
		overrideSetterMethod<unsigned long>(propName, setterMethod, getterMethod, info);
	break;
	case _C_LNG_LNG:
		overrideSetterMethod<long long>(propName, setterMethod, getterMethod, info);
	break;
	case _C_ULNG_LNG:
		overrideSetterMethod<unsigned long long>(propName, setterMethod, getterMethod, info);
	break;
	case _C_FLT:
		overrideSetterMethod<float>(propName, setterMethod, getterMethod, info);
	break;
	case _C_DBL:
		overrideSetterMethod<double>(propName, setterMethod, getterMethod, info);
	break;
	case _C_BFLD:
		// Pretty sure this can't happen, as bitfields can't be top-level and are only found inside structs/unions
		EBAssert(false, @"Observable does not have a way to override the setter for %@.",
				propName);
	break;
	case _C_BOOL:
		overrideSetterMethod<bool>(propName, setterMethod, getterMethod, info);
	break;
	case _C_PTR:
	case _C_CHARPTR:
	case _C_ATOM:		// Apparently never generated? Only docs I can find say treat same as charptr
	case _C_ARY_B:
		overrideSetterMethod<void *>(propName, setterMethod, getterMethod, info);
	break;
	
	case _C_ID:
		overrideSetterMethod<id>(propName, setterMethod, getterMethod, info);
	break;
	case _C_CLASS:
		overrideSetterMethod<Class>(propName, setterMethod, getterMethod, info);
	break;
	case _C_SEL:
		overrideSetterMethod<SEL>(propName, setterMethod, getterMethod, info);
	break;

	case _C_STRUCT_B:
		if (!strncmp(typeOfSetter, @encode(NSRange), 32))
			overrideSetterMethod<NSRange>(propName, setterMethod, getterMethod, info);
		else if (!strncmp(typeOfSetter, @encode(CGPoint), 32))
			overrideSetterMethod<CGPoint>(propName, setterMethod, getterMethod, info);
		else if (!strncmp(typeOfSetter, @encode(CGRect), 32))
			overrideSetterMethod<CGRect>(propName, setterMethod, getterMethod, info);
		else if (!strncmp(typeOfSetter, @encode(CGSize), 32))
			overrideSetterMethod<CGSize>(propName, setterMethod, getterMethod, info);
		else if (!strncmp(typeOfSetter, @encode(UIEdgeInsets), 32))
			overrideSetterMethod<UIEdgeInsets>(propName, setterMethod, getterMethod, info);
		else
			EBAssert(false, @"Observable does not have a way to override the setter for %@.",
					propName);
	break;
	
	case _C_UNION_B:
		// If you hit this assert, look at what we do above for structs, make something like that for
		// unions, and add your type to the if statement
		EBAssert(false, @"Observable does not have a way to override the setter for %@.",
				propName);
	break;
	
	default:
		EBAssert(false, @"Observable does not have a way to override the setter for %@.",
				propName);
	break;
	}
	
	return YES;
}

#pragma mark Debugging KVO

/****************************************************************************************************
	debugBreakOnChange:
	
*/
- (NSString *) debugBreakOnChange:(NSString *) keyPath
{
	return [self debugBreakOnChange:keyPath line:0 file:NULL func:NULL];
}

/****************************************************************************************************
	debugBreakOnChange:
	
	Meant to be used with the DebugBreakOnChange() macro. 
	
	Will break in the debugger when the property value at the end of the given keypath is changed. 
	Sort of like a breakpoint on the setter, but only for this object. Sort of like a watchpoint,
	but without the terrible slowness. 
	
	To use, type something like this into lldb:
	
		po DebugBreakOnChange(object, @"propertyName")
*/
- (NSString *) debugBreakOnChange:(NSString *) keyPath line:(int) lineNum file:(const char *) filePath
		func:(const char *) func
{
	if (!EBNIsADebuggerConnected())
		return @"No debugger detected or not debug build; debugBreakOnChange called but will not fire.";
		
	__block EBNObservation *ob = [[EBNObservation alloc] initForObserved:self observer:self immedBlock:
			^(NSObject *blockSelf, NSObject *observed)
			{
				id newValue = [observed valueForKeyPath:keyPath];
				EBLogStdOut(@"debugBreakOnChange breakpoint on keyPath: %@", keyPath);
				EBLogStdOut(@"    debugString: %@", ob.debugString);
				EBLogStdOut(@"    newValue: %@", newValue);
				
				// This line will cause a break in the debugger! If you stop here in the debugger, it is
				// because someone added a debugBreakOnChange: call somewhere, and its keypath just changed.
				DEBUG_BREAKPOINT;
			}];
			
	if (lineNum > 0)
		[ob setDebugStringWithFn:func file:filePath line:lineNum];
	else
		ob.debugString = @"A DebugBreakOnChange: call set using the debugger. Execution will halt when this property changes.";
	[ob observe:keyPath];
	
	return [NSString stringWithFormat:@"Will break in debugger when %@ changes.", keyPath];
}


/****************************************************************************************************
	debugShowAllObservers
	
	Shows all the observers of the receiver.
	
	To use in lldb, type something like:
		(lldb) po [dict debugShowAllObservers]
*/
- (NSString *) debugShowAllObservers
{
	NSMutableString *debugStr = [NSMutableString stringWithFormat:@"\n%@\n", [self debugDescription]];

	// If this object isn't a shadowed subclass, there's no observing happening
	Class actualClass = object_getClass(self);
	if (!class_respondsToSelector(actualClass, @selector(ebn_shadowClassInfo)))
	{
		[debugStr appendFormat:@"    This object is not set up to observe anything (not isa-swizzled)\n"];
	}

	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	for (NSString *observedMethod in observedKeysDict)
	{
		[debugStr appendFormat:@"    %@ notifies:\n", observedMethod];
		NSMutableArray *keypathEntries = observedKeysDict[observedMethod];
		for (EBNKeypathEntryInfo *entry in keypathEntries)
		{
			EBNObservation *blockInfo = entry->_blockInfo;
			id observer = blockInfo->_weakObserver;
			NSString *blockDebugStr = blockInfo.debugString;
			if (blockDebugStr)
			{
				[debugStr appendFormat:@"        %@", blockDebugStr];
			} else
			{
				[debugStr appendFormat:@"        %p: for <%s: %p> ",
						entry->_blockInfo, class_getName([observer class]), observer];
			}
			
			if (entry->_keyPath.count > 1)
			{
				[debugStr appendFormat:@" path:"];
				NSString *separator = @"";
				for (NSString *prop in entry->_keyPath)
				{
					[debugStr appendFormat:@"%@%@", separator, prop];
					separator = @".";
				}
			}
			
			// Show a warning if this observation has non-swizzled objects in its keypath
			NSObject *obj = self;
			for (NSInteger keyPathIndex = entry->_keyPathIndex; keyPathIndex < entry->_keyPath.count - 1; ++keyPathIndex)
			{
				NSString *property = entry->_keyPath[keyPathIndex];
				if ([property isEqualToString:@"*"])
					continue;
				
				obj = [obj ebn_valueForKey:property];
				if (!obj)
					continue;
				actualClass = object_getClass(obj);
				if (!class_respondsToSelector(actualClass, @selector(ebn_shadowClassInfo)))
				{
					[debugStr appendFormat:@"\n        --WARNING: Keypath property %@ of class %@ is not "
							@"swizzled. This will cause observations to not fire.", property, [obj class]];
				}
				
			}
			
			[debugStr appendFormat:@"\n"];
		}
	}
	[debugStr appendFormat:@"\n"];
	
	return debugStr;
}

@end

/****************************************************************************************************
	ebn_selectorForPropertyGetter()
	
	Returns the SEL for a given property's getter method, given the name of the property as a string
	(NOT the name of the setter method). The SEL will be a valid instance method for this
	class, or nil.
*/
SEL ebn_selectorForPropertyGetter(Class baseClass, NSString * propertyName)
{
	NSString *getterName = nil;
	SEL methodSel;
	Method getterMethod;

	// Check the case where the getter has the same name as the property
	methodSel = NSSelectorFromString(propertyName);
	getterMethod = class_getInstanceMethod(baseClass, methodSel);
	if (getterMethod && method_getNumberOfArguments(getterMethod) == 2)
	{
		return methodSel;
	}

	// If the property has a custom getter, go find it by getting the property attribute string
	objc_property_t prop = class_getProperty(baseClass, [propertyName UTF8String]);
	if (prop)
	{
		NSString *propStr = [NSString stringWithUTF8String:property_getAttributes(prop)];
		NSRange getterStartRange =[propStr rangeOfString:@",G"];
		if (getterStartRange.location != NSNotFound)
		{
			// The property attribute string has a bunch of stuff in it, we're looking for a substring
			// in the format ",GisVariable," or ",GisVariable" at the end of the string
			NSInteger searchStart = getterStartRange.location + getterStartRange.length;
			NSRange nextCommaSearchRange = NSMakeRange(searchStart, [propStr length] - searchStart);
			NSRange nextComma = [propStr rangeOfString:@"," options:0 range:nextCommaSearchRange];
			if (nextComma.location == NSNotFound)
				getterName = [propStr substringWithRange:nextCommaSearchRange];
			else
				getterName = [propStr substringWithRange:NSMakeRange(searchStart, nextComma.location - searchStart)];

			// See if the getter method name actually has a Method
			methodSel = NSSelectorFromString(getterName);
			getterMethod = class_getInstanceMethod(baseClass, methodSel);
			if (getterMethod && method_getNumberOfArguments(getterMethod) == 2)
				return methodSel;
		}
	}
	
	// Try prepending an underscore to the getter name
	getterName = [NSString stringWithFormat:@"_%@", propertyName];
	methodSel = NSSelectorFromString(getterName);
	getterMethod = class_getInstanceMethod(baseClass, methodSel);
	if (getterMethod && method_getNumberOfArguments(getterMethod) == 2)
	{
		return methodSel;
	}
	
	return nil;
}

/****************************************************************************************************
	ebn_selectorForPropertySetter:
	
	Returns the SEL for a given property's setter method, given the name of the property as a string 
	(NOT the name of the setter method). The SEL will be a valid instance method for this
	class, or nil.
*/
SEL ebn_selectorForPropertySetter(Class baseClass, NSString * propertyName)
{
	// If this is an actual declared property, get the property, then its property attributes string,
	// then pull out the setter method from the string. Only finds custom setters, but must be done first.
	const char *propName = [propertyName UTF8String];
	objc_property_t prop = class_getProperty(baseClass, propName);
	if (prop)
	{
		char *propString = property_copyAttributeValue(prop, "S");
		if (propString)
		{
			SEL methodSel = sel_registerName(propString);
			if (methodSel && [baseClass instancesRespondToSelector:methodSel])
			{
				return methodSel;
			}
		}
		
		// It's unclear from the docs whether a property publicly declared readonly but privately redeclared
		// as readwrite would have the "R" encoding as part of its attributes. Since what we really want to know
		// is whether a setter method exists, we're not looking for the (non) existance of the "R" attribute,
		// as it's not clear the existance of the "R" attribute conclusively means the setters aren't there.
	}
	
	// For non-custom setter methods, and for non-properties, we need to guess the setter method.
	// Try to guess the setter name by prepending "set" and uppercasing the first char of the propname
	SEL foundMethodSelector = nil;
	size_t destStrLen = strlen(propName);
	if (destStrLen)
	{
		destStrLen += 10; // for prepending "_set" and appending ":"
		char *setterName = (char *) malloc(destStrLen);
		snprintf(setterName, destStrLen, "_set%c%s:", toupper(propName[0]), propName + 1);
		
		// Check for both "set..." and "_set..." variants
		SEL methodSel = sel_registerName(setterName + 1);
		if (methodSel && class_respondsToSelector(baseClass,methodSel))
		{
			foundMethodSelector = methodSel;
		}
		else
		{
			methodSel = sel_registerName(setterName);
			if (methodSel && class_respondsToSelector(baseClass, methodSel))
				foundMethodSelector = methodSel;
		}
		
		free(setterName);
	}
	
	return foundMethodSelector;
}

/****************************************************************************************************
	ebn_debug_DumpAllObservedMethods
	
	Dumps the all observed classes and all the methods that are being observed.
	
	To use, in LLDB type:
		po ebn_debug_DumpAllObservedMethods()
*/
NSString *ebn_debug_DumpAllObservedMethods(void)
{
	NSMutableString *dumpStr = [[NSMutableString alloc] initWithFormat:@"Observed Methods:\n"];
	
	for (Class baseClass in EBNBaseClassToShadowInfoTable)
	{
		EBNShadowedClassInfo *info = [EBNBaseClassToShadowInfoTable objectForKey:baseClass];
		[dumpStr appendFormat:@"    For class %@ with shadow class %@\n", baseClass, info->_shadowClass];
		
		for (NSString *propertyName in info->_getters)
		{
			[dumpStr appendFormat:@"        getter: %@\n", propertyName];
		}
		for (NSString *propertyName in info->_setters)
		{
			[dumpStr appendFormat:@"        setter: %@\n", propertyName];
		}
	}

	return dumpStr;
}

/****************************************************************************************************
	ebn_shadowed_ClassForCoder
	
	Lifted, more or less, from Mike Ash's MAZeroingWeakRef code, this makes classForCoder return
	the base class instead of our private runtime-created subclass.
*/
static Class ebn_shadowed_ClassForCoder(id self, SEL _cmd)
{
	// Get the shadow class that we created, which isn't necessarily the current isa.
	// (someone else may have come in and made a later runtime subclass of our runtime subclass).
	EBNShadowedClassInfo *info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
	Class observableShadowClass = info->_shadowClass;

	// Get the direct superclass of the shadowClass we made (remember this may be a superclass of self)
	// and if we can't get a better answer, return that.
	Class superclass = class_getSuperclass(observableShadowClass);
	Class classForCoder = superclass;
	
	// Try to call classForCoder on the superclass of our shadowclass. But, don't do it if
	// we're about to call ourselves recursively.
    IMP superClassForCoderMethod = class_getMethodImplementation(superclass, @selector(classForCoder));
    IMP selfClassForCoderMethod = class_getMethodImplementation(object_getClass(self), @selector(classForCoder));
	if (selfClassForCoderMethod != superClassForCoderMethod)
		classForCoder = ((id (*)(id, SEL))superClassForCoderMethod)(self, _cmd);
	
	// Finally, if classForCoder was dumb, fix it. We should never return the shadowclass for coding.
    if (classForCoder == observableShadowClass)
        classForCoder = superclass;
    return classForCoder;
}

/****************************************************************************************************
	EBNOverrideDeallocForClass:
	
	This method replaces the given classes' dealloc method with our wrapper for dealloc--
	ebn_shadowed_dealloc.
	
	The wrapper method cleans up any observations on the about-to-disappear object, does dealloc 
	notifications for anyone using the ObservedObjectDeallocProtocol, and if we have to swizzle out
	an existing dealloc method for this class (not superclasses), calls the original dealloc.
	Note that ARC effectively calls [super dealloc] automatically.
	
	This method is intended to be called for shadow classes that we create at runtime, therefore 
	the shadow class will not have a dealloc method beforehand.
*/
static void EBNOverrideDeallocForClass(Class shadowClass)
{
	// Override dealloc in the shadow class to clean stuff up when the observed object goes away
	// ARC disallows @selector(dealloc), so we're using an alternate method to get the selector.
	// From: http://clang.llvm.org/docs/AutomaticReferenceCounting.html
	// ARC's intent (see their Rationale paragraph) is to prevent messaging dealloc directly,
	// which we won't be doing.
	SEL deallocSelector = sel_getUid("dealloc");
	Method origDealloc = class_getInstanceMethod(shadowClass, deallocSelector);
	if (!class_addMethod(shadowClass, deallocSelector, (IMP) ebn_shadowed_dealloc,
			method_getTypeEncoding(origDealloc)))
	{
		// If there's already a dealloc method in the shadow class, swap it with our
		// dealloc method so that our dealloc method gets called instead. Our dealloc
		// method then calls the original dealloc.
		if (class_addMethod(shadowClass, @selector(ebn_original_dealloc), (IMP) ebn_shadowed_dealloc,
				method_getTypeEncoding(origDealloc)))
		{
			Method ebn_dealloc = class_getInstanceMethod(shadowClass, @selector(ebn_original_dealloc));
			method_exchangeImplementations(origDealloc, ebn_dealloc);
		}
	}
}

/****************************************************************************************************
	ebn_shadowed_dealloc
	
	Replaces dealloc for observed objects, via isa-swizzling.
	
	Cleans up the KVO tables, and calls observedObjectHasBeenDeallocated: on any observers that
	implement the method.
*/
static void ebn_shadowed_dealloc(__unsafe_unretained NSObject *self, SEL _cmd)
{
	NSMutableSet *objectsToNotify = [NSMutableSet set];
	
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (observedKeysDict)
	{
		@synchronized(observedKeysDict)
		{
			for (NSMutableArray *observers in [observedKeysDict allValues])
			{
				for (EBNKeypathEntryInfo *entryInfo in [observers copy])
				{
					// Remove all 'downstream' keypath parts; they'll become inaccessable after
					// this object goes away. This case should only really be hit when this object
					// is weakly held by its 'upstream' object's keypath property.
					[entryInfo ebn_updateKeypathAtIndex:entryInfo->_keyPathIndex from:self to:nil];
					
					if (entryInfo->_keyPathIndex == 0)
					{
						// Only notify using DeallocProtocol for observations where this object is the base
						// of the keypath. That is, observer notifications where the notification itself
						// is going away because this object is the root of the keypath.
						id object = entryInfo->_blockInfo->_weakObserver;
						if (object && [object respondsToSelector:@selector(observedObjectHasBeenDealloced:endingObservation:)])
						{
							[objectsToNotify addObject:entryInfo];
						}
					}
					
					// If index != 0, we could trigger observer notifications here in the case where the
					// object before us in the keypath is holding on to us via a _weak reference.
					// We could do it for _unsafe_unretained too, but it's not great design where we notify
					// observers that we've changed but when they look to see what changed they crash.
					// If anyone sees this code and realizes they could write a notifying _unsafe_unretained
					// property wrapper $DIETY help us all.
				}
			}
		}
	}
	
	// Inform observers that subscribe to the protocol that we're going away
	for (EBNKeypathEntryInfo *entry in objectsToNotify)
	{
		id observer = entry->_blockInfo->_weakObserver;
		NSMutableString *keyPathStr = [[NSMutableString alloc] init];
		NSString *separator = @"";
		for (NSString *prop in entry->_keyPath)
		{
			[keyPathStr appendFormat:@"%@%@", separator, prop];
			separator = @".";
		}
		[observer observedObjectHasBeenDealloced:self endingObservation:keyPathStr];
	}
	
	// At some point around iOS 9, the behavior of object_setIvar was changed so that the method assumed your
	// ivar was unsafe_unretained unless it knew the storage class of the ivar. And, the docs don't appear to give
	// us any way to tell ARC what our desired storage class is for ivars we create with object_addIvar.
	// So we manually force retains of these ivars when setting, and manually release them here.
	@synchronized (EBNBaseClassToShadowInfoTable)
	{
		EBNShadowedClassInfo *info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
	
		for (NSString *propName in info->_objectGettersWithPrivateStorage)
		{
#ifndef __clang_analyzer__
			const char *propNameStr = [propName UTF8String];
			Ivar getterIvar = class_getInstanceVariable(object_getClass(self), propNameStr);
			void *outsideARC = (__bridge void *) object_getIvar(self, getterIvar);
			id object = (__bridge_transfer id) outsideARC;
			object = nil;
#endif
		}
	}

	// If we replaced an earlier dealloc selector IN THIS SHADOWED CLASS (can happen if Apple's KVO adds one, or
	// if a different entity doing runtime isa-swizzling comes in), call through now
	if (class_respondsToSelector(object_getClass(self), @selector(ebn_original_dealloc)))
	{
		[(NSObject<EBNObservable_Custom_Selectors> *) self ebn_original_dealloc];
	}
	else
	{
		Class actualSuperclass = class_getSuperclass(object_getClass(self));
		Method superDeallocMethod = class_getInstanceMethod(actualSuperclass, _cmd);
		if (superDeallocMethod)
		{
			// Here, we call the superDealloc method directly to keep ARC from trying to
			// muck with the result.
			void (*superDealloc)(id, SEL) = (void (*)(id, SEL)) method_getImplementation(superDeallocMethod);
			(superDealloc)(self, _cmd);
		}
	}
}


#pragma mark -
#pragma mark Template Methods

/****************************************************************************************************
	EBNComparePropertyAtIndex
    
	Compares the value of two properties. Determines whether the properties are object-valued (and therefore
	potentially not at the end of their keypath) or POD properties.
*/
BOOL EBNComparePropertyAtIndex(NSInteger index, EBNKeypathEntryInfo *info, NSString *propName, id prevObject, id curObject)
{
	BOOL result = NO;
	
	char *propertyTypeStr = nil;
	Class prevObjectClass = [prevObject class];
	
	if (prevObject)
	{
		objc_property_t prevProp = class_getProperty(prevObjectClass, [propName UTF8String]);
		propertyTypeStr = property_copyAttributeValue(prevProp, "T");
	}
	
	// If prev and current are the same class, or one is the parent of the other, properties they have
	// in common must be the same type. Otherwise, check the prop type of the prop in curObject
	if (curObject && !([curObject isKindOfClass:prevObjectClass] || [prevObject isKindOfClass:[curObject class]]))
	{
		objc_property_t curProp = class_getProperty(object_getClass(curObject), [propName UTF8String]);
		char *curPropTypeStr = property_copyAttributeValue(curProp, "T");
		if (!propertyTypeStr)
		{
			propertyTypeStr = curPropTypeStr;
		}
		else if (curPropTypeStr)
		{
			if (strcmp(propertyTypeStr, curPropTypeStr))
			{
				// If the previous and current object have values for this property, but they are not the same
				// type, bail and consider the value changed.
				free(propertyTypeStr);
				free(curPropTypeStr);
				return YES;
			} 
			else
			{			
				free(curPropTypeStr);
			}
		}
	}
	
	if (!propertyTypeStr)
		return YES;
		
		// Types defined in runtime.h
		// For all the cases in this switch, we assume prevObject and curObject are non-nil.
	switch (propertyTypeStr[0])
	{
	case 0:
		result = YES;
	break;
	case _C_CHR:
		result = EBNComparePropertyEquality<char>(propName, index, info, prevObject, curObject);
	break;
	case _C_UCHR:
		result = EBNComparePropertyEquality<unsigned char>(propName, index, info, prevObject, curObject);
	break;
	case _C_SHT:
		result = EBNComparePropertyEquality<short>(propName, index, info, prevObject, curObject);
	break;
	case _C_USHT:
		result = EBNComparePropertyEquality<unsigned short>(propName, index, info, prevObject, curObject);
	break;
	case _C_INT:
		result = EBNComparePropertyEquality<int>(propName, index, info, prevObject, curObject);
	break;
	case _C_UINT:
		result = EBNComparePropertyEquality<unsigned int>(propName, index, info, prevObject, curObject);
	break;
	case _C_LNG:
		result = EBNComparePropertyEquality<long>(propName, index, info, prevObject, curObject);
	break;
	case _C_ULNG:
		result = EBNComparePropertyEquality<unsigned long>(propName, index, info, prevObject, curObject);
	break;
	case _C_LNG_LNG:
		result = EBNComparePropertyEquality<long long>(propName, index, info, prevObject, curObject);
	break;
	case _C_ULNG_LNG:
		result = EBNComparePropertyEquality<unsigned long long>(propName, index, info, prevObject, curObject);
	break;
	case _C_FLT:
		result = EBNComparePropertyEquality<float>(propName, index, info, prevObject, curObject);
	break;
	case _C_DBL:
		result = EBNComparePropertyEquality<double>(propName, index, info, prevObject, curObject);
	break;
	case _C_BFLD:
		// Pretty sure this can't happen, as bitfields can't be top-level and are only found inside structs/unions
		EBCAssert(false, @"Observable does not have a way to compare equality for %@.",
				propName);
	break;
	case _C_BOOL:
		result = EBNComparePropertyEquality<bool>(propName, index, info, prevObject, curObject);
	break;
	case _C_PTR:
	case _C_CHARPTR:
	case _C_ATOM:		// Apparently never generated? Only docs I can find say treat same as charptr
	case _C_ARY_B:
		result = EBNComparePropertyEquality<void *>(propName, index, info, prevObject, curObject);
	break;
	
		// For id and class objects, we may need to recurse, continuing to evaluate objects along the keypath.
		// Calling ebn_comparePropertyAtIndex: does this.
	case _C_ID:
	case _C_CLASS:
		if (index == [info->_keyPath count] - 1 && (!prevObject || !curObject))
		{
			result = YES;
		}
		else
		{
			result = [info ebn_comparePropertyAtIndex:index from:[prevObject ebn_valueForKey:propName] 
					to:[curObject ebn_valueForKey:propName]];
		}
	break;
	case _C_SEL:
		result = EBNComparePropertyEquality<SEL>(propName, index, info, prevObject, curObject);
	break;

	case _C_STRUCT_B:
		if (!strncmp(propertyTypeStr, @encode(NSRange), 32))
			result = EBNComparePropertyEquality<NSRange>(propName, index, info, prevObject, curObject);
		else if (!strncmp(propertyTypeStr, @encode(CGPoint), 32))
			result = EBNComparePropertyEquality<CGPoint>(propName, index, info, prevObject, curObject);
		else if (!strncmp(propertyTypeStr, @encode(CGRect), 32))
			result = EBNComparePropertyEquality<CGRect>(propName, index, info, prevObject, curObject);
		else if (!strncmp(propertyTypeStr, @encode(CGSize), 32))
			result = EBNComparePropertyEquality<CGSize>(propName, index, info, prevObject, curObject);
		else if (!strncmp(propertyTypeStr, @encode(UIEdgeInsets), 32))
			result = EBNComparePropertyEquality<UIEdgeInsets>(propName, index, info, prevObject, curObject);
		else
			EBCAssert(false, @"Observable does not have a way to compare equality for %@.",
					propName);
	break;
	
	case _C_UNION_B:
		// If you hit this assert, look at what we do above for structs, make something like that forUIEdgeInsets		// unions, and add your type to the if statement
		EBCAssert(false, @"Observable does not have a way to compare equality for %@.",
				propName);
	break;
	
	default:
		EBCAssert(false, @"Observable does not have a way to compare equality for %@.",
				propName);
	break;
	}
	
	free(propertyTypeStr);	
	return result;
}

/****************************************************************************************************
	EBN_PropertyEqualityTest
    
	Template specializations for testing whether two properties are equal. Needed mostly for
	struct-valued properties.
*/

template<typename T> inline BOOL EBN_PropertyEqualityTest(const T prevValue, const T curValue)
{
	return prevValue == curValue;
}
template<> inline BOOL EBN_PropertyEqualityTest<CGRect>(const CGRect prevValue, const CGRect curValue)
{
	return CGRectEqualToRect(prevValue, curValue);
}
template<> inline BOOL EBN_PropertyEqualityTest<CGPoint>(const CGPoint prevValue, const CGPoint curValue)
{
	return CGPointEqualToPoint(prevValue, curValue);
}
template<> inline BOOL EBN_PropertyEqualityTest<CGSize>(const CGSize prevValue, const CGSize curValue)
{
	return CGSizeEqualToSize(prevValue, curValue);
}
template<> inline BOOL EBN_PropertyEqualityTest<NSRange>(const NSRange prevValue, const NSRange curValue)
{
	return NSEqualRanges(prevValue, curValue);
}
template<> inline BOOL EBN_PropertyEqualityTest<UIEdgeInsets>(const UIEdgeInsets prevValue, const UIEdgeInsets curValue)
{
	return UIEdgeInsetsEqualToEdgeInsets(prevValue, curValue);
}

/****************************************************************************************************
	EBNComparePropertyEquality
    
	Given a property name and two objects that may contain that property, evaluates the property value
	for both objects and determines whether the property values are equal.
	
	Not to be used for object-valued properties.
*/
template<typename T> inline BOOL EBNComparePropertyEquality(NSString *propName,
		NSInteger index, EBNKeypathEntryInfo *info, id prevObject, id curObject)
{	
	T prevPropValue;
	T curPropValue;
	
	// For non-object-typed properties, the prop must be the endpoint of this keypath. If we don't have 
	// a previous and current object, the property value is considered modified and we don't need to examine
	// the property value.
	if (!prevObject)
	{
		// However, if curObject is nonnil, we do need to force the endpoint property valid if it is lazy-loaded.
		[curObject ebn_forcePropertyValid:propName];
		return YES;
	}
	else if (!curObject)
	{
		return YES;
	}
		
	Class prevObjClass = object_getClass(prevObject);
	SEL getterSelector = ebn_selectorForPropertyGetter(prevObjClass, propName);
	if (getterSelector)
	{
		typedef T (*getterMethodFnType)(id, SEL);
		getterMethodFnType getterMethod = (getterMethodFnType)
				class_getMethodImplementation(prevObjClass, getterSelector);
		prevPropValue = getterMethod(prevObject, getterSelector);
	}
	else
	{
		return YES;
	}
	
	Class curObjClass = object_getClass(curObject);
	getterSelector = ebn_selectorForPropertyGetter(curObjClass, propName);
	if (getterSelector)
	{
		typedef T (*getterMethodFnType)(id, SEL);
		getterMethodFnType getterMethod = (getterMethodFnType) 
				class_getMethodImplementation(curObjClass, getterSelector);
		curPropValue = getterMethod(prevObject, getterSelector);
	}
	else
	{
		return YES;
	}
	
	return EBN_PropertyEqualityTest(prevPropValue, curPropValue);
}

/****************************************************************************************************
	EBNUpdateKeypath()
	
	Traverses the keypath in the given entry, moving observation entries from the tree rooted at previousValue
	to the tree rooted at newValue. Returns TRUE if any endpoint of the keypath differs semantically due 
	to the change.
	
	If someone is is observing a keypath "a.b.c.d" and object "[b setC]" gets called, property "c"
	of object b will get a new value, meaning that we need to update our observations on object "c",
	removing observation on the old object and adding it to the new (unless either of them is nil).
	All of this keypath craziness only happens for properties of type id, so this template specialization
	makes that happen. That's why the general template case does nothing.
	
	For non-objects, returns true because we already know the previous and new values are different, and 
	they don't have keypaths that extend beyond them.

*/
template<typename T> static inline bool EBNUpdateKeypath(const EBNKeypathEntryInfo * const entry,
			const T previousValue, const T newValue) { return true; }

template<> inline bool EBNUpdateKeypath<id>(const EBNKeypathEntryInfo * const entry,
			const id previousValue, const id newValue)
{
	return [entry ebn_updateNextKeypathEntryFrom:previousValue to:newValue];
}

/****************************************************************************************************
	template <T> overrideSetterMethod()
	
	Overrides the given setter method with a new method (actually a block with implementationWithBlock()
	used on it) that notifies observers after it's called.
*/
template<typename T> void overrideSetterMethod(NSString *propName,
		Method setter, Method getter, EBNShadowedClassInfo *classInfo)
{
	// All of these local variables get copied into the setAndObserve block
	void (*originalSetter)(id, SEL, T) = (void (*)(id, SEL, T)) method_getImplementation(setter);
	SEL setterSEL = method_getName(setter);
	SEL getterSEL = method_getName(getter);
	
	// This is what gets run when the setter method gets called.
	void (^setAndObserve)(NSObject *, T) = ^void (NSObject *blockSelf, T newValue)
	{
		// Do we have any observers active on this property?
		NSMutableArray *observers = NULL;
		NSMutableDictionary *observedKeysDict = [blockSelf ebn_observedKeysDict:NO];
		if (observedKeysDict)
		{
			@synchronized(observedKeysDict)
			{
				observers = [observedKeysDict[propName] mutableCopy];
				NSMutableArray *splatObservers = observedKeysDict[@"*"];
				if (observers && splatObservers)
					[observers addObjectsFromArray:splatObservers];
				else if (splatObservers && !observers)
					observers = [splatObservers copy];				
			}
		}
				
		// If there's no observers, call the original setter, mark the property valid, and return
		if (!observers)
		{
			(originalSetter)(blockSelf, setterSEL, newValue);
			[blockSelf ebn_markPropertyValid:propName];
			return;
		}
		
		// If the property is being observed, check if our new value is actually different than the old one
		// Also, set the new value.  CANNOT BE IN A SYNCHRONIZE
		T (*getterImplementation)(id, SEL) = (T (*)(id, SEL)) method_getImplementation(getter);
		T previousValue = getterImplementation(blockSelf, getterSEL);
		(originalSetter)(blockSelf, setterSEL, newValue);
		
		// If we call the getter, we don't need to do this. If we instead get the previous value via ivar,
		// we'll need to.
		[blockSelf ebn_markPropertyValid:propName];
		
		// If the value actually changes do all the observation stuff
		if (!EBN_PropertyEqualityTest(previousValue, newValue))
		{
			BOOL prevValueHasBeenWrapped = NO;
			id wrappedPreviousValue = nil;
			NSMutableArray *delayedObservers = NULL;
			
			for (EBNKeypathEntryInfo *entry in observers)
			{
				// Update the keypath, and check for path semantic equality
				// Only the object specialization actually implements this
				// (only objects can have properties, ergo everyone else is a keypath endpoint).
				// If UpdateKeypath returns NO, the property at the keypath endpoint didn't change.
				bool pathValueChanged = EBNUpdateKeypath(entry, previousValue, newValue);

				// Break into the debugger if the property value was changed.
				EBNObservation *blockInfo = entry->_blockInfo;
				if (blockInfo.willDebugBreakOnChange)
				{
					if (EBNIsADebuggerConnected())
					{
						EBLogStdOut(@"debugBreakOnChange breakpoint on property: %@", propName);
						if (blockInfo.debugString.length > 0)
						{
							EBLogStdOut(@"    debugString: %@", blockInfo.debugString);
						}
				
						// This line will cause a break in the debugger! If you stop here in the debugger, it is
						// because someone set the debugBreakOnChange property on an EBNObservation to YES, and
						// one of the keypaths it is observing just changed.
						DEBUG_BREAKPOINT;
					}
				}
				
				// If this is an immed block, wrap the previous value and call it.
				// Why not just call [blockSelf valueForKey:]? Immed blocks shouldn't be used much
				// and we'd have to call valueForKey before setting the new value.
				if (blockInfo->_copiedImmedBlock)
				{
					if (!prevValueHasBeenWrapped)
					{
						wrappedPreviousValue = EBNWrapValue(previousValue);
						prevValueHasBeenWrapped = YES;
					}
					[blockInfo executeImmedBlockWithPreviousValue:wrappedPreviousValue];
				}
				
				if (pathValueChanged && blockInfo->_copiedBlock)
				{
					if (!delayedObservers)
						delayedObservers = [[NSMutableArray alloc] init];
					[delayedObservers addObject:entry];
				}
			}
			
			// Add these blocks to the global collections of "run later" blocks. Reap blocks
			// if any of blocks have become zombies (observed object has been dealloc'ed).
			if (delayedObservers.count)
			{
				if ([EBNObservation scheduleBlocks:delayedObservers])
					[blockSelf ebn_reapBlocks];
			}
		}
	};

	// Now replace the setter's implementation with the new one
	IMP swizzledImplementation = imp_implementationWithBlock(setAndObserve);
	class_replaceMethod(classInfo->_shadowClass, setterSEL, swizzledImplementation, method_getTypeEncoding(setter));
}

/****************************************************************************************************
	EBN_RunLoopObserverCallBack()
	
	This method is a CFRunLoopObserver, scheduled with kCFRunLoopBeforeWaiting, so it fires just before
	the run loop idles.
	
	Calls all the observer blocks that got scheduled during the current runloop.
*/
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info)
{
	// Make a copy the list of blocks we need to call. This copy goes into a global that is only
	// mutated by the main thread. So, after this sync, all other threads that mutate observed
	// properties are adding blocks to EBN_ObserverBlocksToRunAfterThisEvent, which will schedule
	// the block for the next time this method is called. Blocks scheduled by the main thread (which
	// functionally means blocks scheduled due to code in other blocks) will be added to the BeingDrained set.
	@synchronized(EBNObservableSynchronizationToken)
	{
		if (![EBN_ObserverBlocksToRunAfterThisEvent count])
			return;

		EBN_ObserverBlocksBeingDrained = [EBN_ObserverBlocksToRunAfterThisEvent mutableCopy];
		[EBN_ObserverBlocksToRunAfterThisEvent removeAllObjects];
		EBN_ObservedObjectBeingDrainedKeepAlive = EBN_ObservedObjectKeepAlive;
		EBN_ObservedObjectKeepAlive = [[NSMutableArray alloc] init];
	}
	
	// Observers could set properties, creating more observation blocks. We should call those
	// observers too, unless it will cause recursion. The idea is the masterCallList tracks
	// every block we've called during this event, and we only call any particular block once.
	NSMutableSet *masterCallList = [NSMutableSet set];
	
	// If we find any blocks whose observer objects have been dealloc'ed, we will want to call reapBlocks on
	// those observed objects, but we only need to call reap once per object.
	NSMutableSet *objectsToReap = nil;
	
	while (EBN_ObserverBlocksBeingDrained)
	{
		// Step 1: Copy the list of objects that have blocks that need to be called
		NSMutableSet *thisIterationCallList = [EBN_ObserverBlocksBeingDrained mutableCopy];
		
		// Step 2: Add the blocks we're going go call to the master list
		[masterCallList unionSet:thisIterationCallList];

		// Step 3: Call each observation block
		for (EBNObservation *blockInfo in thisIterationCallList)
		{
			if (![blockInfo execute])
			{
				// We are holding the observed object in the keepAlive array; _weakObserved should be non-nil
				if (!objectsToReap)
					objectsToReap = [NSMutableSet set];
				[objectsToReap addObject:blockInfo->_weakObserved];
			}
		}

		// Step 4: Remove any blocks we've already called from the global set
		[EBN_ObserverBlocksBeingDrained minusSet:masterCallList];
		if (![EBN_ObserverBlocksBeingDrained count])
			EBN_ObserverBlocksBeingDrained = nil;
	}
	
	// Step 5. Reap
	for (NSObject *obj in objectsToReap)
	{
		[obj ebn_reapBlocks];
	}
	
	// We're done notifying observers, purge the retains we've been keeping
	EBN_ObservedObjectBeingDrainedKeepAlive = nil;
}

/****************************************************************************************************
	EBNIsADebuggerConnected()
	
	EBNIsADebuggerConnected calls sysctl() to see if a debugger is attached. Sample code courtesy Apple:
		https://developer.apple.com/library/mac/qa/qa1361/_index.html

	Because the struct kinfo_proc is marked unstable by Apple, we only use this code for Debug builds.
	That means this method will return FALSE on release builds, even if a debugger *is* attached.
	
	Importantly, this code DOES NOT EVEN COMPILE IN THE CODE THAT WOULD CHECK IF A DEBUGGER IS ATTACHED
	unless you're running DEBUG.
*/
BOOL EBNIsADebuggerConnected(void)
{
#if defined(DEBUG) && DEBUG
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid () };

	// xcode 7 appears not to like the = {0} initializer syntax here
	struct kinfo_proc info;
	
	memset(&info, 0, sizeof(info));
	size_t size = sizeof (info);
	sysctl (mib, sizeof (mib) / sizeof (*mib), &info, &size, NULL, 0);

	// We're being debugged if the P_TRACED flag is set.
	return (info.kp_proc.p_flag & P_TRACED) != 0;
#else
	return NO;
#endif
}



