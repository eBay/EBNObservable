/****************************************************************************************************
	LazyLoaderTests.m
	Observable
	
    Created by Chall Fry on 5/1/14.
    Copyright (c) 2013-2018 eBay Software Foundation.

    Unit tests.
*/

@import CoreGraphics;
@import XCTest;
#import "EBNObservableUnitTestSupport.h"
#import "EBNLazyLoader.h"

// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asynchronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);


	// 5 is for performance testing, it declares many properties
@interface ModelObject5 : NSObject

@property int			intProperty1;
@property int			intProperty2;
@property int			intProperty3;
@property int			intProperty4;
@property int			intProperty5;
@property int			intProperty6;
@property int			intProperty7;
@property int			intProperty8;
@property int			intProperty9;
@property int			intProperty10;
@property int			intProperty11;
@property int			intProperty12;
@property int			intProperty13;
@property int			intProperty14;
@property int			intProperty15;
@property int			intProperty16;
@property int			intProperty17;
@property int			intProperty18;
@property int			intProperty19;
@property int			intProperty20;
@property int			intProperty21;
@property int			intProperty22;
@property int			intProperty23;
@property int			intProperty24;
@property int			intProperty25;
@property int			intProperty26;
@property int			intProperty27;
@property int			intProperty28;
@property int			intProperty29;
@property int			intProperty30;
@property int			intProperty31;
@property int			intProperty32;
@property int			intProperty33;
@property int			intProperty34;
@property int			intProperty35;
@property int			intProperty36;
@property int			intProperty37;
@property int			intProperty38;
@property int			intProperty39;
@property int			intProperty40;
@property int			intProperty41;
@property int			intProperty42;
@property int			intProperty43;
@property int			intProperty44;
@property int			intProperty45;
@property int			intProperty46;
@property int			intProperty47;
@property int			intProperty48;
@property int			intProperty49;
@property int			intProperty50;
@property int			intProperty51;
@property int			intProperty52;
@property int			intProperty53;
@property int			intProperty54;
@property int			intProperty55;
@property int			intProperty56;
@property int			intProperty57;
@property int			intProperty58;
@property int			intProperty59;
@property int			intProperty60;
@property int			intProperty61;
@property int			intProperty62;
@property int			intProperty63;
@property int			intProperty64;
@property int			intProperty65;
@property int			intProperty66;
@property int			intProperty67;
@property int			intProperty68;
@property int			intProperty69;
@property int			intProperty70;
@property int			intProperty71;
@property int			intProperty72;
@property int			intProperty73;
@property int			intProperty74;
@property int			intProperty75;
@property int			intProperty76;
@property int			intProperty77;
@property int			intProperty78;
@property int			intProperty79;
@property int			intProperty80;
@property int			intProperty81;
@property int			intProperty82;
@property int			intProperty83;
@property int			intProperty84;
@property int			intProperty85;
@property int			intProperty86;
@property int			intProperty87;
@property int			intProperty88;
@property int			intProperty89;
@property int			intProperty90;
@property int			intProperty91;
@property int			intProperty92;
@property int			intProperty93;
@property int			intProperty94;
@property int			intProperty95;
@property int			intProperty96;
@property int			intProperty97;
@property int			intProperty98;
@property int			intProperty99;
@property int			intProperty100;

@property float			floatProperty;

@end


@implementation ModelObject5

+ (void) initialize
{
	//	[self syntheticProperty_MACRO_USE_ONLY:@#arg]; self.arg;

	#define PerformanceTestMacro(arg) \
	{ \
		[self syntheticProperty:@#arg dependsOn:@"floatProperty"]; \
	}
	
	PerformanceTestMacro(intProperty1);
	PerformanceTestMacro(intProperty2);
	PerformanceTestMacro(intProperty3);
	PerformanceTestMacro(intProperty4);
	PerformanceTestMacro(intProperty5);
	PerformanceTestMacro(intProperty6);
	PerformanceTestMacro(intProperty7);
	PerformanceTestMacro(intProperty8);
	PerformanceTestMacro(intProperty9);
	PerformanceTestMacro(intProperty10);
	PerformanceTestMacro(intProperty11);
	PerformanceTestMacro(intProperty12);
	PerformanceTestMacro(intProperty13);
	PerformanceTestMacro(intProperty14);
	PerformanceTestMacro(intProperty15);
	PerformanceTestMacro(intProperty16);
	PerformanceTestMacro(intProperty17);
	PerformanceTestMacro(intProperty18);
	PerformanceTestMacro(intProperty19);
	PerformanceTestMacro(intProperty20);
	PerformanceTestMacro(intProperty21);
	PerformanceTestMacro(intProperty22);
	PerformanceTestMacro(intProperty23);
	PerformanceTestMacro(intProperty24);
	PerformanceTestMacro(intProperty25);
	PerformanceTestMacro(intProperty26);
	PerformanceTestMacro(intProperty27);
	PerformanceTestMacro(intProperty28);
	PerformanceTestMacro(intProperty29);
	PerformanceTestMacro(intProperty30);
	PerformanceTestMacro(intProperty31);
	PerformanceTestMacro(intProperty32);
	PerformanceTestMacro(intProperty33);
	PerformanceTestMacro(intProperty34);
	PerformanceTestMacro(intProperty35);
	PerformanceTestMacro(intProperty36);
	PerformanceTestMacro(intProperty37);
	PerformanceTestMacro(intProperty38);
	PerformanceTestMacro(intProperty39);
	PerformanceTestMacro(intProperty40);
	PerformanceTestMacro(intProperty41);
	PerformanceTestMacro(intProperty42);
	PerformanceTestMacro(intProperty43);
	PerformanceTestMacro(intProperty44);
	PerformanceTestMacro(intProperty45);
	PerformanceTestMacro(intProperty46);
	PerformanceTestMacro(intProperty47);
	PerformanceTestMacro(intProperty48);
	PerformanceTestMacro(intProperty49);
	PerformanceTestMacro(intProperty50);
	PerformanceTestMacro(intProperty51);
	PerformanceTestMacro(intProperty52);
	PerformanceTestMacro(intProperty53);
	PerformanceTestMacro(intProperty54);
	PerformanceTestMacro(intProperty55);
	PerformanceTestMacro(intProperty56);
	PerformanceTestMacro(intProperty57);
	PerformanceTestMacro(intProperty58);
	PerformanceTestMacro(intProperty59);
	PerformanceTestMacro(intProperty60);
	PerformanceTestMacro(intProperty61);
	PerformanceTestMacro(intProperty62);
	PerformanceTestMacro(intProperty63);
	PerformanceTestMacro(intProperty64);
	PerformanceTestMacro(intProperty65);
	PerformanceTestMacro(intProperty66);
	PerformanceTestMacro(intProperty67);
	PerformanceTestMacro(intProperty68);
	PerformanceTestMacro(intProperty69);
	PerformanceTestMacro(intProperty70);
	PerformanceTestMacro(intProperty71);
	PerformanceTestMacro(intProperty72);
	PerformanceTestMacro(intProperty73);
	PerformanceTestMacro(intProperty74);
	PerformanceTestMacro(intProperty75);
	PerformanceTestMacro(intProperty76);
	PerformanceTestMacro(intProperty77);
	PerformanceTestMacro(intProperty78);
	PerformanceTestMacro(intProperty79);
	PerformanceTestMacro(intProperty80);
	PerformanceTestMacro(intProperty81);
	PerformanceTestMacro(intProperty82);
	PerformanceTestMacro(intProperty83);
	PerformanceTestMacro(intProperty84);
	PerformanceTestMacro(intProperty85);
	PerformanceTestMacro(intProperty86);
	PerformanceTestMacro(intProperty87);
	PerformanceTestMacro(intProperty88);
	PerformanceTestMacro(intProperty89);
	PerformanceTestMacro(intProperty90);
	PerformanceTestMacro(intProperty91);
	PerformanceTestMacro(intProperty92);
	PerformanceTestMacro(intProperty93);
	PerformanceTestMacro(intProperty94);
	PerformanceTestMacro(intProperty95);
	PerformanceTestMacro(intProperty96);
	PerformanceTestMacro(intProperty97);
	PerformanceTestMacro(intProperty98);
	PerformanceTestMacro(intProperty99);
	PerformanceTestMacro(intProperty100);
}
@end

	// 6 is for testing the non-mutable public/mutable private collection method
@interface ModelObject6 : NSObject
@property		int						intProp1;
@property 		NSDictionary			*dictProp1;
@end

// The "Private" interface
@interface ModelObject6 ()

@property		NSMutableDictionary		*internalDictProp1;
@end

@implementation ModelObject6

+ (void) initialize
{
	[self syntheticProperty:@"intProp1" dependsOn:nil];
	[self publicCollection:@"dictProp1" copiesFromPrivateCollection:@"internalDictProp1"];
	[super initialize];
}

- (instancetype) init
{
	if (self = [super init])
	{
		_internalDictProp1 = [[NSMutableDictionary alloc] init];
	}
	
	return self;
}

- (instancetype) initWithAssertFired
{
	if (self = [super init])
	{
		// Should cause an assert
		[[self class] syntheticProperty:@"dictProp1"];
	}
	
	return self;

}

@end

	// 7 is for testing custom getters and synthesize
@interface ModelObject7 : NSObject

@property (readonly) int			readonlyIntProp;
@end

@implementation ModelObject7

+ (void) initialize
{
	[self syntheticProperty:@"readonlyIntProp" dependsOn:nil];
}

- (int) readonlyIntProp
{
	return 56;
}

@end


@interface LazyObject1 : NSObject

@property int						numGetterCalls;
@property int						numObserverCalls;

@property (nonatomic) NSString		*fullName;
@property NSString					*firstName;
@property NSString					*lastName;

@property (nonatomic) int			intProp1;
@property (nonatomic) int			intProp2;
@property (nonatomic) int			intProp3;
@property (nonatomic) int			intProp4;
@property (nonatomic) int			intProp5;
@property (nonatomic) int			intProp6;

@property (nonatomic) CGFloat		floatProp1;
@property (nonatomic) CGFloat		floatProp2;
@property (nonatomic) CGFloat		floatProp3;
@property (nonatomic) CGFloat		floatProp4;

@property (nonatomic) CGSize		sizeProp1;
@property (nonatomic) CGPoint		pointProp1;
@property (nonatomic) CGRect		rectProp1;


@end

@implementation LazyObject1

+ (void) initialize
{
	SyntheticProperty(LazyObject1, intProp2);
	SyntheticProperty(LazyObject1, fullName, firstName, lastName);
	
	SyntheticProperty(LazyObject1, sizeProp1, floatProp1, floatProp2);
	SyntheticProperty(LazyObject1, pointProp1, floatProp3, floatProp4);
	SyntheticProperty(LazyObject1, rectProp1, pointProp1, sizeProp1);
}

- (instancetype) init
{
	if (self = [super init])
	{
		_firstName = @"John";
		_lastName = @"Smith";
		_intProp1 = 55;
		
	}
	return self;
}

- (NSString *) fullName
{	
	self.numGetterCalls++;
	return _fullName = [NSString stringWithFormat:@"%@ %@", self.firstName, self.lastName];
}

- (int) intProp2
{
	self.numGetterCalls++;
	return _intProp2 = self.intProp1;
}

- (CGSize) sizeProp1
{
	self.numGetterCalls++;
	CGSize ret = CGSizeMake(self.floatProp1, self.floatProp2);
	return _sizeProp1 = ret;
}

- (CGPoint) pointProp1
{
	self.numGetterCalls++;
	CGPoint ret = CGPointMake(self.floatProp3, self.floatProp4);
	return _pointProp1 = ret;
}

- (CGRect) rectProp1
{
	self.numGetterCalls++;
	CGRect ret = CGRectMake(self.pointProp1.x, self.pointProp1.y, self.sizeProp1.width, self.sizeProp1.height);
	return _rectProp1 = ret;
}

- (void) customPropertyLoader:(NSString *) propertyToLoad
{
	if ([propertyToLoad isEqualToString:@"intProp6"])
		_intProp6 = 33;
}

@end


@interface ContainerContainingObject : NSObject

@property	NSArray						*publicArrayProperty;
@property	NSDictionary				*publicDictProperty;
@property	NSSet						*publicSetProperty;
@end

// The "private" interface, with mutable collections
@interface ContainerContainingObject ()

@property	NSMutableArray				*arrayProperty;
@property	NSMutableDictionary			*dictProperty;
@property	NSMutableSet				*setProperty;

@end

@implementation ContainerContainingObject

+ (void) initialize
{	
	// Don't protect this code with a "if (self isKindOfClass:ContainerContainingObject)" guard.
	// Subclasses of this class need to run these methods as part of their +initialize.
	[self publicCollection:@"publicArrayProperty" copiesFromPrivateCollection:@"arrayProperty"];
	[self publicCollection:@"publicDictProperty" copiesFromPrivateCollection:@"dictProperty"];
	[self publicCollection:@"publicSetProperty" copiesFromPrivateCollection:@"setProperty"];

}

@end

@interface LazyObject2 : NSObject
@property int						numGetterCalls;
@property int						numObserverCalls;

@property (nonatomic) NSString		*fullName;
@property NSString					*firstName;
@property NSString					*lastName;

@property int						intProp1;
@property int						intProp2;

@property id						objectProperty1;
@end

@implementation LazyObject2

+ (void) initialize
{
	[self syntheticProperty:@"objectProperty1"];

	[self syntheticProperty:@"fullName" dependsOnPaths:@[@"firstName", @"lastName"]];
	
	[self syntheticProperty:@"intProp2" dependsOn:@"intProp1"];
	
	[super initialize];
}

- (NSString *) fullName
{
	(void)_fullName; // silence the compiler
	
	self.numGetterCalls++;
	return [NSString stringWithFormat:@"%@ %@", self.firstName, self.lastName];
}

@end

@interface LazyObject3 : LazyObject2

@property float				floatProp1;

@end

@implementation LazyObject3

+ (void) initialize
{
	[self syntheticProperty:@"floatProp1"];
	[super initialize];
}

@end

@interface LazyObject4 : LazyObject2

@property float				floatProp2;

@end

@implementation LazyObject4

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
	// This tests that if we call invalidate on a property that isn't lazyloaded, it still works.
	[lo1 invalidatePropertyValue:@"floatProp1"];
	
	// Same idea. count isn't synthetic, and can't be invalidated, but it shouldn't crash or assert
	// if you try to invalidate it.
	NSArray *array = [[NSArray alloc] init];
	[array invalidatePropertyValue:@"count"];
}


- (void) testLazyLoading
{
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	

	EBLogTest(@"%d", lo1.intProp2);
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");
	
	EBLogTest(@"%d", lo1.intProp2);
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");
	
	[lo1 invalidatePropertyValue:@"intProp2"];
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");

	EBLogTest(@"%d", lo1.intProp2);
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");
	
	lo1.intProp2 = 33;
	EBLogTest(@"%d", lo1.intProp2);
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");

	[lo1 invalidatePropertyValue:@"intProp2"];
	lo1.intProp2 = 44;
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");
	EBLogTest(@"%d", lo1.intProp2);
	XCTAssert(lo1.intProp2 == 44, @"Direcly setting a lazy-load property failed to keep its state.");
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");
}

- (void) testObservingSynthetics
{	
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	
	EBLogTest(@"%@", lo1.fullName);
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");

	EBLogTest(@"%@", lo1.fullName);
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");
	
	lo1.firstName = @"Robert";
	XCTAssertEqual(lo1.numGetterCalls, 1, @"Wrong number of calls to getter.");
	EBLogTest(@"%@", lo1.fullName);
	XCTAssertEqual(lo1.numGetterCalls, 2, @"Wrong number of calls to getter.");

}

- (void) testInvalidation
{
	// This is a debug method for a reason!!! Do not start forcing all properties valid in production code!
	[lo1 debug_forceAllPropertiesValid];
	
	// Check that everything is valid now.
	XCTAssertEqual(lo1.debug_invalidProperties.count, 0, @"All synthetic properties should be valid at this point.");
	
	[lo1 invalidateAllSyntheticProperties];
	XCTAssertEqual(lo1.debug_invalidProperties.count, 5, @"All synthetic properties should be invalid at this point.");
	XCTAssert(![lo1 ebn_hasValidProperties], @"Should be no valid properties");

	// Get a prop
	int val = lo1.intProp2;
	XCTAssertEqual(lo1.debug_invalidProperties.count, 4, @"All synthetic properties except intProp2 should be invalid at this point.");
	XCTAssertEqual(lo1.debug_validProperties.count, 1, @"intProp2 should be valid at this point.");
	XCTAssertEqual(val, lo1.intProp2, @"value should be equal to prop.");
	XCTAssert([lo1 ebn_hasValidProperties], @"Should be valid properties");
	
	[lo1 invalidatePropertyValues:[NSSet setWithObject:@"intProp2"]];
	XCTAssertEqual(lo1.debug_invalidProperties.count, 5, @"All synthetic properties should be invalid at this point.");
}

- (void) testCollectionCopying
{
	ContainerContainingObject	*cco = [[ContainerContainingObject alloc] init];
	
	XCTAssertNil(cco.publicArrayProperty, @"Should be nil until set");
	
	// Conceptually, arrayProperty et al. are 'internal' to cco, but whatevs.
	cco.arrayProperty = [NSMutableArray arrayWithObject:@"singleObject"];
	XCTAssertNotNil(cco.publicArrayProperty, @"Should be mirroring the internal arrayProperty.");
	XCTAssertEqualObjects(cco.arrayProperty, cco.publicArrayProperty, @"Arrays should be equal.");
	cco.arrayProperty = [NSMutableArray arrayWithObjects:@"string1", @"string2", nil];
	XCTAssertNotNil(cco.publicArrayProperty, @"Should be mirroring the internal arrayProperty.");
	XCTAssertEqualObjects(cco.arrayProperty, cco.publicArrayProperty, @"Arrays should be equal.");

	cco.dictProperty = [NSMutableDictionary dictionaryWithObject:@"singleObject" forKey:@"singleKey"];
	XCTAssertNotNil(cco.publicDictProperty, @"Should be mirroring the internal dictProperty.");
	XCTAssertEqualObjects(cco.dictProperty, cco.publicDictProperty, @"Dictionaries should be equal.");
	cco.dictProperty = [NSMutableDictionary dictionaryWithObjects:@[@"string1", @"string2"] forKeys:@[@"key1", @"key2"]];
	XCTAssertNotNil(cco.publicDictProperty, @"Should be mirroring the internal dictProperty.");
	XCTAssertEqualObjects(cco.dictProperty, cco.publicDictProperty, @"Dictionaries should be equal.");

	cco.setProperty = [NSMutableSet setWithObject:@"singleObject"];
	XCTAssertNotNil(cco.publicSetProperty, @"Should be mirroring the internal setProperty.");
	XCTAssertEqualObjects(cco.setProperty, cco.publicSetProperty, @"Sets should be equal.");
	cco.setProperty = [NSMutableSet setWithObjects:@"string1", @"string2", nil];
	XCTAssertNotNil(cco.publicSetProperty, @"Should be mirroring the internal setProperty.");
	XCTAssertEqualObjects(cco.setProperty, cco.publicSetProperty, @"Sets should be equal.");
}

- (void) testChainedObservation
{	
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	
	lo1.floatProp1 = 33.3;
	XCTAssertEqual(lo1.numGetterCalls, 0, @"Wrong number of calls to getter.");
	
	CGRect r = lo1.rectProp1;
	EBLogTest(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
	XCTAssertEqual(lo1.numGetterCalls, 3, @"Wrong number of calls to getter.");

	lo1.floatProp1 = 33.3;
	lo1.floatProp2 = 33.3;
	lo1.floatProp3 = 33.3;
	lo1.floatProp4 = 33.3;
	r = lo1.rectProp1;
	EBLogTest(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
	XCTAssertEqual(lo1.numGetterCalls, 6, @"Wrong number of calls to getter.");
	
	[lo1 invalidatePropertyValue:@"rectProp1"];
	XCTAssertEqual(lo1.numGetterCalls, 6, @"Wrong number of calls to getter.");
	r = lo1.rectProp1;
	EBLogTest(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
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
	EBLogTest(@"rect: %fx%f %fx%f", r.origin.x, r.origin.y, r.size.width, r.size.height);
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

#pragma mark Initialization Time LazyLoading

- (void) testInitializationTimeObjects
{
	LazyObject2 *lo2 = [[LazyObject2 alloc] init];
	
	XCTAssert(![lo2.debug_validProperties containsObject:@"fullName"], @"fullName marked as valid before first access.");
	XCTAssert([lo2.debug_invalidProperties containsObject:@"fullName"], @"fullName not marked as invalid before first access.");

	lo2.firstName = @"George";
	lo2.lastName = @"Washington";
	NSString *str = lo2.fullName;
	XCTAssertEqualObjects(str, @"George Washington", @"How does this even.");
    XCTAssert([lo2.debug_validProperties containsObject:@"fullName"], @"fullName not marked as valid after access.");
    
    [lo2 invalidatePropertyValue:@"fullName"];
    XCTAssert(![lo2.debug_validProperties containsObject:@"fullName"], @"fullName marked as valid after invalidation.");
	
	// FullName was invalid before lastName changes--should check the invalid->invalid transition
	lo2.lastName = @"Clooney";
    XCTAssert(![lo2.debug_validProperties containsObject:@"fullName"], @"fullName marked as valid after invalidation.");
	str = lo2.fullName;
	XCTAssertEqualObjects(str, @"George Clooney", @"Name change didn't propagate.");
    XCTAssert([lo2.debug_validProperties containsObject:@"fullName"], @"fullName marked as invalid after access.");

	// FullName is valid at this point; changing lastName should invalidate it
	lo2.lastName = @"Michael";
    XCTAssert(![lo2.debug_validProperties containsObject:@"fullName"], @"fullName marked as valid after source changed.");
	str = lo2.fullName;
	XCTAssertEqualObjects(str, @"George Michael", @"Name change didn't propagate.");
    XCTAssert([lo2.debug_validProperties containsObject:@"fullName"], @"fullName marked as invalid after access.");


	
    // Tests directly using the setter.
	XCTAssert(![lo2.debug_validProperties containsObject:@"objectProperty1"], @"Property valid before first access.");
	lo2.objectProperty1 = @"A String";
	XCTAssert([lo2.debug_validProperties containsObject:@"objectProperty1"], @"Property not valid after being set.");
	[lo2 invalidatePropertyValue:@"objectProperty1"];
	XCTAssert(![lo2.debug_validProperties containsObject:@"objectProperty1"], @"Property valid after invalidation.");
	NSString *str2 = lo2.objectProperty1;
	XCTAssertEqualObjects(str2, @"A String", @"Property should have this value at this point.");
	XCTAssert([lo2.debug_validProperties containsObject:@"objectProperty1"], @"Property not valid after access.");


	// 3 is a subclass of 2, that declares its own synthetic properties
	LazyObject3 *lo3 = [[LazyObject3 alloc] init];
	XCTAssert(![lo2.debug_validProperties containsObject:@"floatProp1"], @"Property valid before first access.");
	lo3.floatProp1 = 33;
	XCTAssert([lo2.debug_validProperties containsObject:@"objectProperty1"], @"Property not valid after being set.");
	[lo3 invalidatePropertyValue:@"floatProp1"];
	XCTAssert(![lo3.debug_validProperties containsObject:@"objectProperty1"], @"Property valid after invalidation.");

	XCTAssert(![lo3.debug_validProperties containsObject:@"objectProperty1"], @"Property valid before first access.");
	lo3.objectProperty1 = @"A String";
	XCTAssert([lo3.debug_validProperties containsObject:@"objectProperty1"], @"Property not valid after being set.");
	[lo3 invalidatePropertyValue:@"objectProperty1"];
	XCTAssert(![lo3.debug_validProperties containsObject:@"objectProperty1"], @"Property valid after invalidation.");
	NSString *str3 = lo3.objectProperty1;
	XCTAssertEqualObjects(str3, @"A String", @"Property should have this value at this point.");
	XCTAssert([lo3.debug_validProperties containsObject:@"objectProperty1"], @"Property not valid after access.");


	// 4 is a subclass of 2, that does not declare synthetic properties of its own, nor does it override initialize
	LazyObject4 *lo4 = [[LazyObject4 alloc] init];
	XCTAssert(![lo4.debug_validProperties containsObject:@"objectProperty1"], @"Property valid before first access.");
	lo4.objectProperty1 = @"A String";
	XCTAssert([lo4.debug_validProperties containsObject:@"objectProperty1"], @"Property not valid after being set.");
	[lo4 invalidatePropertyValue:@"objectProperty1"];
	XCTAssert(![lo4.debug_validProperties containsObject:@"objectProperty1"], @"Property valid after invalidation.");
	NSString *str4 = lo4.objectProperty1;
	XCTAssertEqualObjects(str4, @"A String", @"Property should have this value at this point.");
	XCTAssert([lo4.debug_validProperties containsObject:@"objectProperty1"], @"Property not valid after access.");
}

- (void) testInitializationTimeCollections
{
	// Should assert because ModelObject6's init tries to create a global synthetic property, but we've already
	// alloced an instance of a ModelObject6.
	ModelObject6 *obj = nil;
	EBAssertAsserts(obj = [[ModelObject6 alloc] initWithAssertFired], 
			@"Too-late global synthetic property registration should cause assert.");
	obj = [[ModelObject6 alloc] init];
	
	__block int hitCount = 0;
	
	ObserveProperty(obj, intProp1, { ++hitCount; } );
	obj.intProp1 = 33;
	[obj invalidatePropertyValue:@"intProp1"];
	obj.intProp1 = 55;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssert([obj.debug_validProperties containsObject:@"intProp1"], @"Property not valid after access.");
	XCTAssertEqual(hitCount, 1, @"Wrong number of calls to property observer.");
	
	[obj.internalDictProp1 setObject:@"testObject" forKey:@"testKey"];
	XCTAssert(![obj.debug_validProperties containsObject:@"dictProp1"], @"Property valid before first access.");
	NSMutableDictionary *localDict = (NSMutableDictionary *) obj.dictProp1;
	XCTAssert([obj.debug_validProperties containsObject:@"dictProp1"], @"Property not valid after access.");
	XCTAssert([localDict objectForKey:@"testKey"], @"Key in internal dictionary didn't copy over");
	XCTAssertThrows([localDict setObject:@"Will Fail" forKey:@"Cannot Mutate"], @"Public dict should be non-mutable");
	
}

	// Tests that a readonly property with a custom getter will have a ivar created to cache its value, without
	// having to @synthetsize one.
- (void) testCustomGetter
{
	ModelObject7 *seven = [[ModelObject7 alloc] init];
	
	int x = seven.readonlyIntProp;
	XCTAssertEqual(x, 56, @"readonly int prop may not have received a backing instance variable.");
}

#pragma mark Performance tests

- (void) testInitializationTimePerformance
{
	NSDate *startTime = [NSDate date];
	LazyObject2 *obj = [[LazyObject2 alloc] init];
	EBLogTest(@"Elapsed time:%f", - [startTime timeIntervalSinceNow]);

	startTime = [NSDate date];
	LazyObject2 *obj2 = [[LazyObject2 alloc] init];
	EBLogTest(@"Elapsed time:%f", - [startTime timeIntervalSinceNow]);
	
	[self measureBlock:^
	{
		LazyObject2 *obj3 = [[LazyObject2 alloc] init];
		
		if (![obj isEqual:obj2] || [obj isEqual:obj3])
		{
			EBLogTest(@"Mostly, this suppresses warnings about unused variables.");
		}
	}];
	

}

- (void) testInitPerformance
{
	NSDate *startTime = [NSDate date];
	ModelObject5 *obj = [[ModelObject5 alloc] init];
	EBLogTest(@"Elapsed time:%f", - [startTime timeIntervalSinceNow]);

	startTime = [NSDate date];
	ModelObject5 *obj2 = [[ModelObject5 alloc] init];
	EBLogTest(@"Elapsed time:%f", - [startTime timeIntervalSinceNow]);
	
	[self measureBlock:^
	{
		ModelObject5 *obj3 = [[ModelObject5 alloc] init];
		
		if ([obj isEqual:obj2] || [obj isEqual:obj3])
		{
			EBLogTest(@"Mostly, this suppresses warnings about unused variables.");
		}
	}];
	
}

- (void) testSwizzlePerformance
{
	const int kNumSelectors = 1000;
	
	// Don't profile this part, it just registers the selectors.
	struct becauseBlocksDontAllowArrays
	{
		 SEL names[kNumSelectors];
	} selectorNames = {{0}};
	
	for (int x = 0; x < kNumSelectors; ++x)
	{
		char selNameStr[100];
		sprintf(selNameStr, "runtimeMethod%d", x);
		selectorNames.names[x] = sel_registerName(selNameStr);
	}
	
	// Now that we have a bunch of selectors, create a runtime class and add all the selectors as new
	// methods.
	__block int iterationCount = 0;
	[self measureBlock:^
	{
		int localIterationCount;
		char shadowClassName[100];

		// This all makes sure we run with a new class each time measureBlock executes us.
		@synchronized(self)
		{
			localIterationCount = iterationCount;
			++iterationCount;
		}
		sprintf(shadowClassName, "ModelObject5_SwizzlePerformance%d", localIterationCount);
	
		Class shadowClass = objc_allocateClassPair([ModelObject5 class], shadowClassName, 0);
		
		ModelObject5 *obj = [[shadowClass alloc] init];
		for (int x = 0; x < kNumSelectors; ++x)
		{
			int (^overrideAMethod)(void) = ^int (void)
			{
				return 0;
			};
			IMP overrideAMethodIMP = imp_implementationWithBlock(overrideAMethod);
			Method meth = class_getInstanceMethod([ModelObject5 class], @selector(intProperty1));

			class_addMethod(shadowClass, selectorNames.names[x], overrideAMethodIMP, method_getTypeEncoding(meth));
			
			int y = obj.intProperty15;
			if (y == 55) EBLogTest(@"Y will never equal 55, it's here to ensure we generate the method cache.");
		}
		objc_registerClassPair(shadowClass);
	}];
}

- (void) testCountPropertiesPerformance
{
	[self measureBlock:^
	{
		for (int index = 0; index < 10000; ++index)
		{
			// This code is lifted out of ebn_swizzleImplementationForGetter, to test the performance of
			// counting properties.
			NSInteger numProperties = 0;
			Class curClass = [ModelObject5 class];
			while (curClass)
			{
				unsigned int propCount;
				objc_property_t *properties = class_copyPropertyList(curClass, &propCount);
				if (properties)
				{
					numProperties += propCount;
					free(properties);
				}
				
				curClass = [curClass superclass];
			}
		}
	}];
}

@end
