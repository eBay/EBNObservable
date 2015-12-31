/****************************************************************************************************
	EBNObservableCollections.m
	Observable

	Created by Chall Fry on 5/13/14.
    Copyright (c) 2013-2014 eBay Software Foundation.
*/

#import "EBNObservableInternal.h"
#import "EBNObservableCollections.h"

//

	// This is a proxy object that we create during archiving, because archiving custom subclasses of
	// class clusters doesn't seem to work right--the cluster seems to override the type of object that
	// gets archived.
@interface EBNObservableArchiverProxy : NSObject
@property (strong)	NSMutableArray		*array;
@property (strong)	NSMutableSet		*set;
@property (strong)	NSMutableDictionary	*dict;
@end

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
		_dict = [decoder decodeObjectOfClass:[NSMutableDictionary class] forKey:@"dict"];
		_set = [decoder decodeObjectOfClass:[NSMutableSet class] forKey:@"set"];
		_array = [decoder decodeObjectOfClass:[NSMutableArray class] forKey:@"array"];
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


#pragma mark
@implementation EBNObservableDictionary
{
	// Yes, this class is a subclass of NSMutableDictionary that uses internal composition
	// to implement NSMutableDictionary. See info on class clusters for why.
	NSMutableDictionary 			*_dict;
	
	// observedMethods maps properties (specified by the setter method name, as a string) to
	// a NSMutableSet of blocks to be called when the property changes.
	NSMutableDictionary *_observedMethods;
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
		if (!(_dict = [[NSMutableDictionary alloc] init]))
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
		if (!(_dict = [[NSMutableDictionary alloc] initWithCapacity:numItems]))
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
		if (!(_dict = [[NSMutableDictionary alloc] initWithObjects:objects forKeys:keys count:count]))
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
	return [_dict count];
}

/****************************************************************************************************
	objectForKey:
	
*/
- (id) objectForKey:(id)aKey
{
	return [_dict objectForKey:aKey];
}

/****************************************************************************************************
	keyEnumerator
	
*/
- (NSEnumerator *) keyEnumerator
{
	return [_dict keyEnumerator];
}

#pragma mark NSDictionary Protocols

/****************************************************************************************************
	copyWithZone:
	
	NSCopying. Like NSArray, this shallow-copies the array contents. It also creates a new observation 
	proxy object, and DOES NOT copy any of the observations on the original object.
*/
- (id) copyWithZone:(NSZone *)zone
{
	EBNObservableDictionary *newDict = [[EBNObservableDictionary allocWithZone:zone] initWithDictionary:_dict];
	return newDict;
}

/****************************************************************************************************
	mutableCopyWithZone:
	
	NSMutableCopying. Same as copyWithZone.
*/
- (id) mutableCopyWithZone:(NSZone *)zone
{
	EBNObservableDictionary *newDict = [[EBNObservableDictionary allocWithZone:zone] initWithDictionary:_dict];
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
	proxy.dict = _dict;
	
	return proxy;
}

/****************************************************************************************************
	countByEnumeratingWithState:
	
	NSFastEnumeration protocol. Pass through to composed array.
*/
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
		objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len
{
	return [_dict countByEnumeratingWithState:state objects:buffer count:len];
}

#pragma mark NSMutableDictionary Required Methods

/****************************************************************************************************
	setObject:forKey:
	
	Passes the setObject to our internal private dictionary, and attempts to notify observers of the change.
	Note that dictionaries don't require keys be strings, but if they aren't we won't notify observers.
*/
- (void)setObject:(id)newValue forKey:(id < NSCopying >)aKey
{
	// Get the previous value, and then set the new value
	NSInteger prevCount = [_dict count];
	id previousValue = [_dict objectForKey:aKey];
	[_dict setObject:newValue forKey:aKey];
	
	// Keys that aren't strings aren't observable. Slightly unsafe as we have to assume
	// keyObject is an NSObject subclass.
	NSObject *keyObject = (NSObject *) aKey;
	if ([keyObject isKindOfClass:[NSString class]])
	{
		// If this property was unset, or the new value is different than the old
		if ((previousValue == nil) || ![newValue isEqual:previousValue])
		{
			NSString *aKeyString = (NSString *) aKey;
			[self ebn_manuallyTriggerObserversForProperty:aKeyString previousValue:previousValue newValue:newValue];
			[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
		}
	}
	
	// The count property may have changed; notify for it.
	[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
			[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:[_dict count]]];
}

/****************************************************************************************************
	removeObjectForKey:
	
*/
- (void) removeObjectForKey:(id)aKey
{
	// Get the previous value, and then set the new value
	NSInteger prevCount = [_dict count];
	id previousValue = [_dict objectForKey:aKey];
	[_dict removeObjectForKey:aKey];
	
	// Keys that aren't strings aren't observable. Slightly unsafe as we have to assume
	// keyObject is an NSObject subclass.
	NSObject *keyObject = (NSObject *) aKey;
	if ([keyObject isKindOfClass:[NSString class]])
	{
		// If this property was previously set
		if (previousValue != nil)
		{
			NSString *aKeyString = (NSString *) aKey;
			[self ebn_manuallyTriggerObserversForProperty:aKeyString previousValue:previousValue newValue:nil];
			[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
		}
	}
	
	// The count property may have changed; notify for it.
	[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
			[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:[_dict count]]];
}

#pragma mark Keypaths

/****************************************************************************************************
	ebn_valueForKey:
	
*/
- (id) ebn_valueForKey:(NSString *)key
{
	return [self objectForKey:key];
}

#pragma mark Observable

/****************************************************************************************************
	ebn_observedMethodsDict
	
	For Observable collections, this just returns the ivar for the observed methods table.
	For other classes, this gets the observed methods dict out of an associated object.
	
	The caller of this method must be inside a @synchronized(EBNObservableSynchronizationToken), and must
	remain inside that sync while using the dictionary.
*/
- (NSMutableDictionary *) ebn_observedMethodsDict
{
	if (!_observedMethods)
		_observedMethods = [[NSMutableDictionary alloc] init];

	return _observedMethods;
}

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	Since we're not observing properties, we don't actually implement this method. Better said, we
	override the default implementation to do nothing.
*/
+ (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName
{
	return YES;
}

/****************************************************************************************************
	ebn_createKeypath:atIndex:
	
	This makes '*' observations work correctly for collections; we directly add an entry for '*' 
	instead of iterating through each property. Collection mutators then trigger the '*' observations
	when they get called.
*/
- (BOOL) ebn_createKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
{
	NSString *propName = entryInfo->_keyPath[index];
	return [self ebn_createKeypath:entryInfo atIndex:index forProperty:propName];
}

@end

#pragma mark
@implementation EBNObservableSet
{
	// This class is a subclass of NSMutableSet that uses internal composition
	// to implement NSMutableSet. See info on class clusters for why.
	NSMutableSet 					*set;
	
	// observedMethods maps properties (specified by the setter method name, as a string) to
	// a NSMutableSet of blocks to be called when the property changes.
	NSMutableDictionary *_observedMethods;
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
		if (!(set = [[NSMutableSet alloc] init]))
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
- (instancetype) initWithObjects:(const id [])objects count:(NSUInteger) count
{
	if (self = [super init])
	{
		if (!(set = [[NSMutableSet alloc] initWithObjects:objects count:count]))
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
		if (!(set = [[NSMutableSet alloc] initWithCapacity:numItems]))
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
	EBNObservableSet *newSet = [[EBNObservableSet allocWithZone:zone] initWithSet:set];
	return newSet;
}

/****************************************************************************************************
	mutableCopyWithZone:
	
	NSMutableCopying. Same as copyWithZone.
*/
- (id) mutableCopyWithZone:(NSZone *)zone
{
	EBNObservableSet *newSet = [[EBNObservableSet allocWithZone:zone] initWithSet:set];
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
	proxy.set = set;
	
	return proxy;
}

/****************************************************************************************************
	countByEnumeratingWithState:
	
	NSFastEnumeration protocol. Pass through to composed array.
*/
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
		objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len
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
		NSString *keyForNewValue = [EBNObservableSet keyForObject:object];
		[self ebn_manuallyTriggerObserversForProperty:keyForNewValue previousValue:previousValue
				newValue:object];
		[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
	}
	
	// The count property may have changed; notify for it.
	[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
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
		NSString *keyForPrevValue = [EBNObservableSet keyForObject:previousValue];
		[self ebn_manuallyTriggerObserversForProperty:keyForPrevValue previousValue:previousValue
				newValue:nil];
		[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
	}
	
	// The count property may have changed; notify for it.
	[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
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
+ (NSString *) keyForObject:(id) object
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
	for (id setObject in set)
	{
		if ([setObject hash] == keyHash)
			return setObject;
	}
	
	return nil;
}

/****************************************************************************************************
	ebn_valueForKey:
	
*/
- (id) ebn_valueForKey:(NSString *)key
{
	return [self objectForKey:key];
}

#pragma mark Observable

/****************************************************************************************************
	ebn_observedMethodsDict
	
	For Observable collections, this just returns the ivar for the observed methods table.
	For other classes, this gets the observed methods dict out of an associated object.
	
	The caller of this method must be inside a @synchronized(EBNObservableSynchronizationToken), and must
	remain inside that sync while using the dictionary.
*/

- (NSMutableDictionary *) ebn_observedMethodsDict
{
	if (!_observedMethods)
		_observedMethods = [[NSMutableDictionary alloc] init];

	return _observedMethods;
}

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	Since we're not observing properties, we don't actually implement this method. Better said, we
	override the default implementation to do nothing.
*/
+ (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName
{
	return YES;
}

/****************************************************************************************************
	ebn_createKeypath:atIndex:
	
	This makes '*' observations work correctly for collections; we directly add an entry for '*' 
	instead of iterating through each property. Collection mutators then trigger the '*' observations
	when they get called.
*/
- (BOOL) ebn_createKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
{
	NSString *propName = entryInfo->_keyPath[index];
	return [self ebn_createKeypath:entryInfo atIndex:index forProperty:propName];
}

@end

#pragma mark
@implementation EBNObservableArray
{
	// This class is a subclass of NSMutableArray that uses internal composition
	// to implement NSMutableArray. See info on class clusters for why--the short story is that
	// NSMutableArray doesn't actually implement an array; it's just a protocol class.
	NSMutableArray		 			*array;
	
	// observedMethods maps properties (specified by the setter method name, as a string) to
	// a NSMutableSet of blocks to be called when the property changes.
	NSMutableDictionary *_observedMethods;
}

#pragma mark NSArray Required Methods

/****************************************************************************************************
	init
	
*/
- (instancetype) init
{
	if (self = [super init])
	{
		if (!(array = [[NSMutableArray alloc] init]))
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
		if (!(array = [[NSMutableArray alloc] initWithObjects:objects count:count]))
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
		if (!(array = [[NSMutableArray alloc] initWithCapacity:numItems]))
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
	EBNObservableArray *newArray = [[EBNObservableArray allocWithZone:zone] initWithArray:array];
	return newArray;
}

/****************************************************************************************************
	mutableCopyWithZone:
	
	NSMutableCopying. Same as copyWithZone.
*/
- (id) mutableCopyWithZone:(NSZone *)zone
{
	EBNObservableArray *newArray = [[EBNObservableArray allocWithZone:zone] initWithArray:array];
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
	proxy.array = array;
	
	return proxy;
}

/****************************************************************************************************
	countByEnumeratingWithState:
	
	NSFastEnumeration protocol. Pass through to composed array.
*/
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
		objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len
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
	
	@synchronized(EBNObservableSynchronizationToken)
	{
		for (NSString *propertyKey in self.ebn_observedMethodsDict)
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
					[self ebn_manuallyTriggerObserversForProperty:propertyKey previousValue:prevValueForIndex
							newValue:newValueForIndex];
				}

			} else if ([propertyKey isEqualToString:@"*"])
			{
				// If we have observations on '*', run them here
				[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
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
			NSMapTable *observerTable = self.ebn_observedMethodsDict[moveFromPropKey];
			[self.ebn_observedMethodsDict removeObjectForKey:moveFromPropKey];
			[self.ebn_observedMethodsDict setObject:observerTable forKey:moveToPropKey];
		}
	}
	
	// The count property changed; notify for it.
	[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:[NSNumber numberWithInteger:prevCount]];
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
	
	@synchronized(EBNObservableSynchronizationToken)
	{
		for (NSString *propertyKey in self.ebn_observedMethodsDict)
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
					[self ebn_manuallyTriggerObserversForProperty:propertyKey
							previousValue:prevValueForIndex newValue:newValueForIndex];
				}
			} else if ([propertyKey isEqualToString:@"*"])
			{
				// If we have observations on '*', run them here
				[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
			} else
			{
				NSUInteger keyIndex = [propertyKey integerValue];
				if (keyIndex == removeIndex)
				{
					[self ebn_manuallyTriggerObserversForProperty:propertyKey previousValue:prevValue newValue:nil];
					
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
			NSMapTable *observerTable = self.ebn_observedMethodsDict[moveFromPropKey];
			[self.ebn_observedMethodsDict removeObjectForKey:moveFromPropKey];
			[self.ebn_observedMethodsDict setObject:observerTable forKey:moveToPropKey];
		}
	}
	
	// The count property changed; notify for it.
	[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
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
	
	[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
	[self ebn_manuallyTriggerObserversForProperty:propHashIndexString previousValue:nil newValue:anObject];
	
	// The count property changed; notify for it.
	[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:[NSNumber numberWithInteger:prevCount]];
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
		
		[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
		[self ebn_manuallyTriggerObserversForProperty:propIndexString previousValue:prevValue newValue:nil];
		[self ebn_manuallyTriggerObserversForProperty:propHashIndexString previousValue:prevValue newValue:nil];
				
		// If an 'object-following' property was being observed, and its object is now removed from the array,
		// stop observing, since we can't observe this path anymore.
		[self stopObservingProperty:propIndexString];
		
		// The count property changed; notify for it.
		[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:[NSNumber numberWithInteger:prevCount]];
	}
}

/****************************************************************************************************
	replaceObjectAtIndex:withObject:
	
*/
- (void) replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject
{
	id prevValue = nil;
	if (index < [array count])
		prevValue = array[index];
		
	[array replaceObjectAtIndex:index withObject:anObject];
	
	NSString *propIndexString = [[NSString alloc] initWithFormat:@"%lu", (unsigned long) index];
	NSString *propHashIndexString = [[NSString alloc] initWithFormat:@"#%lu", (unsigned long) index];
	
	[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:nil];
	[self ebn_manuallyTriggerObserversForProperty:propIndexString previousValue:prevValue newValue:anObject];
	[self ebn_manuallyTriggerObserversForProperty:propHashIndexString previousValue:prevValue newValue:anObject];
			
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
	
	@synchronized(EBNObservableSynchronizationToken)
	{
		observerTable = [self.ebn_observedMethodsDict[propertyName] copy];
	}
	
	for (EBNKeypathEntryInfo *entry in observerTable)
	{
		NSObject *observedObject = entry->_blockInfo->_weakObserved;
		if (observedObject)
		{
			[observedObject ebn_removeKeypath:entry atIndex:0];
		}
	}
}

/****************************************************************************************************
	ebn_valueForKey:
	
*/
- (id) ebn_valueForKey:(NSString *)key
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

#pragma mark Observable

/****************************************************************************************************
	ebn_observedMethodsDict
	
	For Observable collections, this just returns the ivar for the observed methods table.
	For other classes, this gets the observed methods dict out of an associated object.
	
	The caller of this method must be inside a @synchronized(EBNObservableSynchronizationToken), and must
	remain inside that sync while using the dictionary.
*/
- (NSMutableDictionary *) ebn_observedMethodsDict
{
	if (!_observedMethods)
		_observedMethods = [[NSMutableDictionary alloc] init];

	return _observedMethods;
}

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	Since we're not observing properties, we don't actually implement this method. Better said, we
	override the default implementation to do nothing.
*/
+ (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName
{
	return YES;
}

/****************************************************************************************************
	ebn_createKeypath:atIndex:
	
	This makes '*' observations work correctly for collections; we directly add an entry for '*' 
	instead of iterating through each property. Collection mutators then trigger the '*' observations
	when they get called.
*/
- (BOOL) ebn_createKeypath:(const EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) index
{
	NSString *propName = entryInfo->_keyPath[index];
	return [self ebn_createKeypath:entryInfo atIndex:index forProperty:propName];
}

/****************************************************************************************************
	ebn_removeKeypath:atIndex:

	For object-following array properties, the 'key' pointing to the property can move around as
	objects are added/removed from the array. When we remove the keypath, we need to go find
	where the entry has moved to.
	
	Also, for '*' observations, we directly remove the '*' entry from the table.
	
	Returns YES if the observation path was removed successfully.
*/
- (BOOL) ebn_removeKeypath:(const EBNKeypathEntryInfo *) removeEntry atIndex:(NSInteger) index
{
	if (index >= [removeEntry->_keyPath count])
		return NO;

	NSString *propName = removeEntry->_keyPath[index];
	
	// For array collections, we need to handle object-following observations (like "array.4")
	// in a special way. That special way is to look through every property to find where
	// the observation may have moved to. And yes, by 'special' you can infer 'because the
	// data model is designed wrong'.
	if (isdigit([propName characterAtIndex:0]))
	{
		@synchronized(EBNObservableSynchronizationToken)
		{
			for (NSString *propertyKey in [_observedMethods allKeys])
			{
				[self ebn_removeKeypath:removeEntry atIndex:index forProperty:propertyKey];
			}
		}
	}
	else if ([propName isEqualToString:@"*"])
	{
		// If this is a '*' observation, remove all observations via recursive calls
		NSArray *properties = nil;
		@synchronized(EBNObservableSynchronizationToken)
		{
			properties = [self.ebn_observedMethodsDict allKeys];
		}
		
		for (NSString *property in properties)
		{
			[self ebn_removeKeypath:removeEntry atIndex:index forProperty:property];
		}
	}
 	else
	{
		return [self ebn_removeKeypath:removeEntry atIndex:index forProperty:propName];
	}
		
	return YES;
}

@end
