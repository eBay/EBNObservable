/****************************************************************************************************
	Observable.mm
	Observable

	Created by Chall Fry on 8/18/13.
    Copyright (c) 2013-2014 eBay Software Foundation.
*/

#import <sys/sysctl.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIGeometry.h>
#import <CoreGraphics/CGGeometry.h>

#import "EBNObservableInternal.h"


// When we create a shadowed subclass we'll add these functions as methods of the new subclass
static void EBNOverrideDeallocForClass(Class shadowClass);
static void ebn_shadowed_dealloc(__unsafe_unretained NSObject *self, SEL _cmd);
static Class ebn_shadowed_ClassForCoder(id self, SEL _cmd);

// This very special function gets template expanded into each type of property we know how to override.
// This creates a function for bool properties, one for int properties, one for Obj-C objects, etc.
template<typename T> void overrideSetterMethod(NSString *propName, Method setter, Method getter, Class classToModify);

// This is the function that gets installed in the run loop to call all the observer blocks that have been scheduled.
extern "C"
{
	void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);
}

// A debugging-support method, this tells us whether a debugger is attached.
BOOL EBNAmIBeingDebugged(void);


	// Keeping track of delayed blocks
static NSMutableSet				*EBN_ObserverBlocksToRunAfterThisEvent;
static NSMutableSet				*EBN_ObserverBlocksBeingDrained;
static NSMutableArray			*EBN_ObservedObjectKeepAlive;
static NSMutableArray 			*EBN_ObservedObjectBeingDrainedKeepAlive;

	// Shadow classes--private subclasses that we create to implement overriding setter methods
	// This dictionary holds EBNShadowedClassInfo objects, and is keyed with Class objects
NSMutableDictionary				*EBNBaseClassToShadowInfoTable;

	// Not used for anything other than as a @synchronize token. Currently is a pointer alias to
	// EBN_ObserverBlocksToRunAfterThisEvent, but that could change.
NSMutableSet					*EBNObservableSynchronizationToken;

	// Whether we should issue warnings when we see the same object observing the same keypath multiple times.
BOOL 							ebn_WarnOnMultipleObservations = true;


#pragma mark -
/**
	EBNKeypathEntryInfo is pretty much just a data struct; its only method is the debugging method below.
*/
@implementation EBNKeypathEntryInfo

- (NSString *) debugDescription
{
	NSString *returnStr = [NSString stringWithFormat:@"Path:\"%@\": %@", self->_keyPath,
			[self->_blockInfo debugDescription]];
	return returnStr;
}

@end

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
		self->_baseClass = baseClass;
		self->_shadowClass = newShadowClass;
		self->_getters = [[NSMutableSet alloc] init];
		self->_setters = [[NSMutableSet alloc] init];
	}
	return self;
}
@end

#pragma mark -
/**
	EBNObservable used to be the required base class for any class whose properties were observed. Now
	that any class can be observed, EBNObservable is still being kept around for continuity. 
	
	It does also provide a minor performance boost, as associated objects aren't required, but that's really minor.
 */
@implementation EBNObservable
{
@public
	// observedMethods maps properties (specified by the setter method name, as a string) to
	// a NSMutableSet of blocks to be called when the property changes.
	NSMutableDictionary *_observedMethods;
}

/**
	For subclasses of EBNObservable, this just returns the ivar for the observed methods table.
	For other classes, this gets the observed methods dict out of an associated object.

	@return Returns the observed methods dictionary.
 */
- (NSMutableDictionary *) ebn_observedMethodsDict
{
	@synchronized(EBNObservableSynchronizationToken)
	{
		if (!_observedMethods)
			_observedMethods = [[NSMutableDictionary alloc] init];
	}

	return _observedMethods;
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
	
	Deregisters all notifications for a particular keypath that notify the given listener. 
	Usually this is one observation block, as this is usally the 'remove one KVO observation' call.
	But there can be multiple blocks registered by the same observer to view the same keypath.
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
	@synchronized(EBNObservableSynchronizationToken)
	{
		NSMapTable *observerTable = self.ebn_observedMethodsDict[propName];
		for (EBNKeypathEntryInfo *entry in observerTable)
		{
			if (entry->_blockInfo->_weakObserver_forComparisonOnly == observer &&
					[keyPath isEqualToArray:entry->_keyPath] &&
					!entry->_blockInfo.isForLazyLoader)
			{
				NSInteger index = [[observerTable objectForKey:entry] integerValue];
				if (index == 0)
				{
					// We've found the right entry. Call the recursive remove method.
					[entriesToRemove addObject:entry];
				}
			}
		}
	}
	
	// And then remove them
	for (EBNKeypathEntryInfo *entry in entriesToRemove)
	{
		[self ebn_removeKeypath:entry atIndex:0];
	}
}

/****************************************************************************************************
	stopTelling:aboutChangesToArray:
	
	The companion method for tell:whenAny:changes:.
*/
- (void) stopTelling:(id) observer aboutChangesToArray:(NSArray *) propertyList
{
	for (NSString *propName in propertyList)
	{
		[self stopTelling:observer aboutChangesTo:propName];
	}
}

/****************************************************************************************************
	stopTellingAboutChanges:
	
	Stop telling the given observer object about all changes to any known property.
*/
- (void) stopTellingAboutChanges:(id) observer
{
	int removedBlockCount = 0;
	NSMutableSet *entriesToRemove = [[NSMutableSet alloc] init];

	@synchronized(EBNObservableSynchronizationToken)
	{
		for (NSString *propertyKey in [self.ebn_observedMethodsDict allKeys])
		{
			NSMapTable *observerTable = self.ebn_observedMethodsDict[propertyKey];
			
			for (EBNKeypathEntryInfo *entryInfo in observerTable)
			{
				// We're only looking for the blocks for which this is the observed object.
				NSInteger index = [[observerTable objectForKey:entryInfo] integerValue];
				if (entryInfo->_blockInfo->_weakObserver_forComparisonOnly == observer && index == 0 &&
						!entryInfo->_blockInfo.isForLazyLoader)
				{
					[entriesToRemove addObject:entryInfo];
					++removedBlockCount;
				}
			}
		}
	}

	for (EBNKeypathEntryInfo *entryInfo in entriesToRemove)
	{
		[self ebn_removeKeypath:entryInfo atIndex:0];
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
	remove all KVO notifications for this object that'd call that block.
	
	Must be sent to the same object that you sent the "tell:" method to when you set up the observation,
	but matches any keypath. That is, this won't remove an observation whose keypath goes through or
	ends at this object, only ones that start at this object.
*/
- (void) stopAllCallsTo:(ObservationBlock) stopBlock
{
	int removedBlockCount = 0;
	NSMutableSet *entriesToRemove = [[NSMutableSet alloc] init];

	@synchronized(EBNObservableSynchronizationToken)
	{
		for (NSString *propertyKey in [self.ebn_observedMethodsDict allKeys])
		{
			NSMapTable *observerTable = self.ebn_observedMethodsDict[propertyKey];
			
			for (EBNKeypathEntryInfo *entryInfo in observerTable)
			{
				// Match on the entries where the block that gets run is the indicated block
				NSInteger index = [[observerTable objectForKey:entryInfo] integerValue];
				if (entryInfo->_blockInfo->_copiedBlock == stopBlock && index == 0)
				{
					[entriesToRemove addObject:entryInfo];
					++removedBlockCount;
				}
			}
		}
	}
	
	for (EBNKeypathEntryInfo *entryInfo in entriesToRemove)
	{
		[self ebn_removeKeypath:entryInfo atIndex:0];
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
	
	See prepareToObserveProperty:, where this class method gets overridden for Observable shadow classes,
	and will return the propert base class.
*/
+ (Class) ebn_properBaseClass
{
	return self;
}

#pragma mark Somewhat Protected

/****************************************************************************************************
	ebn_manuallyTriggerObserversForProperty:previousValue:
	
	Manually adds the observers for the given property to the list of observers to call. Useful
	if a observed object needs to use direct ivar access yet still wants to trigger observers.
*/
- (void) ebn_manuallyTriggerObserversForProperty:(NSString *) propertyName previousValue:(id) prevValue
{
	NSMapTable *observerTable = nil;
	@synchronized(EBNObservableSynchronizationToken)
	{
		observerTable = [self.ebn_observedMethodsDict[propertyName] copy];
	}
	
	// If nobody's observing, nothing to do
	if (!observerTable)
		return;
	
	// Execute all the LazyLoader blocks; this handles chained lazy properties--that is, cases where
	// one lazy property depends on another lazy property. We should do this before calling
	// immediate blocks, so that an immed block that references a lazy property will force a recompute.
	
	size_t numLazyLoaderBlocks = 0;
	for (EBNKeypathEntryInfo *entry in observerTable)
	{
		EBNObservation *blockInfo = entry->_blockInfo;

		if (blockInfo.isForLazyLoader)
		{
			// Make sure the observed object still exists before calling/scheduling blocks
			NSObject *strongObserved = blockInfo->_weakObserved;
			if (strongObserved)
			{
				// Execute any immediate blocks
				if (blockInfo->_copiedImmedBlock)
				{
					[blockInfo executeWithPreviousValue:prevValue];
				}
			}
			++numLazyLoaderBlocks;
		}
	}
	
	// If that was all the blocks, we're done. Return before we go eval the new value
	if ([observerTable count] == numLazyLoaderBlocks)
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
			copiedObserverTable:observerTable];
}

/****************************************************************************************************
	ebn_manuallyTriggerObserversForProperty:previousValue:newValue:
	
	Manually adds the observers for the given property to the list of observers to call.
	
	This method takes the new value of the property as a parameter, and exits early if the value didn't
	change. It's better to use this method in the case where the new value of the property is known.
	
	This method is used by the collection classes, including the case where the special "*" key
	changes.
*/
- (void) ebn_manuallyTriggerObserversForProperty:(NSString *) propertyName previousValue:(id) prevValue
		newValue:(id) newValue
{
	// Don't test for 'isEqual' here--keypaths need to be updated whenever the pointers are different
	if (newValue != prevValue || [propertyName isEqualToString:@"*"])
	{
		NSMapTable *observerTable = nil;
		@synchronized(EBNObservableSynchronizationToken)
		{
			observerTable = [self.ebn_observedMethodsDict[propertyName] copy];
		}
		
		// If nobody's observing, we're done.
		if (!observerTable)
			return;
		
		// Execute all the LazyLoader blocks; this handles chained lazy properties--that is, cases where
		// one lazy property depends on another lazy property. We should do this before calling
		// immediate blocks, so that an immed block that references a lazy property will force a recompute.
		
		size_t numLazyLoaderBlocks = 0;
		for (EBNKeypathEntryInfo *entry in observerTable)
		{
			EBNObservation *blockInfo = entry->_blockInfo;

			if (blockInfo.isForLazyLoader)
			{
				// Make sure the observed object still exists before calling/scheduling blocks
				NSObject *strongObserved = blockInfo->_weakObserved;
				if (strongObserved)
				{
					// Execute any immediate blocks
					if (blockInfo->_copiedImmedBlock)
					{
						[blockInfo executeWithPreviousValue:prevValue];
					}
				}
				++numLazyLoaderBlocks;
			}
		}
		
		// If that was all the blocks, we're done. Return before we go eval the new value
		if ([observerTable count] == numLazyLoaderBlocks)
			return;

	[self ebn_manuallyTriggerObserversForProperty:propertyName previousValue:prevValue newValue:newValue
				copiedObserverTable:observerTable];
	}
}

/****************************************************************************************************
	ebn_manuallyTriggerObserversForProperty:previousValue:newValue:copiedObserverTable:
	
	Internal method to trigger observers. Takes a COPY of the observer table (because @sync).
	The caller should check that the previous and new values aren't equal (using ==) and not call
	this method if they are, but should not check isEqual: (because of how keypath updating works).
*/
- (void) ebn_manuallyTriggerObserversForProperty:(NSString *)propertyName previousValue:(id)prevValue
		newValue:(id)newValue copiedObserverTable:(NSMapTable *) observerTable
{
	// Go through all the observations, update any keypaths that need it.
	// If we update a keypath, we'll need to evaluate the property value to get the new value
	for (EBNKeypathEntryInfo *entry in observerTable)
	{
		// If the property that changed had a observation on it that was in the
		// middle of the keypath's observation, fix up the observation keypath.
		NSInteger index = [[observerTable objectForKey:entry] integerValue];
		if (index != [entry->_keyPath count] - 1)
		{
			[prevValue ebn_removeKeypath:entry atIndex:index + 1];
			[newValue ebn_createKeypath:entry atIndex:index + 1];
		}
	}
	
	// Now, if the property didn't change value we don't need to schedule blocks
	if ([newValue isEqual:prevValue])
	{
		return;
	}

	// Go through the table again and schedule all the non-lazyloader blocks
	BOOL reapBlocksAfter = NO;
	for (EBNKeypathEntryInfo *entry in observerTable)
	{
		EBNObservation *blockInfo = entry->_blockInfo;
		
		// We already went through all the lazyloader blocks
		if (blockInfo.isForLazyLoader)
			continue;

		// Make sure the observed object still exists before calling/scheduling blocks
		NSObject *strongObserved = blockInfo->_weakObserved;
		if (strongObserved)
		{
			// Execute any immediate blocks
			if (blockInfo->_copiedImmedBlock)
			{
				[blockInfo executeWithPreviousValue:prevValue];
			}
		
			// Schedule any delayed blocks; also keep the observed object alive until the delayed block is called.
			if (blockInfo->_copiedBlock)
			{
				@synchronized(EBNObservableSynchronizationToken)
				{
					if (EBN_ObserverBlocksBeingDrained && [NSThread isMainThread])
					{
						[EBN_ObserverBlocksBeingDrained addObject:blockInfo];
						[EBN_ObservedObjectBeingDrainedKeepAlive addObject:strongObserved];
					}
					else
					{
						[EBN_ObserverBlocksToRunAfterThisEvent addObject:blockInfo];
						[EBN_ObservedObjectKeepAlive addObject:strongObserved];
					}
				}
			}
		} else
		{
			reapBlocksAfter	= YES;
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
	// Clean out any observation blocks that are inactive because their observer went away.
	// We don't want to count them.
	[self ebn_reapBlocks];
	
	@synchronized(EBNObservableSynchronizationToken)
	{
		NSMutableSet *observerTable = self.ebn_observedMethodsDict[propertyName];
		NSUInteger numObservers = [observerTable count];
		return numObservers;
	}
}

/****************************************************************************************************
	allObservedProperties
	
	Returns all the properties currently being observed, as an array of strings. This includes
	properties being observed because a keypath rooted at some other object runs through (or ends at)
	this object.
*/
- (NSArray *) allObservedProperties
{
	[self ebn_reapBlocks];
	
	NSArray *properties = nil;
	@synchronized(EBNObservableSynchronizationToken)
	{
		properties = [self.ebn_observedMethodsDict allKeys];
	}
	
	return properties;
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
		EBNBaseClassToShadowInfoTable = [[NSMutableDictionary alloc] init];
	});
}

/****************************************************************************************************
	ebn_observedMethodsDict
	
	This gets the observed methods dict out of an associated object, creating it if necessary.
	Note the EBNObservable has its own implementation of this method, which gets the dict out of an ivar.
	
	The caller of this method must be inside a @synchronized(EBNObservableSynchronizationToken), and must
	remain inside that sync while using the dictionary.
*/
- (NSMutableDictionary *) ebn_observedMethodsDict
{
	NSMutableDictionary *observedMethods = objc_getAssociatedObject(self, @selector(ebn_observedMethodsDict));
	if (!observedMethods)
	{
		observedMethods = [[NSMutableDictionary alloc] init];
		objc_setAssociatedObject(self, @selector(ebn_observedMethodsDict), observedMethods,
				OBJC_ASSOCIATION_RETAIN);
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
	
	This version just passes through to valueForKey, but the Observable collection classes override this method.
*/
- (id) ebn_valueForKey:(NSString *)key
{
	// valueForKey is inside an exception handler because some property types aren't KVC-compliant
	// and throw NSUnknownKeyException when it appears the actual problem is that KVC can't box up the type,
	// as opposed to being unable to find a getter method or ivar. ebn_valueForKey is private to Observable
	// and doesn't care about these exceptions.
	@try
	{
    	return [self valueForKey:key];
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
	
	return nil;
}

/****************************************************************************************************
	ebn_observe:using:
	
	Sets up an observation.
*/
- (BOOL) ebn_observe:(NSString *) keyPathString using:(EBNObservation *) blockInfo
{
	// Create our keypath entry
	EBNKeypathEntryInfo	*entryInfo = [[EBNKeypathEntryInfo alloc] init];
	entryInfo->_keyPath = [keyPathString componentsSeparatedByString:@"."];
	entryInfo->_blockInfo = blockInfo;
	
	for (int index = 0; index < [entryInfo->_keyPath count] - 1; ++index)
	{
		EBAssert(![entryInfo->_keyPath[index] isEqualToString:@"*"],
				@"Only the final part of a keypath can use the '*' operator.");
	}

	BOOL kvoSetUp = [self ebn_createKeypath:entryInfo atIndex:0];
	EBAssert(kvoSetUp, @"Unable to set up observation on keypath %@", keyPathString);
	
	return kvoSetUp;
}

/****************************************************************************************************
	ebn_createKeypath:atIndex:
	
	Keypaths look like "a.b.c.d" where "a" is an EBNObservable object, "b" and "c" are 
	properties of the object before them (and are also of type EBNObservable), and "d" is a
	property of "c" but can have any valid property type.
	
	The index argument tells this method what part of the keypath it's setting up. This method works
	by setting up observation on one property of one object, and then if this isn't the end of the 
	keypath it calls the ebn_createKeypath method of the next object in the path, incrementing
	the index argument in the call.

	If the current property value of the non-endpoint property being observed is nil, we stop
	setting up observation on the keypath. If the property's value changes to non-nil in the 
	future, ebn_createKeypath:atIndex: is called to continue setting up the keypath. Similarly,
	if the property value changes, the 'old' keypath from that point is removed, and a new
	one is built from the changed property value to the end of the keypath.
	
	Returns TRUE if the keypath was set up successfully.
*/
- (BOOL) ebn_createKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
{
	// Get the property name we'll be adding observation on
	NSString *propName = entryInfo->_keyPath[index];
	
	// If this is a '*' observation, observe all properties via recusive calls
	if ([propName isEqualToString:@"*"])
	{
		Class curClass = [self class];

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
					// If any particular observe fails, it's okay (probably means a readonly property)
					NSString *propString = @(property_getName(properties[propIndex]));
					if (propString)
					{
						[self ebn_createKeypath:entryInfo atIndex:index forProperty:propString];
					}
				}
			
				free(properties);
			}
			
			curClass = [curClass superclass];
		}
	} else
	{
		return [self ebn_createKeypath:entryInfo atIndex:index forProperty:propName];
	}
	
	return true;
}

/****************************************************************************************************
	ebn_createKeypath:atIndex:forProperty:
	
	Keypaths look like "a.b.c.d" where "a" is an EBNObservable object, "b" and "c" are 
	properties of the object before them (and are also of type EBNObservable), and "d" is a
	property of "c" but can have any valid property type.
	
	The index argument tells this method what part of the keypath it's setting up. This method works
	by setting up observation on one property of one object, and then if this isn't the end of the 
	keypath it calls the ebn_createKeypath method of the next object in the path, incrementing
	the index argument in the call.

	If the current property value of the non-endpoint property being observed is nil, we stop
	setting up observation on the keypath. If the property's value changes to non-nil in the 
	future, ebn_createKeypath:atIndex: is called to continue setting up the keypath. Similarly,
	if the property value changes, the 'old' keypath from that point is removed, and a new
	one is built from the changed property value to the end of the keypath.
	
	Returns TRUE if the keypath was set up successfully.
*/
- (BOOL) ebn_createKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
		forProperty:(NSString *) propName
{
	BOOL success = NO;
	BOOL tableWasEmpty = NO;

	// Check that this class is set up to observe the given property. That is, check that we've
	// swizzled the setter.
	[self ebn_swizzleImplementationForSetter:propName];

	@synchronized(EBNObservableSynchronizationToken)
	{
		NSMapTable *observerTable = self.ebn_observedMethodsDict[propName];

		// Check for the case where this entryInfo is already in the table. Since
		// there's one entryInfo for each keypath, this likely indicates a property loop
		NSNumber *keypathIndex = [observerTable objectForKey:entryInfo];
		if (keypathIndex)
		{
			EBAssert([keypathIndex integerValue] != index, @"This keypath entry is already being observed? Shouldn't happen.");
			EBAssert([keypathIndex integerValue] == index, @"This appears to be property loop? Observable can't handle these.");
		}

		if (ebn_WarnOnMultipleObservations)
		{
			// Check for the case where the observer is already observing this property
			id observer = entryInfo->_blockInfo->_weakObserver;
			if (observer)
			{
				for (EBNKeypathEntryInfo *entry in observerTable)
				{
					if (entry->_blockInfo->_weakObserver == observer && [entry->_keyPath isEqualToArray:entryInfo->_keyPath])
					{
						EBLogContext(kLoggingContextOther,
								@"%@: While adding a new observer: The observer object (%@) is already "
								@"observing the property %@. This is sometimes okay, but more often an error.",
								[self class], [observer debugDescription], propName);
					}
				}
			}
		}
	
		// Now get the set of blocks to invoke when a particular setter is called.
		// If the set doesn't exist, create it and add it to the method dict.
		if (!observerTable)
		{
			observerTable = [NSMapTable strongToStrongObjectsMapTable];
			self.ebn_observedMethodsDict[propName] = observerTable;
			tableWasEmpty = true;
		}
				
		[observerTable setObject:[NSNumber numberWithInteger:index] forKey:entryInfo];
	}
	
	if (index == [entryInfo->_keyPath count] - 1)
	{
		// If this is the endoint, we're done.
		success = true;
		
		// Get the value of the endpoint property; this forces lazyloader to mark it valid if it's lazyloaded
		if (!entryInfo->_blockInfo.isForLazyLoader)
			[self ebn_forcePropertyValid:propName];
	} else
	{
		// Not endoint. Move to the next property in the chain, and recurse.
		NSObject *next = [self ebn_valueForKey:propName];
		if (next)
		{
			EBAssert([next respondsToSelector:@selector(ebn_createKeypath:atIndex:)],
					@"Every property in a keypath (except the last) needs to respond to createKeypath.");
			success = [next ebn_createKeypath:entryInfo atIndex:index + 1];
		} else
		{
			// If the property value is nil, we can't recurse any farther, but it also means
			// we've successfully setup observation.
			success = true;
		}
	}
		
	// If the table had been empty, but now isn't, this means the given property
	// is now being observed (and wasn't before now). Inform ourselves.
	if (tableWasEmpty && [self respondsToSelector:@selector(property:observationStateIs:)])
	{
		NSObject <EBNObserverNotificationProtocol> *target = (NSObject<EBNObserverNotificationProtocol> *) self;
		[target property:propName observationStateIs:TRUE];
	}
		
	return success;
}

/****************************************************************************************************
	ebn_removeKeypath:atIndex:

	Removes the observation on the property at the given index into the given keypath entry,
	(which should map to a property of this object), and then calls ebn_removeKeypath:atIndex:
	with index + 1 on the next object in the keypath. Stops when we get to the endpoint property.
	
	When a property in the middle of an observed keypath changes value, this method gets called
	as the 'old' path is removed (and then the 'new' path gets built).
	
	Returns TRUE if the observation path was removed successfully.
*/
- (BOOL) ebn_removeKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
{
	if (index >= [entryInfo->_keyPath count])
		return NO;

	NSString *propName = entryInfo->_keyPath[index];
	
	// If this is a '*' observation, remove all observations via recursive calls
	if ([propName isEqualToString:@"*"])
	{
		NSArray *properties = nil;
		@synchronized(EBNObservableSynchronizationToken)
		{
			properties = [self.ebn_observedMethodsDict allKeys];
		}
		
		for (NSString *property in properties)
		{
			[self ebn_removeKeypath:entryInfo atIndex:index forProperty:property];
		}
	}
	else
	{
		return [self ebn_removeKeypath:entryInfo atIndex:index forProperty:propName];
	}
	
	return true;
}

/****************************************************************************************************
	ebn_removeKeypath:atIndex:forProperty:

	Removes the observation on the property at the given index into the given keypath entry,
	(which should map to a property of this object), and then calls ebn_removeKeypath:atIndex:
	with index + 1 on the next object in the keypath. Stops when we get to the endpoint property.
	
	When a property in the middle of an observed keypath changes value, this method gets called
	as the 'old' path is removed (and then the 'new' path gets built).
	
	Returns TRUE if the observation path was removed successfully.
*/
- (BOOL) ebn_removeKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
		forProperty:(NSString *) propName
{
	BOOL observerTableRemoved = NO;

	// Remove the entry from the observer table for the given property.
	@synchronized(EBNObservableSynchronizationToken)
	{
		NSMapTable *observerTable = self.ebn_observedMethodsDict[propName];
		[observerTable removeObjectForKey:entryInfo];
		
		// Could check for duplicate entries and reap zeroed entries here
		
		if (observerTable && ![observerTable count])
		{
			[self.ebn_observedMethodsDict removeObjectForKey:propName];
			observerTableRemoved = true;
		}
	}
	
	// If this isn't the endpoint property, recurse--call this same method in the
	// next object in the keypath
	if (index < [entryInfo->_keyPath count] - 1)
	{
		NSObject *next = [self ebn_valueForKey:propName];
		if (next)
		{
			[next ebn_removeKeypath:entryInfo atIndex:index + 1];
		}
	}
	
	// If nobody is observing this property anymore, inform ourselves
	if (observerTableRemoved && [self respondsToSelector:@selector(property:observationStateIs:)])
	{
		NSObject <EBNObserverNotificationProtocol> *target = (NSObject<EBNObserverNotificationProtocol> *) self;
		[target property:propName observationStateIs:FALSE];
	}
	
	return observerTableRemoved;
}

/****************************************************************************************************
	ebn_reapBlocks

	Checks every registered block in this object, removing blocks whose observer has been deallocated.
	This method will tell other Observable objects to remove entries for keypaths where their observing
	object has been deallocated.
	
	Rember that the lifetime of an observer block should be until either the observed or observing
	object goes away (or it's explicitly removed). However, since there isn't a notifying zeroing 
	weak pointer, we do this to clean up.
	
	Returns the number of blocks that got reaped.
*/
- (int) ebn_reapBlocks
{
	int removedBlockCount = 0;
	NSMutableSet *entriesToRemove = [[NSMutableSet alloc] init];

	@synchronized(EBNObservableSynchronizationToken)
	{
		for (NSString *propertyKey in [self.ebn_observedMethodsDict allKeys])
		{
			NSMapTable *observerTable = self.ebn_observedMethodsDict[propertyKey];
			for (EBNKeypathEntryInfo *entry in observerTable)
			{
				if (!entry->_blockInfo->_weakObserver)
				{
					[entriesToRemove addObject:entry];
				}
			}
		}
	}
		
	for (EBNKeypathEntryInfo *entry in entriesToRemove)
	{
		NSObject *strongObserved = entry->_blockInfo->_weakObserved;
		if (strongObserved)
		{
			[strongObserved ebn_removeKeypath:entry atIndex:0];
			++removedBlockCount;
		}
	}

	return removedBlockCount;
}

/****************************************************************************************************
	ebn_selectorForPropertySetter:
	
	Returns the SEL for a given property's setter method, given the name of the property as a string 
	(NOT the name of the setter method). The SEL will be a valid instance method for this
	class, or nil.
*/
+ (SEL) ebn_selectorForPropertySetter:(NSString *) propertyName
{
	// If this is an actual declared property, get the property, then its property attributes string,
	// then pull out the setter method from the string. Only finds custom setters, but must be done first.
	const char *propName = [propertyName UTF8String];
	objc_property_t prop = class_getProperty(self, propName);
	if (prop)
	{
		char *propString = property_copyAttributeValue(prop, "S");
		if (propString)
		{
			SEL methodSel = sel_registerName(propString);
			if (methodSel && [self instancesRespondToSelector:methodSel])
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
		if (methodSel && [self instancesRespondToSelector:methodSel])
		{
			foundMethodSelector = methodSel;
		}
		else
		{
			methodSel = sel_registerName(setterName);
			if (methodSel && [self instancesRespondToSelector:methodSel])
				foundMethodSelector = methodSel;
		}
		
		free(setterName);
	}
	
	return foundMethodSelector;
}

/****************************************************************************************************
	ebn_selectorForPropertyGetter:
	
	Returns the SEL for a given property's getter method, given the name of the property as a string
	(NOT the name of the setter method). The SEL will be a valid instance method for this
	class, or nil.
*/
+ (SEL) ebn_selectorForPropertyGetter:(NSString *) propertyName
{
	NSString *getterName = nil;
	SEL methodSel;
	Method getterMethod;

	// Check the case where the getter has the same name as the property
	methodSel = NSSelectorFromString(propertyName);
	getterMethod = class_getInstanceMethod(self, methodSel);
	if (getterMethod && method_getNumberOfArguments(getterMethod) == 2)
	{
		return methodSel;
	}

	// If the property has a custom getter, go find it by getting the property attribute string
	objc_property_t prop = class_getProperty(self, [propertyName UTF8String]);
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
			getterMethod = class_getInstanceMethod(self, methodSel);
			if (getterMethod && method_getNumberOfArguments(getterMethod) == 2)
				return methodSel;
		}
	}
	
	// Try prepending an underscore to the getter name
	getterName = [NSString stringWithFormat:@"_%@", propertyName];
	methodSel = NSSelectorFromString(getterName);
	getterMethod = class_getInstanceMethod(self, methodSel);
	if (getterMethod && method_getNumberOfArguments(getterMethod) == 2)
	{
		return methodSel;
	}
	
	return nil;
}

/****************************************************************************************************
	ebn_prepareToObserveProperty:isSetter:alreadyPrepared
	
	This returns the class where we should add/replace getter and setter methods in order to 
	implement observation.
	
	This class should be a runtime-created subclass of the given class. It could be a class created
	by Apple's KVO, or one created by us. If this method returns nil, it means either no suitable
	class exists and we can't observe this property, or we are already prepared to observe the
	given property and don't need to do anything.
	
	You can optionally pass a BOOL pointer in the alreadyPrepared parameter; in the case where
	the return value is nil this will tell you whether observation is going to work or not. 
	Should always be NO if the method returns a non-nil value.
	
	This method early-returns in several places. Edit carefully!
*/
- (Class) ebn_prepareToObserveProperty:(NSString *)propertyName isSetter:(BOOL) isSetter
		alreadyPrepared:(BOOL *) alreadyPrepared
{
	//
	Class curClass = object_getClass(self);
	Class shadowClass;
	EBNShadowedClassInfo *info = nil;
	BOOL mustSetMethodImplementation = NO;
	
	// Assume we haven't already prepared this property for observation
	if (alreadyPrepared)
		*alreadyPrepared = NO;
	
	@synchronized (EBNBaseClassToShadowInfoTable)
	{
			// 1. Is this object already shadowed?
		if (class_respondsToSelector(curClass, @selector(ebn_shadowClassInfo)))
		{
			info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
		}

		if (!info)
		{
			// 2. Do we have a shadow class for this base object class already?
			info = EBNBaseClassToShadowInfoTable[curClass];
			if (info && !info->_isAppleKVOClass)
			{
				// In this case we have to make the object be the shadow class
				object_setClass(self, info->_shadowClass);
			}
		}
		
		if (!info)
		{
			// 3. If this object is subclassed by Apple's KVO, we can't subclass their subclass.
			// Apple's code becomes unhappy, apparently. So instead we'll method swizzle methods in
			// Apple's KVO subclass.
			if ([self class] == class_getSuperclass(curClass))
			{
				info = [[EBNShadowedClassInfo alloc] initWithBaseClass:[self class] shadowClass:curClass];
				info->_isAppleKVOClass = true;
				EBNOverrideDeallocForClass(curClass);
				
				// This makes the Apple KVO subclass be both the base and the subclass in the table.
				// Future lookups against this class will get found by step 2, above.
				[EBNBaseClassToShadowInfoTable setObject:info forKey:curClass];
			}
		}
	
		if (!info)
		{
			// Check if we should make a new class
			
				// 1. Do not make shadow classes for tagged pointers. Because that is not going
				// to work at all.
			uintptr_t value = (uintptr_t)(__bridge void *) self;
			if (value & 0xF)
				return nil;
	
				// 2. Do not make shadow classes for CF objects that are toll-free bridged.
			NSString *className = NSStringFromClass(curClass);
			if ([className hasPrefix:@"NSCF"] || [className hasPrefix:@"__NSCF"])
			{
				// So, you stopped at this assert. Most likely it is because someone set a toll-free bridged
				// CF object as a NS property value, and someone else observed on it. This doesn't work, and won't work.
				// You'll just submit a bug report about it, but the level of hacking required to make this work
				// is incompatible with App Store apps.
				EBLogContext(kLoggingContextOther, @"Properties of toll-free bridged CoreFoundation objects can't be observed.");
				return nil;
			}
		
			// Have to make a new class
			static NSString *shadowClassSuffix = @"_EBNShadowClass";
			NSString *shadowClassName = [NSString stringWithFormat:@"%@%@", className, shadowClassSuffix];
			shadowClass = objc_allocateClassPair(curClass, [shadowClassName UTF8String], 0);
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
				Class baseClass = [self class];
				info = [[EBNShadowedClassInfo alloc] initWithBaseClass:baseClass shadowClass:shadowClass];
				
				// Override -class (the instance method, not the class method).
				Class (^overrideTheMethodNamedClass)(NSObject *) = ^Class (NSObject *)
				{
					return baseClass;
				};
				Method classforClassInstanceMethod = class_getInstanceMethod(curClass, @selector(class));
				IMP classMethodImplementation = imp_implementationWithBlock(overrideTheMethodNamedClass);
				class_addMethod(shadowClass, @selector(class), classMethodImplementation,
						method_getTypeEncoding(classforClassInstanceMethod));
				

				// Override classForCoder to return the parent class; this keeps us from encoding the
				// shadowed class with NSCoder
				Method classForCoder = class_getInstanceMethod(curClass, @selector(classForCoder));
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
			
				// Remember, the base class is not necessarily our direct superclass.
				Class (^properBaseClass_Override)(NSObject *) = ^Class (NSObject *)
				{
					return baseClass;
				};
				classMethodImplementation = imp_implementationWithBlock(properBaseClass_Override);
				class_addMethod(object_getClass(shadowClass), @selector(ebn_properBaseClass),
						classMethodImplementation, "#@:");

				// And then we have to register the new class.
				objc_registerClassPair(shadowClass);
				
				// Add our new class to the table; other objects of the same base class will get isa-swizzled
				// to this subclass when first observed upon
				[EBNBaseClassToShadowInfoTable setObject:info forKey:baseClass];
			}
			
			// This last bit isa-swizzles self to make it an instance of our shadow class.
			if (info)
				object_setClass(self, info->_shadowClass);
		}
		
		// If after all this we don't have an info object, we need to bail as we can't observe this.
		if (!info)
			return nil;
		
		// Check to see if the getter/setter has been overridden in this class.
		// We will only attempt to set the method implementation once. If it fails, we have recorded
		// here that we we attempted it.
		if (isSetter)
		{
			if (![info->_setters containsObject:propertyName])
			{
				mustSetMethodImplementation = true;
				[info->_setters addObject:propertyName];
			}
		}
		else
		{
			if (![info->_getters containsObject:propertyName])
			{
				mustSetMethodImplementation = true;
				[info->_getters addObject:propertyName];
			}
		}
	}
	
	if (mustSetMethodImplementation)
		return info->_shadowClass;
	
	// If we haven't early-returned before this point, it means we're already set up for observing this.
	if (alreadyPrepared)
		*alreadyPrepared = YES;
	
	return nil;
}

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	Swizzles the implemention of the setter method of the given property. The swizzled implementation
	calls through to the original implementation and then processes observer blocks.
	
	The bulk of this method is a switch statement that switches on the type of the property (parsed
	from the string returned by method_getArgumentType()) and calls a templatized C++ function
	called overrideSetterMethod<>() to create a new method and swizzle it in.
	
	Returns YES if we were able to swizzle the setter method. 
*/
- (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName
{
	// This checks to see if we've made a subclass for observing, and if that subclass has
	// an override for the setter method for the given property. It returns the class that we need
	// to modify iff we need to override the setter.
	BOOL alreadyPrepared;
	Class classToModify = [self ebn_prepareToObserveProperty:propName isSetter:YES
			alreadyPrepared:&alreadyPrepared];
	if (!classToModify)
		return alreadyPrepared;
	
	// The setter doesn't need to be found, although we still return false.
	// This is what will happen for readonly properties in a keypath.
	SEL setterSelector = [classToModify ebn_selectorForPropertySetter:propName];
	if (!setterSelector)
		return NO;
		
	// For the setter we'll need the method definition, so we can get the argument type
	// As with the selector, this could be nil (in this case it means that some other class
	// defines the setter method, but the property is readonly in this class).
	Method setterMethod = class_getInstanceMethod(classToModify, setterSelector);
	if (!setterMethod)
		return NO;
	
	// The getter really needs to be found. For keypath properties, we need to use the getter
	// to figure out what object to move to next; for endpoint properties, we use the getter
	// to determine if the value actually changes when the setter is called.
	SEL getterSelector = [classToModify ebn_selectorForPropertyGetter:propName];
	EBAssert(getterSelector, @"Couldn't find getter method for property %@ in object %@", propName, self);
	if (!getterSelector)
		return NO;
	
	// Get the getter method.
	Method getterMethod = class_getInstanceMethod(classToModify, getterSelector);
	EBAssert(getterMethod, @"Could not find getter method. Make sure class %@ has a method named %@.",
			[self class], NSStringFromSelector(getterSelector));
	if (!getterMethod)
		return NO;
		
	char typeOfSetter[32];
	method_getArgumentType(setterMethod, 2, typeOfSetter, 32);

	// Types defined in runtime.h
	switch (typeOfSetter[0])
	{
	case _C_CHR:
		overrideSetterMethod<char>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_UCHR:
		overrideSetterMethod<unsigned char>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_SHT:
		overrideSetterMethod<short>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_USHT:
		overrideSetterMethod<unsigned short>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_INT:
		overrideSetterMethod<int>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_UINT:
		overrideSetterMethod<unsigned int>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_LNG:
		overrideSetterMethod<long>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_ULNG:
		overrideSetterMethod<unsigned long>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_LNG_LNG:
		overrideSetterMethod<long long>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_ULNG_LNG:
		overrideSetterMethod<unsigned long long>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_FLT:
		overrideSetterMethod<float>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_DBL:
		overrideSetterMethod<double>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_BFLD:
		// Pretty sure this can't happen, as bitfields can't be top-level and are only found inside structs/unions
		EBAssert(false, @"Observable does not have a way to override the setter for %@.",
				propName);
	break;
	case _C_BOOL:
		overrideSetterMethod<bool>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_PTR:
	case _C_CHARPTR:
	case _C_ATOM:		// Apparently never generated? Only docs I can find say treat same as charptr
	case _C_ARY_B:
		overrideSetterMethod<void *>(propName, setterMethod, getterMethod, classToModify);
	break;
	
	case _C_ID:
		overrideSetterMethod<id>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_CLASS:
		overrideSetterMethod<Class>(propName, setterMethod, getterMethod, classToModify);
	break;
	case _C_SEL:
		overrideSetterMethod<SEL>(propName, setterMethod, getterMethod, classToModify);
	break;

	case _C_STRUCT_B:
		if (!strncmp(typeOfSetter, @encode(NSRange), 32))
			overrideSetterMethod<NSRange>(propName, setterMethod, getterMethod, classToModify);
		else if (!strncmp(typeOfSetter, @encode(CGPoint), 32))
			overrideSetterMethod<CGPoint>(propName, setterMethod, getterMethod, classToModify);
		else if (!strncmp(typeOfSetter, @encode(CGRect), 32))
			overrideSetterMethod<CGRect>(propName, setterMethod, getterMethod, classToModify);
		else if (!strncmp(typeOfSetter, @encode(CGSize), 32))
			overrideSetterMethod<CGSize>(propName, setterMethod, getterMethod, classToModify);
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
	if (!EBNAmIBeingDebugged())
		return @"No debugger detected or not debug build; debugBreakOnChange called but will not fire.";
		
	__block EBNObservation *ob = [[EBNObservation alloc] initForObserved:self observer:self immedBlock:
			^(NSObject *blockSelf, NSObject *observed, id previousValue)
			{
				id newValue = [observed valueForKeyPath:keyPath];
				if (!(newValue == previousValue) && ![newValue isEqual:previousValue])
				{
					EBLogStdOut(@"debugBreakOnChange breakpoint on keyPath: %@", keyPath);
					EBLogStdOut(@"    debugString: %@", ob.debugString);
					EBLogStdOut(@"    prevValue: %@", previousValue);
					EBLogStdOut(@"    newValue: %@", newValue);
					
					// This line will cause a break in the debugger! If you stop here in the debugger, it is
					// because someone added a debugBreakOnChange: call somewhere, and its keypath just changed.
					DEBUG_BREAKPOINT;
				}
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
	
	Shows all the observers of the given observed object.
*/
- (NSString *) debugShowAllObservers
{
	NSMutableString *debugStr = [NSMutableString stringWithFormat:@"\n%@\n", [self debugDescription]];
	for (NSString *observedMethod in self.ebn_observedMethodsDict)
	{
		[debugStr appendFormat:@"    %@ notifies:\n", observedMethod];
		NSMutableSet *keypathEntries = self.ebn_observedMethodsDict[observedMethod];
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
			
			if ([entry->_keyPath count] > 1)
			{
				[debugStr appendFormat:@" path:"];
				NSString *separator = @"";
				for (NSString *prop in entry->_keyPath)
				{
					[debugStr appendFormat:@"%@%@", separator, prop];
					separator = @".";
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
		EBNShadowedClassInfo *info = EBNBaseClassToShadowInfoTable[baseClass];
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
	
	@synchronized(EBNObservableSynchronizationToken)
	{
		for (NSMapTable *observerTable in [[self ebn_observedMethodsDict] allValues])
		{
			for (EBNKeypathEntryInfo *entryInfo in [observerTable copy])
			{
				// Remove all 'downstream' keypath parts; they'll become inaccessable after
				// this object goes away. This case should only really be hit when this object
				// is weakly held by its 'upstream' object's keypath property.
				NSInteger index = [[observerTable objectForKey:entryInfo] integerValue];
				[self ebn_removeKeypath:entryInfo atIndex:index];
				
				if (index == 0)
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

// Comparison methods for overrideSetterMethod(). General case and specializations.
// These are used in the overrideSetterMethod template function, as a way
// to give that function a generalized comparison capability.
template<typename T> struct SetterValueCompare
{
	static inline bool isEqual(const T a, const T b)
	{
		return a == b;
	};
};

template<> struct SetterValueCompare <CGPoint>
{
	static inline bool isEqual(const CGPoint a, const CGPoint b) 
	{
		return a.x == b.x && a.y == b.y;
	}
};

template<> struct SetterValueCompare <NSRange>
{
	static inline bool isEqual(const NSRange a, const NSRange b)
	{
		return a.location == b.location && a.length == b.length;
	}
};

template<> struct SetterValueCompare <CGSize>
{
	static inline bool isEqual(const CGSize a, const CGSize b)
	{
		return a.width == b.width && a.height == b.height;
	}
};

template<> struct SetterValueCompare <CGRect>
{
	static inline bool isEqual(const CGRect a, const CGRect b)
	{
		return a.origin.x == b.origin.x && a.origin.y == b.origin.y &&
				a.size.width == b.size.width && a.size.height == b.size.height;
	}
};

// If someone is is observing a keypath "a.b.c.d" and object "[b setC]" gets called, property "c"
// of object b will get a new value, meaning that we need to update our observations on object "c",
// removing observation on the old object and adding it to the new (unless either of them is nil).
// All of this keypath craziness only happens for properties of type id, so this template specialization
// makes that happen. That's why the general template case does nothing.
template<typename T> struct SetterKeypathUpdate
{
	static inline void updateKeypath(const EBNKeypathEntryInfo * const entry, const NSMapTable * const observerTable,
			const T previousValue, const T newValue) {}
	
		// Also return the observed methods dict for non-object properties, and a copy for object properties
	static inline NSMapTable *getIteratorTable(const NSObject * const blockSelf, const NSString * const propName)
	{
		return blockSelf.ebn_observedMethodsDict[propName];
	}
};

template<> struct SetterKeypathUpdate <id>
{
	static inline void updateKeypath(const EBNKeypathEntryInfo * const entry, const NSMapTable * const observerTable,
			const id previousValue, const id newValue)
	{
		NSInteger index = [[observerTable objectForKey:entry] integerValue];
		if (index != [entry->_keyPath count] - 1)
		{
			[previousValue ebn_removeKeypath:entry atIndex:index + 1];
			[newValue ebn_createKeypath:entry atIndex:index + 1];
		}

	}
	
	static inline NSMapTable *getIteratorTable(const NSObject * const blockSelf, const NSString * const propName)
	{
		return [blockSelf.ebn_observedMethodsDict[propName] copy];
	}
};

// All this because I didn't want to call valueForKey: before we knew whether there were immediate
// mode blocks to be called or not.
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

/****************************************************************************************************
	template <T> overrideSetterMethod()
	
	Overrides the given setter method with a new method (actually a block with implementationWithBlock()
	used on it) that notifies observers after it's called.
*/
template<typename T> void overrideSetterMethod(NSString *propName,
		Method setter, Method getter, Class classToModify)
{
	// All of these local variables get copied into the setAndObserve block
	void (*originalSetter)(id, SEL, T) = (void (*)(id, SEL, T)) method_getImplementation(setter);
	SEL setterSEL = method_getName(setter);
	SEL getterSEL = method_getName(getter);
	
	// This is what gets run when the setter method gets called.
	void (^setAndObserve)(NSObject *, T) = ^void (NSObject *blockSelf, T newValue)
	{
		// Do we have any observers active on this property?
		NSMapTable *observerTable = NULL;
		@synchronized(EBNObservableSynchronizationToken)
		{
			observerTable = SetterKeypathUpdate<T>::getIteratorTable(blockSelf, propName);
		}
		
		// If this property isn't being observed, just call the original setter and exit
		if (!observerTable)
		{
			[blockSelf ebn_markPropertyValid:propName];
			(originalSetter)(blockSelf, setterSEL, newValue);
			return;
		}
		
		// If the property is being observed, check if our new value is actually different than the old one
		// Also, set the new value.
		T (*getterImplementation)(id, SEL) = (T (*)(id, SEL)) method_getImplementation(getter);
		T previousValue = getterImplementation(blockSelf, getterSEL);
		(originalSetter)(blockSelf, setterSEL, newValue);
		
		// If the value actually changes do all the observation stuff
		if (!SetterValueCompare<T>::isEqual(previousValue, newValue))
		{
			BOOL reapAfterIterating = NO;
			NSMutableArray *immedBlocksToRun = nil;
			
			@synchronized(EBNObservableSynchronizationToken)
			{
				for (EBNKeypathEntryInfo *entry in observerTable)
				{
					// Only the object specialization actually implements this
					// (only objects can have properties, ergo everyone else is a keypath endpoint).
					SetterKeypathUpdate<T>::updateKeypath(entry, observerTable, previousValue, newValue);
	
					// If this is an immed block, wrap the previous value and call it.
					// Why not just call [blockSelf valueForKey:]? Immed blocks shouldn't be used much
					// and we'd have to call valueForKey before setting the new value.
					EBNObservation *blockInfo = entry->_blockInfo;

					if (blockInfo.debugBreakOnChange)
					{
						if (EBNAmIBeingDebugged())
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
					
					if (blockInfo->_copiedImmedBlock)
					{
						if (!immedBlocksToRun)
							immedBlocksToRun = [[NSMutableArray alloc] init];
						[immedBlocksToRun addObject:blockInfo];
					}
					
					if (blockInfo->_copiedBlock)
					{
						NSObject *strongObserved = blockInfo->_weakObserved;
						if (strongObserved)
						{
							if (EBN_ObserverBlocksBeingDrained && [NSThread isMainThread])
							{
								[EBN_ObserverBlocksBeingDrained addObject:blockInfo];
								[EBN_ObservedObjectBeingDrainedKeepAlive addObject:strongObserved];
							}
							else
							{
								[EBN_ObserverBlocksToRunAfterThisEvent addObject:blockInfo];
								[EBN_ObservedObjectKeepAlive addObject:strongObserved];
							}
						}
						else
						{
							reapAfterIterating = true;
						}
					}
				}
			}
			
			// If there are immediate blocks to run, execute them now.
			if (immedBlocksToRun)
			{
				id wrappedPreviousValue = EBNWrapValue(previousValue);
				for (EBNObservation *observation in immedBlocksToRun)
				{
					[observation executeWithPreviousValue:wrappedPreviousValue];
				}
			}

			if (reapAfterIterating)
				[blockSelf ebn_reapBlocks];
		}
	};

	// Now replace the setter's implementation with the new one
	IMP swizzledImplementation = imp_implementationWithBlock(setAndObserve);
	class_replaceMethod(classToModify, setterSEL, swizzledImplementation, method_getTypeEncoding(setter));
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
	
	while (EBN_ObserverBlocksBeingDrained)
	{
		// Step 1: Copy the list of objects that have blocks that need to be called
		NSMutableSet *thisIterationCallList = [EBN_ObserverBlocksBeingDrained mutableCopy];
		
		// Step 2: Add the blocks we're going go call to the master list
		[masterCallList unionSet:thisIterationCallList];

		// Step 3: Call each observation block
		for (EBNObservation *blockInfo in thisIterationCallList)
		{
			[blockInfo execute];
		}

		// Step 4: Remove any blocks we've already called from the global set
		[EBN_ObserverBlocksBeingDrained minusSet:masterCallList];
		if (![EBN_ObserverBlocksBeingDrained count])
			EBN_ObserverBlocksBeingDrained = nil;
	}
	
	// We're done notifying observers, purge the retains we've been keeping
	EBN_ObservedObjectBeingDrainedKeepAlive = nil;
}

/****************************************************************************************************
	EBNAmIBeingDebugged()
	
	EBNAmIBeingDebugged calls sysctl() to see if a debugger is attached. Sample code courtesy Apple:
		https://developer.apple.com/library/mac/qa/qa1361/_index.html

	Because the struct kinfo_proc is marked unstable by Apple, we only use this code for Debug builds.
	That means this method will return FALSE on release builds, even if a debugger *is* attached.
*/
BOOL EBNAmIBeingDebugged(void)
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



