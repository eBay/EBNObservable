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

@interface LazyObject1 : EBNLazyLoader

@property int						numGetterCalls;

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
	XCTAssert(lo1.numGetterCalls == 0, @"Wrong number of calls to getter.");
	

	NSLog(@"%d", lo1.intProp2);
	XCTAssert(lo1.numGetterCalls == 1, @"Wrong number of calls to getter.");
	
	NSLog(@"%d", lo1.intProp2);
	XCTAssert(lo1.numGetterCalls == 1, @"Wrong number of calls to getter.");

	[lo1 invalidatePropertyValue:@"intProp2"];
	XCTAssert(lo1.numGetterCalls == 1, @"Wrong number of calls to getter.");

	NSLog(@"%d", lo1.intProp2);
	XCTAssert(lo1.numGetterCalls == 2, @"Wrong number of calls to getter.");
	
	lo1.intProp2 = 33;
	NSLog(@"%d", lo1.intProp2);
	XCTAssert(lo1.numGetterCalls == 2, @"Wrong number of calls to getter.");

	[lo1 invalidatePropertyValue:@"intProp2"];
	lo1.intProp2 = 44;
	XCTAssert(lo1.numGetterCalls == 2, @"Wrong number of calls to getter.");
	NSLog(@"%d", lo1.intProp2);
	XCTAssert(lo1.intProp2 == 44, @"Direcly setting a lazy-load property failed to keep its state.");
	XCTAssert(lo1.numGetterCalls == 2, @"Wrong number of calls to getter.");
}

- (void) testObservation
{	
	XCTAssert(lo1.numGetterCalls == 0, @"Wrong number of calls to getter.");
	
	NSLog(@"%@", lo1.fullName);
	XCTAssert(lo1.numGetterCalls == 1, @"Wrong number of calls to getter.");

	NSLog(@"%@", lo1.fullName);
	XCTAssert(lo1.numGetterCalls == 1, @"Wrong number of calls to getter.");
	
	lo1.firstName = @"Robert";
	XCTAssert(lo1.numGetterCalls == 1, @"Wrong number of calls to getter.");
	NSLog(@"%@", lo1.fullName);
	XCTAssert(lo1.numGetterCalls == 2, @"Wrong number of calls to getter.");

}

- (void) testChainedObservation
{	
	XCTAssert(lo1.numGetterCalls == 0, @"Wrong number of calls to getter.");
	
	lo1.floatProp1 = 33.3;
	XCTAssert(lo1.numGetterCalls == 0, @"Wrong number of calls to getter.");
	
	CGRect r = lo1.rectProp1;
	NSLog(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
	XCTAssert(lo1.numGetterCalls == 3, @"Wrong number of calls to getter.");

	lo1.floatProp1 = 33.3;
	lo1.floatProp2 = 33.3;
	lo1.floatProp3 = 33.3;
	lo1.floatProp4 = 33.3;
	r = lo1.rectProp1;
	NSLog(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
	XCTAssert(lo1.numGetterCalls == 6, @"Wrong number of calls to getter.");
	
	[lo1 invalidatePropertyValue:@"rectProp1"];
	XCTAssert(lo1.numGetterCalls == 6, @"Wrong number of calls to getter.");
	r = lo1.rectProp1;
	NSLog(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
	XCTAssert(lo1.numGetterCalls == 7, @"Wrong number of calls to getter.");

}

@end
