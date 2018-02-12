/****************************************************************************************************
	NSDictionary+EBNObservable.m
	Observable

 	Created by Chall Fry on 2/22/16.
	Copyright © 2013-2018 eBay Software Foundation.
*/

#import <objc/message.h>

#import "NSDictionary+EBNObservable.h"
#import "EBNObservableInternal.h"

static void ebn_shadowed_setObjectForKey(NSMutableDictionary *self, SEL _cmd, id newValue, id<NSCopying> aKey);
static void ebn_shadowed_removeObjectForKey(NSMutableDictionary *self, SEL _cmd, id<NSCopying> aKey);
static void ebn_shadowed_setObjectForKeyedSubscript(NSMutableDictionary *self, SEL _cmd, id newValue, id<NSCopying> aKey);
static void ebn_shadowed_removeAllObjects(NSMutableDictionary *self, SEL _cmd);

@implementation NSDictionary (EBNObservable)

/****************************************************************************************************
	ebn_compareKeypathValues:atIndex:from:to:
    
    Compares the values of the given key in both fromObj and toObj. Handles wildcards.
*/
+ (BOOL) ebn_compareKeypathValues:(EBNKeypathEntryInfo *) info atIndex:(NSInteger) index from:(id) fromObj to:(id) toObj
{
	BOOL result = NO;
	
	NSDictionary *fromDict = (NSDictionary *) fromObj;
	NSDictionary *toDict = (NSDictionary *) toObj;
	
	NSString *propName = info->_keyPath[index];
	if ([propName isEqualToString:@"*"])
	{
		NSMutableSet *allEntries = [NSMutableSet set];
		if (fromDict)
		{
			[allEntries addObjectsFromArray:fromDict.allKeys];
		}
		if (toDict)
		{
			[allEntries addObjectsFromArray:toDict.allKeys];
		}

		for (id dictEntry in allEntries)
		{
			id fromMember = [fromDict objectForKey:dictEntry];
			id toMember = [toDict objectForKey:dictEntry];
			result |= [info ebn_comparePropertyAtIndex:index from:fromMember to:toMember];
		}
	}
	else
	{
		id fromDictValue = [fromDict objectForKey:propName];
		id toDictValue = [toDict objectForKey:propName];
		result = [info ebn_comparePropertyAtIndex:index from:fromDictValue to:toDictValue];
	}

	return result;
}

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	Overrides the NSObject(EBNObservable) implementation.
	
	Like the superclass implementation, this method calls prepareObjectForObservation, which 
	isa-swizzles the object to ensure it's an Observable subclass of its original class.
	
	Why bother observing immutable objects? The objects in the dictionary could have mutable properties;
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

	// If the value being swizzled is an actual property and not a dictionary key, call super to handle it
	// Except in the case of count; count can't change..
	if (propName && class_getProperty(object_getClass(self), [propName UTF8String]) && ![propName isEqualToString:@"count"])
	{
		[super ebn_swizzleImplementationForSetter:propName];
	}
	
	return YES;
}

/****************************************************************************************************
	ebn_allProperties
	
	Returns the set of all properties that should be observed on by a "*" wildcard observation.
*/
- (NSSet *) ebn_allProperties
{
	return [NSSet setWithArray:[self allKeys]];
}

/****************************************************************************************************
	ebn_valueForKey:
	
*/
- (id) ebn_valueForKey:(NSString *)key
{		
	return [self valueForKey:key];
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
	EBAssert(entryInfo->_keyPath.count > 1 || [self isKindOfClass:[NSMutableDictionary class]],
			@"Observing an immutable dictionary for changes. This observation will never fire.");
		
	// The dictionary must be isa-swizzled even in the case where the value being observed isn't
	// currently in the dictionary, so we make sure that happens here.
	[self ebn_swizzleImplementationForSetter:nil];

	[super ebn_addEntry:entryInfo forProperty:propName];
}

@end


@implementation NSMutableDictionary (EBNObservable)

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
	
			// Override setObject:forKey: in the subclass
			Method setObjectForKeyMethod = class_getInstanceMethod([self class], @selector(setObject:forKey:));
			class_addMethod(classToModify, @selector(setObject:forKey:), (IMP) ebn_shadowed_setObjectForKey,
					method_getTypeEncoding(setObjectForKeyMethod));
			
			// Override removeObjectForKey: in the subclass
			Method removeObjectForKeyMethod = class_getInstanceMethod([self class], @selector(removeObjectForKey:));
			class_addMethod(classToModify, @selector(removeObjectForKey:), (IMP) ebn_shadowed_removeObjectForKey,
					method_getTypeEncoding(removeObjectForKeyMethod));

			// Override setObject:forKeyedSubscript: in the subclass
			Method setObjectForKeyedSubscriptMethod = class_getInstanceMethod([self class], 
					@selector(setObject:forKeyedSubscript:));
			class_addMethod(classToModify, @selector(setObject:forKeyedSubscript:), (IMP) ebn_shadowed_setObjectForKeyedSubscript,
					method_getTypeEncoding(setObjectForKeyedSubscriptMethod));

			// Override removeAllObjects in the subclass
			Method removeAllObjectsMethod = class_getInstanceMethod([self class], @selector(removeAllObjects));
			class_addMethod(classToModify, @selector(removeAllObjects), (IMP) ebn_shadowed_removeAllObjects,
					method_getTypeEncoding(removeAllObjectsMethod));
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


@end

/****************************************************************************************************
	ebn_shadowed_setObjectForKey
	

*/
static void ebn_shadowed_setObjectForKey(NSMutableDictionary *self, SEL _cmd, id newValue, id<NSCopying> aKey)
{
	// Get the previous value
	NSInteger prevCount = [self count];
	id previousValue = [self objectForKey:aKey];
	
	// Call the superclass to actually set the value
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, id, id<NSCopying>) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, newValue, aKey);
	
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
		}
	}
	
	// The count property may have changed; notify for it.
	NSInteger curCount = self.count;
	if (prevCount != curCount)
	{
		[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
				[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:curCount]];
	}
}

/****************************************************************************************************
	ebn_shadowed_removeObjectForKey
	
*/
static void ebn_shadowed_removeObjectForKey(NSMutableDictionary *self, SEL _cmd, id<NSCopying> aKey)
{
	// Get the previous value, and then set the new value
	NSInteger prevCount = self.count;
	id previousValue = [self objectForKey:aKey];

	// Call the superclass to actually set the value
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, id<NSCopying>) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, aKey);
	
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
		}
	}
	
	// The count property may have changed; notify for it.
	NSInteger curCount = self.count;
	if (prevCount != curCount)
	{
		[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
				[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:curCount]];
	}
}

/****************************************************************************************************
	ebn_shadowed_setObjectForKeyedSubscript
	
	Sometime around iOS 11, this became a new primitive method for NSMutableDictionary.
*/
static void ebn_shadowed_setObjectForKeyedSubscript(NSMutableDictionary *self, SEL _cmd, id newValue, id<NSCopying> aKey)
{
	// Get the previous value
	NSInteger prevCount = [self count];
	id previousValue = [self objectForKey:aKey];
	
	// Call the superclass to actually set the value
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, id, id<NSCopying>) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, newValue, aKey);
	
	// Keys that aren't strings aren't observable. Slightly unsafe as we have to assume
	// keyObject is an NSObject subclass.
	NSObject *keyObject = (NSObject *) aKey;
	if ([keyObject isKindOfClass:[NSString class]])
	{
		// If the new value is different than the old
		if (!((!previousValue && !newValue) || (newValue && [newValue isEqual:previousValue])))
		{
			NSString *aKeyString = (NSString *) aKey;
			[self ebn_manuallyTriggerObserversForProperty:aKeyString previousValue:previousValue newValue:newValue];
		}
	}
	
	// The count property may have changed; notify for it.
	NSInteger curCount = self.count;
	if (prevCount != curCount)
	{
		[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
				[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:curCount]];
	}
}

/****************************************************************************************************
	ebn_shadowed_removeAllObjects
	
	Sometime around iOS 11, this became a new primitive method for NSMutableDictionary.
*/
static void ebn_shadowed_removeAllObjects(NSMutableDictionary *self, SEL _cmd)
{
	// Get the previous value, and then set the new value
	NSInteger prevCount = self.count;
	NSDictionary *prevValue = [self copy];
	
	// Call the superclass to actually remove everything
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd);

	// Trigger observations on evey dictionary entry that is being removed
	for (id keyObject in prevValue)
	{
		// Keys that aren't strings aren't observable. Slightly unsafe as we have to assume keyObject is an NSObject subclass.
		if ([keyObject isKindOfClass:[NSString class]])
		{
			NSString *keyString = (NSString *) keyObject;
			id previousValueOfEntry = [prevValue objectForKey:keyString];
			[self ebn_manuallyTriggerObserversForProperty:keyString previousValue:previousValueOfEntry newValue:nil];
		}
	}
		
	// The count property may have changed; notify for it.
	NSInteger curCount = self.count;
	if (prevCount != curCount)
	{
		[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
				[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:curCount]];
	}
}

