/****************************************************************************************************
	EBNLazyLoader.mm
	Observable
	
	Created by Chall Fry on 4/29/14.
    Copyright (c) 2013-2014 eBay Software Foundation.
	
	EBNLazyLoader is a super class for model objects (that is, objects in your app's Model layer),
	that has methods making it easy to create synthetic properties that compute their value
	lazily.
	
	EBNLazyLoader is a subclass of EBNObservable.
*/

#import <CoreGraphics/CoreGraphics.h>
#include <map>

#import "DebugUtils.h"
#import "EBNLazyLoader.h"
#import "EBNObservableInternal.h"

template<typename T> void overrideGetterMethod(NSString *propName, Method getter, Ivar getterIvar);

// Statics
static std::map<Method, Class> EBNSwizzledGetterMethodTable;


// Declares EBNLazyLoader to conform to the EBNPropertyValidityProtocol, privately
@interface EBNLazyLoader () <EBNPropertyValidityProtocol>
@end

@implementation EBNLazyLoader
{
@public
	NSMutableSet 	*currentlyValidProperties;
}

#pragma mark Public API

/****************************************************************************************************
	syntheticProperty:
	
	Declares a synthetic property, with no dependents. This property will lazily compute its value;
	you must use the invalidate methods to clear it.
*/
- (void) syntheticProperty:(NSString *) property
{
	[self syntheticProperty:property dependsOn:nil];
}

/****************************************************************************************************
	syntheticProperty:dependsOn:
	
	Declares a synthetic property which computes is value from the value of self.keypath.
	May be called multiple times for the same property, to set up multiple dependent keypaths.
	
	Changing the value of the dependent property will cause the synthetic property's value to be
	invalidated; it will be recomputed next time it's accessed.
*/
- (void) syntheticProperty:(NSString *) property dependsOn:(NSString *) keyPath
{
	[self wrapPropertyMethods:property];

	if (keyPath)
	{
		// Set up our observation
		EBNObservation *blockInfo = NewObservationBlockImmed(self,
		{
			[blockSelf manuallyTriggerObserversForProperty:property previousValue:prevValue];
		});
		[blockInfo setDebugString:[NSString stringWithFormat:
				@"%p: Synthetic property \"%@\" of <%@: %p>",
				blockInfo, property, [self class], self]];
		[blockInfo observe:keyPath];
	}
}

/****************************************************************************************************
	syntheticProperty:dependsOnPaths:
	
	Declares property to be a lazy-loading synthetic property whose value is dependent on all the
	paths in keyPaths.
*/
- (void) syntheticProperty:(NSString *) property dependsOnPaths:(NSArray *) keyPaths
{
	[self wrapPropertyMethods:property];

	// Set up our observation
	EBNObservation *blockInfo = NewObservationBlockImmed(self,
	{
		[blockSelf manuallyTriggerObserversForProperty:property previousValue:prevValue];
	});
	[blockInfo setDebugString:[NSString stringWithFormat:
			@"%p: Synthetic property \"%@\" of <%@: %p>",
			blockInfo, property, [self class], self]];
	[blockInfo observeMultiple:keyPaths];
}

/****************************************************************************************************
	syntheticProperty_MACRO_USE_ONLY:dependsOnKeyPathStrings
	
	A special version of the synteticPropery method, specifically for use by the SyntheticProperty macro.
	Probably best not to use this method and use the 'dependsOnPaths:' variant instead.
*/
- (void) syntheticProperty_MACRO_USE_ONLY:(NSString *) propertyAndPaths
{
	// Parse the propertyAndPaths string, which is a stringification of the macro arguments
	NSMutableArray *keyPathArray = [[NSMutableArray alloc] init];
	NSArray *keyPathStringArray = [propertyAndPaths componentsSeparatedByString:@","];
	for (NSString *keyPath in keyPathStringArray)
	{
		NSString *trimmedKeyPath = [keyPath stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		[keyPathArray addObject:trimmedKeyPath];
	}
	
	// The first item in the array is now the property being declared as synthetic
	EBAssert([keyPathArray count], @"The SyntheticProperty() macro needs to be called with at least the"
			@" property you're declaring as synthetic.");
	NSString *property = [keyPathArray objectAtIndex:0];
	[self wrapPropertyMethods:property];
	[keyPathArray removeObjectAtIndex:0];
	
	if ([keyPathArray count])
	{
		// Set up our observation
		EBNObservation *blockInfo = NewObservationBlockImmed(self,
		{
			[blockSelf manuallyTriggerObserversForProperty:property previousValue:prevValue];
		});
		
		[blockInfo setDebugString:[NSString stringWithFormat:
				@"%p: Synthetic property \"%@\" of <%@: %p>",
				blockInfo, property, [self class], self]];
		[blockInfo observeMultiple:keyPathArray];
	}
}

/****************************************************************************************************
	invalidatePropertyValue:
	
	Marks the given property as invalid; this flags it so that it will be recomputed the next time
	its getter is called. If the property is being observed, it's possible for the getter to be called
	immediately.
*/
- (void) invalidatePropertyValue:(NSString *) property
{
	// Get the current cached value for the property. If the property was invalid, temporarily mark
	// it valid. This makes the get wrapper return the value from the ivar.
	@synchronized(self)
	{
		[currentlyValidProperties addObject:property];
	}
	id prevValue = [self valueForKeyPath:property];

	// Mark this property invalid, and trigger anyone observing it, telling them that the property
	// value has changed (to something not yet known).
	[self manuallyTriggerObserversForProperty:property previousValue:prevValue];
}

/****************************************************************************************************
	invalidateAllSyntheticProperties
	
	Marks all synthetic properties of the current object invalid. They will all be recomputed the next
	time they are accessed.
*/
- (void) invalidateAllSyntheticProperties
{
	NSArray *validPropertyArray = nil;
	
	@synchronized(self)
	{
		validPropertyArray =  [self->currentlyValidProperties allObjects];
	}
	
	for (NSString *curProperty in validPropertyArray)
	{
		[self invalidatePropertyValue:curProperty];
	}
}

/****************************************************************************************************
	manuallyTriggerObserversForProperty:previousValue:
	
	Marks the property as invalid, and calls all of its observers.
	
	Note that you can't use this to set the ivar for a property directly and then get 
	observers to be nofitied. Since synthetic properties compute their value from other properties
	in a defined way, calling this will just mark the property as invalid and then it gets 
	recomputed lazily.
*/
- (void) manuallyTriggerObserversForProperty:(NSString *) propertyName previousValue:(id) prevValue
{
	// I'd considered checking to see if the property was already invalid and not triggering observers
	// in that case, but I don't think that works. If a new observer registered between the first
	// and second invalidations it wouldn't get called.
	@synchronized(self)
	{
		[currentlyValidProperties removeObject:propertyName];
	}
	[super manuallyTriggerObserversForProperty:propertyName previousValue:prevValue];
}

#pragma mark Private Methods

/****************************************************************************************************
	wrapPropertyMethods
	
	Swaps out the getter and setter for the given property.
*/
- (bool) wrapPropertyMethods:(NSString *) propName
{
	bool propertyIsLazyLoadable = [[self class] swizzleImplementationForGetter:propName];
	
	// If lazy loading is going to work, make sure to try wrapping the setter as well, so that
	// it can mark the property valid when it gets set manually
	if (propertyIsLazyLoadable)
	{
		[[self class] swizzleImplementationForSetter:propName];

		// Lazily create our set of currently valid properties. At the start, none of the lazily loaded
		// properties are going to be valid.
		if (!self->currentlyValidProperties)
		{
			self->currentlyValidProperties = [[NSMutableSet alloc] init];
		}
	}
	
	return propertyIsLazyLoadable;
}

/****************************************************************************************************
	markPropertyValid:
	
	Internal method to mark a property as being cached in its ivar, so that future accesses to 
	it will return the cached value.
*/
- (void) markPropertyValid:(NSString *) property
{
	// This just sanity checks that the property string is actually 1) a property, and 2) set up
	// to be lazily loaded. As it happens, everything works fine without this check, even if you
	// do call it with non-properties. Not that you should do that.
	{
		// Get the method selector for the getter on this property
		SEL getterSelector = [[self class] selectorForPropertyGetter:property];
		if (!getterSelector)
			return;
		
		// Then get the method we'd call for that selector
		Method getterMethod = class_getInstanceMethod([self class], getterSelector);
		if (!getterMethod)
			return;
		
		@synchronized([EBNLazyLoader class])
		{
			if (EBNSwizzledGetterMethodTable.count(getterMethod) == 0)
			{
				return;
			}
		}
	}

	// Mark it valid
	@synchronized(self)
	{
		[self->currentlyValidProperties addObject:property];
	}
}

/****************************************************************************************************
	swizzleImplementationForGetter:
	
	Swizzles the implemention of the getter method of the given property. The swizzled implementation
	checks to see if the ivar backing the property is valid (== if lazy loading has happened) and if so
	returns the ivar. 

	The bulk of this method is a switch statement that switches on the type of the property (parsed
	from the string returned by method_getArgumentType()) and calls a templatized C++ function
	called overrideGetterMethod<>() to create a new method and swizzle it in.
*/
+ (bool) swizzleImplementationForGetter:(NSString *) propertyName
{
	// Get the method selector for the getter on this property
	SEL getterSelector = [self selectorForPropertyGetter:propertyName];
	EBAssert(getterSelector, @"Couldn't find getter method for property %@ in object %@", propertyName, self);
	if (!getterSelector)
		return false;
	
	// Then get the method we'd call for that selector
	Method getterMethod = class_getInstanceMethod([self class], getterSelector);
	if (!getterMethod)
		return false;
	
	// If this method is already in the table, it's swizzled already (or we tried and failed), so just return true.
	// Otherwise, add the method to the table here.
	// NOTE to whoever changes this from @synchronized to something faster--move out the return statement!!!
	@synchronized([EBNLazyLoader class])
	{
		if (EBNSwizzledGetterMethodTable.count(getterMethod) == 0)
		{
			EBNSwizzledGetterMethodTable[getterMethod] = self;
		}
		else
		{
			return true;
		}
	}

	// Get the instance variable that backs the property
	Ivar getterIvar = nil;
	objc_property_t prop = class_getProperty(self, [propertyName UTF8String]);
	if (prop)
	{
		NSString *propStr = [NSString stringWithUTF8String:property_getAttributes(prop)];
		NSRange getterIvarRange = [propStr rangeOfString:@",V"];
		if (getterIvarRange.location != NSNotFound)
		{
			NSString *ivarString = [propStr substringFromIndex:getterIvarRange.location + getterIvarRange.length];
			getterIvar = class_getInstanceVariable(self, [ivarString UTF8String]);
		}
	}
	EBAssert(getterIvar, @"No instance variable found to back property %@.", propertyName);
	if (!getterIvar)
		return false;
		
	char typeOfGetter[32];
	method_getReturnType(getterMethod, typeOfGetter, 32);

	// Types defined in runtime.h
	switch (typeOfGetter[0])
	{
	case _C_CHR:
		overrideGetterMethod<char>(propertyName, getterMethod, getterIvar);
	break;
	case _C_UCHR:
		overrideGetterMethod<unsigned char>(propertyName, getterMethod, getterIvar);
	break;
	case _C_SHT:
		overrideGetterMethod<short>(propertyName, getterMethod, getterIvar);
	break;
	case _C_USHT:
		overrideGetterMethod<unsigned short>(propertyName, getterMethod, getterIvar);
	break;
	case _C_INT:
		overrideGetterMethod<int>(propertyName, getterMethod, getterIvar);
	break;
	case _C_UINT:
		overrideGetterMethod<unsigned int>(propertyName, getterMethod, getterIvar);
	break;
	case _C_LNG:
		overrideGetterMethod<long>(propertyName, getterMethod, getterIvar);
	break;
	case _C_ULNG:
		overrideGetterMethod<unsigned long>(propertyName, getterMethod, getterIvar);
	break;
	case _C_LNG_LNG:
		overrideGetterMethod<long long>(propertyName, getterMethod, getterIvar);
	break;
	case _C_ULNG_LNG:
		overrideGetterMethod<unsigned long long>(propertyName, getterMethod, getterIvar);
	break;
	case _C_FLT:
		overrideGetterMethod<float>(propertyName, getterMethod, getterIvar);
	break;
	case _C_DBL:
		overrideGetterMethod<double>(propertyName, getterMethod, getterIvar);
	break;
	case _C_BFLD:
		// Pretty sure this can't happen, as bitfields can't be top-level and are only found inside structs/unions
		EBAssert(false, @"Observable does not have a way to override the setter for %@.", propertyName);
	break;
	case _C_BOOL:
		overrideGetterMethod<bool>(propertyName, getterMethod, getterIvar);
	break;
	case _C_PTR:
	case _C_CHARPTR:
	case _C_ATOM:		// Apparently never generated? Only docs I can find say treat same as charptr
	case _C_ARY_B:
		overrideGetterMethod<void *>(propertyName, getterMethod, getterIvar);
	break;
	
	case _C_ID:
		overrideGetterMethod<id>(propertyName, getterMethod, getterIvar);
	break;
	case _C_CLASS:
		overrideGetterMethod<Class>(propertyName, getterMethod, getterIvar);
	break;
	case _C_SEL:
		overrideGetterMethod<SEL>(propertyName, getterMethod, getterIvar);
	break;

	case _C_STRUCT_B:
		if (!strncmp(typeOfGetter, @encode(NSRange), 32))
			overrideGetterMethod<NSRange>(propertyName, getterMethod, getterIvar);
		else if (!strncmp(typeOfGetter, @encode(CGPoint), 32))
			overrideGetterMethod<CGPoint>(propertyName, getterMethod, getterIvar);
		else if (!strncmp(typeOfGetter, @encode(CGRect), 32))
			overrideGetterMethod<CGRect>(propertyName, getterMethod, getterIvar);
		else if (!strncmp(typeOfGetter, @encode(CGSize), 32))
			overrideGetterMethod<CGSize>(propertyName, getterMethod, getterIvar);
		else
			EBAssert(false, @"Observable does not have a way to override the setter for %@.", propertyName);
	break;
	
	case _C_UNION_B:
		// If you hit this assert, look at what we do above for structs, make something like that for
		// unions, and add your type to the if statement
		EBAssert(false, @"Observable does not have a way to override the setter for %@.", propertyName);
	break;
	
	default:
		EBAssert(false, @"Observable does not have a way to override the setter for %@.", propertyName);
	break;
	}
	
	return true;
}

#pragma mark Debug Methods

/****************************************************************************************************
	debug_validProperties
	
	This method is for debugging. If you're trying to use this method to implement some sort of
	validity introspection that invalidates/forces caching in some weird way you are probably 
	doing it wrong.
	
	Returns the set of synthetic properties whose values are currently being cached in their ivars.

	To use, type in the debugger:
		po [<object> debug_validProperties]
*/
- (NSSet *) debug_validProperties
{
	return currentlyValidProperties;
}

/****************************************************************************************************
	debug_invalidProperties
	
	This method is for debugging. If you're trying to use this method to implement some sort of
	validity introspection that invalidates/forces caching in some weird way you are probably 
	doing it wrong.
	
	Returns the set of synthetic properties whose values are currently wrong.

	To use, type in the debugger:
		po [<object> debug_invalidProperties]
*/
- (NSSet *) debug_invalidProperties
{
	NSMutableSet *invalidPropertySet = [[NSMutableSet alloc] init];
	
	Class curClass = [self class];
	while (curClass != [EBNLazyLoader class])
	{
		// Get a list of all the properties of this class (does not include superclasses)
		unsigned int propCount;
		objc_property_t *properties = class_copyPropertyList(curClass, &propCount);
		if (properties)
		{
			// For each property, check if it's being lazyloaded, and if so add its name to our set.
			for (int propIndex = 0; propIndex < propCount; ++propIndex)
			{
				NSString *propName = @(property_getName(properties[propIndex]));
				SEL getterSelector = [[self class] selectorForPropertyGetter:propName];
				Method getterMethod = class_getInstanceMethod([self class], getterSelector);

				if (EBNSwizzledGetterMethodTable.count(getterMethod) > 0)
				{
					[invalidPropertySet addObject:propName];
				}
			}
			
			free(properties);
		}
		
		curClass = [curClass superclass];
	}
	
	// Now subtract out all the properties that are currently valid. What's left is the invalid properties.
	[invalidPropertySet minusSet:currentlyValidProperties];
	
	return invalidPropertySet;
}

/****************************************************************************************************
	debugForceAllPropertiesValid
	
	This method is for debugging. If you're trying to use this method to implement some sort of
	validity introspection that invalidates/forces caching in some weird way you are probably 
	doing it wrong.
	
	Calls the getter for each property whose value isn't currently valid, which makes the value valid.

	To use, type in the debugger:
		po [<object> debug_forceAllPropertiesValid]
*/
- (void) debug_ForceAllPropertiesValid
{
	NSSet *invalidProps = [self debug_invalidProperties];
	for (NSString *propName in invalidProps)
	{
		EBLogContext(kLoggingContextOther, @"    Value for \"%@\" is now %@", propName,
				[self valueForKeyPath:propName]);
	}
	EBLogContext(kLoggingContextOther, @"All properties should be valid now. You may need to step once in the debugger.");
}

#pragma mark -
#pragma mark Template Get Override Functions

/****************************************************************************************************
	template <T> overrideGetterMethod()
	
	Overrides the given getter method with a new method (actually a block with implementationWithBlock()
	used on it) that checks whether the property value cached in the ivar backing the property is
	valid, and if so returns that. 
	
	If it isn't valid, we call the original getter method to compute the proper value, and cache that
	value in the ivar.
	
	This is the general case for the template; note the template specializations below.
*/
template<typename T> void overrideGetterMethod(NSString *propName, Method getter, Ivar getterIvar)
{
	// All of these local variables get copied into the setAndObserve block
	T (*originalGetter)(id, SEL) = (T (*)(id, SEL)) method_getImplementation(getter);
	SEL getterSEL = method_getName(getter);
	ptrdiff_t ivarOffset = ivar_getOffset(getterIvar);
	
	// This is what gets run when the getter method gets called.
	T (^getLazily)(EBNLazyLoader *_s) = ^ T (EBNLazyLoader *_s)
	{
		@synchronized(_s)
		{
			// NOTE: Read this fn's comments. This doesn't get called for object properties.
			// And yes--we need all 3 casts.
			T *ivarPtr = (T *) (((char *) ((__bridge void *) _s)) + ivarOffset);
			if ([_s->currentlyValidProperties containsObject:propName])
			{
				return *ivarPtr;
			}
			else
			{
				T value = (originalGetter)(_s, getterSEL);
				*ivarPtr = value;
				[_s->currentlyValidProperties addObject:propName];
				return value;
			}
		}
	};

	// Now replace the getter's implementation with the new one
	IMP swizzledImplementation = imp_implementationWithBlock(getLazily);
	method_setImplementation(getter, swizzledImplementation);
}

/****************************************************************************************************
	template<> overrideGetterMethod()<id>
	
	This is a template specialization for 'id' objects.

	Overrides the given getter method with a new method (actually a block with implementationWithBlock()
	used on it) that checks whether the property value cached in the ivar backing the property is
	valid, and if so returns that. 
	
	If it isn't valid, we call the original getter method to compute the proper value, and cache that
	value in the ivar.
*/
template<> void overrideGetterMethod<id>(NSString *propName, Method getter, Ivar getterIvar)
{
	// All of these local variables get copied into the setAndObserve block
	id (*originalGetter)(id, SEL) = (id (*)(id, SEL)) method_getImplementation(getter);
	SEL getterSEL = method_getName(getter);
	
	// This is what gets run when the getter method gets called.
	id (^getLazily)(EBNLazyLoader *_s) = ^ id (EBNLazyLoader *_s)
	{
		@synchronized(_s)
		{
			if ([_s->currentlyValidProperties containsObject:propName])
			{
				return object_getIvar(_s, getterIvar);
			}
			else
			{
				id value = (originalGetter)(_s, getterSEL);
				object_setIvar(_s, getterIvar, value);
				[_s->currentlyValidProperties addObject:propName];
				return value;
			}
		}
	};

	// Now replace the getter's implementation with the new one
	IMP swizzledImplementation = imp_implementationWithBlock(getLazily);
	method_setImplementation(getter, swizzledImplementation);
}

/****************************************************************************************************
	template<> overrideGetterMethod()<class>
	
	This is a template specialization for 'Class' objects.

	Overrides the given getter method with a new method (actually a block with implementationWithBlock()
	used on it) that checks whether the property value cached in the ivar backing the property is
	valid, and if so returns that. 
	
	If it isn't valid, we call the original getter method to compute the proper value, and cache that
	value in the ivar.
*/
template<> void overrideGetterMethod<Class>(NSString *propName, Method getter, Ivar getterIvar)
{
	// All of these local variables get copied into the setAndObserve block
	Class (*originalGetter)(id, SEL) = (Class (*)(id, SEL)) method_getImplementation(getter);
	SEL getterSEL = method_getName(getter);
	
	// This is what gets run when the getter method gets called.
	Class (^getLazily)(EBNLazyLoader *_s) = ^ Class (EBNLazyLoader *_s)
	{
		@synchronized(_s)
		{
			if ([_s->currentlyValidProperties containsObject:propName])
			{
				return object_getIvar(_s, getterIvar);
			}
			else
			{
				id value = (originalGetter)(_s, getterSEL);
				object_setIvar(_s, getterIvar, value);
				[_s->currentlyValidProperties addObject:propName];
				return value;
			}
		}
	};

	// Now replace the getter's implementation with the new one
	IMP swizzledImplementation = imp_implementationWithBlock(getLazily);
	method_setImplementation(getter, swizzledImplementation);
}




@end
