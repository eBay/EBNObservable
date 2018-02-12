/****************************************************************************************************
	EBNObservableInternal.h
	Observable
	
	Created by Chall Fry on 5/3/14.
    Copyright (c) 2013-2018 eBay Software Foundation.
	
	This header is intended for use only within EBNObservable and friends. 
	Client code shouldn't need it; this includes EBNObservable subclasses.
*/

#import "EBNDebugUtilities.h"
#import "EBNObservable.h"

#if defined(__cplusplus) || defined(c_plusplus)
	extern "C" {
#endif

/**
	Used to track the shadow classes we create. Shadow classes are private subclasses of observed classes,
	and we isa swizzle the observed object to make it be one of these private subclasses. This dictionary
	maps base classes to EBNShadowClassInfo objects.
 */
extern NSMapTable				*EBNBaseClassToShadowInfoTable;

/**
	Used as a private, global @synchronize token for EBNObservable. Your code should not sync against this.
	Currently points to EBN_ObserverBlocksToRunAfterThisEvent, but *could* point to any global object.
*/
extern NSMutableSet				*EBNObservableSynchronizationToken;

/**
	These keep track of the blocks that we need to execute at the end of the current runloop. The *beingDrained
	variants are for blocks added to the list while we're in the process of executing the blocks.
*/
extern NSMutableSet				*EBN_ObserverBlocksToRunAfterThisEvent;
extern NSMutableSet				*EBN_ObserverBlocksBeingDrained;
extern NSMutableArray			*EBN_ObservedObjectKeepAlive;
extern NSMutableArray 			*EBN_ObservedObjectBeingDrainedKeepAlive;

#pragma mark - EBNShadowedClassInfo

/**
	Observable keeps a static dictionary that maps Class objects to these info objects. There is one of these created
	for each shadowed class. This object is then responsible for tracking the overridden getters and setters that have
	been created for this class.
*/
@interface EBNShadowedClassInfo : NSObject
{
@public
	Class					_baseClass;			// Objects originally of this class...
	Class					_shadowClass;		// ...get isa-swizzled to this class...
	BOOL					_isAppleKVOClass;	// ...unless Apple's KVO has already isa-swizzled. In that case,
												// we method-swizzle methods in the Apple KVO-created subclass.

	BOOL					_collectionSwizzlesDone; // TRUE if this is a collection class and we've swizzled
													 // the right methods

		// Note that these contain property names, NOT method names!
	NSMutableOrderedSet		*_getters;			// All the properties that have had their getters wrapped.
	NSMutableSet 			*_setters;			// All the properties that have had their setters wrapped.
	
		// iOS9 has an issue with object_setIvar() in that it assumes the ivar is unsafe_unretained, if the ivar
		// is object-valued and we created the ivar ourselves with class_addIvar(). This is a list of all properties
		// where this case happened; we clean these up during dealloc.
	NSMutableSet			*_objectGettersWithPrivateStorage;
	
	NSMutableArray			*_globalObservations;	// Observations to copy into all instances of this class
													// Cannot be mutated after +initialize time.

	BOOL					_allocHasHappened;		// TRUE once our overridden alloc has been called for this
													// class. Used to ensure no global lazyloads are set up
													// once alloc is called.

	NSInteger				_validPropertyBitfieldSize;	// Size in bits of the valid properties bitfield--
														// therefore, the number of properties we can lazyload.
														// NSNotFound until initially determined.
}

	/// An internal initializer used to create EBNShadowedClassInfo objects
- (instancetype) initWithBaseClass:(Class) baseClass shadowClass:(Class) newShadowClass;

@end

#pragma mark - EBNKeypathEntryInfo
/**
	This structure manages internal bookeeping for a single keypath someone is observing.
	Each object in the observation path has this object in the dictionary for the property of that 
	object being observed.
	
	The ebn_observedKeysDict: dictionary (stored in an associated object for something being observed) maps
	property names to NSMutableArrays of these objects.
	
	This object uses ivars instead of properties for a reason--I don't want for it to be possible to observe on
	the internal mechanics of observation itself.
 */
@interface EBNKeypathEntryInfo : NSObject <NSCopying>
{
@public
	EBNObservation			*_blockInfo;
	NSArray		 			*_keyPath;
	NSInteger				_keyPathIndex;
}

/**
	This is used as we're traversing the objects in a keypath to update the keypath's conents. The
	KeyPathEntryInfo object for item N in the keypath determines the previous and current values for
	the next property in the keypath, and calls this method so that item N + 1 in the keypath can remove
	observations on fromObj and start observing on toObj (either of which may be nil).
*/
- (BOOL) ebn_updateNextKeypathEntryFrom:(id) fromObj to:(id) toObj;

/**
	This is used to start the process of updating a keypath. Pass in the index of the first item that needs
	updating.
*/
- (BOOL) ebn_updateKeypathAtIndex:(NSInteger) index from:(id) fromObj to:(id) toObj;

- (BOOL) ebn_comparePropertyAtIndex:(NSInteger) index from:(id) prevPropValue to:(id) newPropValue;

/**
	In certain cases Observable needs to stop an observation entirely, and it determines this while looking
	at an item in the middle of the keypath. removeObservation will get the root object of the observation
	and stop observing on that, removing all the keypath entries along the keypath.
*/
- (BOOL) ebn_removeObservation;

@end


#pragma mark - EBNObservation
/**
	An internal category for EBNObservation objects. This category contains the ivars for the
	observed and observer pointers, and the observationBlock pointers for this observation.
	Note that this class also has public properties.
	
	This describes a single observation block. There is one of these for each observationBlock,
	and much of the coalescing of change notifications is actually unioning sets of these objects.
	Note that this object does *not* know the keypath(s) that it's observing--KeypathEntryInfo does that.
*/
@interface EBNObservation ()
{

// @public doesn't mean public to you--just to EBNObservable.
@public
	NSObject * __weak 		_weakObserved;
	
		// WeakObserver and its forComparisonOnly doppelganger should hold the same value; we have
		// both values so that we can compare an observation object's observer against the observer pointer
		// when the observer object is in the process of getting dealloced (generally, the observer's
		// dealloc method calls stopTellingAboutChanges: is how this happens). Zeroing weak refs will
		// return nil when the object pointed to is being deallocated, as they call objc_loadWeak().
		// The debugger, moreover, will show a non-nil value for the pointer to the being-dealloced object.
	id __weak 				_weakObserver;
	id __unsafe_unretained	_weakObserver_forComparisonOnly;
	
	
	ObservationBlock 		_copiedBlock;
	ObservationBlock		_copiedImmedBlock;

}

+ (BOOL) scheduleBlocks:(NSArray<EBNKeypathEntryInfo *> *) blocks;

@end

#pragma mark - EBNObservable_Custom_Selectors
/**
	These are runtime-generated methods that we install on shadow classes with class_addMethod().
	Having these selectors in a protocol makes the compiler happy (well, happier, at least).
 */
@protocol EBNObservable_Custom_Selectors

@optional
- (void) ebn_original_dealloc;
- (EBNShadowedClassInfo *) ebn_shadowClassInfo;

@end


/**
	This is an category on NSObject whose definition and use are internal to Observable. It simply
	declares NSObject objects to conform to the EBNObservable_Internal protocol. Since the protocol
	definition itself is private to Observable, it's still private.
	
	These are all methods that the Observable code calls on itself to get things done, but which
	shouldn't be called from outside Observable. All these methods have the ebn_ prefix to 
	reduce the chance they'll cause method namespace collisions.
*/
@interface NSObject (EBNObservable_Internal)

/**
	This is how Observable gets at the list of methods that are being observed.
	
	The returned dictionary is keyed on the properties currently being observed, and each key's value is a set
	of all the observations active on that property.

	@return A dictionary containing sub-dictionaries for each method which has an active observation.
 */
- (NSMutableDictionary *) ebn_observedKeysDict:(BOOL) createIfNil;

	// When setting up an observation, or when an object in the middle of a keypath changes value, these
	// methods are used to set up observations on each object in the key path except for the endoint property.
	// That is, for an observation rooted on object A with the keypath "B.C.D", A will set up its local observation
	// on property B, and then call createKeypath: on object B. B will then do the same, calling object C.
- (BOOL) ebn_observe:(NSString *) keyPathString using:(EBNObservation *) blockInfo;
- (void) ebn_addEntry:(EBNKeypathEntryInfo *) entryInfo forProperty:(NSString *) propName;
- (EBNKeypathEntryInfo *) ebn_removeEntry:(EBNKeypathEntryInfo *) entryInfo atIndex:(NSInteger) pathIndex
		forProperty:(NSString *) propName;


/**
	Creates a new Objective C class at runtime so that instances of the given baseClass that we want to observe
	can be isa-swizzled to the new runtime-created class (herein called a shadow class) and their observed properties
	can be overridden with observing wrappers in the shadow class.
	
	@param baseClass the 'visible to Cocoa' class. The result of [self class].
	@param actualClass the actual class we are subclassing. Be sure to use object_getClass, NOT [self class].
	@return An EBNShadowedClassInfo object with info about the new shadow class.
	
	baseClass and actualClass are usually the same, but not always.
*/
+ (EBNShadowedClassInfo *) ebn_createShadowedSubclass:(Class) baseClass actualClass:(Class) actualClass
		additionalOverrides:(BOOL) additionalOverrides;

/**
	valueForKey: does odd things with collections. This method works like valueForKey, except it
	gets overridden by the observable collection classes so that EBNObservableArray can work with 
	keypaths like "array.5".

	@param key The key to evaluate

	@return The value for the given key, as an objecgt
*/
- (id) ebn_valueForKey:(NSString *)key;


/**
	The Execute methods in EBNObservation can cause reaping, so Observable's reapBlocks is exposed 
	here for Observation's use.

	@return number of dead observations that got removed.
 */
- (int) ebn_reapBlocks;

/**
	Marks the given property as being valid. LazyLoader uses this to keep track of which synthetic
	properties have valid values. This method does not actually cause the synthetic property to compute its value.

	@param property The property to mark as valid.
 */
- (void) ebn_markPropertyValid:(NSString *) property;

/**
	Returns a set of all properties of self, as an array of strings.
*/
- (NSSet *) ebn_allProperties;

/**
	Forces the given (synthetic) property getter to evaluate its value. The method does this by
	calling the getter on the property.

	@param property The property to force to become valid.
*/
- (void) ebn_forcePropertyValid:(NSString *) property;


	// Don't call these methods unless you have a good reason.
- (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName;
+ (BOOL) ebn_swizzleImplementationForSetter:(NSString *) propName info:(EBNShadowedClassInfo *) info;
- (EBNShadowedClassInfo *) ebn_prepareObjectForObservation;

+ (void) ebn_installAdditionalOverrides:(EBNShadowedClassInfo *) info actualClass:(Class) actualClass;

+ (BOOL) ebn_compareKeypathValues:(EBNKeypathEntryInfo *) info atIndex:(NSInteger) index from:(id) fromObj to:(id) toObj;

@end


/// This function dumps all methods that have been set up for observation in all classes
NSString *ebn_debug_DumpAllObservedMethods(void);

// Utility functions for finding property getters and setter selectors
SEL ebn_selectorForPropertyGetter(Class baseClass, NSString * propertyName);
SEL ebn_selectorForPropertySetter(Class baseClass, NSString * propertyName);

/**
	Returns YES if this is a DEBUG build and there is a debugger attached. Will always return NO on
	other build types, even if there IS a debugger attached. 
	
	This function checks for the existence of a debugger using a method marked ustable by Apple. The code
	to make this check doesn't even get compiled into non-DEBUG builds, so we don't risk app rejection.
*/
BOOL EBNIsADebuggerConnected(void);


/****************************************************************************************************
	DEBUG_BREAKPOINT
	
	This is inline ASM code to programmatically break in the debugger at a specific point. Intended
	to be used with Apple's AmIBeingDebugged() method. Works on ARM and x86 processors, and their 64
	bit variants.
	
	DO NOT use this macro in your code to try debugging something. You'll forget, leave it there,
	and then your code will ship with a debugger break in it and will crash for no reason for your users.
	
	At some point, years from now, someone is going to have to have to extend this to a new target CPU type.
	Sorry.
*/
#if TARGET_CPU_ARM
	#define DEBUG_BREAKPOINT \
	({ \
		__asm__ __volatile__ ( \
				"mov r0, %0\n" \
				"mov r1, %1\n" \
				"mov r12, #37\n" \
				"svc 128\n" \
				: : "r" (getpid ()), "r" (SIGINT) : "r12", "r0", "r1", "cc"); \
	})
#elif TARGET_CPU_ARM64
	#define DEBUG_BREAKPOINT \
	({ \
		__asm__ __volatile__ ( \
				"mov x0, %0\n" \
				"mov x1, %1\n" \
				"mov x12, #37\n" \
				"svc 128\n" \
				: : "r" ((long) getpid ()), "r" ((long) SIGINT) : "x12", "x0", "x1", "cc"); \
	})
#elif TARGET_CPU_X86
	#define DEBUG_BREAKPOINT \
	({ \
		__asm__ __volatile__ ( \
				"pushl %0\n" \
				"pushl %1\n" \
				"push $0\n" \
				"movl %2, %%eax\n" \
				"int $0x80\n" \
				"add $12, %%esp" \
				: : "g" (SIGINT), "g" (getpid ()), "n" (37) : "eax", "cc"); \
	})
#elif TARGET_CPU_X86_64
	#define DEBUG_BREAKPOINT \
	({ \
		__asm__ __volatile__ ( \
				"int $3" \
				: : : "cc"); \
	})
#else
	// Can't break. Unknown cpu target.
	#define DEBUG_BREAKPOINT
#endif


#if defined(__cplusplus) || defined(c_plusplus)
	}
#endif

