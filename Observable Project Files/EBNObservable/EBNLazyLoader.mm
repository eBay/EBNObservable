/****************************************************************************************************
	EBNLazyLoader.mm
	Observable
	
	Created by Chall Fry on 4/29/14.
    Copyright (c) 2013-2018 eBay Software Foundation.
	
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

#import <UIKit/UIGeometry.h>
#import <CoreGraphics/CGGeometry.h>
#import <objc/message.h>
#import <atomic>
#import <pthread/pthread.h>

#import "EBNLazyLoader.h"
#import "EBNObservableInternal.h"

static uint32_t sBlockCreationIndex = 0;

/**
	A collection of fields we need to set up a lazily loaded property. Not kept after we've finished
	setting up the new lazyloaded property; this is purely a way to not have a bunch of methods all taking
	8 parameters.
*/
@interface LazyLoaderConstructionInfo : NSObject
{
@public
	EBNShadowedClassInfo 	*_classInfo;
	NSString 				*_propertyName;
	NSInteger 				_propertyIndex;
	Method 					_getterMethod;
	Ivar					_getterIvar;
	Class 					_classToModify;
	SEL 					_loader;
	NSString 				*_copyFromPropertyName;
	SEL 					_copyFromSEL;
	objc_property_t			_propInfo;
	BOOL 					_myOwnPrivateIvar;

}
@end

@implementation LazyLoaderConstructionInfo
@end

/**
	The type of the bitfield of valid properties for an object. This can be found  as a runtime-generated ivar 
	in the object directly.
*/
typedef struct ValidPropertiesStruct
{
	std::atomic<uint32_t>	propertyBitfield[];
} ValidPropertiesStruct;


template<typename T> void overrideGetterMethod(LazyLoaderConstructionInfo *constructionInfo);

@implementation NSObject (EBNLazyLoader)

#pragma mark Public API

/****************************************************************************************************
	syntheticProperty:
	
*/
+ (void) syntheticProperty:(nonnull NSString *) property
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
+ (void) syntheticProperty:(NSString *) property dependsOn:(NSString *) keyPathString
{
	EBNShadowedClassInfo *classInfo = [self ebn_wrapPropertyMethods:property customLoader:nil copyFromProperty:nil];
	if (!classInfo)
		return;

	if (keyPathString)
	{
		// Set up our observation, with nil set for observed and observer
		EBNObservation *blockInfo = [[EBNObservation alloc] initForObserved:nil observer:nil
				immedBlock:^(id blockSelf, id observed)
		{
			[blockSelf invalidatePropertyValue:property];
		}];
		blockInfo.isForLazyLoader = YES;
		
#if defined(DEBUG) && DEBUG
		[blockInfo setDebugString:[NSString stringWithFormat:
				@"%p: Global synthetic property invalidation observation for \"%@\" of class <%@>",
				blockInfo, property, classInfo->_shadowClass]];
#endif

		// Create a keypath entry
		EBNKeypathEntryInfo	*entryInfo = [[EBNKeypathEntryInfo alloc] init];
		entryInfo->_blockInfo = blockInfo;
		entryInfo->_keyPath = [keyPathString componentsSeparatedByString:@"."];
		entryInfo->_keyPathIndex = 0;
		
		@synchronized(EBNBaseClassToShadowInfoTable)
		{
			// Add the keypath entry to the global observations to be copied into objects during alloc
			// This can be thought of as being similar to an NSInvocation in that it 'freeze-dries' an observeration
			// for later deployment.
			if (!classInfo->_globalObservations)
				classInfo->_globalObservations = [[NSMutableArray alloc] init];
			[classInfo->_globalObservations addObject:entryInfo];
		}
	}
}

/****************************************************************************************************
	syntheticProperty:dependsOnPaths:
	
	Declares property to be a lazy-loading synthetic property whose value is dependent on all the
	paths in keyPaths.
*/
+ (void) syntheticProperty:(NSString *) property dependsOnPaths:(NSArray *) keyPaths
{
	EBNShadowedClassInfo *classInfo = [self ebn_wrapPropertyMethods:property customLoader:nil copyFromProperty:nil];
	if (!classInfo)
		return;
	
	if (keyPaths && keyPaths.count)
	{
		// Set up our observation, with nil set for observed and observer
		EBNObservation *blockInfo = [[EBNObservation alloc] initForObserved:nil observer:nil
		immedBlock:^(id blockSelf, id observed)
		{
			[blockSelf invalidatePropertyValue:property];
		}];
		blockInfo.isForLazyLoader = YES;
		
#if defined(DEBUG) && DEBUG
		[blockInfo setDebugString:[NSString stringWithFormat:
				@"%p: Global synthetic property invalidation observation for \"%@\" of class <%@>",
				blockInfo, property, classInfo->_shadowClass]];
#endif

		@synchronized(EBNBaseClassToShadowInfoTable)
		{
			if (!classInfo->_globalObservations)
				classInfo->_globalObservations = [[NSMutableArray alloc] init];

			for (NSString *keyPathString in keyPaths)
			{
				// Create a keypath entry
				EBNKeypathEntryInfo	*entryInfo = [[EBNKeypathEntryInfo alloc] init];
				entryInfo->_blockInfo = blockInfo;
				entryInfo->_keyPath = [keyPathString componentsSeparatedByString:@"."];
				entryInfo->_keyPathIndex = 0;
				
				// Add it to the global observations
				[classInfo->_globalObservations addObject:entryInfo];
			}
		}
	}
}

/****************************************************************************************************
	syntheticProperty:withLazyLoaderMethod:
	
	Declares a synthetic property, with no dependents. This property will lazily compute its value;
	you must use the invalidate methods to clear it.
	
	The lazyLoader selector identifies a method to call to 'load' values into this property. So,
	just like a custom getter, except the lodaer method gets the name of the property it's loading
	as a parameter. Depending on how your class sources its data, this may make it much easier to
*/
+ (void) syntheticProperty:(NSString *) property withLazyLoaderMethod:(SEL) loader
{
	[self ebn_wrapPropertyMethods:property customLoader:loader copyFromProperty:nil];
}

/****************************************************************************************************
	publicCollection:copiesFromPrivateCollection:
	
	This method is used to set up a public property for an immutable collection that keeps updated 
	with the contents of a private, mutable collection in your class.
	
	'Collection' in this context means NSSet, NSArray, or NSDictionary.
	
	Add a line like this to your init method:
		[self publicCollection:@"publicNSArray" copiesFromPrivateCollection:@"privateNSMutableArray"];
		
	... and you're done. You don't need to write a custom getter that does the copy, the copy happens at 
	most once per mutation of the private array, and the public array is properly observable--that is,
	changes to the private array are noticed immediately by observers on elements of the public array.
*/
+ (void) publicCollection:(NSString *) propertyName copiesFromPrivateCollection:(NSString *) copyFromProperty
{
	// Wrap the getter and setter, isa-swizzle self if necessary
	EBNShadowedClassInfo *classInfo = [self ebn_wrapPropertyMethods:propertyName customLoader:nil
			copyFromProperty:copyFromProperty];
	if (!classInfo)
		return;

	// Set up our observation that'll invalidate the public property when the private property mutates
	EBNObservation *blockInfo = NewObservationBlockImmed(self,
	{
		[blockSelf invalidatePropertyValue:propertyName];
	});
	blockInfo.isForLazyLoader = YES;
	
#if defined(DEBUG) && DEBUG
	[blockInfo setDebugString:[NSString stringWithFormat:
			@"%p: Global synthetic property invalidation observation for \"%@\" of class <%@>",
			blockInfo, propertyName, classInfo->_shadowClass]];
#endif

	NSString *observationKeypath = [copyFromProperty stringByAppendingString:@".*"];

	// Create a keypath entry
	EBNKeypathEntryInfo	*entryInfo = [[EBNKeypathEntryInfo alloc] init];
	entryInfo->_blockInfo = blockInfo;
	entryInfo->_keyPath = [observationKeypath componentsSeparatedByString:@"."];
	entryInfo->_keyPathIndex = 0;
	
	@synchronized(EBNBaseClassToShadowInfoTable)
	{
		// Add the keypath entry to the global observations to be copied into objects during alloc
		// This can be thought of as being similar to an NSInvocation in that it 'freeze-dries' an observeration
		// for later deployment.
		if (!classInfo->_globalObservations)
			classInfo->_globalObservations = [[NSMutableArray alloc] init];
		[classInfo->_globalObservations addObject:entryInfo];
	}
}

/****************************************************************************************************
	syntheticProperty_MACRO_USE_ONLY:dependsOnKeyPathStrings
	
	A special version of the syntheticPropery method, specifically for use by the SyntheticProperty macro.
	Probably best not to use this method directly; use the 'dependsOnPaths:' variant instead.
*/
+ (void) syntheticProperty_MACRO_USE_ONLY:(NSString *) propertyAndPaths
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
	
	// The first item in the array is now the property being declared as synthetic. The SyntheticProperty()
	// macro takes the class name as the first argument, but doesn't pass it into this method.
	EBAssert([keyPathArray count], @"The SyntheticProperty() macro needs to be called with the class name and the"
			@"property you're declaring as synthetic.");
	NSString *property = [keyPathArray objectAtIndex:0];
	[keyPathArray removeObjectAtIndex:0];
	
	[self syntheticProperty:property dependsOnPaths:keyPathArray];
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
	ValidPropertiesStruct *validProperties = nil;

	// Is this property currently valid?
	NSInteger propIndex = [self ebn_indexOfProperty:property];
	if (propIndex != NSNotFound)
	{
		validProperties = self.ebn_currentlyValidProperties;
		if (validProperties)
		{
			// Get the bitfield, check whether the indexed bit is set.
			uint32_t longLoad = validProperties->propertyBitfield[propIndex / 32];
			wasValid = (longLoad & (1 << (propIndex & 31))) != 0;
		}
	}
	else
	{
		// This where we need to invalidate a property we're not actually tracking, as
		// our fixed-size bitfield has run out of room. In this case we have to assume
		// the property was previously valid, so that we'll notify observers.
		wasValid = YES;
	}
	
	// A bit of inductive logic here: If the property wasn't previously valid, it wasn't being
	// observed, as observed properties have to be forced valid. This is all being done because
	// asking for prevValue won't recompute if wasValid is true.
	if (wasValid)
	{
		// This should get the cached (valid) value. Can't be done inside a synchronize.
		id prevValue = [self ebn_valueForKey:property];
		
		// validPropertyBitfield will be nil in the case where the property index is beyond the end
		// of the bitfield
		if (validProperties != nil)
		{
			// Now we remove the property from the valid list
			std::atomic_fetch_and(validProperties->propertyBitfield + propIndex / 32, 
					(uint32_t) ~(1 << (propIndex & 31)));
		}
		
		// And call the manual trigger to tell observers about the change. Note that we only have to
		// call this if wasValid was true, as if it was false there's no observers.
		[self ebn_manuallyTriggerObserversForProperty:property previousValue:prevValue];
	}
}

/****************************************************************************************************
	invalidatePropertyValues:
	
	Marks the given properties as invalid; this flags them so that they will be recomputed the next time
	their getter is called. If the property is being observed, it's possible for the getter to be called
	immediately.
	
	This method checks the set property values against the set of lazy properties, and only tries to 
	invalidate properties that are actually lazily loaded.
*/
- (void) invalidatePropertyValues:(NSSet *) properties
{
	// If there's no valid properties, exit early
	if (![self ebn_hasValidProperties])
		return;

	NSMutableOrderedSet *lazyProperties = nil;
	
	// Get the set of lazy getters from our subclass. If it doesn't exist or is empty we intersect against
	// the null set and don't invalidate anything, which is what we want if we don't actually have lazy properties.
	@synchronized(EBNBaseClassToShadowInfoTable)
	{
		EBNShadowedClassInfo *info = nil;
		
		if (class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
		{
			info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
		}
		
		// Get all the registered lazy properties, and intersect that with the set of newly-invalid properties.
		if (info && info->_getters)
		{
			lazyProperties = [info->_getters mutableCopy];
			[lazyProperties intersectSet:properties];
		}
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
	ValidPropertiesStruct *validProperties = self.ebn_currentlyValidProperties;
	if (!validProperties)
		return;
	
	EBNShadowedClassInfo *info = nil;
	if (class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
	{
		info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
	}
	if (!info)
		return;
	
	uint32_t hasValidProperties = 0;
	for (int longIndex = 0; longIndex < (info->_validPropertyBitfieldSize + 31) / 32; ++longIndex)
	{
		hasValidProperties |= validProperties->propertyBitfield[longIndex];
	}
	
	// If there's no valid properties, exit early
	if (!hasValidProperties)
		return;
	
	// rcf Also have to call invalidate on any properties that are being observed.
	
	for (NSUInteger longIndex = 0; longIndex < (info->_validPropertyBitfieldSize + 31) / 32; longIndex++)
	{
		uint32_t bitfield = validProperties->propertyBitfield[longIndex];
		for (int bitIndex = 0; bitIndex < 32; ++bitIndex)
		{
			if (bitfield & (1 << bitIndex))
			{
				[self invalidatePropertyValue:[self ebn_propertyNameAtIndex:longIndex * 32 + bitIndex]];
			}
		}
	}
}

/****************************************************************************************************
	ebn_hasValidProperties
	
	YES if the receiver has lazily loaded properties that are marked valid, otherwise NO.
*/
- (BOOL) ebn_hasValidProperties
{
	UInt32 hasValidProperties = 0;
	ValidPropertiesStruct *validProperties = self.ebn_currentlyValidProperties;
	
	EBNShadowedClassInfo *info = nil;
	if (class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
	{
		info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
	}
	if (!info)
		return NO;
	
	if (validProperties)
	{
		for (int longIndex = 0; longIndex < (info->_validPropertyBitfieldSize + 31) / 32; ++longIndex)
		{
			hasValidProperties |= validProperties->propertyBitfield[longIndex];
		}
	}

	if (hasValidProperties)
		return YES;
		
	return NO;
}

#pragma mark Private Methods

/****************************************************************************************************
	ebn_installAdditionalOverrides:
	
	This gets called by ebn_createShadowedSubclass during shadow class creation, before 
	objc_registerClassPair is called. This allows LazyLoader to install some additional method
	overrides (and more importantly, add additional ivars to the subclass).
	
	This method installs overrides for:
		+allocWithZone:
		-ebn_observedKeysDict:
		-ebn_currentlyValidProperties 
*/
+ (void) ebn_installAdditionalOverrides:(EBNShadowedClassInfo *) classInfo actualClass:(Class) actualClass
{
	// We *may* need to check for overridden alloc behavior here.

	Class metaClass = object_getClass(actualClass);
	Class shadowClass = classInfo->_shadowClass;
	
	// Save the allocWithZone: method that we'd normally call, and copy it into the block
	Method allocWithZoneMethod = class_getClassMethod(actualClass, @selector(allocWithZone:));

////// 		allocWithZone:	//////

	// Override allocWithZone: to force instances of the base class to all be the shadow class
	// To do this, we're overriding allocWithZone on the actual class, not in the shadow class.
	id (^allocWithZone_Override)(Class, NSZone *) __attribute((ns_returns_retained)) =
			^id (Class classToAlloc, NSZone *zone) __attribute((ns_returns_retained))
	{
		id returnedObject = nil;
		
		// AllocWithZone will be called for the non-shadowed class, then recursively called for the
		// shadowed subclass. Figure out which case this is first thing.
		if (class_respondsToSelector(classToAlloc, @selector(ebn_shadowClassInfo)))
		{
			// If we get here, we're being asked to alloc a shadowed subclass.
			// These 3 lines amount to "[classToAlloc allocWithZone:zone]", but calling the original allocWithZone:.
			// Remember that classToAlloc will now be the shadowed subclass.
			typedef id (*allocWithZoneFnPtr)(Class, Method, NSZone *) __attribute((ns_returns_retained));
			allocWithZoneFnPtr allocWithZone_method_invoke = (allocWithZoneFnPtr) method_invoke;
			returnedObject = allocWithZone_method_invoke(classToAlloc, allocWithZoneMethod, zone);

			// Copy our global observations into this new object. We don't need to copy in observations
			// made globally by super- or sub-classes, as we just effectively called super, above.
			NSMutableArray *globalObservations = nil;
			@synchronized(EBNBaseClassToShadowInfoTable)
			{
				globalObservations = classInfo->_globalObservations;
			}
			
			// Importantly, this uses the classInfo copied into the block, NOT necessarily the classInfo
			// for the current class.
			for (EBNKeypathEntryInfo *entryInfo in globalObservations)
			{
				EBNKeypathEntryInfo *entryInfoCopy = [entryInfo copy];
				entryInfoCopy->_blockInfo = [entryInfo->_blockInfo copy];
				EBNObservation *blockInfoCopy = entryInfoCopy->_blockInfo;
				blockInfoCopy->_weakObserved = returnedObject;
				blockInfoCopy->_weakObserver = returnedObject;
				blockInfoCopy->_weakObserver_forComparisonOnly = returnedObject;
				
				[returnedObject ebn_addEntry:entryInfoCopy forProperty:entryInfoCopy->_keyPath[0]];
			}
		}
		else
		{
			// If we get here, we're being asked to alloc a non-shadowed class, which could be the base class,
			// or some non-shadowed subclass of the base class.  Any non-shadowed subclass of this class that 
			// the runtime attempts to allocate must instead be created as the shadowed subclass of that subclass.

			// Get the class info object for the class we're supposed to alloc, which could be any
			// subclass of the class where we install
			Class shadowClassToAlloc = nil;
			@synchronized(EBNBaseClassToShadowInfoTable)
			{
				// Note: If BaseClass has synthetic properties, DerivedClass will have a shadowed class in the table,
				// because [DerivedClass initialize] calls its super, which is BaseClass, which sets things up for it.
				EBNShadowedClassInfo *curClassInfo = [EBNBaseClassToShadowInfoTable objectForKey:classToAlloc];
				if (curClassInfo)
				{
					if (!curClassInfo->_allocHasHappened)
					{
						// We have to register the new class.
						objc_registerClassPair(curClassInfo->_shadowClass);
						curClassInfo->_allocHasHappened = YES;
					}
					shadowClassToAlloc = curClassInfo->_shadowClass;
				}
			}
			
			// Call allocs outside of the sync
			if (shadowClassToAlloc)
			{
				// This case is where we convert an alloc call on the base class into an alloc call
				// for the shadowed subclass.
				returnedObject = [shadowClassToAlloc allocWithZone:zone];
			}
			else
			{
				// In this case we're asked to alloc a class that we have no shadowed class for.
				// Just pass the alloc through to the original method.

				// Call the original allocWithZone: method using method_invoke(). Have to cast the fn ptr first.
				typedef id (*allocWithZoneFnPtr)(Class, Method, NSZone *) __attribute((ns_returns_retained));
				allocWithZoneFnPtr allocWithZone_method_invoke = (allocWithZoneFnPtr) method_invoke;
				returnedObject = allocWithZone_method_invoke(classToAlloc, allocWithZoneMethod, zone);
			}
		}
		
		return returnedObject;
	};
	IMP allocWithZoneMethodImplementation = imp_implementationWithBlock(allocWithZone_Override);
	class_addMethod(metaClass, @selector(allocWithZone:),
			(IMP) allocWithZoneMethodImplementation, method_getTypeEncoding(allocWithZoneMethod));

////// 		ebn_observedKeysDict:	//////

	// Add an ivar to the class that'll hold the observation dict; this will obviate having to store the
	// dict in an associatied object.
	BOOL addedObservationDictIvar = class_addIvar(shadowClass, "ebn_ObservationDictionary",
			sizeof(id), log2(sizeof(id)), @encode(id));

	if (addedObservationDictIvar)
	{			
		NSMutableDictionary *(^ebn_observedKeysDict_Override)(NSObject *, BOOL)  =
		^NSMutableDictionary *(NSObject *blockSelf, BOOL createIfNil)
		{
			Ivar observationDictIvar = class_getInstanceVariable(shadowClass, "ebn_ObservationDictionary");
			NSMutableDictionary *returnDict = object_getIvar(blockSelf, observationDictIvar);
			if (!returnDict && createIfNil)
			{
				@synchronized(EBNObservableSynchronizationToken)
				{
					// Recheck for non-nil inside the sync
					returnDict = object_getIvar(blockSelf, observationDictIvar);
					if (!returnDict)
					{
						returnDict = [[NSMutableDictionary alloc] init];
						[blockSelf setValue:returnDict forKey:@"ebn_ObservationDictionary"];
					}
				}
			}
			
			return returnDict;
		};
		IMP ebn_observedKeysDict_MethodImplementation = imp_implementationWithBlock(ebn_observedKeysDict_Override);
		Method observedKeysMethod = class_getInstanceMethod(shadowClass, @selector(ebn_observedKeysDict:));
		class_addMethod(shadowClass, @selector(ebn_observedKeysDict:),
				(IMP) ebn_observedKeysDict_MethodImplementation, method_getTypeEncoding(observedKeysMethod));
		
		// Add this ivar to the list of ivars to manually dealloc when we dealloc objects of this class
		if (!classInfo->_objectGettersWithPrivateStorage)
		{
			classInfo->_objectGettersWithPrivateStorage = [NSMutableSet set];
		}
		[classInfo->_objectGettersWithPrivateStorage addObject:@"ebn_ObservationDictionary"];
	}

	// Determine how many properties these objects will have, and reserve ivar space for a bitfield
	// large enough to have 1 bit per property. Since shadowClass may not be the direct child of baseClass
	// in the case of other runtime-subclassers out there, count properties from shadow's super.
	int numProperties = [class_getSuperclass(shadowClass) ebn_countOfAllProperties];
	classInfo->_validPropertyBitfieldSize = numProperties;
	char typeDesc[32];
	snprintf(typeDesc, 30, "[%dI]", numProperties / 32);

////// 		ebn_currentlyValidProperties	//////

	// Add the ivar, and override the method that returns the bitfield pointer to return the ivar address
	BOOL addedPropValidityIvar = class_addIvar(shadowClass, "ebn_PropertyValidityBitfield",
			numProperties / 8, 2, typeDesc);
	if (addedPropValidityIvar)
	{
		Ivar propValidityIvar = class_getInstanceVariable(shadowClass, "ebn_PropertyValidityBitfield");
		ptrdiff_t propValidityIvarOffset = ivar_getOffset(propValidityIvar);

		ValidPropertiesStruct *(^ebn_currentlyValidProperties)(NSObject *) =
				^ValidPropertiesStruct *(NSObject *blockSelf)
				{
					uint8_t *blockSelfCharPtr = (uint8_t *) ((__bridge void *) blockSelf);
					return (ValidPropertiesStruct *) (blockSelfCharPtr + propValidityIvarOffset);
				};
		IMP ebn_currentlyValidProperties_MethodImplementation =
				imp_implementationWithBlock(ebn_currentlyValidProperties);
		Method currentlyValidPropertiesMethod = class_getInstanceMethod(shadowClass,
				@selector(ebn_currentlyValidProperties));
		class_addMethod(shadowClass, @selector(ebn_currentlyValidProperties),
				(IMP) ebn_currentlyValidProperties_MethodImplementation,
				method_getTypeEncoding(currentlyValidPropertiesMethod));
	}
	
}

/****************************************************************************************************
	ebn_wrapPropertyMethods
	
	Swaps out the getter and setter for the given property. The receiver class for this method should
	be the base class (also known as the Cocoa-visible class, or what [self class] returns]). self shouldn't
	be a runtime-generated class when this is called.
	
	Both loader and copyFromProperty may be nil.
*/
+ (EBNShadowedClassInfo *) ebn_wrapPropertyMethods:(NSString *) propName customLoader:(SEL) loader
		copyFromProperty:(NSString *) copyFromProperty
{
	// Once we create our runtime subclass, the runtime subclass will get a +initialize call on first use.
	// The base class's +initialize will usually be what gets called, and it will usually re-call all
	// the synthetic properties. This makes those calls do nothing.
	if (class_respondsToSelector(self, @selector(ebn_shadowClassInfo)))
	{
		return nil;
	}
	
	LazyLoaderConstructionInfo *constructionInfo = [[LazyLoaderConstructionInfo alloc] init];
	constructionInfo->_propertyName = propName;
	constructionInfo->_loader = loader;
	constructionInfo->_copyFromPropertyName = copyFromProperty;
	
	EBNShadowedClassInfo *classInfo = nil;
	@synchronized(EBNBaseClassToShadowInfoTable)
	{
		// Returns an object with info about the runtime-created subclass we made for this class
		classInfo = [NSObject ebn_createShadowedSubclass:self actualClass:self
				additionalOverrides:YES];
		if (!classInfo)
			return nil;
		
		// The getter must be found and swizzled
		constructionInfo->_classInfo = classInfo;
		if (![self ebn_swizzleImplementationForGetter:constructionInfo])
			return nil;

		// Readonly properties don't have a setter; this will fail in that case and that's okay
		[self ebn_swizzleImplementationForSetter:propName info:classInfo];
	}
	
	// This check may not be strictly necessary, but it means we don't need to synch synthetic property and
	// alloc-time access to globalObservations, it ensures no objects of the base class exist (they'll all
	// be the shadowed subclass, making debugging easier), and it's easier to get synthetic property registration
	// correct when done in +initialize.
	EBAssert(!classInfo->_allocHasHappened, @"Global synthetic properties for a class should all be set up "
			@"before you alloc instances of the class.");

	return classInfo;
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
+ (BOOL) ebn_swizzleImplementationForGetter:(LazyLoaderConstructionInfo *) constructionInfo
{
	@synchronized (EBNBaseClassToShadowInfoTable)
	{
		EBNShadowedClassInfo *classInfo = constructionInfo->_classInfo;
		
		// Check to see if the getter has been overridden in this class. If we've already swizzled, we're done.
		if ([classInfo->_getters containsObject:constructionInfo->_propertyName])
			return YES;
		
		// Next, check that we've calculated the the # of properties this class contains.
		NSInteger numProperties = classInfo->_validPropertyBitfieldSize;
		if (numProperties == NSNotFound)
		{
			numProperties = [self ebn_countOfAllProperties];
			classInfo->_validPropertyBitfieldSize = numProperties;
		}
		
		// We add the getter to the array even if this method ends up failing and unable to swizzle.
		// This prevents us from repeatedly attempting a swizzle that won't work.
		[classInfo->_getters addObject:constructionInfo->_propertyName];
		constructionInfo->_classToModify = classInfo->_shadowClass;

		// Get the index of the property. If the index is larger than the # of bits in the bitfield,
		// no point in swizzling as we can't record validity.
		constructionInfo->_propertyIndex = [classInfo->_getters indexOfObject:constructionInfo->_propertyName];
		if ((constructionInfo->_propertyIndex >= numProperties || constructionInfo->_propertyIndex == NSNotFound) &&
				!constructionInfo->_loader)
			return NO;
	}

	// Get the method selector for the getter on this property
	SEL getterSelector = ebn_selectorForPropertyGetter(constructionInfo->_classToModify, constructionInfo->_propertyName);
	EBAssert(getterSelector, @"Couldn't find getter method for property %@ in class %@",
			constructionInfo->_propertyName, constructionInfo->_classToModify);
	if (!getterSelector)
		return NO;
	
	// Then get the method we'd call for that selector. This is the method that this runtime subclass
	// would call, which may not be same as the method the non-runtime-created parent class would call.
	// It *is* the method that we should call through to.
	constructionInfo->_getterMethod = class_getInstanceMethod(constructionInfo->_classToModify, getterSelector);
	if (!constructionInfo->_getterMethod)
		return NO;
	
	// If there's a copyfrom property, get that property's getter selector as well
	if (constructionInfo->_copyFromPropertyName)
	{
		constructionInfo->_copyFromSEL = ebn_selectorForPropertyGetter(constructionInfo->_classToModify,
				constructionInfo->_copyFromPropertyName);
		EBAssert(constructionInfo->_copyFromSEL, @"Couldn't find getter method for property %@ in class %@",
				constructionInfo->_propertyName, constructionInfo->_classToModify);
		if (!constructionInfo->_copyFromSEL)
			return NO;
	}

	// Get the instance variable that backs the property, if one exists
	const char *propertyNameStr = [constructionInfo->_propertyName UTF8String];
	constructionInfo->_propInfo = class_getProperty(constructionInfo->_classToModify, propertyNameStr);
	if (constructionInfo->_propInfo)
	{
		const char *ivarNameStr = property_copyAttributeValue(constructionInfo->_propInfo, "V");
		if (ivarNameStr)
		{
			constructionInfo->_getterIvar = class_getInstanceVariable(constructionInfo->_classToModify, ivarNameStr);
			free((void *) ivarNameStr);
		}
	}

	char typeOfGetter[32];
	method_getReturnType(constructionInfo->_getterMethod, typeOfGetter, 32);

	// Types defined in runtime.h
	switch (typeOfGetter[0])
	{
	case _C_CHR:
		overrideGetterMethod<char>(constructionInfo);
	break;
	case _C_UCHR:
		overrideGetterMethod<unsigned char>(constructionInfo);
	break;
	case _C_SHT:
		overrideGetterMethod<short>(constructionInfo);
	break;
	case _C_USHT:
		overrideGetterMethod<unsigned short>(constructionInfo);
	break;
	case _C_INT:
		overrideGetterMethod<int>(constructionInfo);
	break;
	case _C_UINT:
		overrideGetterMethod<unsigned int>(constructionInfo);
	break;
	case _C_LNG:
		overrideGetterMethod<long>(constructionInfo);
	break;
	case _C_ULNG:
		overrideGetterMethod<unsigned long>(constructionInfo);
	break;
	case _C_LNG_LNG:
		overrideGetterMethod<long long>(constructionInfo);
	break;
	case _C_ULNG_LNG:
		overrideGetterMethod<unsigned long long>(constructionInfo);
	break;
	case _C_FLT:
		overrideGetterMethod<float>(constructionInfo);
	break;
	case _C_DBL:
		overrideGetterMethod<double>(constructionInfo);
	break;
	case _C_BFLD:
		// Pretty sure this can't happen, as bitfields can't be top-level and are only found inside structs/unions
		EBAssert(NO, @"Observable does not have a way to override the setter for %@.", constructionInfo->_propertyName);
	break;
	
		// From "Objective-C Runtime Programming Guide: Type Encodings" -- 'B' is "A C++ bool or a C99 _Bool"
	case _C_BOOL:
		overrideGetterMethod<bool>(constructionInfo);
	break;
	case _C_PTR:
	case _C_CHARPTR:
	case _C_ATOM:		// Apparently never generated? Only docs I can find say treat same as charptr
	case _C_ARY_B:
		overrideGetterMethod<void *>(constructionInfo);
	break;
	
	case _C_ID:
		overrideGetterMethod<id>(constructionInfo);
	break;
	case _C_CLASS:
		overrideGetterMethod<Class>(constructionInfo);
	break;
	case _C_SEL:
		overrideGetterMethod<SEL>(constructionInfo);
	break;

	case _C_STRUCT_B:
		if (!strncmp(typeOfGetter, @encode(NSRange), 32))
			overrideGetterMethod<NSRange>(constructionInfo);
		else if (!strncmp(typeOfGetter, @encode(CGPoint), 32))
			overrideGetterMethod<CGPoint>(constructionInfo);
		else if (!strncmp(typeOfGetter, @encode(CGRect), 32))
			overrideGetterMethod<CGRect>(constructionInfo);
		else if (!strncmp(typeOfGetter, @encode(CGSize), 32))
			overrideGetterMethod<CGSize>(constructionInfo);
		else if (!strncmp(typeOfGetter, @encode(UIEdgeInsets), 32))
			overrideGetterMethod<UIEdgeInsets>(constructionInfo);
		else
			EBAssert(NO, @"Observable does not have a way to override the setter for %@.", constructionInfo->_propertyName);
	break;
	
	case _C_UNION_B:
		// If you hit this assert, look at what we do above for structs, make something like that for
		// unions, and add your type to the if statement
		EBAssert(NO, @"Observable does not have a way to override the setter for %@.", constructionInfo->_propertyName);
	break;
	
	default:
		EBAssert(NO, @"Observable does not have a way to override the setter for %@.", constructionInfo->_propertyName);
	break;
	}
	
	return YES;
}

/****************************************************************************************************
	ebn_propertyNameAtIndex:
	
	The list of overridden getters in a ShadowedClassInfo object is in a NSOrderedSet, and this
	method gets the name of an overridden property at a given index in that set. This index matches
	the bit index into the currentlyVaidProperties bitfield that says whether this property is 
	currently valid or not.
*/
- (NSString *) ebn_propertyNameAtIndex:(NSInteger) index
{
	@synchronized (EBNBaseClassToShadowInfoTable)
	{
		if (class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
		{
			EBNShadowedClassInfo *info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
		
			if (info)
			{
				if (index >= [info->_getters count])
					return nil;
				return [info->_getters objectAtIndex:index];
			}
		}
	}
	
	return nil;
}

/****************************************************************************************************
	ebn_indexOfProperty:
	
	The list of overridden getters in a ShadowedClassInfo object is in a NSOrderedSet, and this
	method takes the name of an overridden property and returns its index in that set. This index matches
	the bit index into the currentlyVaidProperties bitfield that says whether this property is 
	currently valid or not.
*/
- (NSInteger) ebn_indexOfProperty:(NSString *) propName
{
	if (!class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
	{
		return NSNotFound;
	}
	
	@synchronized (EBNBaseClassToShadowInfoTable)
	{
		EBNShadowedClassInfo *info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
		if (info)
		{
			NSInteger index = [info->_getters indexOfObject:propName];
			if (index < info->_validPropertyBitfieldSize)
				return index;
		}
	}
	
	return NSNotFound;
}

/****************************************************************************************************
	ebn_currentlyValidProperties

	This is the base implementation of currentlyValidProperties, which is what gets called when someone
	asks for the ValidPropertiesStruct for an object that isn't swizzled (and therefore has no valid properties, 
	as it has no synthetic properties). 
	
	The method ebn_installAdditionalOverrides:, above, installs a block implmentation of this method for
	shadow classes which returns the ValidPropertiesStruct for the receiver.
 
	Returns nil for objects that aren't set up for lazy loading. If this implementation gets called, that's
	where we are.
*/
- (ValidPropertiesStruct *) ebn_currentlyValidProperties
{
	return nil;
}

/****************************************************************************************************
	ebn_markPropertyValid:
	
	Internal method to mark a property as being cached in its ivar, so that future accesses to 
	it will return the cached value.
	
	Call this method when you know the property's ivar has the correct value. This method doesn't
	get the correct value or put it in the ivar.
*/
- (void) ebn_markPropertyValid:(NSString *) property
{
	// Get the index of the property
	NSInteger propIndex = [self ebn_indexOfProperty:property];
	if (propIndex != NSNotFound)
	{
		ValidPropertiesStruct *validProperties = [self ebn_currentlyValidProperties];
		if (validProperties)
		{
			std::atomic_fetch_or(validProperties->propertyBitfield + propIndex / 32, 
					(uint32_t) (1 << (propIndex & 31)));
		}
	}
}

/****************************************************************************************************
	ebn_forcePropertyValid:
	
 	Forces the given property into its valid state. The method does this by calling the getter on the
	property.
	
	If speed is *really* an issue with this method, we could probably make a template to fix this.
*/
- (void) ebn_forcePropertyValid:(NSString *) property
{
	// Check whether this property is lazy-loaded; return directly if it isn't.
	NSInteger propIndex = [self ebn_indexOfProperty:property];
	if (propIndex == NSNotFound)
		return;
		
// These if 0 statements are here to be informative, not deadcode.
#if 0
	// Why not just do this? Because this throws an exception if the property's type can't be boxed
	// (selectors, function pointers, and several other types valid for properties). LazyLoader
	// ought to work correctly even for properties that aren't KVC compliant. Well, properties at the end
	// of a keypath, that is.
	[self ebn_valueForKey:property];
#endif
#if 0
	// Okay then, why not do this, and call the getter method directly via method lookup?
	// ARC chokes on this as the result of the getter method is dependent on the type of the property.
	Class selfClass = object_getClass(self);
	SEL getterSelector = ebn_selectorForPropertyGetter(selfClass, property);
    IMP getterMethod = class_getMethodImplementation(selfClass, getterSelector);
	((void (*)(id, SEL))getterMethod)(self, getterSelector);
#endif

	// Use NSInvocation to run the getter method.
	SEL getterSelector = ebn_selectorForPropertyGetter([self class], property);
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
	ebn_countOfAllProperties
	
	Determines how much space to allocate for the validity bitfield for objects of the receiving class.
	It does this by counting how many declared properties objects of this class will have, and
	rounding up ot the next multiple of 32.
	
	Ignoring classes that do special trickery, this should allow us to allocate enough bitfield space for
	all the properties that are lazy-loadable for the given class.
*/
+ (int) ebn_countOfAllProperties
{
	// Go count properties in our class and all our superclasses. This method of counting
	// will count a property overridden with a subclass property twice, but that's okay.
	// There's very unlikely to be a large number of those, and this is an estimate anyway.
	// We'd rather the estimate be high rather than low.
	//
	// Also, this loop usually counts superclasses from the actual class of an object up to NSObject.
	// This is an important distinction because actualClass could be someone else's subclass of the shadowed class we made,
	// and could have its own properties added.
	int numProperties = 0;
	Class curClass = self;
	while (curClass)
	{
		unsigned int propCount;
		objc_property_t *properties = class_copyPropertyList(curClass, &propCount);
		if (properties)
		{
			numProperties += propCount;
			free(properties);
		}
		
		curClass = class_getSuperclass(curClass);
	}
	
	// Round up to the next multiple of 32--no reason not to. Also disallow 0 properties.
	numProperties = (numProperties + 31) & ~31;
	if (numProperties == 0)
		numProperties = 32;
	
	return numProperties;
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
	if (!class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
		return nil;
	
	EBNShadowedClassInfo *info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
	if (!info)
		return nil;

	NSMutableSet *resultSet = [[NSMutableSet alloc] init];
	ValidPropertiesStruct *validProperties = self.ebn_currentlyValidProperties;

	for (NSUInteger longIndex = 0; longIndex < (info->_validPropertyBitfieldSize + 31) / 32; longIndex++)
	{
		uint32_t bitfield = validProperties->propertyBitfield[longIndex];
		for (int bitIndex = 0; bitIndex < 32; ++bitIndex)
		{
			if (bitfield & (1 << bitIndex))
			{
				[resultSet addObject:[self ebn_propertyNameAtIndex:longIndex * 32 + bitIndex]];
			}
		}
	}
	
	return [resultSet copy];
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
	if (!class_respondsToSelector(object_getClass(self), @selector(ebn_shadowClassInfo)))
		return nil;
	
	EBNShadowedClassInfo *info = [(NSObject<EBNObservable_Custom_Selectors> *) self ebn_shadowClassInfo];
	if (!info)
		return nil;

	NSMutableSet *invalidPropertySet = [[NSMutableSet alloc] init];
	
	// Debugger method, so we're avoiding the sync. This gets all the lazyloaded properties of the class.
	[invalidPropertySet unionSet:[info->_getters set]];
	
	// Now subtract out all the properties that are currently valid. What's left is the invalid properties.
	[invalidPropertySet minusSet:[self debug_validProperties]];
	
	return [invalidPropertySet copy];
}

/****************************************************************************************************
	debug_dumpAllObjectProperties
	
	This method is for debugging. If you're trying to use this method to implement some sort of
	validity introspection that invalidates/forces caching in some weird way you are probably 
	doing it wrong.
 
 	This method returns a string containing a list of all the properties of this object and
	its superclasses.

	To use, type in the debugger:
		po [<object> debug_dumpAllObjectProperties]
*/
- (NSString *) debug_dumpAllObjectProperties
{
	Class curClass = object_getClass(self);

	NSMutableString *resultString = [[NSMutableString alloc] initWithFormat:
			@"Dumping all properties of class %@\n", curClass];
	
	while (curClass)
	{
		unsigned int propCount;
		objc_property_t *properties = class_copyPropertyList(curClass, &propCount);
		if (properties)
		{
			for (int x = 0; x < propCount; ++x)
			{
				[resultString appendFormat:@"    Prop %d in class %@: %s\n", x, curClass,
						property_getName(properties[x])];
			}
		}
		
		curClass = [curClass superclass];
	}

	return resultString;
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
- (void) debug_forceAllPropertiesValid
{
	// For each invalid property go call valueForKeyPath:, which will force the property to get computed.
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

// This mutex forces ordered accesses to our private ivar getters and setters.
static pthread_mutex_t EBN_GetSetMutex = PTHREAD_MUTEX_INITIALIZER;

/****************************************************************************************************
	EBNGetIvar
	
	Inline template method, gets inlined into overrideGetterMethod.
	
	This method returns the value from the given ivar. Note that there's specializations for 
	object-valued properties.
	
	There are several specializations to this template method. Object-valued properties have a specialization
	for ARC that uses object_getIvar(). Primitive types that have naturally atomic loads and stores have 
	specializations for performace reasons (the lock is time consuming and not necessary).
*/
template<typename T> static inline T EBNGetIvar(NSObject *blockSelf, ptrdiff_t ivarOffset, Ivar getterIvar)
{
	// Yes--we need all 3 casts. 
	T *ivarPtr = (T *) (((char *) ((__bridge void *) blockSelf)) + ivarOffset);
	
	// For ivars that can't be read atomically (size is > 4), use the lock
	// NOTE: a smart compiler may be able to optimize away the if statement
	if (sizeof(T) > 4)
	{
		// Lock for threading, get the value from the ivar, unlock
		pthread_mutex_lock(&EBN_GetSetMutex);
		T localValue = *ivarPtr;
		pthread_mutex_unlock(&EBN_GetSetMutex);
		return localValue;
	}
	
	return *ivarPtr;
}
template<> inline id EBNGetIvar<id>(NSObject *blockSelf, ptrdiff_t ivarOffset, Ivar getterIvar)
{
	// object_getIvar handles threaded access issues internally.
	return object_getIvar(blockSelf, getterIvar);
}
template<> inline Class EBNGetIvar<Class>(NSObject *blockSelf, ptrdiff_t ivarOffset, Ivar getterIvar)
{
	return object_getIvar(blockSelf, getterIvar);
}

/****************************************************************************************************
	EBNSetIvar
	
	Inline template method, gets inlined into overrideGetterMethod.
	
	This method sets the given value into the given ivar. Note that there's a specialization for
	object-valued properties.
*/
template<typename T> static inline void EBNSetIvar(NSObject *blockSelf, ptrdiff_t ivarOffset,
		Ivar getterIvar, T value, BOOL isPrivate)
{
	// Get a pointer to the value we need to set. Yes we need all 3 casts.
	T *ivarPtr = (T *) (((char *) ((__bridge void *) blockSelf)) + ivarOffset);

	// For ivars that can't be written atomically (size is > 4), use the lock
	// NOTE: a smart compiler may be able to optimize away the if statement
	if (sizeof(T) > 4)
	{
		pthread_mutex_lock(&EBN_GetSetMutex);
		*ivarPtr = value;
		pthread_mutex_unlock(&EBN_GetSetMutex);
	}
	else
	{
		*ivarPtr = value;
	}
}

template<> inline void EBNSetIvar<id>(NSObject *blockSelf, ptrdiff_t ivarOffset,
		Ivar getterIvar, id value, BOOL isPrivate)
{
#ifndef __clang_analyzer__
	// As of iOS 9, object_setIvar assumes the ivar being set is unsafe_unretained, which is not what
	// we want. iOS 10 has a new object_setIvarWithStrongDefault() function, which we will want to use.
	// Until then, we're doing this madness to release the previous value and retain the new one.
	if (isPrivate)
	{
		void *outsideARC = (__bridge void *) object_getIvar(blockSelf, getterIvar);
		id object = (__bridge_transfer id) outsideARC;
		object = nil;
		void *newValueRetained = (__bridge_retained void *) value;
		value = (__bridge id) newValueRetained;
	}

	// object_setIvar handles threaded access issues internally.
	object_setIvar(blockSelf, getterIvar, value);
#endif
}

template<> inline void EBNSetIvar<Class>(NSObject *blockSelf, ptrdiff_t ivarOffset,
		Ivar getterIvar, Class value, BOOL isPrivate)
{
	object_setIvar(blockSelf, getterIvar, value);
}

/****************************************************************************************************
	EBNCallPropertyGetter
	
	Inline template method, gets inlined into overrideGetterMethod.
	
	For arguments of type id, calls the
	
	@param blockSelf		The receiver of the getter call.
	@param getterSEL		The selector for the getter method of the  property
	@param copyFromSEL		The selector for the getter method of the copyfrom property, can be nil
*/
template<typename T> static inline T EBNCallPropertyGetter(NSObject *blockSelf, T (*originalGetter)(id, SEL),
		SEL getterSEL, SEL copyFromSEL)
{
	// Call the original getter to get the value of the property.
	return (originalGetter)(blockSelf, getterSEL);
}

/// For the 'id' template specialization, we check to see if the copyFromSEL is non-nil, and if so,
/// use it to get a value from another property and return a copy of it (by calling copy on the property value)
template<> inline id EBNCallPropertyGetter<id>(NSObject *blockSelf, id (*originalGetter)(id, SEL),
		SEL getterSEL, SEL copyFromSEL)
{
	if (copyFromSEL)
	{
		// If we're supposed to get the value by copying it from another property, this is where we
		// do so. Do this instead of calling the original getter method.
		//
		// Implementation note: Calling copy on the value of another property in this way isn't thread safe.
		// But, it's as thread safe as having a custom getter that does the copy (and doesn't use Observable/
		// LazyLoader at all). The difficulty is that if you *need* to be thread safe there's no good way to
		// add it here. However, you don't need to use the publicCollection:copiesFromPrivateCollection: method.
		// It's an easy way to do what can be done with a synthetic property and a custom getter.
		id (*copyFromPropertyGetter)(id, SEL) = (id (*)(id, SEL))
				[object_getClass(blockSelf) instanceMethodForSelector:copyFromSEL];
		return [(copyFromPropertyGetter)(blockSelf, copyFromSEL) copy];
	}
	else
	{
		// Call the original getter to get the value of the property.
		return (originalGetter)(blockSelf, getterSEL);
	}
}

/****************************************************************************************************
	EBNPrivateIvarObjectFixer
	
	This is an empty template with a non-empty specialization for 'id' objects.
	
	Its purpose is to get stuck into the overrideGetterMethod() template below, so that when we 
	add private iVars to back object properties (which only happens when the prop doesn't have a backing
	ivar of its own) we record that we did it in the classInfo's objectGettersWithPrivateStorage set.
*/
template<typename T> static inline void EBNPrivateIvarObjectFixer(LazyLoaderConstructionInfo *constructionInfo) { }
template<> inline void EBNPrivateIvarObjectFixer<id>(LazyLoaderConstructionInfo *constructionInfo)
{
	NSMutableSet *privateObjectIvars = constructionInfo->_classInfo->_objectGettersWithPrivateStorage;
	if (!privateObjectIvars)
	{
		privateObjectIvars = [NSMutableSet set];
		constructionInfo->_classInfo->_objectGettersWithPrivateStorage = privateObjectIvars;
	}
	[privateObjectIvars addObject:constructionInfo->_propertyName];
}


/****************************************************************************************************
	template <T> overrideGetterMethod()
	
	Overrides the given getter method with a new method (actually a block with implementationWithBlock()
	used on it) that checks whether the property value cached in the ivar backing the property is
	valid, and if so returns that. 
	
	If it isn't valid, we call the original getter method to compute the proper value, and cache that
	value in the ivar.
*/
template<typename T> void overrideGetterMethod(LazyLoaderConstructionInfo *constructionInfo)
{
	// If we couldn't find an ivar backing this getter, time to make one.
	// Note that this happens BEFORE class registration.
	BOOL myOwnPrivateIvar = NO;
	if (!constructionInfo->_getterIvar && constructionInfo->_propInfo)
	{
		const char *propTypeStr = property_copyAttributeValue(constructionInfo->_propInfo, "T");
		if (propTypeStr)
		{
			// use class_addIvar to put the ivar in the class. This code is here in the template so that
			// we have acesss to the size of the ivar to create.
			const char *propNameStr = [constructionInfo->_propertyName UTF8String];
			myOwnPrivateIvar = class_addIvar(constructionInfo->_classToModify, 
					propNameStr, sizeof(T), log2(sizeof(T)), propTypeStr);
			free((void *) propTypeStr);
			
			if (myOwnPrivateIvar)
			{
				EBNPrivateIvarObjectFixer<T>(constructionInfo);
			}
		}
	}

	// If we have a custom loader, get its IMP so we can use it in the block. We also maintain
	// a set of which threads are inside calls to the loader method, to disallow recursion while
	// allowing multithreaded access. As it says in the header, "Mutex guards around resources are
	// the loader's problem."
	void (*loaderFunc)(id, SEL, NSString *) = nil;
	uint32_t blockCreationIndex = 0;
	if (constructionInfo->_loader)
	{
		blockCreationIndex = sBlockCreationIndex;
		sBlockCreationIndex++;
		IMP loaderIMP = [constructionInfo->_classToModify instanceMethodForSelector:constructionInfo->_loader];
		loaderFunc = (void (*)(id, SEL, NSString *)) loaderIMP;
	}
	uint32_t longBitMask = 1 << (blockCreationIndex & 31);
	
	// Set up variables to be copied into the block
	// All of these local variables get copied into the setAndObserve block
	T (*originalGetter)(id, SEL) = (T (*)(id, SEL)) method_getImplementation(constructionInfo->_getterMethod);
	SEL getterSEL = method_getName(constructionInfo->_getterMethod);
	NSInteger propertyIndex = constructionInfo->_propertyIndex;
	SEL loader = constructionInfo->_loader;
	NSString *propName = constructionInfo->_propertyName;
	SEL copyFromSEL = constructionInfo->_copyFromSEL;

	__block Ivar getterIvar = constructionInfo->_getterIvar;
	__block ptrdiff_t ivarOffset = 0;
	if (getterIvar)
	{
		ivarOffset = ivar_getOffset(getterIvar);
	}

	// This is what gets run when the getter method gets called.
	T (^getLazily)(NSObject *) = ^ T (NSObject *blockSelf)
	{
		// ivar_getOffset gets called during setIvar, and was causing a crash. I think the cause is calling
		// class_getInstanceVariable after ivar creation but before class_registerClass.
		// So, get the getterIvar here if necessary. Should only get called once per override.
		if (!getterIvar)
		{
			const char *propNameStr = [propName UTF8String];
			getterIvar = class_getInstanceVariable(object_getClass(blockSelf), propNameStr);
			ivarOffset = ivar_getOffset(getterIvar);

			EBCAssert(getterIvar, @"No instance variable found to back property %@.", propName);
		}

		// Check whether the property is valid. We are not synchronizing on currentlyValidProperties
		// here because it shouldn't be necessary.
		ValidPropertiesStruct *validProperties = blockSelf.ebn_currentlyValidProperties;
		
		// If the property is valid, just get the ivar and return it--we're done.
		if (propertyIndex != NSNotFound &&
				(validProperties->propertyBitfield[propertyIndex / 32] & (1 << (propertyIndex & 31))) != 0)
		{
			return EBNGetIvar<T>(blockSelf, ivarOffset, getterIvar);
		}
		
		// The optional loader method is called with a property name and is responsible for
		// 'loading' the value of that property--generally making it so the getter will
		// return the right value. Useful for cases where properties are actually stored in
		// dictionaries and fronted with property names.
		if (loaderFunc)
		{
			// Check if this thread is already loading this property. The intent is to disallow recursive loading,
			// while allowing different theads to load concurrently. This recursion check is:
			//		• Per Thread
			//		• Per Getter We've Overridden
			// It is *not* per object. If a loader func for Object A gets a property from Object B (of the same class)
			// the property loader for B will be bypassed due to this recursion check.
			NSMutableDictionary *threadDict = [[NSThread currentThread ]threadDictionary];
			if (threadDict)
			{
				// Each thread gets one of these mutableDatas in their thread dict. Create it if it's not there.
				NSMutableData *insideLoaderData = [threadDict objectForKey:@"EBNLazyLoader_IsInsideLoaderFunc"];
				if (!insideLoaderData)
				{
					insideLoaderData = [[NSMutableData alloc] initWithLength:((sBlockCreationIndex + 31) / 32) * 8];
					[threadDict setObject:insideLoaderData forKey:@"EBNLazyLoader_IsInsideLoaderFunc"];
				}
				
				// If the insideLoaderData for this thread isn't big enough, expand it so that it is.
				if (insideLoaderData.length * 8 < blockCreationIndex)
				{
					insideLoaderData.length = ((sBlockCreationIndex + 31) / 32) * 8;
				}
				
				// If our bit is already set, the loader is calling itself recursively; prevent this
				uint32_t *bitfieldLong = ((uint32_t *) [insideLoaderData mutableBytes]) + blockCreationIndex / 32;
				if (!(*bitfieldLong & longBitMask))
				{
					@try
					{
						*bitfieldLong |= longBitMask;
					
						// Call the loader. Even if the loader throws we've got to remove ourselves from
						// the performingLoads set, else we will break property access in this thread.
						loaderFunc(blockSelf, loader, propName);
					}
					@finally
					{
						// Other threads can't mutate our thread's insideLoaderData, but recursion can
						bitfieldLong = ((uint32_t *) [insideLoaderData mutableBytes]) + blockCreationIndex / 32;
						*bitfieldLong &= ~longBitMask;
					}
				}
				else
				{
					// You got here because we're trying to prevent infinite recursion. But, this means that we
					// have to return old/invalid values for this property--only for the result of the inner call.
					// Hence this log notice.
					EBLogContext(kLoggingContextOther, @"The property loader (%@) for class %@ and property %@ "
							@"is calling itself recursively.",
							NSStringFromSelector(loader), [blockSelf class], propName);
				}
			}
		}
		
		// Get the new value from the original getter, and set the ivar
		// Both the getter and ivar setter are inline template expansions with specializations.
		// The getter takes value as a parameter so that template expansion works correctly; the param is unused.
		T value = EBNCallPropertyGetter<T>(blockSelf, originalGetter, getterSEL, copyFromSEL);
		if (myOwnPrivateIvar || copyFromSEL)
		{
			EBNSetIvar(blockSelf, ivarOffset, getterIvar, value, myOwnPrivateIvar);
		}

		// If both the bitfield of valid properties is valid and our index into it is valid,
		// mark this property as being valid (we just called the getter and set the ivar, so we're all ready
		// to start returning the ivar directly on future calls).
		if (validProperties && propertyIndex != NSNotFound)
		{
			std::atomic_fetch_or(validProperties->propertyBitfield + propertyIndex / 32, (uint32_t) (1 << (propertyIndex & 31)));
		}
		return value;
	};

	// Now replace the getter's implementation with the new one
	IMP swizzledImplementation = imp_implementationWithBlock(getLazily);
	class_replaceMethod(constructionInfo->_classToModify, getterSEL, swizzledImplementation,
			method_getTypeEncoding(constructionInfo->_getterMethod));
}

@end


