/****************************************************************************************************
	EBNObservableCollections.m
	Observable

	Created by Chall Fry on 5/13/14.
    Copyright (c) 2013-2014 eBay Software Foundation.
*/

#import "DebugUtils.h"
#import "EBNObservableCollections.h"

@class EBNObservableCollectionProxy;

id EBN_ForwardingTargetGuts(EBNObservableCollectionProxy *object, SEL aSelector);

id EBN_ForwardingTargetGuts(EBNObservableCollectionProxy *object, SEL aSelector)
{
	if (aSelector == @selector(tell:when:changes:) ||
			aSelector == @selector(tell:whenAny:changes:) ||
			aSelector == @selector(stopTelling:aboutChangesTo:) ||
			aSelector == @selector(stopTelling:aboutChangesToArray:) ||
			aSelector == @selector(stopTellingAboutChanges:) ||
			aSelector == @selector(stopAllCallsTo:) ||
			aSelector == @selector(property:observationStateIs:) ||
			aSelector == @selector(manuallyTriggerObserversForProperty:previousValue:) ||
			aSelector == @selector(numberOfObservers:) ||
			aSelector == @selector(allObservedProperties) ||
			aSelector == @selector(observe:using:) ||
			aSelector == @selector(reapBlocks) ||
			aSelector == @selector(createKeypath:atIndex:) ||
			aSelector == @selector(removeKeypath:atIndex:))
	{
		return object;
	} else
	{
		return nil;
	}
}

	// This is a proxy object that we create during archiving, because archiving custom subclasses of
	// class clusters doesn't seem to work right--the cluster seems to override the type of object that
	// gets archived.
@interface EBNObservableArchiverProxy : NSObject
@property (strong)	NSMutableArray		*array;
@property (strong)	NSMutableSet		*set;
@property (strong)	NSMutableDictionary	*dict;
@end


	// This is the observer proxy that goes into the custom collection subclasses and actually
	// tracks the observations. Since the collection classes need to subclass the
@interface EBNObservableCollectionProxy : EBNObservable
@end

@implementation EBNObservableCollectionProxy
{
	// The collection holds the proxy strongly; it's our parent.
	NSObject <EBNObservableProtocol> *__weak collectionObject;
}

/****************************************************************************************************
	initForCollection:
	
	The collection proxy needs to be able to get to the collection object.
*/
- (instancetype) initForCollection:(id<EBNObservableProtocol>) collectionObj
{
	if (self = [super init])
	{
		self->collectionObject = collectionObj;
	}
	return self;
}

/****************************************************************************************************
	swizzleImplementationForSetter:
	
	Since we're not observing properties, we don't actually implement this method.
*/
+ (bool) swizzleImplementationForSetter:(NSString *) propName
{
	return true;
}

/****************************************************************************************************
	valueForKeyEBN:
	
*/
- (id) valueForKeyEBN:(NSString *)key
{
	return [collectionObject valueForKeyEBN:key];
}

/****************************************************************************************************
	createKeypath:atIndex:
	
	This makes '*' observations work correctly for collections; we directly add an entry for '*' 
	instead of iterating through each property. Collection mutators then trigger the '*' observations
	when they get called.
*/
- (bool) createKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
{
	NSString *propName = entryInfo->keyPath[index];
	return [self createKeypath:entryInfo atIndex:index forProperty:propName];
}

/****************************************************************************************************
	removeKeypath:atIndex:

	For object-following array properties, the 'key' pointing to the property can move around as
	objects are added/removed from the array. When we remove the keypath, we need to go find
	where the entry has moved to.
	
	Also, for '*' observations, we directly remove the '*' entry from the table.
	
	Returns TRUE if the observation path was removed successfully.
*/
- (bool) removeKeypath:(const EBNKeypathEntryInfo *) removeEntry atIndex:(NSInteger) index
{
	if (index >= [removeEntry->keyPath count])
		return false;

	bool observerTableRemoved = false;
	NSString *propName = removeEntry->keyPath[index];
	
	// For array collections, we need to handle object-following observations (like "array.4")
	// in a special way. That special way is to look through every property to find where
	// the observation may have moved to. And yes, by 'special' you can infer 'because the
	// data model is designed wrong'.
	if ([collectionObject isKindOfClass:[NSArray class]] && isdigit([propName characterAtIndex:0]))
	{
		@synchronized(self)
		{
			for (NSString *propertyKey in [observedMethods allKeys])
			{
				[self removeKeypath:removeEntry atIndex:index forProperty:propertyKey];
			}
		}
	} else
	{
		return [self removeKeypath:removeEntry atIndex:index forProperty:propName];
	}
		
	return observerTableRemoved;
}


@end

	// This class uses forwardingTargetForSelector:, to dynamically resolve a bunch of methods,
	// so we're turning off the protocol method not implemented warnings.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma mark
@implementation EBNObservableDictionary
{
	// Yes, this class is a subclass of NSMutableDictionary that uses internal composition
	// to implement NSMutableDictionary. See info on class clusters for why.
	NSMutableDictionary 			*dict;
	
	EBNObservableCollectionProxy	*observationProxy;
}

#pragma mark NSDictionary Required Methods

/****************************************************************************************************
	init
	
	Designated initializer for NSDictionary.
*/
- (instancetype) init
{
	if (self = [super init])
	{
		if ((dict = [[NSMutableDictionary alloc] init]))
		{
			observationProxy = [[EBNObservableCollectionProxy alloc] initForCollection:self];
		} else
		{
			// If dict didn't get initialized, neither did we
			self = nil;
		}
	}

	return self;
}

/****************************************************************************************************
	initWithCapacity:
	
	Designated initializer for NSMutableDictionary.
*/
- (instancetype) initWithCapacity:(NSUInteger)numItems
{
	if (self = [super init])
	{
		if ((dict = [[NSMutableDictionary alloc] initWithCapacity:numItems]))
		{
			observationProxy = [[EBNObservableCollectionProxy alloc] initForCollection:self];
		} else
		{
			// If dict didn't get initialized, neither did we
			self = nil;
		}
	}

	return self;
}

/****************************************************************************************************
	initWithObjects:forKeys:count:
	
	Designated initializer for NSDictionary.
*/
- (instancetype) initWithObjects:(const id [])objects forKeys:(const id<NSCopying> [])keys count:(NSUInteger)count
{
	if (self = [super init])
	{
		if ((dict = [[NSMutableDictionary alloc] initWithObjects:objects forKeys:keys count:count]))
		{
			observationProxy = [[EBNObservableCollectionProxy alloc] initForCollection:self];
		} else
		{
			// If dict didn't get initialized, neither did we
			self = nil;
		}
	}

	return self;
}

/****************************************************************************************************
	count
	
*/
- (NSUInteger) count
{
	return [dict count];
}

/****************************************************************************************************
	objectForKey:
	
*/
- (id) objectForKey:(id)aKey
{
	return [dict objectForKey:aKey];
}

/****************************************************************************************************
	keyEnumerator
	
*/
- (NSEnumerator *) keyEnumerator
{
	return [dict keyEnumerator];
}

#pragma mark NSDictionary Protocols

/****************************************************************************************************
	copyWithZone:
	
	NSCopying. Like NSArray, this shallow-copies the array contents. It also creates a new observation 
	proxy object, and DOES NOT copy any of the observations on the original object.
*/
- (id) copyWithZone:(NSZone *)zone
{
	EBNObservableDictionary *newDict = [[EBNObservableDictionary allocWithZone:zone] initWithDictionary:self->dict];
	return newDict;
}

/****************************************************************************************************
	mutableCopyWithZone:
	
	NSMutableCopying. Same as copyWithZone.
*/
- (id) mutableCopyWithZone:(NSZone *)zone
{
	EBNObservableDictionary *newDict = [[EBNObservableDictionary allocWithZone:zone] initWithDictionary:self->dict];
	return newDict;
}

/****************************************************************************************************
	replacementObjectForCoder:
	
	NSCoder has issues encoding custom subclasses of class cluster objects, so instead, we designate
	a coding proxy that *isn't* a subclass of NSMutableDictionary. That proxy knows how to encode the
	dictionary elements, and uses awakeAfterUsingCoder: to recreate the correct object class on decode.
*/
- (id) replacementObjectForCoder:(NSCoder *)aCoder
{
	EBNObservableArchiverProxy	*proxy = [[EBNObservableArchiverProxy alloc] init];
	proxy.dict = self->dict;
	
	return proxy;
}

/****************************************************************************************************
	countByEnumeratingWithState:
	
	NSFastEnumeration protocol. Pass through to composed array.
*/
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
		objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len;
{
	return [dict countByEnumeratingWithState:state objects:buffer count:len];
}

#pragma mark NSMutableDictionary Required Methods

/****************************************************************************************************
	setObject:forKey:
	
*/
- (void)setObject:(id)newValue forKey:(id < NSCopying >)aKey
{
	// Get the previous value, and then set the new value
	NSInteger prevCount = [dict count];
	id previousValue = [dict objectForKey:aKey];
	[dict setObject:newValue forKey:aKey];
	
	// Keys that aren't strings aren't observable. Slightly unsafe as we have to assume
	// keyObject is an NSObject subclass.
	NSObject *keyObject = (NSObject *) aKey;
	if ([keyObject isKindOfClass:[NSString class]])
	{
		// If this property was unset, or the new value is different than the old
		if ((previousValue == nil) || ![newValue isEqual:previousValue])
		{
			NSString *aKeyString = (NSString *) aKey;
			[observationProxy manuallyTriggerObserversForProperty:aKeyString previousValue:previousValue newValue:newValue];
			[observationProxy manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
		}
	}
	
	// The count property may have changed; notify for it.
	[observationProxy manuallyTriggerObserversForProperty:@"count" previousValue:
			[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:[dict count]]];
}

/****************************************************************************************************
	removeObjectForKey:
	
*/
- (void) removeObjectForKey:(id)aKey
{
	// Get the previous value, and then set the new value
	NSInteger prevCount = [dict count];
	id previousValue = [dict objectForKey:aKey];
	[dict removeObjectForKey:aKey];
	
	// Keys that aren't strings aren't observable. Slightly unsafe as we have to assume
	// keyObject is an NSObject subclass.
	NSObject *keyObject = (NSObject *) aKey;
	if ([keyObject isKindOfClass:[NSString class]])
	{
		// If this property was previously set
		if (previousValue != nil)
		{
			NSString *aKeyString = (NSString *) aKey;
			[observationProxy manuallyTriggerObserversForProperty:aKeyString previousValue:previousValue newValue:nil];
			[observationProxy manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
		}
	}
	
	// The count property may have changed; notify for it.
	[observationProxy manuallyTriggerObserversForProperty:@"count" previousValue:
			[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:[dict count]]];
}

#pragma mark Keypaths

/****************************************************************************************************
	valueForKeyEBN:
	
*/
- (id) valueForKeyEBN:(NSString *)key
{
	return [self objectForKey:key];
}

#pragma mark Observable Calls get Forwarded

/****************************************************************************************************
	forwardingTargetForSelector:
	
*/
- (id) forwardingTargetForSelector:(SEL)aSelector
{
	id forwardTarget = EBN_ForwardingTargetGuts(self->observationProxy, aSelector);
	if (!forwardTarget)
		return [super forwardingTargetForSelector:aSelector];
	
	return forwardTarget;
}

@end

#pragma mark
@implementation EBNObservableSet
{
	// This class is a subclass of NSMutableSet that uses internal composition
	// to implement NSMutableSet. See info on class clusters for why.
	NSMutableSet 					*set;
	
	EBNObservableCollectionProxy	*observationProxy;
}

#pragma mark NSSet Required Methods

/****************************************************************************************************
	init
	
	Designated initializer for NSSet.
*/
- (instancetype) init
{
	if (self = [super init])
	{
		if ((set = [[NSMutableSet alloc] init]))
		{
			observationProxy = [[EBNObservableCollectionProxy alloc] initForCollection:self];
		} else
		{
			// If dict didn't get initialized, neither did we
			self = nil;
		}
	}

	return self;
}

/****************************************************************************************************
	initWithObjects:count:
	
	This and init are the designated initializers for this class.
*/
- (instancetype) initWithObjects:(const id [])objects count:(NSUInteger) count;
{
	if (self = [super init])
	{
		if ((set = [[NSMutableSet alloc] initWithObjects:objects count:count]))
		{
			observationProxy = [[EBNObservableCollectionProxy alloc] initForCollection:self];
		} else
		{
			// If set didn't get initialized, neither did we
			self = nil;
		}
	}

	return self;
}

/****************************************************************************************************
	initWithCapacity
	
	Designated initializer for NSMutableSet.
*/
- (instancetype) initWithCapacity:(NSUInteger)numItems
{
	if (self = [super init])
	{
		if ((set = [[NSMutableSet alloc] initWithCapacity:numItems]))
		{
			observationProxy = [[EBNObservableCollectionProxy alloc] initForCollection:self];
		} else
		{
			// If dict didn't get initialized, neither did we
			self = nil;
		}
	}

	return self;
}

/****************************************************************************************************
	count
	
*/
- (NSUInteger) count
{
	return [set count];
}

/****************************************************************************************************
	member:
	
*/
- (id) member:(id)object
{
	return [set member:object];
}

/****************************************************************************************************
	objectEnumerator
	
*/
- (NSEnumerator *) objectEnumerator
{
	return [set objectEnumerator];
}

#pragma mark NSSet Protocols

/****************************************************************************************************
	copyWithZone:
	
	NSCopying. Like NSArray, this shallow-copies the array contents. It also creates a new observation 
	proxy object, and DOES NOT copy any of the observations on the original object.
*/
- (id) copyWithZone:(NSZone *)zone
{
	EBNObservableSet *newSet = [[EBNObservableSet allocWithZone:zone] initWithSet:self->set];
	return newSet;
}

/****************************************************************************************************
	mutableCopyWithZone:
	
	NSMutableCopying. Same as copyWithZone.
*/
- (id) mutableCopyWithZone:(NSZone *)zone
{
	EBNObservableSet *newSet = [[EBNObservableSet allocWithZone:zone] initWithSet:self->set];
	return newSet;
}

/****************************************************************************************************
	replacementObjectForCoder:
	
	NSCoder has issues encoding custom subclasses of class cluster objects, so instead, we designate
	a coding proxy that *isn't* a subclass of NSMutableSet. That proxy knows how to encode the
	set elements, and uses awakeAfterUsingCoder: to recreate the correct object class on decode.
*/
- (id) replacementObjectForCoder:(NSCoder *)aCoder
{
	EBNObservableArchiverProxy	*proxy = [[EBNObservableArchiverProxy alloc] init];
	proxy.set = self->set;
	
	return proxy;
}

/****************************************************************************************************
	countByEnumeratingWithState:
	
	NSFastEnumeration protocol. Pass through to composed array.
*/
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
		objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len;
{
	return [set countByEnumeratingWithState:state objects:buffer count:len];
}

#pragma mark NSMutableSet required methods

/****************************************************************************************************
	addObject
	
*/
- (void) addObject:(id)object
{
	NSUInteger prevCount = [set count];
	id previousValue = [set member:object];
	[set addObject:object];
	
	// If this property was unset before, report as a change to the 'any' property and to the hash
	if (previousValue == nil)
	{
		NSString *keyForPrevValue = [self keyForObject:previousValue];
		[observationProxy manuallyTriggerObserversForProperty:keyForPrevValue previousValue:previousValue
				newValue:object];
		[observationProxy manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
	}
	
	// The count property may have changed; notify for it.
	[observationProxy manuallyTriggerObserversForProperty:@"count" previousValue:
			[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:[set count]]];
}

/****************************************************************************************************
	removeObject
	
*/
- (void) removeObject:(id)object
{
	// Get the previous value, and then do the remove
	NSUInteger prevCount = [set count];
	id previousValue = [set member:object];
	[set removeObject:object];
	
	if (previousValue)
	{
		NSString *keyForPrevValue = [self keyForObject:previousValue];
		[observationProxy manuallyTriggerObserversForProperty:keyForPrevValue previousValue:previousValue
				newValue:nil];
		[observationProxy manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
	}
	
	// The count property may have changed; notify for it.
	[observationProxy manuallyTriggerObserversForProperty:@"count" previousValue:
			[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:[set count]]];
}

#pragma mark Keypaths

/****************************************************************************************************
	keyForObject:
	
	Returns a NSString key that can be used to identify an object in the receiver. The object doesn't 
	have to be in the set, I guess, but being in the set is sort of the point.
	
	The purpose of this method is that it allows the caller to put the returned string into a keypath
	referencing that object. Be aware that keypaths containing this construct are not compliant with
	Apple's KVC!
*/
- (NSString *) keyForObject:(id) object
{
	NSUInteger hashValue = [object hash];
	NSString *hashString = [NSString stringWithFormat:@"&%lu", (unsigned long) hashValue];
	return hashString;
}

/****************************************************************************************************
	objectForKey:
	
	key must be a NSSet hash string, as returned by keyForObject. Generally, this is a string starting
	with '&' followed by a bunch of numbers.
*/
- (id) objectForKey:(NSString *) key
{
	if (!key || ![key hasPrefix:@"&"] || [key length] < 2)
		return nil;
	
	NSUInteger keyHash = (NSUInteger) [[key substringFromIndex:1] longLongValue];
	for (id setObject in self->set)
	{
		if ([setObject hash] == keyHash)
			return setObject;
	}
	
	return nil;
}

/****************************************************************************************************
	valueForKeyEBN:
	
*/
- (id) valueForKeyEBN:(NSString *)key
{
	return [self objectForKey:key];
}

#pragma mark Observable Calls get Forwarded

/****************************************************************************************************
	forwardingTargetForSelector:
	
*/
- (id) forwardingTargetForSelector:(SEL)aSelector
{
	id forwardTarget = EBN_ForwardingTargetGuts(self->observationProxy, aSelector);
	if (!forwardTarget)
		return [super forwardingTargetForSelector:aSelector];
	
	return forwardTarget;
}

@end

#pragma mark
@implementation EBNObservableArray
{
	// This class is a subclass of NSMutableArray that uses internal composition
	// to implement NSMutableArray. See info on class clusters for why--the short story is that
	// NSMutableArray doesn't actually implement an array; it's just a protocol class.
	NSMutableArray		 			*array;
	
	EBNObservableCollectionProxy	*observationProxy;
}

#pragma mark NSArray Required Methods

/****************************************************************************************************
	init
	
*/
- (instancetype) init
{
	if (self = [super init])
	{
		if ((array = [[NSMutableArray alloc] init]))
		{
			observationProxy = [[EBNObservableCollectionProxy alloc] initForCollection:self];
		} else
		{
			// If dict didn't get initialized, neither did we
			self = nil;
		}
	}

	return self;
}

/****************************************************************************************************
	initWithObjects:count:
	
*/
- (instancetype) initWithObjects:(const id []) objects count:(NSUInteger) count
{
	if (self = [super init])
	{
		if ((array = [[NSMutableArray alloc] initWithObjects:objects count:count]))
		{
			observationProxy = [[EBNObservableCollectionProxy alloc] initForCollection:self];
		} else
		{
			// If dict didn't get initialized, neither did we
			self = nil;
		}
	}

	return self;
}

/****************************************************************************************************
	initWithCapacity:
	
*/
- (instancetype) initWithCapacity:(NSUInteger)numItems
{
	if (self = [super init])
	{
		if ((array = [[NSMutableArray alloc] initWithCapacity:numItems]))
		{
			observationProxy = [[EBNObservableCollectionProxy alloc] initForCollection:self];
		} else
		{
			// If dict didn't get initialized, neither did we
			self = nil;
		}
	}

	return self;
}

/****************************************************************************************************
	count
	
*/
- (NSUInteger) count
{
	return [array count];
}

/****************************************************************************************************
	objectAtIndex:
	
*/
- (id) objectAtIndex:(NSUInteger)index
{
	return [array objectAtIndex:index];
}

#pragma mark NSArray Protocols

/****************************************************************************************************
	copyWithZone:
	
	NSCopying. Like NSArray, this shallow-copies the array contents. It also creates a new observation 
	proxy object, and DOES NOT copy any of the observations on the original object.
*/
- (id) copyWithZone:(NSZone *)zone
{
	EBNObservableArray *newArray = [[EBNObservableArray allocWithZone:zone] initWithArray:self->array];
	return newArray;
}

/****************************************************************************************************
	mutableCopyWithZone:
	
	NSMutableCopying. Same as copyWithZone.
*/
- (id) mutableCopyWithZone:(NSZone *)zone
{
	EBNObservableArray *newArray = [[EBNObservableArray allocWithZone:zone] initWithArray:self->array];
	return newArray;
}

/****************************************************************************************************
	replacementObjectForCoder:
	
	NSCoder has issues encoding custom subclasses of class cluster objects, so instead, we designate
	a coding proxy that *isn't* a subclass of NSMutableArray. That proxy knows how to encode the
	array elements, and uses awakeAfterUsingCoder: to recreate the correct object class on decode.
*/
- (id) replacementObjectForCoder:(NSCoder *)aCoder
{
	EBNObservableArchiverProxy	*proxy = [[EBNObservableArchiverProxy alloc] init];
	proxy.array = self->array;
	
	return proxy;
}

/****************************************************************************************************
	countByEnumeratingWithState:
	
	NSFastEnumeration protocol. Pass through to composed array.
*/
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
		objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len;
{
	return [array countByEnumeratingWithState:state objects:buffer count:len];
}

#pragma mark NSMutableArray Required Methods

/****************************************************************************************************
	insertObject:atIndex:
	
*/
- (void) insertObject:(id)anObject atIndex:(NSUInteger) insertIndex
{
	NSUInteger prevCount = [array count];
	[array insertObject:anObject atIndex:insertIndex];
		
	NSMutableArray *adjustObservations = [[NSMutableArray alloc] init];
	
	@synchronized(observationProxy)
	{
		for (NSString *propertyKey in observationProxy->observedMethods)
		{
			// array.#4 observes the object at index 4, and follows the index
			if ([propertyKey hasPrefix:@"#"])
			{
				NSUInteger observedIndex = [[propertyKey substringFromIndex:1] integerValue];
				if (observedIndex >= insertIndex && observedIndex < [array count])
				{
					id prevValueForIndex = nil;
					if (observedIndex + 1 < [array count])
						prevValueForIndex = array[observedIndex + 1];
					id newValueForIndex = array[observedIndex];
					[observationProxy manuallyTriggerObserversForProperty:propertyKey previousValue:prevValueForIndex
							newValue:newValueForIndex];
				}

			} else if ([propertyKey isEqualToString:@"*"])
			{
				// If we have observations on '*', run them here
				[observationProxy manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
			} else
			{
				// array.4 observes the object at index 4 *at the time observation starts*, and follows that object
				NSUInteger keyIndex = [propertyKey integerValue];
				if (keyIndex >= insertIndex)
					[adjustObservations addObject:propertyKey];
			}
		}
	
		// Sort the number type observations that are active
		[adjustObservations sortUsingComparator:^(NSString *obj1, NSString *obj2)
		{
			int intVal1 = [obj1 intValue];
			int intVal2 = [obj2 intValue];
			
			if (intVal1 > intVal2)
				return (NSComparisonResult) NSOrderedDescending;
			if (intVal1 < intVal2)
				return (NSComparisonResult)NSOrderedAscending;
		
			return (NSComparisonResult)NSOrderedSame;
		}];
		
		// Traverse the observations in decreasing order, moving N to (N+1)
		for ( long moverIndex = [adjustObservations count] - 1; moverIndex >= 0; --moverIndex)
		{
			NSString *moveFromPropKey = adjustObservations[moverIndex];
			NSString *moveToPropKey = [NSString stringWithFormat:@"%d", [moveFromPropKey intValue] + 1];
			NSMapTable *observerTable = observationProxy->observedMethods[moveFromPropKey];
			[observationProxy->observedMethods removeObjectForKey:moveFromPropKey];
			[observationProxy->observedMethods setObject:observerTable forKey:moveToPropKey];
		}
	}
	
	// The count property changed; notify for it.
	[observationProxy manuallyTriggerObserversForProperty:@"count" previousValue:
			[NSNumber numberWithInteger:prevCount]];
}

/****************************************************************************************************
	removeObjectAtIndex:
	
*/
- (void) removeObjectAtIndex:(NSUInteger) removeIndex
{
	NSUInteger prevCount = [array count];
	id prevValue = nil;
	if (removeIndex < [array count])
		prevValue = [array objectAtIndex:removeIndex];
	[array removeObjectAtIndex:removeIndex];
		
	NSMutableArray *adjustObservations = [[NSMutableArray alloc] init];
	NSMutableArray *stopObservingProperties = [[NSMutableArray alloc] init];
	
	@synchronized(observationProxy)
	{
		for (NSString *propertyKey in observationProxy->observedMethods)
		{
			if ([propertyKey hasPrefix:@"#"])
			{
				// There can be observations beyond the end of the array. They should get notified
				// in the case where their value changes, and when the array shrinks and becomes
				// smaller than their index.
				NSUInteger observedIndex = [[propertyKey substringFromIndex:1] integerValue];
				if (observedIndex >= removeIndex && observedIndex <= [array count])
				{
					id prevValueForIndex = nil;
					if (observedIndex == removeIndex)
						prevValueForIndex = prevValue;
					else if (observedIndex > 0 && observedIndex < [array count])
						prevValueForIndex = array[observedIndex - 1];
					id newValueForIndex = nil;
					if (observedIndex < [array count])
						newValueForIndex = array[observedIndex];
					[observationProxy manuallyTriggerObserversForProperty:propertyKey
							previousValue:prevValueForIndex newValue:newValueForIndex];
				}
			} else if ([propertyKey isEqualToString:@"*"])
			{
				// If we have observations on '*', run them here
				[observationProxy manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
			} else
			{
				NSUInteger keyIndex = [propertyKey integerValue];
				if (keyIndex == removeIndex)
				{
					[observationProxy manuallyTriggerObserversForProperty:propertyKey previousValue:prevValue
							newValue:nil];
					
					// When this 'object-following' property is removed from the array, stop observing,
					// since we can't observe this path anymore.
					[stopObservingProperties addObject:propertyKey];

				} else if (keyIndex > removeIndex)
				{
					[adjustObservations addObject:propertyKey];
				}
				
			}
		}
		
		for (NSString *propKey in stopObservingProperties)
		{
			[self stopObservingProperty:propKey];
		}
	
		// Sort the number type observations that are active
		[adjustObservations sortUsingComparator:^(NSString *obj1, NSString *obj2)
		{
			int intVal1 = [obj1 intValue];
			int intVal2 = [obj2 intValue];
			
			if (intVal1 > intVal2)
				return (NSComparisonResult) NSOrderedDescending;
			if (intVal1 < intVal2)
				return (NSComparisonResult)NSOrderedAscending;
		
			return (NSComparisonResult)NSOrderedSame;
		}];
		
		// Traverse the number observersations in increasing order, moving N to (N-1)
		for (int moverIndex = 0; moverIndex < [adjustObservations count]; ++moverIndex)
		{
			NSString *moveFromPropKey = adjustObservations[moverIndex];
			NSString *moveToPropKey = [NSString stringWithFormat:@"%d", [moveFromPropKey intValue] - 1];
			NSMapTable *observerTable = observationProxy->observedMethods[moveFromPropKey];
			[observationProxy->observedMethods removeObjectForKey:moveFromPropKey];
			[observationProxy->observedMethods setObject:observerTable forKey:moveToPropKey];
		}
	}
	
	// The count property changed; notify for it.
	[observationProxy manuallyTriggerObserversForProperty:@"count" previousValue:
			[NSNumber numberWithInteger:prevCount]];

}

/****************************************************************************************************
	addObject:
	
	No index shifting can occur here, making this method significantly easier than addObject:atIndex:.
	
*/
- (void) addObject:(id)anObject
{
	NSString *propHashIndexString = [[NSString alloc] initWithFormat:@"#%lu",  (unsigned long) [array count]];

	NSUInteger prevCount = [array count];
	[array addObject:anObject];
	
	[observationProxy manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
	[observationProxy manuallyTriggerObserversForProperty:propHashIndexString previousValue:nil newValue:anObject];
	
	// The count property changed; notify for it.
	[observationProxy manuallyTriggerObserversForProperty:@"count" previousValue:
			[NSNumber numberWithInteger:prevCount]];
}

/****************************************************************************************************
	removeLastObject:
	
*/
- (void) removeLastObject
{
	id prevValue = nil;
	NSUInteger prevCount = [array count];
	if (prevCount == 0)
	{
		// Will fail, but that's for NSArray to handle
		[array removeLastObject];
	} else
	{
		NSInteger prevLastIndex = prevCount - 1;
		prevValue = array[prevLastIndex];
	
		[array removeLastObject];

		NSString *propIndexString = [[NSString alloc] initWithFormat:@"%lu", (long) prevLastIndex];
		NSString *propHashIndexString = [[NSString alloc] initWithFormat:@"#%lu", (long) prevLastIndex];
		
		[observationProxy manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
		[observationProxy manuallyTriggerObserversForProperty:propIndexString
				previousValue:prevValue newValue:nil];
		[observationProxy manuallyTriggerObserversForProperty:propHashIndexString
				previousValue:prevValue newValue:nil];
				
		// If an 'object-following' property was being observed, and its object is now removed from the array,
		// stop observing, since we can't observe this path anymore.
		[self stopObservingProperty:propIndexString];
		
		// The count property changed; notify for it.
		[observationProxy manuallyTriggerObserversForProperty:@"count" previousValue:
				[NSNumber numberWithInteger:prevCount]];
	}
}

/****************************************************************************************************
	replaceObjectAtIndex:withObject:
	
*/
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject
{
	id prevValue = nil;
	if (index < [array count])
		prevValue = array[index];
		
	[array replaceObjectAtIndex:index withObject:anObject];
	
	NSString *propIndexString = [[NSString alloc] initWithFormat:@"%lu", (unsigned long) index];
	NSString *propHashIndexString = [[NSString alloc] initWithFormat:@"#%lu", (unsigned long) index];
	
	[observationProxy manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
	[observationProxy manuallyTriggerObserversForProperty:propIndexString
			previousValue:prevValue newValue:anObject];
	[observationProxy manuallyTriggerObserversForProperty:propHashIndexString
			previousValue:prevValue newValue:anObject];
			
	// Object-following properties need to stop observing after their object leaves the array
	[self stopObservingProperty:propIndexString];
}

/****************************************************************************************************
	stopObservingProperty:
	
	Internal method that stops observing the given array element property. This method will retrieve
	the observed object (the object at the root of the keypath) and tell it to remove the entire 
	path.
	
*/
- (void) stopObservingProperty:(NSString *) propertyName
{
	NSMapTable *observerTable = nil;
	@synchronized(observationProxy)
	{
		observerTable = [observationProxy->observedMethods[propertyName] copy];
	}
	
	for (EBNKeypathEntryInfo *entry in observerTable)
	{
		EBNObservable *observedObject = entry->blockInfo->weakObserved;
		if (observedObject)
		{
			[observedObject removeKeypath:entry atIndex:0];
		}
	}
}

/****************************************************************************************************
	valueForKeyEBN:
	
*/
- (id) valueForKeyEBN:(NSString *)key
{
	NSInteger index = -1;
	if ([key hasPrefix:@"#"])
	{
		index = [[key substringFromIndex:1] integerValue];
	} else if (isdigit([key characterAtIndex:0]))
	{
		index = [key integerValue];
	}

	if (index >= 0 && index < [array count])
		return array[index];
		
	return nil;
}

#pragma mark Observable Calls get Forwarded

/****************************************************************************************************
	forwardingTargetForSelector:
	
*/
- (id) forwardingTargetForSelector:(SEL)aSelector
{
	id forwardTarget = EBN_ForwardingTargetGuts(self->observationProxy, aSelector);
	if (!forwardTarget)
		return [super forwardingTargetForSelector:aSelector];
	
	return forwardTarget;
}

/****************************************************************************************************
	debugShowAllObservers
	
*/
- (NSString *) debugShowAllObservers
{
	return [observationProxy debugShowAllObservers];
}


@end

#pragma mark
@implementation EBNObservableArchiverProxy

/****************************************************************************************************
	initWithCoder:
	
	NSCoding. This inits a proxy object used for encode and decode, to get around an issue with how
	class clusters decide what type of object to encode.
*/
- (instancetype) initWithCoder:(NSCoder *)decoder
{
	if (self = [super init])
	{
		// 2 of these will be nil
		self.dict = [decoder decodeObjectOfClass:[NSMutableDictionary class] forKey:@"dict"];
		self.set = [decoder decodeObjectOfClass:[NSMutableSet class] forKey:@"set"];
		self.array = [decoder decodeObjectOfClass:[NSMutableArray class] forKey:@"array"];
	}
	
	return self;
}

/****************************************************************************************************
	awakeAfterUsingCoder:
	
	NSCoding. Observation information does not get encoded or decoded as part of NSCoding; only the 
	collection gets saved/restored.
*/
- (id) awakeAfterUsingCoder:(NSCoder *)decoder
{
	if (self.dict)
	{
		EBNObservableDictionary *finalDict = [[EBNObservableDictionary alloc] init];
		[finalDict setDictionary:self.dict];
		return finalDict;
	} else if (self.set)
	{
		EBNObservableSet *finalSet = [[EBNObservableSet alloc] init];
		[finalSet setSet:self.set];
		return finalSet;
	} else if (self.array)
	{
		EBNObservableArray *finalArray = [[EBNObservableArray alloc] init];
		[finalArray setArray:self.array];
		return finalArray;
	}
	
	return nil;
}

/****************************************************************************************************
	encodeWithCoder:
	
	NSCoding. Encodes a EBNObservable collection by encoding the composed base Cocoa collection object.
*/
- (void) encodeWithCoder:(NSCoder *)encoder
{
	if (self.dict)
		[encoder encodeObject:self.dict forKey:@"dict"];
	else if (self.set)
		[encoder encodeObject:self.set forKey:@"set"];
	else if (self.array)
		[encoder encodeObject:self.array forKey:@"array"];
}

@end

#pragma clang diagnostic pop
