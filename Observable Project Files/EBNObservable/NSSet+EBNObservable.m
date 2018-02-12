/****************************************************************************************************
	NSSet+EBNObservable.m
	Observable

 	Created by Chall Fry on 2/22/16.
	Copyright © 2013-2018 eBay Software Foundation.
*/

#import <objc/message.h>

#import "NSSet+EBNObservable.h"
#import "EBNObservableInternal.h"

static void ebn_shadowed_addObject(NSMutableSet *self, SEL _cmd, id newValue);
static void ebn_shadowed_removeObject(NSMutableSet *self, SEL _cmd, id obj);
static void ebn_shadowed_removeAllObjects(NSMutableSet *self, SEL _cmd);


@implementation NSSet (EBNObservable)

/****************************************************************************************************
	ebn_compareKeypathValues:atIndex:from:to:
    
    Compares the values of the given key in both fromObj and toObj. Handles wildcards.
*/
+ (BOOL) ebn_compareKeypathValues:(EBNKeypathEntryInfo *) info atIndex:(NSInteger) index from:(id) fromObj to:(id) toObj
{
	BOOL result = NO;
	
	NSSet *fromSet = (NSSet *) fromObj;
	NSSet *toSet = (NSSet *) toObj;
	
	NSString *propName = info->_keyPath[index];
	if ([propName isEqualToString:@"*"])
	{		
		// Remember that for sets, member: returns the object in the set that isEqual: to the given object.
		// This is important here because the member has/needs observations; a discrete object equal to it does not.
		NSSet *allMembers = fromSet;
		if (!allMembers)
			allMembers = toSet;
		else
			allMembers = [allMembers setByAddingObjectsFromSet:toSet];
			
		for (id setObject in allMembers)
		{
			id fromMember = [fromSet member:setObject];
			id toMember = [toSet member:setObject];
			result |= [info ebn_comparePropertyAtIndex:index from:fromMember to:toMember];
		}
	}
	else
	{
		id fromDictValue = [fromSet ebn_objectForKey:propName];
		id toDictValue = [toSet ebn_objectForKey:propName];
		result = [info ebn_comparePropertyAtIndex:index from:fromDictValue to:toDictValue];
	}

	return result;
}

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	Overrides the NSObject(EBNObservable) implementation.
	
	Like the superclass implementation, this method calls prepareObjectForObservation, which 
	isa-swizzles the object to ensure it's an Observable subclass of its original class.
	
	Why bother observing immutable objects? The objects in the set could have mutable properties;
	and you can create observation keypaths that go through the set, to an object in the set, and then to
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
	ebn_addEntry:forProperty:
	
	Really, this just checks for a degenerate case and calls super. Super does the real work.
*/
- (void) ebn_addEntry:(EBNKeypathEntryInfo *) entryInfo forProperty:(NSString *) propName
{
	// Assert on the easy-to-find case of a useless observation. If this is an immutable set
	// and the observation path is just 1 entry, the observation won't ever do anything.
	// "NSSet.NSSet" and similar paths won't get caught by this.
	EBAssert(entryInfo->_keyPath.count > 1 || [self isKindOfClass:[NSMutableSet class]],
			@"Observing an immutable set for changes. This observation will never fire.");

	// The dictionary must be isa-swizzled even in the case where the value being observed isn't
	// currently in the dictionary, so we make sure that happens here.
	[self ebn_swizzleImplementationForSetter:nil];

	[super ebn_addEntry:entryInfo forProperty:propName];
}

#pragma mark Keypaths

/****************************************************************************************************
	ebn_keyForObject:
	
	Returns a NSString key that can be used to identify an object in the receiver. The object doesn't 
	have to be in the set, but being in the set is sort of the point. 
	
	The key is based on the object's hash, which means there could possibly be hash collision issues--
	remember that a set can have multiple items with the same hash, as long as they don't pass the isEqual: 
	test. At worst, this should mean that an observer block is called spuriously, when the 'other' object 
	with the same hash is changed.
	
	The purpose of this method is that it allows the caller to put the returned string into a keypath
	referencing that object. Be aware that keypaths containing this construct are not compliant with
	Apple's KVC!
*/
+ (NSString *) ebn_keyForObject:(id) object
{
	NSUInteger hashValue = [object hash];
	NSString *hashString = [NSString stringWithFormat:@"&%lu", (unsigned long) hashValue];
	return hashString;
}

/****************************************************************************************************
	ebn_objectForKey:
	
	key must be a NSSet hash string, as returned by keyForObject. Generally, this is a string starting
	with '&' followed by a bunch of numbers.
	
	This method might return a different object than you think it should due to hash collisions!
	
	A special note on this: keyForObject could instead create a string based off of the object's address, 
	instead of the result of hash. But, you'd still run the risk of collisions, if the object you were 
	looking for was removed from the set and replaced with another object with the same pointer.
*/
- (id) ebn_objectForKey:(NSString *) key
{
	if (!key || ![key hasPrefix:@"&"] || [key length] < 2)
		return nil;
	
	NSUInteger keyHash = (NSUInteger) [[key substringFromIndex:1] longLongValue];
	for (id setObject in self)
	{
		if ([setObject hash] == keyHash)
			return setObject;
	}
	
	return nil;
}

/****************************************************************************************************
	ebn_valueForKey:
	
	NSSet's valueForKey: works by calling valueForKey: on every set member, and returns those results
	as a new set.
	
	This method does not work like that. Instead, it takes a key string produced by keyForObject: and
	returns an object in the set that matches it. Beware of possible hash collisions.
*/
- (id) ebn_valueForKey:(NSString *)key
{
	// If key refers to an actual property, call super to get the property value
	if (class_getProperty(object_getClass(self), [key UTF8String]))
	{
		return [super ebn_valueForKey:key];
	}

	// Else, assume key is a string hash of a object.
	return [self ebn_objectForKey:key];
}

@end


@implementation NSMutableSet (EBNObservable)

/****************************************************************************************************
	ebn_swizzleImplementationForSetter:
	
	Overrides the NSObject(EBNObservable) implementation.
	
	Like the superclass implementation, this method calls prepareObjectForObservation, which 
	isa-swizzles the object to ensure it's an Observable subclass of its original class.
	
	For sets we're most interested in observing set membership, not properties. So, this method
	swizzles the core mutating methods of NSMutableSet so we can watch for changes made to the
	set. If it's actually a property that's going to be observed, we call through to the superclass,
	which is set up to handle that.
	
	This means that any non-property is assumed to be a possible set member, even if getter and setter methods
	with the correct names exist (likely in a category). Be sure to use @property if you want to observe 
	actual properties.
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

		if (!info->_collectionSwizzlesDone)
		{
			info->_collectionSwizzlesDone = true;
			Class classToModify = info->_shadowClass;
	
			// Override addObject: in the subclass
			Method addObjectMethod = class_getInstanceMethod([self class], @selector(addObject:));
			class_addMethod(classToModify, @selector(addObject:), (IMP) ebn_shadowed_addObject,
					method_getTypeEncoding(addObjectMethod));
			
			// Override removeObject: in the subclass
			Method removeObjectMethod = class_getInstanceMethod([self class], @selector(removeObject:));
			class_addMethod(classToModify, @selector(removeObject:), (IMP) ebn_shadowed_removeObject,
					method_getTypeEncoding(removeObjectMethod));

			// You know how the docs on NSMutableSet say you need to override the 2 primitive methods,
			// addObject: and removeObject:? Empirical testing says you need this too, as it isn't
			// apparently written in terms of removeObject:.
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
	ebn_shadowed_addObject
	

*/
static void ebn_shadowed_addObject(NSMutableSet *self, SEL _cmd, id newValue)
{
	// Get the previous value
	NSUInteger prevCount = self.count;
	id previousValue = [self member:newValue];
	
	// Call the superclass to actually set the value
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, id) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, newValue);

	// If this property was unset before, report as a change to the 'any' property and to the hash
	// This is based on tests showing that adding an object that isEqual: to one already in the set
	// does not cause a replace.
	if (previousValue == nil)
	{
		NSString *keyForNewValue = [[self class] ebn_keyForObject:newValue];
		[self ebn_manuallyTriggerObserversForProperty:keyForNewValue previousValue:previousValue
				newValue:newValue];

		// Also notify for "*" and count
		[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
				[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:self.count]];
	}
}

/****************************************************************************************************
	ebn_shadowed_removeObject
	
*/
static void ebn_shadowed_removeObject(NSMutableSet *self, SEL _cmd, id obj)
{
	// Get the previous value
	NSUInteger prevCount = self.count;
	id previousValue = [self member:obj];

	// Call the superclass to actually remove the object
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL, id) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd, obj);
	
	if (previousValue)
	{
		NSString *keyForPrevValue = [[self class] ebn_keyForObject:previousValue];
		[self ebn_manuallyTriggerObserversForProperty:keyForPrevValue previousValue:previousValue
				newValue:nil];
		
		// Also notify for "*" and count
		[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
				[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:self.count]];
	}
}

/****************************************************************************************************
	ebn_shadowed_removeAllObjects
	
	It appears this method is treated as a primitive, so here we handle it as such.
*/
static void ebn_shadowed_removeAllObjects(NSMutableSet *self, SEL _cmd)
{
	// Get the previous count and set contents
	NSUInteger prevCount = self.count;
	NSSet *prevContents = [self copy];

	// Call the superclass to actually remove eveything
	struct objc_super superStruct = { self, class_getSuperclass(object_getClass(self)) };
	void (* const objc_msgSendSuper_typed)(struct objc_super *, SEL) = (void *)&objc_msgSendSuper;
	objc_msgSendSuper_typed(&superStruct, _cmd);
	
	if (prevCount)
	{
		for (id obj in prevContents)
		{
			NSString *keyForPrevValue = [[self class] ebn_keyForObject:obj];
			[self ebn_manuallyTriggerObserversForProperty:keyForPrevValue previousValue:obj newValue:nil];
		}
		
		// Also notify for "*" and count
		[self ebn_manuallyTriggerObserversForProperty:@"count" previousValue:
				[NSNumber numberWithInteger:prevCount] newValue:[NSNumber numberWithInteger:self.count]];
	}
}

