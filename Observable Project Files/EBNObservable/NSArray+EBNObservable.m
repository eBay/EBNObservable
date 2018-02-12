/****************************************************************************************************
	NSArray+EBNObservable.m
	Observable

 	Created by Chall Fry on 2/22/16.
	Copyright © 2013-2018 eBay Software Foundation.
*/

#import <objc/message.h>

#import "NSArray+EBNObservable.h"
#import "EBNObservableInternal.h"

static void ebn_shadowed_insertObjectAtIndex(NSMutableArray *self, SEL _cmd, id anObject, NSUInteger insertIndex);
static void ebn_shadowed_removeObjectAtIndex(NSMutableArray *self, SEL _cmd, NSUInteger removeIndex);
static void ebn_shadowed_addObject(NSMutableArray *self, SEL _cmd, id anObject);
static void ebn_shadowed_removeLastObject(NSMutableArray *self, SEL _cmd);
static void ebn_shadowed_replaceObjectAtIndex(NSMutableArray *self, SEL _cmd, NSUInteger index, id anObject);
static void ebn_shadowed_removeAllObjects(NSMutableArray *self, SEL _cmd);
static void ebn_shadowed_addObjectsFromArray(NSMutableArray *self, SEL _cmd, NSArray *sourceArray);


@implementation NSArray (EBNObservable)

/****************************************************************************************************
	ebn_compareKeypathValues:atIndex:from:to:
    
    Compares the values of the given key in both fromObj and toObj. Handles wildcards.
*/
+ (BOOL) ebn_compareKeypathValues:(EBNKeypathEntryInfo *) info atIndex:(NSInteger) index from:(id) fromObj to:(id) toObj
{
	BOOL result = NO;
	
	NSArray *fromArray = (NSArray *) fromObj;
	NSArray *toArray = (NSArray *) toObj;
	
	NSString *propName = info->_keyPath[index];
	if ([propName isEqualToString:@"*"])
	{
		NSInteger maxCount = fromArray.count;
		if (toArray.count > maxCount)
			maxCount = toArray.count;
		
		for (int arrayIndex = 0; arrayIndex < maxCount; ++arrayIndex)
		{
			id fromValue = nil;
			if (arrayIndex < fromArray.count)
				fromValue = fromArray[arrayIndex];
			id toValue = nil;
			if (arrayIndex < toArray.count)
				toValue = toArray[arrayIndex];
			result |= [info ebn_comparePropertyAtIndex:index from:fromValue to:toValue];
		}
	}
	else
	{
		id fromArrayValue = [fromArray ebn_valueForKey:propName];
		id toArrayValue = [toArray ebn_valueForKey:propName];
		result = [info ebn_comparePropertyAtIndex:index from:fromArrayValue to:toArrayValue];
	}

	return result;
}

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	Overrides the NSObject(EBNObservable) implementation.
	
	Like the superclass implementation, this method calls prepareObjectForObservation, which 
	isa-swizzles the object to ensure it's an Observable subclass of its original class.
	
	Why bother observing immutable objects? The objects in the array could have mutable properties;
	and you can create observation keypaths that go through the dict, to the dict's objectForKey:, to
	a given property.
*/
- (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName
{
	@synchronized (EBNBaseClassToShadowInfoTable)
	{
		// This checks to see if we've made a shadow subclass of this object's class, and if we've
		// isa-swizzled this object to be that class.
		EBNShadowedClassInfo *info = [self ebn_prepareObjectForObservation];
		if (!info)
			return NO;
	}

	// If the value being swizzled is an actual property and not a array key, call super to handle it
	// Except in the case of count. Count can't change in NSArray, and for mutable subclasses we
	// notify for changes to count by intercepting the mutating primitive methods.
	if (propName && class_getProperty(object_getClass(self), [propName UTF8String]) && ![propName isEqualToString:@"count"])
	{
		[super ebn_swizzleImplementationForSetter:propName];
	}
	
	return YES;
}

/****************************************************************************************************
	ebn_valueForKey:
	
	NSArray's valueForKey: works by calling valueForKey: on every array member, and returns those results
	as a new array.
	
	This method does not work like that.
*/
- (id) ebn_valueForKey:(NSString *)key
{
	// If key refers to an actual property, call super to get the property value
	if (class_getProperty(object_getClass(self), [key UTF8String]))
	{
		return [super ebn_valueForKey:key];
	}
	else if ([key hasPrefix:@"#"])
	{
		NSUInteger arrayIndex = [[key substringFromIndex:1] integerValue];
		if (arrayIndex < self.count)
			return self[arrayIndex];
		else
			return nil;
	}
	else if ([key length] > 0 && isdigit([key characterAtIndex:0]))
	{
		NSUInteger arrayIndex = [key integerValue];
		if (arrayIndex < self.count)
			return self[arrayIndex];
		else
			return nil;
	}
	
	return nil;
}

/****************************************************************************************************
	ebn_addEntry:forProperty:
	
	Really, this just checks for a degenerate case and calls super. Super does the real work.
*/
- (void) ebn_addEntry:(EBNKeypathEntryInfo *) entryInfo forProperty:(NSString *) propName
{
	// Assert on the easy-to-find case of a useless observation. If this is an immutable dictionary
	// and the observation path is just 1 entry, the observation won't ever do anything.
	// "NSDictionary.NSDictionary" and similar paths won't get caught by this.
	EBAssert(entryInfo->_keyPath.count > 1 || [self isKindOfClass:[NSMutableArray class]],
			@"Observing an immutable dictionary for changes. This observation will never fire.");

	// The dictionary must be isa-swizzled even in the case where the value being observed isn't
	// currently in the dictionary, so we make sure that happens here.
	[self ebn_swizzleImplementationForSetter:nil];

	[super ebn_addEntry:entryInfo forProperty:propName];
}

/****************************************************************************************************
	ebn_removeEntry:atIndex:forProperty:
    
    
*/
- (EBNKeypathEntryInfo *) ebn_removeEntry:(EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) pathIndex 
		forProperty:(NSString *) propName
{
	if (isdigit([propName characterAtIndex:0]))
	{
		// For array collections, we need to handle object-following observations (like "array.4")
		// in a special way. That special way is to look through every property to find where
		// the observation may have moved to. And yes, by 'special' you can infer 'because the
		// data model is designed wrong'.
		NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
		if (!observedKeysDict)
			return nil;
			
		EBNKeypathEntryInfo *indexedEntry = [entryInfo copy];
		indexedEntry->_keyPathIndex = pathIndex;
		
		@synchronized(observedKeysDict)
		{
			for (NSString *propertyKey in observedKeysDict.allKeys)
			{
				if (isdigit([propertyKey characterAtIndex:0]) && [observedKeysDict[propertyKey] containsObject:indexedEntry])
				{
					[super ebn_removeEntry:entryInfo atIndex:pathIndex forProperty:propertyKey];
				}
			}
		}
	}
	else
	{
		[super ebn_removeEntry:entryInfo atIndex:pathIndex forProperty:propName];
	}
	
	return nil;
}

@end


@implementation NSMutableArray (EBNObservable)

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	Overrides the NSObject(EBNObservable) implementation.
	
	Like the superclass implementation, this method calls prepareObjectForObservation, which 
	isa-swizzles the object to ensure it's an Observable subclass of its original class.
	
	For dictionaries we're most interested in observing dictionary keys, not properties. So, this method
	swizzles the core mutating methods of NSMutableDictionary so we can watch for changes made to the
	dictionary. If it's actually a property that's going to be observed, we call through to the superclass,
	which is set up to handle that.
	
	This means that any non-property is assumed to be a dictionary key, even if getter and setter methods
	with the correct names exist (likely in a category). Be sure to use @property.
*/
- (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName
{
	Class classToModify = nil;
	
	@synchronized (EBNBaseClassToShadowInfoTable)
	{
		// This checks to see if we've made a shadow subclass of this object's class, and if we've
		// isa-swizzled this object to be that class.
		EBNShadowedClassInfo *info = [self ebn_prepareObjectForObservation];
		if (!info)
			return NO;

		if (!info->_collectionSwizzlesDone)
		{
			info->_collectionSwizzlesDone = true;
			classToModify = info->_shadowClass;
	
			// Override insertObject:atIndex: in the subclass
			Method insetObjectAtIndexMethod = class_getInstanceMethod([self class], @selector(insertObject:atIndex:));
			class_addMethod(classToModify, @selector(insertObject:atIndex:), (IMP) ebn_shadowed_insertObjectAtIndex,
					method_getTypeEncoding(insetObjectAtIndexMethod));
			
			// Override removeObjectAtIndex: in the subclass
			Method removeObjectAtIndexMethod = class_getInstanceMethod([self class], @selector(removeObjectAtIndex:));
			class_addMethod(classToModify, @selector(removeObjectAtIndex:), (IMP) ebn_shadowed_removeObjectAtIndex,
					method_getTypeEncoding(removeObjectAtIndexMethod));

			// Override replaceObjectAtIndex:withObject: in the subclass
			Method replaceObjectAtIndexMethod = class_getInstanceMethod([self class],
					@selector(replaceObjectAtIndex:withObject:));
			class_addMethod(classToModify, @selector(replaceObjectAtIndex:withObject:),
					(IMP) ebn_shadowed_replaceObjectAtIndex, method_getTypeEncoding(replaceObjectAtIndexMethod));

			// Override replaceObjectAtIndex:withObject: in the subclass
			Method removeAllObjectsMethod = class_getInstanceMethod([self class], @selector(removeAllObjects));
			class_addMethod(classToModify, @selector(removeAllObjects),
					(IMP) ebn_shadowed_removeAllObjects, method_getTypeEncoding(removeAllObjectsMethod));

			// Override addObjectsFromArray: in the subclass
			// New in iOS 10, this method is not defined in terms of the primitive methods, that is,
			// it is now apparently a primitive itself.
			NSOperatingSystemVersion minVers = { 10, 0, 0 };
			if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:minVers])
			{
				Method addObjectsFromArrayMethod = class_getInstanceMethod([self class], @selector(addObjectsFromArray:));
				class_addMethod(classToModify, @selector(addObjectsFromArray:),
						(IMP) ebn_shadowed_addObjectsFromArray, method_getTypeEncoding(addObjectsFromArrayMethod));
			}
			else
			{
				// Prior to iOS 10, addObject: and removeLastObject: were primitives.
				// In iOS 10, they go to insertObjectAtIndex:/removeObjectAtIndex:.
			
				// Override addObject: in the subclass
				Method addObjectMethod = class_getInstanceMethod([self class], @selector(addObject:));
				class_addMethod(classToModify, @selector(addObject:), (IMP) ebn_shadowed_addObject,
						method_getTypeEncoding(addObjectMethod));

				// Override removeLastObject in the subclass
				Method removeLastObjectMethod = class_getInstanceMethod([self class], @selector(removeLastObject));
				class_addMethod(classToModify, @selector(removeLastObject), (IMP) ebn_shadowed_removeLastObject,
						method_getTypeEncoding(removeLastObjectMethod));
			}
		}
	}
	
	// If the value being swizzled is an actual property and not a dictionary key, call super to handle it
	// Except in the case of count, where we can handle it in setObject: and removeObject:.
	if (class_getProperty(object_getClass(self), [propName UTF8String]) && ![propName isEqualToString:@"count"])
	{
		[super ebn_swizzleImplementationForSetter:propName];
	}
	
	return YES;
}

/****************************************************************************************************
	ebn_stopObservationsOnKey:
	
	Internal method that stops observing the given array element key. This method will retrieve
	the observed object (the object at the root of the keypath) and tell it to remove the entire 
	path.
*/
- (void) ebn_stopObservationsOnKey:(NSString *) propertyName
{
	// Do we have any observers active on this property?
	NSMutableArray *observers = NULL;
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (!observedKeysDict)
		return;
	
	@synchronized(observedKeysDict)
	{
		observers = [observedKeysDict[propertyName] copy];
	}
	
	for (EBNKeypathEntryInfo *entry in observers)
	{
		[entry ebn_removeObservation];
	}
}

@end

/****************************************************************************************************
	insertObject:atIndex:
	
*/
static void ebn_shadowed_insertObjectAtIndex(NSMutableArray *self, SEL _cmd, id anObject, NSUInteger insertIndex)
{
	NSUInteger prevCount = self.count;

	// Call the superclass to actually set the value. There's a couple ways insertObject:atIndex:
	//  can throw exceptions, but if that happens, the array didn't mutate, so we just let the throw happen.
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, id, NSUInteger) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, anObject, insertIndex);

	NSMutableArray *adjustObservations = [[NSMutableArray alloc] init];

	// Get a copy of the keys in the observed methods dictionary
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (!observedKeysDict)
		return;
	
	NSArray *observedKeys;
	@synchronized(observedKeysDict)
	{
		observedKeys = [observedKeysDict allKeys];
	}
	
	for (NSString *propertyKey in observedKeys)
	{
		if ([propertyKey isEqualToString:@"*"])
		{
			// If we have observations on '*', run them here
			[self ebn_manuallyTriggerObserversForProperty:propertyKey previousValue:nil newValue:anObject];
		}
		else if ([propertyKey isEqualToString:@"count"])
		{
			// If we have observations on count, run them here
			[self ebn_manuallyTriggerObserversForProperty:propertyKey
					previousValue:[NSNumber numberWithInteger:prevCount]
					newValue:[NSNumber numberWithInteger:self.count]];
		}
		else if ([propertyKey hasPrefix:@"#"])
		{
			// array.#4 observes the object at index 4, and follows the index
			NSUInteger observedIndex = [[propertyKey substringFromIndex:1] integerValue];
			if (observedIndex >= insertIndex && observedIndex < self.count)
			{
				id prevValueForIndex = nil;
				if (observedIndex + 1 < self.count)
					prevValueForIndex = self[observedIndex + 1];
				id newValueForIndex = self[observedIndex];
				[self ebn_manuallyTriggerObserversForProperty:propertyKey previousValue:prevValueForIndex
						newValue:newValueForIndex];
			}
		}
		else if ([propertyKey length] > 0 && isdigit([propertyKey characterAtIndex:0]))
		{
			// array.4 observes the object at index 4 *at the time observation starts*, and follows that object
			NSUInteger keyIndex = [propertyKey integerValue];
			if (keyIndex >= insertIndex)
				[adjustObservations addObject:propertyKey];
		}
		
		// Observations that don't fit in one of the above categories must be property observations, and
		// we assume they aren't modified by array inserts.
	}
	
	if (adjustObservations.count)
	{
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
		
		@synchronized(observedKeysDict)
		{
			// Traverse the observations in decreasing order, moving N to (N+1)
			for (long moverIndex = adjustObservations.count - 1; moverIndex >= 0; --moverIndex)
			{
				NSString *moveFromPropKey = adjustObservations[moverIndex];
				NSString *moveToPropKey = [NSString stringWithFormat:@"%d", [moveFromPropKey intValue] + 1];
				NSMutableArray *observers = observedKeysDict[moveFromPropKey];
				if (observers)
				{
					[observedKeysDict removeObjectForKey:moveFromPropKey];
					[observedKeysDict setObject:observers forKey:moveToPropKey];
				}
			}
		}
	}
}

/****************************************************************************************************
	removeObjectAtIndex:
	
*/
static void ebn_shadowed_removeObjectAtIndex(NSMutableArray *self, SEL _cmd, NSUInteger removeIndex)
{
	NSUInteger prevCount = self.count;
	id prevValue = nil;
	if (removeIndex < self.count)
		prevValue = [self objectAtIndex:removeIndex];

	// Call the superclass to actually set the value. There's a couple ways removeObjectAtIndex:
	// can throw exceptions, but if that happens, the array didn't mutate, so we just let the throw happen.
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, NSUInteger) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, removeIndex);


	NSMutableArray *adjustObservations = [[NSMutableArray alloc] init];
	
	// Get a copy of the keys in the observed methods dictionary
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (!observedKeysDict)
		return;
	
	NSArray *observedKeys;
	@synchronized(observedKeysDict)
	{
		observedKeys = [observedKeysDict allKeys];
	}

	for (NSString *observedKey in observedKeys)
	{
		if ([observedKey isEqualToString:@"*"])
		{
			// If we have observations on '*', run them here
			[self ebn_manuallyTriggerObserversForProperty:observedKey previousValue:prevValue newValue:nil];
		}
		else if ([observedKey isEqualToString:@"count"])
		{
			// If we have observations on count, run them here
			[self ebn_manuallyTriggerObserversForProperty:observedKey
					previousValue:[NSNumber numberWithInteger:prevCount]
					newValue:[NSNumber numberWithInteger:self.count]];
		}
		else if ([observedKey hasPrefix:@"#"])
		{
			// There can be observations beyond the end of the array. They should get notified
			// in the case where their value changes, and when the array shrinks and becomes
			// smaller than their index.
			NSUInteger observedIndex = [[observedKey substringFromIndex:1] integerValue];
			if (observedIndex >= removeIndex && observedIndex <= self.count)
			{
				id prevValueAtIndex = nil;
				if (observedIndex == removeIndex)
					prevValueAtIndex = prevValue;
				else if (observedIndex > 0 && observedIndex < self.count)
					prevValueAtIndex = self[observedIndex - 1];
				id newValueAtIndex = nil;
				if (observedIndex < self.count)
					newValueAtIndex = self[observedIndex];
				[self ebn_manuallyTriggerObserversForProperty:observedKey
						previousValue:prevValueAtIndex newValue:newValueAtIndex];
			}
		}
		else if ([observedKey length] > 0 && isdigit([observedKey characterAtIndex:0]))
		{
			NSUInteger keyIndex = [observedKey integerValue];
			if (keyIndex == removeIndex)
			{
				[self ebn_manuallyTriggerObserversForProperty:observedKey previousValue:prevValue newValue:nil];
				[self ebn_stopObservationsOnKey:observedKey];
				
			} else if (keyIndex > removeIndex)
			{
				[adjustObservations addObject:observedKey];
			}
		}
		
		// Observations that don't fit in one of the above categories must be property observations, and
		// we assume they aren't modified by array inserts.
	}
	
	if (adjustObservations.count)
	{
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
		
		@synchronized(observedKeysDict)
		{
			// Traverse the number observations in increasing order, moving N to (N-1)
			for (int moverIndex = 0; moverIndex < adjustObservations.count; ++moverIndex)
			{
				NSString *moveFromPropKey = adjustObservations[moverIndex];
				NSString *moveToPropKey = [NSString stringWithFormat:@"%d", [moveFromPropKey intValue] - 1];
				NSMutableArray *observers = observedKeysDict[moveFromPropKey];
				[observedKeysDict removeObjectForKey:moveFromPropKey];
				[observedKeysDict setObject:observers forKey:moveToPropKey];
			}
		}
	}
}

/****************************************************************************************************
	addObject:
	
	No index shifting can occur here, making this method significantly easier than addObject:atIndex:.
*/
static void ebn_shadowed_addObject(NSMutableArray *self, SEL _cmd, id anObject)
{
	NSUInteger prevCount = self.count;
	
	// Call the superclass to actually set the value. There's a couple ways addObject:
	// can throw exceptions, but if that happens, the array didn't mutate, so we just let the throw happen.
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, id) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, anObject);
	
	// Trigger observations on * and count.
	[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:nil newValue:anObject];
	[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:[NSNumber numberWithInteger:prevCount]];

	// If there was a '#' style observation just past the (previous) end of the array, trigger it as well.
	NSString *propHashIndexString = [[NSString alloc] initWithFormat:@"#%lu",  (unsigned long) prevCount];
	[self ebn_manuallyTriggerObserversForProperty:propHashIndexString previousValue:nil newValue:anObject];
}

/****************************************************************************************************
	removeLastObject
	
*/
static void ebn_shadowed_removeLastObject(NSMutableArray *self, SEL _cmd)
{
	NSUInteger prevCount = self.count;
	NSInteger prevLastIndex = prevCount - 1;
	id prevValue = nil;
	if (prevCount)
		prevValue = [self objectAtIndex:prevLastIndex];
	
	// Call the superclass to actually do the remove. There's a couple ways removeLastObject
	// can throw exceptions, but if that happens, the array didn't mutate, so we just let the throw happen.
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd);

	NSString *propIndexString = [[NSString alloc] initWithFormat:@"%lu", (long) prevLastIndex];
	NSString *propHashIndexString = [[NSString alloc] initWithFormat:@"#%lu", (long) prevLastIndex];
	
	// Notify for * and count
	[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:prevValue newValue:nil];
	[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:[NSNumber numberWithInteger:prevCount]];

	// Then, notify for "#<index>" and "<index>" style observations
	[self ebn_manuallyTriggerObserversForProperty:propIndexString previousValue:prevValue newValue:nil];
	[self ebn_manuallyTriggerObserversForProperty:propHashIndexString previousValue:prevValue newValue:nil];

	// If an 'object-following' key was being observed, and its object is now removed from the array,
	// stop observing, since we can't observe this path anymore.
	[self ebn_stopObservationsOnKey:propIndexString];
	
}

/****************************************************************************************************
	replaceObjectAtIndex:withObject:
	
*/
static void ebn_shadowed_replaceObjectAtIndex(NSMutableArray *self, SEL _cmd, NSUInteger index, id anObject)
{
	id prevValue = nil;
	if (index < self.count)
		prevValue = self[index];
		
	// Call the superclass to actually do the remove. There's a couple ways removeLastObject
	// can throw exceptions, but if that happens, the array didn't mutate, so we just let the throw happen.
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, NSUInteger, id) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, index, anObject);
	
	// Notify on all the things that might be relevant.
	NSString *propIndexString = [[NSString alloc] initWithFormat:@"%lu", (unsigned long) index];
	NSString *propHashIndexString = [[NSString alloc] initWithFormat:@"#%lu", (unsigned long) index];
	[self ebn_manuallyTriggerObserversForProperty:@"*" previousValue:prevValue newValue:anObject];
	[self ebn_manuallyTriggerObserversForProperty:propIndexString previousValue:prevValue newValue:anObject];
	[self ebn_manuallyTriggerObserversForProperty:propHashIndexString previousValue:prevValue newValue:anObject];
			
	// Object-following properties need to stop observing after their object leaves the array
	[self ebn_stopObservationsOnKey:propIndexString];
}


/****************************************************************************************************
	removeAllObjects
	
	It appears this method is treated as a primitive, so here we handle it as such.
*/
static void ebn_shadowed_removeAllObjects(NSMutableArray *self, SEL _cmd)
{
	// Get the previous count and set contents
	NSUInteger prevCount = self.count;
	NSArray *prevContents = [self copy];
	
	// Call the superclass to actually remove eveything
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd);
	
	if (prevCount)
	{
		// Get a copy of the keys in the observed keys dictionary
		NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
		if (!observedKeysDict)
			return;
			
		NSArray *observedKeys;
		@synchronized(observedKeysDict)
		{
			observedKeys = [observedKeysDict allKeys];
		}
		
		for (NSString *observedKey in observedKeys)
		{
			if ([observedKey isEqualToString:@"*"])
			{
				// If we have observations on '*', run them here
				for (NSObject *obj in prevContents)
				{
					[self ebn_manuallyTriggerObserversForProperty:observedKey previousValue:obj newValue:nil];
				}
			}
			else if ([observedKey isEqualToString:@"count"])
			{
				// If we have observations on count, run them here
				[self ebn_manuallyTriggerObserversForProperty:observedKey
						previousValue:[NSNumber numberWithInteger:prevCount]
						newValue:[NSNumber numberWithInteger:self.count]];
			}
			else if ([observedKey hasPrefix:@"#"])
			{
				// There can be observations beyond the end of the array. They should get notified
				// in the case where their value changes, and when the array shrinks and becomes
				// smaller than their index.
				NSUInteger observedIndex = [[observedKey substringFromIndex:1] integerValue];
				if (observedIndex < prevCount)
				{
					id prevValueAtIndex = prevContents[observedIndex];
					id newValueAtIndex = nil;
					[self ebn_manuallyTriggerObserversForProperty:observedKey
							previousValue:prevValueAtIndex newValue:newValueAtIndex];
				}
			}
			else if ([observedKey length] > 0 && isdigit([observedKey characterAtIndex:0]))
			{
				NSUInteger keyIndex = [observedKey integerValue];
				id prevValueAtIndex = nil;
				if (prevContents.count > keyIndex)
				{
					prevValueAtIndex = prevContents[keyIndex];
				}
				[self ebn_manuallyTriggerObserversForProperty:observedKey previousValue:prevValueAtIndex
						newValue:nil];
				[self ebn_stopObservationsOnKey:observedKey];
					
			}
		}
	}
}

/****************************************************************************************************
	ebn_shadowed_addObjectsFromArray:
	
	Before iOS 10, this method was defined in terms of primitive NSMutableArray methods, probably
	addObject:. Now, it appears to be a primitive on its own.
*/
static void ebn_shadowed_addObjectsFromArray(NSMutableArray *self, SEL _cmd, NSArray *sourceArray)
{
	// Get the previous count	
	NSUInteger prevCount = self.count;

	// Call the superclass to actually do the remove. There's a couple ways addObjectsFromArray:
	// can throw exceptions, but if that happens, the array didn't mutate, so we just let the throw happen.
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, NSArray *) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, sourceArray);
	
	// If the source array was nil or empty, no mutation happened.
	if (!sourceArray.count)
		return;
		
	// Get a copy of the keys in the observed keys dictionary
	NSArray *observedKeys = nil;
	NSMutableDictionary *observedKeysDict = [self ebn_observedKeysDict:NO];
	if (!observedKeysDict)
		return;
	@synchronized(observedKeysDict)
	{
		observedKeys = [observedKeysDict allKeys];
	}
	
	for (NSString *observedKey in observedKeys)
	{
		if ([observedKey isEqualToString:@"*"])
		{
			// If we have observations on '*', run them here
			for (NSObject *obj in sourceArray)
			{
				[self ebn_manuallyTriggerObserversForProperty:observedKey previousValue:nil newValue:obj];
			}
		}
		else if ([observedKey isEqualToString:@"count"])
		{
			// If we have observations on count, run them here
			[self ebn_manuallyTriggerObserversForProperty:observedKey
					previousValue:[NSNumber numberWithInteger:prevCount]
					newValue:[NSNumber numberWithInteger:self.count]];
		}
		else if ([observedKey hasPrefix:@"#"])
		{
			// There can be observations beyond the end of the array. They should get notified
			// in the case where their value changes, and when the array shrinks and becomes
			// smaller than their index.
			NSUInteger observedIndex = [[observedKey substringFromIndex:1] integerValue];
			if (observedIndex >= prevCount && observedIndex < self.count)
			{
				id newValueAtIndex = self[observedIndex];
				[self ebn_manuallyTriggerObserversForProperty:observedKey previousValue:nil newValue:newValueAtIndex];
			}
		}
	}
}


