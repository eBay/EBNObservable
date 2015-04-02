/****************************************************************************************************
	EBNLazyLoader.h
	Observable
	
	Created by Chall Fry on 4/29/14.
	Copyright (c) 2013-2014 eBay Software Foundation.
	
	LazyLoader is a class that makes it easier to create synthetic properties whose value is calculated
	from other property values. You declare a property to be synthetic once (usually in the init method);
	and write a normal getter method that calculates the property's value. That property will then
	evaluate the getter once, and then cache the result until one of the invalidation methods is called
	to force the cached result to be discarded.
	
	You can also declare properties for whom changes will force invalidation of the lazily loaded property.
	This automates the invalidation of those properties whenever the source properties change value.
	The classic example of this is making a fullName property recalculate its value when firstName or lastName
	change value.
*/

#import "EBNObservable.h"

#pragma mark Convenience Macros

/**
	This declares its first argument to be a lazy-loading synthetic property, and other
	arguments (if given) are dependent properties. References 'self' from within the macro.
	
	Performs property validation of the arguments.

	@return void
 */
#define SyntheticProperty(...) \
({ \
	EBNValidateProperties(__VA_ARGS__)(__VA_ARGS__) \
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
	ValidateProperty(propertyName); \
	[self invalidatePropertyValue:EBNStringify(propertyName)]; \
})
	// The loader block is an optional way to load properties. We use the term 'loading' because it's
	// not a getter--it doesn't return the value. It's not a setter--that's where the caller sets the value.
	// The loader's job is to determine the correct value for the property and set it.




#pragma mark EBNLazyLoader class

@interface EBNLazyLoader : EBNObservable

/**
	Declares a synthetic property. Must be a property of the receiver. This property will cache the result
	from its getter method, only recalculating its value after one of the invalidate methods is called.

	@param property The property to make synthetic.
 */
- (void) syntheticProperty:(NSString *) property;

/**
	Declares a synthetic property. Must be a property of the receiver. This property will cache the result
	from its getter method, only recalculating its value after one of the invalidate methods is called.
	
	This property will automatically invalidate its value whenever the value in keyPath changes.

	@param property The proprety to make synthetic
	@param keyPath  A path to a value that is used to determine the value of property. Path must be rooted at self.
 */
- (void) syntheticProperty:(NSString *) property dependsOn:(NSString *) keyPath;

/**
	Declares a synthetic property. Must be a property of the receiver. This property will cache the result
	from its getter method, only recalculating its value after one of the invalidate methods is called.

	This property will automatically invalidate its value whenever the value of any of the keyPaths change.

	@param property The proprety to make synthetic
	@param keyPath  An array of keypaths. Paths must be rooted at the receiver.
 */
- (void) syntheticProperty:(NSString *) property dependsOnPaths:(NSArray *) keyPaths;


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
- (void) syntheticProperty:(NSString *) property withLazyLoaderMethod:(SEL) loader;


/**
	Markes the given property invalid, meaning that its value will be recalculated (the getter or loader method
	will be called) the next time its value is requested.

	@param property The property to invalidate
 */
- (void) invalidatePropertyValue:(NSString *) property;

/**
	Mass-invalidates propeties.

	@param properties A set of properties to invalidate.
 */
- (void) invalidatePropertyValues:(NSSet *) properties;

/**
	Invalidates all of the synthetic properties of the receiver.
 */
- (void) invalidateAllSyntheticProperties;


/**
	Designed for use by macros. Takes the property to set up and all its dependent keyPaths
	as a single string in the form @"propertyName, a.b.c, a.b.d"

	@param propertyAndPaths A string produced by the SyntheticProperty() VA_ARGS macro
 */
- (void) syntheticProperty_MACRO_USE_ONLY:(NSString *) propertyAndPaths;

@end

@interface EBNLazyLoader (debugging)

/**
	For debugging only, shows the set of currently valid properties. Don't use this for production code.

	@return A NSSet of valid properties
 */
- (NSSet *) debug_validProperties;

/**
	For debugging only, shows the set of currently invalid properties. Don't use this for production code.

	@return A NSSet of invalid properties
 */
- (NSSet *) debug_invalidProperties;

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
- (void) 	debug_forceAllPropertiesValid;

@end












// Just don't look at the stuff below this line. You'll lose sanity. This stuff is used by
// the SyntheticProperty() macro above, and isn't designed for direct use.
/*********************************************************************************************/

	// This macro is used by SyntheticProperty to ensure its arguments are actually properties
	// of self. Do not call it directly.
#define ValidateProperty(propertyName) \
	if (0) \
	{ \
		__attribute__((unused)) __typeof__(self.propertyName) _EBNNotUsed = self.propertyName; \
	}

	// This mess of macros is how we handle iterating the va_args that SyntheticProperty takes into
	// individual property calls. Each one checks the first property, and sends the rest to the n-1 version.
#define ValidateProperty1(propertyName) ValidateProperty(propertyName);
#define ValidateProperty2(propertyName, ...) ValidateProperty(propertyName); ValidateProperty1(__VA_ARGS__)
#define ValidateProperty3(propertyName, ...) ValidateProperty(propertyName); ValidateProperty2(__VA_ARGS__)
#define ValidateProperty4(propertyName, ...) ValidateProperty(propertyName); ValidateProperty3(__VA_ARGS__)
#define ValidateProperty5(propertyName, ...) ValidateProperty(propertyName); ValidateProperty4(__VA_ARGS__)
#define ValidateProperty6(propertyName, ...) ValidateProperty(propertyName); ValidateProperty5(__VA_ARGS__)
#define ValidateProperty7(propertyName, ...) ValidateProperty(propertyName); ValidateProperty6(__VA_ARGS__)
#define ValidateProperty8(propertyName, ...) ValidateProperty(propertyName); ValidateProperty7(__VA_ARGS__)
#define ValidateProperty9(propertyName, ...) ValidateProperty(propertyName); ValidateProperty8(__VA_ARGS__)
#define ValidateProperty10(propertyName, ...) ValidateProperty(propertyName); ValidateProperty9(__VA_ARGS__)
#define ValidateProperty11(propertyName, ...) ValidateProperty(propertyName); ValidateProperty10(__VA_ARGS__)
#define ValidateProperty12(propertyName, ...) ValidateProperty(propertyName); ValidateProperty11(__VA_ARGS__)
#define ValidateProperty13(propertyName, ...) _Pragma("GCC error \"The SyntheticProperty macro supports 12 dependent properties max. Use the syntheticProperty:dependsOn: methods instead.\"")

	// This is a trick to figure out which ValidateProperty<#> to start with, based on
	// the number of arguments in varargs. Does not work with more then 12 arguments--
	// just use the syntheticProperty:dependsOnPaths: method in that case.
#define EBNValidateProperties(...) EBNValidateProperties_(,##__VA_ARGS__,13,12,11,10,9,8,7,6,5,4,3,2,1,0)
#define EBNValidateProperties_(a,b,c,d,e,f,g,h,i,j,k,l,m,n,count,...) ValidateProperty ## count


