/****************************************************************************************************
	EBNDebugUtilities.h
	Observable
	
	Created by Chall Fry on 4/19/14.
    Copyright (c) 2013-2018 eBay Software Foundation.
	
	This file replaces a few macros eBay uses internally with stubs that will let us
	easily transport the bulk of the code in and out of eBay projects.
	
	Everything declared in this file is also declared in eBay codebases, but is implemented
	differently there.
*/


#import <Foundation/Foundation.h>

/// Unit tests use this to ensure the code asserts where it's supposed to.
#define EBAssertAsserts(expression, ...) \
    _XCTPrimitiveAssertThrows(self, expression, @#expression, __VA_ARGS__)

// Chintzy. Replace with more normal asserts in your app.
// I'm using a throw here so we can unit-test it using EBAssertAsserts().
#define EBAssert(testValue, format, ...) \
({ \
	if (!(testValue)) \
	{ \
		NSString *__debugStr = [NSString stringWithFormat:format, ## __VA_ARGS__]; \
		NSLog(@"%@", __debugStr); \
		@throw [NSException exceptionWithName:@"Unit Test Exception" reason:__debugStr userInfo:nil]; \
	} \
})

// Same idea, but for C style asserts
#define EBCAssert(testValue, format, ...) \
({ \
	if (!(testValue)) \
	{ \
		NSString *__debugStr = [NSString stringWithFormat:format, ## __VA_ARGS__]; \
		NSLog(@"%@", __debugStr); \
		@throw [NSException exceptionWithName:@"Unit Test Exception" reason:__debugStr userInfo:nil]; \
	} \
})



// Again, somewhat chintzy, but you can implement this in your code if you want it.
#define EBAssertContainerIsSolelyKindOfClass(...)

// eBay defines more complicated macros for these; they're defined simply here to make the code work
#define EBLogContext(context, format, ...) NSLog(format, ## __VA_ARGS__)
#define EBLogTest(format, ...) NSLog(format, ## __VA_ARGS__)
#define EBLogStdOut(format, ...) printf("%s\n", [[NSString stringWithFormat:format, ## __VA_ARGS__] UTF8String])


// We now also subclass XCTestCase in our apps; here I'm just using a macro for simplicity.
#define EBNTestCase XCTestCase
