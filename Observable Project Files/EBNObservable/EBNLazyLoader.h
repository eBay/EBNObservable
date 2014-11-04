/****************************************************************************************************
	EBNLazyLoader.h
	Observable
	
	Created by Chall Fry on 4/29/14.
	Copyright (c) 2013-2014 eBay Software Foundation.
	
*/

#import "EBNObservable.h"

#pragma mark Convenience Macros

	// This declares its first argument to be a lazy-loading synthetic property, and other
	// arguments (if given) are dependent properties. References 'self' from within the macro.
#define SyntheticProperty(...) \
({ \
	EBNValidateProperties(__VA_ARGS__)(__VA_ARGS__) \
	[self syntheticProperty_MACRO_USE_ONLY:@#__VA_ARGS__]; \
})

	// Call this macro to invalidate a synthetic property's value. This macro just provides
	// property name validation. References 'self' from within the macro.
#define InvalidatePropertyValue(propertyName) \
({ \
	ValidateProperty(propertyName); \
	[self invalidatePropertyValue:EBNStringify(propertyName)]; \
})

#pragma mark Blocks

	// The loader block is an optional way to load properties. We use the term 'loading' because it's
	// not a getter--it doesn't return the value. It's not a setter--that's where the caller sets the value.
	// The loader's job is to determine the correct value for the property and set it.
typedef void (^EBNLazyLoaderBlock)(id blockSelf);


#pragma mark EBNLazyLoader class

@interface EBNLazyLoader : EBNObservable

- (void) syntheticProperty:(NSString *) property;
- (void) syntheticProperty:(NSString *) property dependsOn:(NSString *) keyPath;
- (void) syntheticProperty:(NSString *) property dependsOnPaths:(NSArray *) keyPaths;
- (void) syntheticProperty:(NSString *) property withLazyLoaderBlock:(EBNLazyLoaderBlock) loaderBlock;


// There's nothing preventing us from creating methods for dependent keypaths not rooted on self,
// but I want to see how this works first.

- (void) invalidatePropertyValue:(NSString *) property;
- (void) invalidatePropertyValues:(NSSet *) properties;
- (void) invalidateAllSyntheticProperties;

	// Designed for use by macros. Takes the property to set up and all its dependent keyPaths
	// as a single string in the form @"propertyName, a.b.c, a.b.d"
- (void) syntheticProperty_MACRO_USE_ONLY:(NSString *) propertyAndPaths;

@end

@interface EBNLazyLoader (debugging)

- (NSSet *) debug_validProperties;
- (NSSet *) debug_invalidProperties;
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


