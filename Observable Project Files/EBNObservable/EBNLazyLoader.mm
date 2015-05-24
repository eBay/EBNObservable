/****************************************************************************************************
	EBNLazyLoader.mm
	Observable
	
	Created by Chall Fry on 4/29/14.
    Copyright (c) 2013-2014 eBay Software Foundation.
	
	EBNLazyLoader is a category on NSObject that provides the ability for creating synthetic properties.

	Synthetic properties use lazy evaluation--they only compute their value when requested.
	They also use caching--once they compute their value, that value is cached.
	A synthetic property has a concept of whether it is in a valid or invalid state, separate from whether
			its value is 0 or NULL.
	There are methods to invalidate a synthetic properties' value--meaning it will be recomputed next time requested.
	Synthetic properties can optionally declare themselves dependent on the values of other properties;
			meaning they are automatically invalidated when the property they take a value from changes.
	Synthetic properties interoperate correctly with observations.
	Synthetic properties can chain off of other synthetic properties.
*/

#import <CoreGraphics/CGGeometry.h>
#import <objc/message.h>

#import "DebugUtils.h"
#import "EBNLazyLoader.h"
#import "EBNObservableInternal.h"

template<typename T> void overrideGetterMethod(NSString *propName, Method getter,
		Ivar getterIvar, Class classToModify);

@implementation NSObject (EBNLazyLoader)

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
	syntheticProperty:withLazyLoaderMethod:
	
	Declares a synthetic property, with no dependents. This property will lazily compute its value;
	you must use the invalidate methods to clear it.
*/
- (void) syntheticProperty:(NSString *)property withLazyLoaderMethod:(SEL) loader
{
	[self ebn_wrapPropertyMethods:property customLoader:loader];
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
	[self ebn_wrapPropertyMethods:property customLoader:nil];

	if (keyPath)
	{
		// Set up our observation
		EBNObservation *blockInfo = NewObservationBlockImmed(self,
		{
			[blockSelf invalidatePropertyValue:property];
		});
		[blockInfo setDebugString:[NSString stringWithFormat:
				@"%p: Synthetic property \"%@\" of <%@: %p>",
				blockInfo, property, [self class], self]];
		blockInfo.isForLazyLoader = YES;
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
	[self ebn_wrapPropertyMethods:property customLoader:nil];

	// Set up our observation
	EBNObservation *blockInfo = NewObservationBlockImmed(self,
	{
		[blockSelf invalidatePropertyValue:property];
	});
	[blockInfo setDebugString:[NSString stringWithFormat:
			@"%p: Synthetic property \"%@\" of <%@: %p>",
			blockInfo, property, [self class], self]];
	blockInfo.isForLazyLoader = YES;
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
	[self ebn_wrapPropertyMethods:property customLoader:nil];
	[keyPathArray removeObjectAtIndex:0];
	
	if ([keyPathArray count])
	{
		// Set up our observation
		EBNObservation *blockInfo = [[EBNObservation alloc] initForObserved:self observer:self
				immedBlock:^(NSObject *blockSelf, NSObject *observer, id prevValue)
				{
					[blockSelf invalidatePropertyValue:property];
				}];

#if defined(DEBUG) && DEBUG
		[blockInfo setDebugString:[NSString stringWithFormat:
				@"%p: Synthetic property \"%@\" of <%@: %p>",
				blockInfo, property, [self class], self]];
#endif
		blockInfo.isForLazyLoader = YES;
		[blockInfo observeMultiple:keyPathArray];
	}
}

/****************************************************************************************************
	invalidatePropertyValue:
	
	Marks the given property as invalid; this flags it so that it will be recomputed the next time
	its getter is called. If the property is being observed, it's possible for the getter to be called
	immediately.
	
	This method does NOT check to see if the property parameter is actually a property of the object,
	and will throw an exception if it isn't. Use invalidatePropertyValues: which does do this check.
*/
- (void) invalidatePropertyValue:(NSString *) property
{
	BOOL wasValid = NO;
	
	// First check whether the property is in the valid list
	@synchronized(EBNObservableSynchronizationToken)
	{
		NSMutableSet *validProperties = self.ebn_currentlyValidProperties;
		if ([validProperties containsObject:property])
		{
			wasValid = YES;
		}
	}
	
	// A bit of inductive logic here: If the property wasn't previously valid, it wasn't being
	// observed, as observed properties have to be forced valid. This is all being done because
	// asking for prevValue won't recompute if wasValid is true.
	if (wasValid)
	{
		// This should get the cached (valid) value
		id prevValue = [self ebn_valueForKey:property];
		@synchronized(EBNObservableSynchronizationToken)
		{
			// Now we remove the property from the valid list
			NSMutableSet *validProperties = self.ebn_currentlyValidProperties;
			[validProperties removeObject:property];
		}
	
		// And call manually trigger to tell observers about the change.
		[self ebn_manuallyTriggerObserversForProperty:property previousValue:prevValue];
	}
}

/****************************************************************************************************
	invalidatePropertyValues:
	
	Marks the given properties as invalid; this flags them so that they will be recomputed the next time
	its getter is called. If the property is being observed, it's possible for the getter to be called
	immediately.
	
	This method checks the set property values against the set of lazy properties, and only tries to 
	invalidate properties that are actually lazily loaded.
*/
- (void) invalidatePropertyValues:(NSSet *) properties
{
	NSMutableSet *lazyProperties = [[NSMutableSet alloc] init];
	
	// Get the set of lazy getters from our subclass. If it doesn't exist or is empty we intersect against
	// the null set and don't invalidate anything, which is what we want if we don't actually have lazy properties.
	@synchronized (EBNBaseClassToShadowInfoTable)
	{
		EBNShadowedClassInfo *info = nil;
		
		if (class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
		{
			info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
		}
		if (!info)
		{
			info = EBNBaseClassToShadowInfoTable[[self class]];
		}
		
		// Get all the registered lazy properties, and intersect that with the set of newly-invalid properties.
		if (info && info->_getters)
			[lazyProperties setSet:info->_getters];
		[lazyProperties intersectSet:properties];
	}
	
	for (NSString *curProperty in lazyProperties)
	{
		[self invalidatePropertyValue:curProperty];
	}
}

/****************************************************************************************************
	invalidateAllSyntheticProperties
	
	Marks all synthetic properties of the current object invalid. They will all be recomputed the next
	time they are accessed.
*/
- (void) invalidateAllSyntheticProperties
{
	NSArray *validPropertyArray = nil;
	
	@synchronized(EBNObservableSynchronizationToken)
	{
		validPropertyArray =  self.ebn_currentlyValidProperties.allObjects;
	}
	
	for (NSString *curProperty in validPropertyArray)
	{
		[self invalidatePropertyValue:curProperty];
	}
}

#pragma mark Private Methods

/****************************************************************************************************
	ebn_currentlyValidProperties

	This gets the observed methods dict out of an associated object, creating it if necessary.
	Note the EBNObservable has its own implementation of this method, which gets the dict out of an ivar.
	
	The caller of this method must be inside a @synchronized(EBNObservableSynchronizationToken), and must
	remain inside that sync while using the dictionary.
*/
- (NSMutableSet *) ebn_currentlyValidProperties
{
	NSMutableSet *currentlyValidProperties =
			objc_getAssociatedObject(self, @selector(ebn_currentlyValidProperties));
	if (!currentlyValidProperties)
	{
		currentlyValidProperties = [[NSMutableSet alloc] init];
		objc_setAssociatedObject(self, @selector(ebn_currentlyValidProperties), currentlyValidProperties,
				OBJC_ASSOCIATION_RETAIN);
	}
	
	return currentlyValidProperties;
}

/****************************************************************************************************
	ebn_wrapPropertyMethods
	
	Swaps out the getter and setter for the given property.
*/
- (BOOL) ebn_wrapPropertyMethods:(NSString *) propName customLoader:(SEL) loader
{
	// The getter must be found and swizzled
	if (![self ebn_swizzleImplementationForGetter:propName customLoader:loader])
		return NO;

	// Readonly properties don't have a setter; this will fail in that case and that's okay
	[self ebn_swizzleImplementationForSetter:propName];
	
	return YES;
}

/****************************************************************************************************
	ebn_markPropertyValid:
	
	Internal method to mark a property as being cached in its ivar, so that future accesses to 
	it will return the cached value.
*/
- (void) ebn_markPropertyValid:(NSString *) property
{
	// This just sanity checks that the property string is actually 1) a property, and 2) set up
	// to be lazily loaded. As it happens, everything works fine without this check, even if you
	// do call it with non-properties. Not that you should do that.
	@synchronized(EBNBaseClassToShadowInfoTable)
	{
		EBNShadowedClassInfo *info = nil;
		
		if (class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
		{
			info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
		}
		if (!info)
		{
			info = EBNBaseClassToShadowInfoTable[[self class]];
		}
		
		if (!info || ![info->_getters containsObject:property])
		{
			return;
		}
	}

	// Mark it valid
	@synchronized(EBNObservableSynchronizationToken)
	{
		[self.ebn_currentlyValidProperties addObject:property];
	}
}

/****************************************************************************************************
	ebn_forcePropertyValid:
	
 	Forces the given property into its valid state. The method does this by calling the getter on the
	property.

*/
- (void) ebn_forcePropertyValid:(NSString *) property
{
	// Are we valid already?
	@synchronized(EBNObservableSynchronizationToken)
	{
		if ([self.ebn_currentlyValidProperties containsObject:property])
			return;
	}
	
	SEL getterSelector = [[self class] ebn_selectorForPropertyGetter:property];
	if (getterSelector)
	{
		NSMethodSignature *methodSig = [self methodSignatureForSelector:getterSelector];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
		[invocation setTarget:self];
		[invocation setSelector:getterSelector];
		[invocation invoke];
	}
}

/****************************************************************************************************
	ebn_swizzleImplementationForGetter:
	
	Swizzles the implemention of the getter method of the given property. The swizzled implementation
	checks to see if the ivar backing the property is valid (== if lazy loading has happened) and if so
	returns the ivar. 

	The bulk of this method is a switch statement that switches on the type of the property (parsed
	from the string returned by method_getArgumentType()) and calls a templatized C++ function
	called overrideGetterMethod<>() to create a new method and swizzle it in.
*/
- (BOOL) ebn_swizzleImplementationForGetter:(NSString *) propertyName customLoader:(SEL) loader
{
	Class classToModify = [self ebn_prepareToObserveProperty:propertyName isSetter:NO];
	if (!classToModify)
		return YES;

	// Get the method selector for the getter on this property
	SEL getterSelector = [[self class] ebn_selectorForPropertyGetter:propertyName];
	EBAssert(getterSelector, @"Couldn't find getter method for property %@ in object %@", propertyName, self);
	if (!getterSelector)
		return NO;
	
	// Then get the method we'd call for that selector
	Method getterMethod = class_getInstanceMethod([self class], getterSelector);
	if (!getterMethod)
		return NO;
	
	// Get the instance variable that backs the property
	Ivar getterIvar = nil;
	objc_property_t prop = class_getProperty([self class], [propertyName UTF8String]);
	if (prop)
	{
		NSString *propStr = [NSString stringWithUTF8String:property_getAttributes(prop)];
		NSRange getterIvarRange = [propStr rangeOfString:@",V"];
		if (getterIvarRange.location != NSNotFound)
		{
			NSString *ivarString = [propStr substringFromIndex:getterIvarRange.location + getterIvarRange.length];
			getterIvar = class_getInstanceVariable([self class], [ivarString UTF8String]);
		}
	}
	EBAssert(getterIvar, @"No instance variable found to back property %@.", propertyName);
	if (!getterIvar)
		return NO;
		
	char typeOfGetter[32];
	method_getReturnType(getterMethod, typeOfGetter, 32);

	// Types defined in runtime.h
	switch (typeOfGetter[0])
	{
	case _C_CHR:
		overrideGetterMethod<char>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_UCHR:
		overrideGetterMethod<unsigned char>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_SHT:
		overrideGetterMethod<short>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_USHT:
		overrideGetterMethod<unsigned short>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_INT:
		overrideGetterMethod<int>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_UINT:
		overrideGetterMethod<unsigned int>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_LNG:
		overrideGetterMethod<long>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_ULNG:
		overrideGetterMethod<unsigned long>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_LNG_LNG:
		overrideGetterMethod<long long>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_ULNG_LNG:
		overrideGetterMethod<unsigned long long>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_FLT:
		overrideGetterMethod<float>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_DBL:
		overrideGetterMethod<double>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_BFLD:
		// Pretty sure this can't happen, as bitfields can't be top-level and are only found inside structs/unions
		EBAssert(NO, @"Observable does not have a way to override the setter for %@.", propertyName);
	break;
	
		// From "Objective-C Runtime Programming Guide: Type Encodings" -- 'B' is "A C++ bool or a C99 _Bool"
	case _C_BOOL:
		overrideGetterMethod<bool>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_PTR:
	case _C_CHARPTR:
	case _C_ATOM:		// Apparently never generated? Only docs I can find say treat same as charptr
	case _C_ARY_B:
		overrideGetterMethod<void *>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	
	case _C_ID:
		overrideGetterMethod<id>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_CLASS:
		overrideGetterMethod<Class>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;
	case _C_SEL:
		overrideGetterMethod<SEL>(propertyName, getterMethod, getterIvar, classToModify, loader);
	break;

	case _C_STRUCT_B:
		if (!strncmp(typeOfGetter, @encode(NSRange), 32))
			overrideGetterMethod<NSRange>(propertyName, getterMethod, getterIvar, classToModify, loader);
		else if (!strncmp(typeOfGetter, @encode(CGPoint), 32))
			overrideGetterMethod<CGPoint>(propertyName, getterMethod, getterIvar, classToModify, loader);
		else if (!strncmp(typeOfGetter, @encode(CGRect), 32))
			overrideGetterMethod<CGRect>(propertyName, getterMethod, getterIvar, classToModify, loader);
		else if (!strncmp(typeOfGetter, @encode(CGSize), 32))
			overrideGetterMethod<CGSize>(propertyName, getterMethod, getterIvar, classToModify, loader);
		else
			EBAssert(NO, @"Observable does not have a way to override the setter for %@.", propertyName);
	break;
	
	case _C_UNION_B:
		// If you hit this assert, look at what we do above for structs, make something like that for
		// unions, and add your type to the if statement
		EBAssert(NO, @"Observable does not have a way to override the setter for %@.", propertyName);
	break;
	
	default:
		EBAssert(NO, @"Observable does not have a way to override the setter for %@.", propertyName);
	break;
	}
	
	return YES;
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
	return self.ebn_currentlyValidProperties;
}

/****************************************************************************************************
	debug_invalidProperties
	
	This method is for debugging. If you're trying to use this method to implement some sort of
	validity introspection that invalidates/forces caching in some weird way you are probably 
	doing it wrong.
	
	This method purposefully doesn't @synchronize because it could cause a debugger deadlock.
	
	Returns the set of synthetic properties whose values are currently wrong.

	To use, type in the debugger:
		po [<object> debug_invalidProperties]
*/
- (NSSet *) debug_invalidProperties
{
	NSMutableSet *invalidPropertySet = [[NSMutableSet alloc] init];
	EBNShadowedClassInfo *info = nil;
		
	if (class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
	{
		info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
	}
	if (!info)
	{
		info = EBNBaseClassToShadowInfoTable[[self class]];
	}
	
	if (info)
	{
		[invalidPropertySet unionSet:info->_getters];
	}
	
	// Now subtract out all the properties that are currently valid. What's left is the invalid properties.
	[invalidPropertySet minusSet:self.ebn_currentlyValidProperties];
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
	// For each invalid property go call valueForKey:, which will force the property to get computed.
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
template<typename T> void overrideGetterMethod(NSString *propName, Method getter,
		Ivar getterIvar, Class classToModify, SEL loader)
{
	// All of these local variables get copied into the setAndObserve block
	T (*originalGetter)(id, SEL) = (T (*)(id, SEL)) method_getImplementation(getter);
	SEL getterSEL = method_getName(getter);
	ptrdiff_t ivarOffset = ivar_getOffset(getterIvar);
	
	NSMutableSet *threadsPerformingLoads = nil;
	if (loader)
	{
		threadsPerformingLoads = [[NSMutableSet alloc] init];
	}

	// This is what gets run when the getter method gets called.
	T (^getLazily)(NSObject *) = ^ T (NSObject *blockSelf)
	{
		// NOTE: Read this fn's comments. This doesn't get called for object properties.
		// And yes--we need all 3 casts.
		T *ivarPtr = (T *) (((char *) ((__bridge void *) blockSelf)) + ivarOffset);
		BOOL propertyIsValid = false;
		BOOL mustPerformLoad = false;
		
		// Check whether the property is valid.
		@synchronized(EBNObservableSynchronizationToken)
		{
			propertyIsValid = [blockSelf.ebn_currentlyValidProperties containsObject:propName];
			if (!propertyIsValid && loader && ![threadsPerformingLoads containsObject:[NSThread currentThread]])
			{
				[threadsPerformingLoads addObject:[NSThread currentThread]];
				mustPerformLoad	= true;
			}
		}
		
		if (propertyIsValid)
		{
			return *ivarPtr;
		}
		else
		{
			// The optional loader method is called with a property name and is responsible for
			// 'loading' the value of that property--generally making it so the getter will
			// return the right value. Useful for cases where properties are actually stored in
			// dictionaries and fronted with property names.
			if (mustPerformLoad)
			{
				@try
				{
					// Because ARC doesn't know what type the dynamic 'loader' selector returns, and more
					// importantly how ARC is supposed to treat the the returned value's ownership state (if
					// it returns an object at all), ARC will warn that performSelector might leak here.
					// Since the loader is defined to return NULL, it won't leak in this case, hence the pragmas.
					#pragma clang diagnostic push
					#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
					[blockSelf performSelector:loader withObject:propName];
					#pragma clang diagnostic pop
				}
				@finally
				{
					@synchronized(EBNObservableSynchronizationToken)
					{
						[threadsPerformingLoads removeObject:[NSThread currentThread]];
					}
				}
			}

			// Call the original getter to get the value of the property and save that value
			// in the ivar. Then we need to mark the property as valid.
			T value = (originalGetter)(blockSelf, getterSEL);
			*ivarPtr = value;
			@synchronized(EBNObservableSynchronizationToken)
			{
				[blockSelf.ebn_currentlyValidProperties addObject:propName];
			}
			return value;
		}
	};

	// Now replace the getter's implementation with the new one
	IMP swizzledImplementation = imp_implementationWithBlock(getLazily);
	class_replaceMethod(classToModify, getterSEL, swizzledImplementation, method_getTypeEncoding(getter));
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
template<> void overrideGetterMethod<id>(NSString *propName, Method getter, Ivar getterIvar,
		Class classToModify, SEL loader)
{
	// All of these local variables get copied into the setAndObserve block
	id (*originalGetter)(id, SEL) = (id (*)(id, SEL)) method_getImplementation(getter);
	SEL getterSEL = method_getName(getter);
	
	NSMutableSet *threadsPerformingLoads = nil;
	if (loader)
	{
		threadsPerformingLoads = [[NSMutableSet alloc] init];
	}

	// This is what gets run when the getter method gets called.
	id (^getLazily)(NSObject *) = ^ id (NSObject *blockSelf)
	{
		BOOL propertyIsValid = false;
		BOOL mustPerformLoad = false;
		
		// Check whether the property is valid.
		@synchronized(EBNObservableSynchronizationToken)
		{
			propertyIsValid = [blockSelf.ebn_currentlyValidProperties containsObject:propName];
			if (!propertyIsValid && loader && ![threadsPerformingLoads containsObject:[NSThread currentThread]])
			{
				[threadsPerformingLoads addObject:[NSThread currentThread]];
				mustPerformLoad	= true;
			}
		}
		
		if (propertyIsValid)
		{
			return object_getIvar(blockSelf, getterIvar);
		}
		else
		{
			// The optional loader method is called with a property name and is responsible for
			// 'loading' the value of that property--generally making it so the getter will
			// return the right value. Useful for cases where properties are actually stored in
			// dictionaries and fronted with property names.
			if (mustPerformLoad)
			{
				@try
				{
					// Because ARC doesn't know what type the dynamic 'loader' selector returns, and more
					// importantly how ARC is supposed to treat the the returned value's ownership state (if
					// it returns an object at all), ARC will warn that performSelector might leak here.
					// Since the loader is defined to return NULL, it won't leak in this case, hence the pragmas.
					#pragma clang diagnostic push
					#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
					[blockSelf performSelector:loader withObject:propName];
					#pragma clang diagnostic pop
				}
				@finally
				{
					@synchronized(EBNObservableSynchronizationToken)
					{
						[threadsPerformingLoads removeObject:[NSThread currentThread]];
					}
				}
			}
			
			// Call the original getter to get the value of the property and save that value
			// in the ivar. Then we need to mark the property as valid.
			id value = (originalGetter)(blockSelf, getterSEL);
			object_setIvar(blockSelf, getterIvar, value);
			@synchronized(EBNObservableSynchronizationToken)
			{
				[blockSelf.ebn_currentlyValidProperties addObject:propName];
			}
			return value;
		}
	};

	// Now replace the getter's implementation with the new one
	IMP swizzledImplementation = imp_implementationWithBlock(getLazily);
	class_replaceMethod(classToModify, getterSEL, swizzledImplementation, method_getTypeEncoding(getter));
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
template<> void overrideGetterMethod<Class>(NSString *propName, Method getter,
		Ivar getterIvar, Class classToModify, SEL loader)
{
	// All of these local variables get copied into the setAndObserve block
	Class (*originalGetter)(id, SEL) = (Class (*)(id, SEL)) method_getImplementation(getter);
	SEL getterSEL = method_getName(getter);
	
	NSMutableSet *threadsPerformingLoads = nil;
	if (loader)
	{
		threadsPerformingLoads = [[NSMutableSet alloc] init];
	}

	// This is what gets run when the getter method gets called.
	Class (^getLazily)(NSObject *) = ^ Class (NSObject *blockSelf)
	{
		BOOL propertyIsValid = false;
		BOOL mustPerformLoad = false;
		
		// Check whether the property is valid.
		@synchronized(EBNObservableSynchronizationToken)
		{
			propertyIsValid = [blockSelf.ebn_currentlyValidProperties containsObject:propName];
			if (!propertyIsValid && loader && ![threadsPerformingLoads containsObject:[NSThread currentThread]])
			{
				[threadsPerformingLoads addObject:[NSThread currentThread]];
				mustPerformLoad	= true;
			}
		}
		
		if (propertyIsValid)
		{
			return object_getIvar(blockSelf, getterIvar);
		}
		else
		{
			// The optional loader method is called with a property name and is responsible for
			// 'loading' the value of that property--generally making it so the getter will
			// return the right value. Useful for cases where properties are actually stored in
			// dictionaries and fronted with property names.
			if (mustPerformLoad)
			{
				@try
				{
					// Because ARC doesn't know what type the dynamic 'loader' selector returns, and more
					// importantly how ARC is supposed to treat the the returned value's ownership state (if
					// it returns an object at all), ARC will warn that performSelector might leak here.
					// Since the loader is defined to return NULL, it won't leak in this case, hence the pragmas.
					#pragma clang diagnostic push
					#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
					[blockSelf performSelector:loader withObject:propName];
					#pragma clang diagnostic pop
				}
				@finally
				{
					@synchronized(EBNObservableSynchronizationToken)
					{
						[threadsPerformingLoads removeObject:[NSThread currentThread]];
					}
				}
			}

			// Call the original getter to get the value of the property and save that value
			// in the ivar. Then we need to mark the property as valid.
			id value = (originalGetter)(blockSelf, getterSEL);
			object_setIvar(blockSelf, getterIvar, value);
			@synchronized(EBNObservableSynchronizationToken)
			{
				[blockSelf.ebn_currentlyValidProperties addObject:propName];
			}
			return value;
		}
	};

	// Now replace the getter's implementation with the new one
	IMP swizzledImplementation = imp_implementationWithBlock(getLazily);
	class_replaceMethod(classToModify, getterSEL, swizzledImplementation, method_getTypeEncoding(getter));
}

@end


/****************************************************************************************************
	EBNLazyLoader the class is deprecated. Here for compatibility.

*/
@implementation EBNLazyLoader
@end


