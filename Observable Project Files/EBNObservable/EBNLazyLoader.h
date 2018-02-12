/****************************************************************************************************
	EBNLazyLoader.h
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

	
	
	To use, you declare a property to be synthetic once (usually in the init method);
	and write a normal getter method that calculates the property's value. That property will then
	evaluate the getter once, and then cache the result until one of the invalidation methods is called
	to force the cached result to be discarded.
	
	You can also declare properties for whom changes will force invalidation of the lazily loaded property.
	This automates the invalidation of those properties whenever the source properties change value.
	The classic example of this is making a fullName property recalculate its value when firstName or lastName
	change value.
	
	So in your init method:
		 SyntheticProperty(fullName);
	and you have made fullName into a synthetic property that only calls the getter to compute the property
	value when the property's cached value is invalid. Use the Invalidate methods to declare when
	properties become invalid.
	
	Or, also in your init method:
		SyntheticProperty(fullName, firstName, lastName);
	and you have made fullName into a synthetic property whose value depends on firstName and lastName.
	FullName will automatically invalidate itself (and recompute the next time its value is requested) when
	either firstName or lastName changes. No need to call an Invalidate method (although you still can do so).

	Making your synthetic properties LazyLoaded can provide a performance improvement; the more complicated
	the getter, the better. However, the real benefits of this class are:
		- a system of handling mass property invalidation,
		- a way to specify value dependencies, so that changing a source property invalidates dependent 
		  properties automatically,
		- a way to make synthetic properties that can be observed correctly.
*/

#import "EBNObservable.h"

#pragma mark Convenience Macros

/**
	This declares its first argument to be a lazy-loading synthetic property, and other
	arguments (if given) are dependent properties.
	
	Performs property validation of the arguments.

	@return void
 */
#define SyntheticProperty(className, ...) \
({ \
	if (0) \
	{ \
		className *__internalObserved; \
		EBNValidatePathsInternal(__VA_ARGS__)(__VA_ARGS__) \
	} \
	[self syntheticProperty_MACRO_USE_ONLY:@#__VA_ARGS__]; \
})

/**
	Call this macro to invalidate a synthetic property's value. This macro just provides
	property name validation. References 'self' from within the macro.

	@param propertyName The name of the property that is no longer valid and must be recalculated

	@return void
 */
#define InvalidatePropertyValue(propertyName) \
({ \
	EBNValidatePaths(self, propertyName); \
	[self invalidatePropertyValue:EBNStringify(propertyName)]; \
})
	// The loader block is an optional way to load properties. We use the term 'loading' because it's
	// not a getter--it doesn't return the value. It's not a setter--that's where the caller sets the value.
	// The loader's job is to determine the correct value for the property and set it.




#pragma mark - EBNLazyLoader Category

@interface NSObject (EBNLazyLoader)


/**
	Declares a synthetic property. Must be a property of the receiver. This property will cache the result
	from its getter method, only recalculating its value after one of the invalidate methods is called.

	@param property The property to make synthetic.
 */
+ (void) syntheticProperty:(nonnull NSString *) property;

/**
	Declares a synthetic property. Must be a property of the receiver. This property will cache the result
	from its getter method, only recalculating its value after one of the invalidate methods is called.
	
	This property will automatically invalidate its value whenever the value in keyPath changes.

	@param property The proprety to make synthetic
	@param keyPathString  A path to a value that is used to determine the value of property. Path must be rooted at self.
 */
+ (void) syntheticProperty:(nonnull NSString *) property dependsOn:(nullable NSString *) keyPathString;

/**
	Declares a synthetic property. Must be a property of the receiver. This property will cache the result
	from its getter method, only recalculating its value after one of the invalidate methods is called.

	This property will automatically invalidate its value whenever the value of any of the keyPaths change.

	@param property The proprety to make synthetic
	@param keyPaths  An array of keypaths. Paths must be rooted at the receiver.
 */
+ (void) syntheticProperty:(nonnull NSString *) property dependsOnPaths:(nonnull NSArray *) keyPaths;

/**
	Declares a synthetic property. Must be a property of the receiver. This property will cache the result
	from its loader method, only recalculating its value after one of the invalidate methods is called.

	The loader is like a getter, but is a custom selector that takes the name of the property it needs to 
	load. Useful for making an object with a property-style API where the property values are backed by
	a dictionary or other collection object. In this way you can write a single loader method instead of
	a large number of custom getters.

	The loader argument has the form:
	
		- (void) loader:(NSString *) propertyName
	
	@note The loader method can get called whenever the getter might get called and LazyLoader
	doesn't serialize access to the loader method. Mutex guards around resources are the loader's problem.
	(same idea as when you write a custom getter or setter method).
	
	@param property The property to make synthetic
	@param loader   A selector
 */
+ (void) syntheticProperty:(nonnull NSString *) property withLazyLoaderMethod:(nullable SEL) loader;

/**
	The SyntheticProperty() macro calls this method from within the macro. This method takes the property
	to be made synthetic and any dependent paths as a single comma-separated string, because of how 
	variadic marco arguments work.
	
	This method needs to exist because the SyntheticProperty() macro can't organize its argument list in such
	a way that it can call syntheticProperty:dependsOnPaths:. But you can, and you should.
*/
+ (void) syntheticProperty_MACRO_USE_ONLY:(nonnull NSString *) propertyAndPaths;


/**
	Declares a public non-mutable collection object to be a lazily loaded copy of a private mutable collection.
	
	If your class needs to expose an array as part of its API, and your object needs to modify the array internally,
	it's safer if you make a NSArray public property with a custom getter that copies an internal NSMutableArray.
	However, this breaks observation and produces new copies each time the array is accessed.
	
	Instead, you can use this method to bind the public and private properties. Put this method in your init,
	listing the public and private collection properties (must be NSSet, NSDictionary, or NSArray for the moment).
	
	Mutating the private property will cause the public property to be invalidated. Accessing the public property
	will cause the value to be copied and stored in the property's ivar. The copy occurs at most once per mutation
	of the private property. Additionally, the public property can be observed, and will get updated/notified 
	whenever the private property mutates.
	
	Important note: This cannot be turned on for some instances of a class and not others. Due to how it works,
	it's partially global and partially per-instance. So, if you're going to use this in your class, make sure
	it's on in all your classes' designated initializers.
	
	Important note 2: This method doesn't work when you need to synchronize access to the mutable collection;
	luckily this method is a convenience for an observation you can roll yourself. Your observation block
	can then do whatever thread synchroniztion is necessary.
	
	@param publicPropertyName		The name of the publically visible, immutable collection property
	@param copyFromProperty			The name of the private, mutable collection property
	
*/
+ (void) publicCollection:(nonnull NSString *) publicPropertyName copiesFromPrivateCollection:(nonnull NSString *) copyFromProperty;


/**
	Markes the given property invalid, meaning that its value will be recalculated (the getter or loader method
	will be called) the next time its value is requested.

	@param property The property to invalidate
 */
- (void) invalidatePropertyValue:(nonnull NSString *) property;

/**
	Mass-invalidates propeties.

	@param properties A set of properties to invalidate.
 */
- (void) invalidatePropertyValues:(nonnull NSSet *) properties;

/**
	Invalidates all of the synthetic properties of the receiver.
 */
- (void) invalidateAllSyntheticProperties;

/**
	TRUE if the receiver has at least one synthetic property that is currently marked valid.
	FALSE if all properties are invalid, or if no properties are synthetic.
*/
- (BOOL) ebn_hasValidProperties;


@end


#pragma mark - Debugging Support

@interface NSObject (EBNLazyLoaderDebugging)

/**
	For debugging only, shows the set of currently valid properties. Don't use this for production code.

	@return A NSSet of valid properties
 */
- (nullable NSSet *) debug_validProperties;

/**
	For debugging only, shows the set of currently invalid properties. Don't use this for production code.

	@return A NSSet of invalid properties
 */
- (nullable NSSet *) debug_invalidProperties;

/**
	This method is for debugging. If you're trying to use this method to implement some sort of
	validity introspection that invalidates/forces caching in some weird way you are probably 
	doing it wrong.
	
	Calls the getter for each property whose value isn't currently valid, which makes the value valid.
	
	You will need to click on another stack frame and back to force lldb to reload values in the variable
	display pane after calling this.

	To use, type in the debugger:
		po [<object> debug_forceAllPropertiesValid]
	
 */
- (void) debug_forceAllPropertiesValid;

@end


