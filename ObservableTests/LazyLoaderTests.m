/****************************************************************************************************
	LazyLoaderTests.m
	Observable
	
    Created by Chall Fry on 5/1/14.
    Copyright (c) 2013-2014 eBay Software Foundation.

    Unit tests.
*/

@import CoreGraphics;
@import XCTest;
#import "EBNLazyLoader.h"

// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asynchronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);



@interface LazyObject1 : NSObject

@property int						numGetterCalls;
@property int						numObserverCalls;

@property (nonatomic) NSString		*fullName;
@property NSString					*firstName;
@property NSString					*lastName;

@property (nonatomic) int			intProp1;
@property (nonatomic) int			intProp2;

@property (nonatomic) CGFloat		floatProp1;
@property (nonatomic) CGFloat		floatProp2;
@property (nonatomic) CGFloat		floatProp3;
@property (nonatomic) CGFloat		floatProp4;

@property (nonatomic) CGSize		sizeProp1;
@property (nonatomic) CGPoint		pointProp1;
@property (nonatomic) CGRect		rectProp1;


@end

@implementation LazyObject1

- (instancetype) init
{
	if (self = [super init])
	{
		_firstName = @"John";
		_lastName = @"Smith";
		_intProp1 = 55;
		
		SyntheticProperty(intProp2);
		SyntheticProperty(fullName, firstName, lastName);
		
		SyntheticProperty(sizeProp1, floatProp1, floatProp2);
		SyntheticProperty(pointProp1, floatProp3, floatProp4);
		SyntheticProperty(rectProp1, pointProp1, sizeProp1);
	}
	return self;
}

- (NSString *) fullName
{
	self.numGetterCalls++;
	return [NSString stringWithFormat:@"%@ %@", self.firstName, self.lastName];
}

- (int) intProp2
{
	self.numGetterCalls++;
	return self.intProp1;
}

- (CGSize) sizeProp1
{
	self.numGetterCalls++;
	CGSize ret = CGSizeMake(self.floatProp1, self.floatProp2);
	return ret;
}

- (CGPoint) pointProp1
{
	self.numGetterCalls++;
	CGPoint ret = CGPointMake(self.floatProp3, self.floatProp4);
	return ret;
}

- (CGRect) rectProp1
{
	self.numGetterCalls++;
	CGRect ret = CGRectMake(self.pointProp1.x, self.pointProp1.y, self.sizeProp1.width, self.sizeProp1.height);
	return ret;
}

@end





@interface LazyLoaderTests : XCTestCase

@end

@implementation LazyLoaderTests
{
	LazyObject1	*lo1;
}

- (void) setUp
{
    [super setUp];
	
	lo1 = [[LazyObject1 alloc] init];
}

- (void) tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void) testNonLazyLoadedInvalidation
{
	[lo1 invalidatePropertyValue:@"floatProp1"];
}

- (void) testLazyLoading
{
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	

	NSLog(@"%d", lo1.intProp2);
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");
	
	NSLog(@"%d", lo1.intProp2);
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");

	[lo1 invalidatePropertyValue:@"intProp2"];
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");

	NSLog(@"%d", lo1.intProp2);
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");
	
	lo1.intProp2 = 33;
	NSLog(@"%d", lo1.intProp2);
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");

	[lo1 invalidatePropertyValue:@"intProp2"];
	lo1.intProp2 = 44;
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");
	NSLog(@"%d", lo1.intProp2);
	XCTAssert(lo1.intProp2 == 44, @"Direcly setting a lazy-load property failed to keep its state.");
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");
}

- (void) testObservingSynthetics
{	
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	
	NSLog(@"%@", lo1.fullName);
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");

	NSLog(@"%@", lo1.fullName);
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");
	
	lo1.firstName = @"Robert";
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");
	NSLog(@"%@", lo1.fullName);
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");

}

- (void) testChainedObservation
{	
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	
	lo1.floatProp1 = 33.3;
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	
	CGRect r = lo1.rectProp1;
	NSLog(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
	XCTAssertEqual(lo1.numGetterCalls, 3, @"Wrong number of calls to getter.");

	lo1.floatProp1 = 33.3;
	lo1.floatProp2 = 33.3;
	lo1.floatProp3 = 33.3;
	lo1.floatProp4 = 33.3;
	r = lo1.rectProp1;
	NSLog(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
	XCTAssertEqual(lo1.numGetterCalls, 6, @"Wrong number of calls to getter.");
	
	[lo1 invalidatePropertyValue:@"rectProp1"];
	XCTAssertEqual(lo1.numGetterCalls, 6, @"Wrong number of calls to getter.");
	r = lo1.rectProp1;
	NSLog(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
	XCTAssertEqual(lo1.numGetterCalls, 7, @"Wrong number of calls to getter.");
}

- (void) testObservationOfSynthetics
{
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	
	lo1.floatProp1 = 50.0;
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	
	[lo1 tell:self when:@"rectProp1" changes:^(LazyLoaderTests *blockSelf, LazyObject1 *observed)
	{
		++observed.numObserverCalls;
	}];
	
	// Adding an observation on RectProp1 causes RectProp1 to be evaluated, which in turn
	// causes SizeProp1 and PointProp1 to be evaluated. So, 3 evals.
	XCTAssertEqual(lo1.numGetterCalls, 3, @"Wrong number of calls to getter.");
	
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(lo1.numObserverCalls, 0, @"Wrong number of calls to property observer.");

	lo1.floatProp1 = 33.3;
	
	// Then, changing the value of floatProp1 causes SizeProp1 and RectProp1 to be invalidated,
	// and the observation then immediately forces a recompute, causing those 2 getters to get called.
	XCTAssertEqual(lo1.numGetterCalls, 5, @"Wrong number of calls to getter.");

	// Changing floatProp causes a change to RectProp causes that change to RectProp to be observed.
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(lo1.numObserverCalls, 1, @"Wrong number of calls to property observer.");

	// At this point, accessing rectProp1 shouldn't cause more evaluating
	CGRect r = lo1.rectProp1;
	NSLog(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
	XCTAssertEqual(lo1.numGetterCalls, 5, @"Wrong number of calls to getter.");
	
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(lo1.numObserverCalls, 1, @"Wrong number of calls to property observer.");

	// And, setting floatProp1 to the same value it previously had shouldn't cause re-evals either
	// Note that this test is subject to the whims of optimization;
	lo1.floatProp1 = 33.3;
	XCTAssertEqual(lo1.numGetterCalls, 5, @"Wrong number of calls to getter.");

	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(lo1.numObserverCalls, 1, @"Wrong number of calls to property observer.");
	
	// Manually invalidating the point property causes the rect property to also get invalidated.
	// Because there's an observation on the rect property, we eval the rect property to see if it's
	// value changed, which causes pointProperty to get re-evaluated as well. So the number of getter
	// calls increments by 2. Easy, right?
	[lo1 invalidatePropertyValue:@"pointProp1"];
	XCTAssertEqual(lo1.numGetterCalls, 7, @"Wrong number of calls to getter.");
	
	// Since the manual invalidation of pointProperty didn't actually change its value, we figure out
	// that we don't need to call observers
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(lo1.numObserverCalls, 1, @"Wrong number of calls to property observer.");

}

@end
