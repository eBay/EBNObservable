/****************************************************************************************************
	EBNProtocolBinderTests.m
	Observable
	
	Created by Fry, Chall on 9/19/17.
	Copyright © 2017 eBay Inc. All rights reserved.

    Unit tests.
*/
#import <XCTest/XCTest.h>

#import "EBNProtocolBinder.h"

// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asyncronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);


#pragma mark - Test Objects

@protocol TestBinderProtocol <NSObject>

@property int				intProperty;
@property NSArray			*arrayProperty;


@end

@protocol TestDerivedProtocol <TestBinderProtocol>

@property NSString 			*stringProperty;
@property Class				classProperty;
@property SEL				selectorProperty;
@property NSRange			rangeProperty;

@end

@protocol TestDerivedProtocol2 <TestBinderProtocol>

@property NSRange			rangeProperty;

@end

@protocol TestLeafProtocol <TestDerivedProtocol, TestDerivedProtocol2>

@property float				floatProperty;
@property (weak) NSString	*stringProperty_Weak;
@property (copy) NSString	*stringProperty_Copy;
@property char				*charPointerProperty;


	// Properties that are here to appease code coverage; only because CC works in a dumb way where it treats
	// each template expansion as a separate method for coverage percentages.
@property char				charProperty;
@property unsigned char 	ucharProperty;
@property short				shortProperty;
@property unsigned short	ushortProperty;
@property unsigned int		uintProperty;
@property long				longProperty;
@property unsigned long 	ulongProperty;
@property long long			longlongProperty;
@property unsigned long long ulonglongProperty;
@property double			doubleProperty;
@property bool 				boolProperty;
@property CGPoint			pointProperty;
@property CGRect			rectProperty;
@property CGSize			sizeProperty;
@property UIEdgeInsets		insetsProperty;

@end


@interface SourceClass1 : NSObject <TestLeafProtocol>


@end

@interface DestClass1 : NSObject <TestLeafProtocol>

@end


@implementation SourceClass1

@synthesize intProperty;
@synthesize arrayProperty;
@synthesize stringProperty;
@synthesize classProperty;
@synthesize selectorProperty;
@synthesize rangeProperty;
@synthesize floatProperty;
@synthesize stringProperty_Weak;
@synthesize stringProperty_Copy;
@synthesize charPointerProperty;

@synthesize charProperty;
@synthesize ucharProperty;
@synthesize shortProperty;
@synthesize ushortProperty;
@synthesize uintProperty;
@synthesize longProperty;
@synthesize ulongProperty;
@synthesize longlongProperty;
@synthesize ulonglongProperty;
@synthesize doubleProperty;
@synthesize boolProperty;
@synthesize pointProperty;
@synthesize rectProperty;
@synthesize sizeProperty;
@synthesize insetsProperty;

@end

@implementation DestClass1

@synthesize intProperty;
@synthesize arrayProperty;
@synthesize stringProperty;
@synthesize classProperty;
@synthesize selectorProperty;
@synthesize rangeProperty;
@synthesize floatProperty;
@synthesize stringProperty_Weak;
@synthesize stringProperty_Copy;
@synthesize charPointerProperty;

@synthesize charProperty;
@synthesize ucharProperty;
@synthesize shortProperty;
@synthesize ushortProperty;
@synthesize uintProperty;
@synthesize longProperty;
@synthesize ulongProperty;
@synthesize longlongProperty;
@synthesize ulonglongProperty;
@synthesize doubleProperty;
@synthesize boolProperty;
@synthesize pointProperty;
@synthesize rectProperty;
@synthesize sizeProperty;
@synthesize insetsProperty;

@end









@interface EBNProtocolBinderTests : XCTestCase

@end

@implementation EBNProtocolBinderTests

- (void)setUp 
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown 
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void) testBinding 
{
	SourceClass1 *sourceObj = [[SourceClass1 alloc] init];
	DestClass1 *destObj = [[DestClass1 alloc] init];
	
	sourceObj.intProperty = 5;
	sourceObj.arrayProperty = [NSArray new];
	destObj.intProperty = 7;
	
	[destObj bindTo:sourceObj withProtocol:@protocol(TestBinderProtocol)];	
	
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(destObj.intProperty, 5, @"Binding failed for int property.");
	XCTAssertEqualObjects(destObj.arrayProperty, sourceObj.arrayProperty, @"Binding failed for array property.");
	XCTAssertEqual(destObj.stringProperty, nil, @"String Property shouldn't be bound (not in the bound protocol).");
	
	sourceObj.intProperty = 55;
	sourceObj.arrayProperty = [NSArray arrayWithObject:@"anObjectInTheArray"];
	sourceObj.stringProperty = @"newString";

	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(destObj.intProperty, 55, @"Binding failed for int property.");
	XCTAssertEqualObjects(destObj.arrayProperty, sourceObj.arrayProperty, @"Binding failed for array property.");
	XCTAssertEqualObjects(destObj.stringProperty, nil, @"String Property shouldn't be bound (not in the bound protocol).");

	[destObj unbind:sourceObj fromProtocol:@protocol(TestBinderProtocol)];

	sourceObj.intProperty = 77;
	sourceObj.stringProperty = @"newerString";

	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(destObj.intProperty, 55, @"Unbinding failed for int property.");
	XCTAssertEqualObjects(destObj.arrayProperty, sourceObj.arrayProperty, @"Unbinding failed for array property.");
	XCTAssertEqualObjects(destObj.stringProperty, nil, @"String Property shouldn't be bound (not in the bound protocol).");

}

- (void) testDerivedBinding 
{
	SourceClass1 *sourceObj = [[SourceClass1 alloc] init];
	DestClass1 *destObj = [[DestClass1 alloc] init];
	
	sourceObj.intProperty = 5;
	sourceObj.arrayProperty = [NSArray new];
	destObj.intProperty = 7;
	sourceObj.rangeProperty = NSMakeRange(33, 5);
	sourceObj.floatProperty = 10.0;
	
	[destObj bindTo:sourceObj withProtocol:@protocol(TestLeafProtocol)];	
	
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(destObj.rangeProperty.location, 33, @"Binding failed for range property.");
	XCTAssert(fabs(destObj.floatProperty - 10.0) < .0001, @"Binding failed for range property.");
	XCTAssertEqualObjects(destObj.arrayProperty, sourceObj.arrayProperty, @"Binding failed for array property.");
	XCTAssertEqualObjects(destObj.stringProperty, nil, @"String Property shouldn't be bound (not in the bound protocol).");
	
	// Weak property test
	{
		NSString *strongString = @"aStringValue";
		sourceObj.stringProperty_Weak = strongString;
		EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
		XCTAssertEqualObjects(sourceObj.stringProperty_Weak, strongString, @"Binding failed for string property.");
		XCTAssertEqualObjects(destObj.stringProperty_Weak, strongString, @"Binding failed for string property.");
	}
	
	destObj.intProperty = 99;
	sourceObj.arrayProperty = nil;
	sourceObj.stringProperty_Copy = @"A Copied String";

	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(destObj.intProperty, 99, @"Binding overridefailed for int property.");
	XCTAssertEqualObjects(destObj.arrayProperty, nil, @"Binding failed for array property.");
	XCTAssertEqualObjects(destObj.stringProperty_Copy, @"A Copied String", @"Binding failed for string property).");
	
	sourceObj.intProperty = 44;

	[destObj unbind:sourceObj fromProtocol:@protocol(TestLeafProtocol)];

	sourceObj.intProperty = 77;
	sourceObj.stringProperty = @"newerString";
	sourceObj.floatProperty = 20.0;

	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(destObj.intProperty, 77, @"Unbinding failed for int property.");
	XCTAssert(fabs(destObj.floatProperty - 10.0) < .0001, @"Unbinding failed for float property.");
	XCTAssertEqualObjects(destObj.stringProperty, nil, @"Unbinding failed for string property");

}

@end
