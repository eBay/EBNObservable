/****************************************************************************************************
	EBNKeypathEntryInfo.mm
	Observable
	
	Created by Chall Fry on 3/14/17.
	Copyright (c) 2013-2018 eBay Software Foundation.
*/

#import "EBNObservableInternal.h"

#import <UIKit/UIGeometry.h>


/**
	EBNKeypathEntryInfo is pretty much just a data struct. Its purpose is to track a keypath
	through all the objects in the path. Each object in a keypath will have one of these structs.
	
	This object does implement isEqual and hash, as well as debugDescription.
*/
@implementation EBNKeypathEntryInfo

/****************************************************************************************************
	isEqual:
	
*/
- (BOOL) isEqual:(id) otherObject
{
	if (self == otherObject)
	{
		return YES;
	}

	if ([otherObject isKindOfClass:[EBNKeypathEntryInfo class]])
	{
		EBNKeypathEntryInfo *otherKeypathEntry = (EBNKeypathEntryInfo *) otherObject;
		
		// The blockInfo must be an identity match for the keypathInfos to be considered equal.
		if (_blockInfo == otherKeypathEntry->_blockInfo &&
				_keyPathIndex == otherKeypathEntry->_keyPathIndex &&
				[_keyPath isEqualToArray:otherKeypathEntry->_keyPath])
		{
			return YES;
		}
	}

	return NO;
}

/****************************************************************************************************
	hash
	
*/
- (NSUInteger) hash
{
	return ((NSUInteger) _blockInfo) ^ _keyPathIndex ^ [_keyPath hash];
}

/****************************************************************************************************
	copyWithZone:
	
*/
- (EBNKeypathEntryInfo *) copyWithZone:(NSZone *) zone
{
	EBNKeypathEntryInfo *result = [[EBNKeypathEntryInfo alloc] init];
	
	result->_blockInfo = _blockInfo;
	result->_keyPath = _keyPath;
	result->_keyPathIndex = _keyPathIndex;
	
	return result;
}

#pragma mark Keypath Management

/****************************************************************************************************
	ebn_removeObservation
	
	Tells the object at the root of the observation keypath to stop the observation, cleaning
	up observation keypath objects on all objects in the path.
	
	Works by telling the observed object (the object at the root of the keypath) to remove the keypath. 
	You can actually call this method with an entry taken from any point in the keypath's object chain.
*/
- (BOOL) ebn_removeObservation
{
	NSObject *strongObserved = _blockInfo->_weakObserved;
	if (strongObserved)
	{
		[self ebn_updateKeypathAtIndex:0 from:strongObserved to:nil];
		return YES;
	}

	return NO;
}

/****************************************************************************************************
	ebn_updateNextKeypathEntryFrom:to:

	Updates the keypath at the *next* index from the one in entryInfo.
	
	Returns YES if changing fromObj to toObj causes an endpoint of the keypath to change value.
*/
- (BOOL) ebn_updateNextKeypathEntryFrom:(id) fromObj to:(id) toObj
{
	if (_keyPathIndex == _keyPath.count - 1)
	{
		if (!fromObj && !toObj)
			return NO;
		if (!fromObj)
		{
			NSString *propName = _keyPath[_keyPathIndex];
			[toObj ebn_forcePropertyValid:propName];
			return YES;
		}
		if (!toObj || ![fromObj isEqual:toObj])
			return YES;
		
		return NO;
	}
	
	return [self ebn_updateKeypathAtIndex:_keyPathIndex + 1 from:fromObj to:toObj];
}

/****************************************************************************************************
	ebn_updateKeypath:atIndex:from:to:
	
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
	
	Returns TRUE if this update changed something being observed (the endpoint of a keypath) and 
	the observation block should be scheduled.
*/
- (BOOL) ebn_updateKeypathAtIndex:(NSInteger) index from:(id) fromObj to:(id) toObj
{
	BOOL result = NO;

	// Get the property name we'll be updating
	NSString *propName = _keyPath[index];
		
	EBNKeypathEntryInfo	*indexedInfo = [fromObj ebn_removeEntry:self atIndex:index forProperty:propName];
	if (!indexedInfo)
	{
		indexedInfo = [self copy];
		indexedInfo->_keyPathIndex = index;
	}
	[toObj ebn_addEntry:indexedInfo forProperty:propName];
	
	// Get the class of an object that is non-nil, and ask that class to do the value getting and comparison.
	Class objectClass = object_getClass(fromObj);
	if (!objectClass)
	{
		objectClass  = object_getClass(toObj);
	}
	result = [objectClass ebn_compareKeypathValues:self atIndex:index from:fromObj to:toObj];
	
	return result;
}

/****************************************************************************************************
	ebn_comparePropertyAtIndex:from:to:
    
 	Returns TRUE if this update changed something being observed (the endpoint of a keypath) and 
	the observation block should be scheduled.
	
	The receiver is the KeypathEntryInfo for the previous entry in the path--therefore it'll be index 0
	for the first item in the path.
	
	FromObj and toObj are the objects that *contain* the property named propName.
	
	Therefore, you can call this with the KeypathEntryInfo for index 0, but either fromObj or toObj should
	be nil, as you're creating or removing the base observation. You can't call this with the terminal property
	values e.g. for a keyPath of "stringProperty" you can't pass the string values of the property in.
   
*/
- (BOOL) ebn_comparePropertyAtIndex:(NSInteger) index from:(id) prevPropValue to:(id) newPropValue
{
	BOOL result = NO;
	
	// If both the previous and new values for this property are nil, we're done.
	if (!prevPropValue && !newPropValue)
	{
		result = NO;
	}
	else if (index == _keyPath.count - 1)
	{
		// If either endpoint value is nil this is an observable change, as we've already handled the both-nil case.
		if (prevPropValue == nil || newPropValue == nil || ![prevPropValue isEqual:newPropValue])
		{
			result = YES;
		}
	}
	else
	{
		// Check pointer equality. If they're equal, the rest of the keypath is already set up!
		if (prevPropValue != newPropValue)
		{
			result = [self ebn_updateKeypathAtIndex:index + 1 from:prevPropValue to:newPropValue];
		}
	}
	
	return result;
}

/****************************************************************************************************
	description
	
*/
- (NSString *) description
{
	NSString *returnStr = [NSString stringWithFormat:@"Path:\"%@\": %@", self->_keyPath,
			[self->_blockInfo debugDescription]];
	return returnStr;
}

@end

