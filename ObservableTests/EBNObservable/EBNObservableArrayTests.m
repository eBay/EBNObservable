/****************************************************************************************************
	ObservableArrayTests.m
	Observable
	
    Created by Chall Fry on 5/30/14.
    Copyright (c) 2013-2018 eBay Software Foundation.

    Unit tests.
*/

#import "EBNObservable.h"
#import "EBNObservableUnitTestSupport.h"

@import XCTest;


// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asyncronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);


@interface ModelArrayObject1 : NSObject

@property (strong) NSMutableArray	*array;
@property int						intProperty;
@property int						intProperty2;

@end

@implementation ModelArrayObject1

- (instancetype) init
{
	if (self = [super init])
	{
		// The use of self. syntax here is deliberate, to ensure that lazy loader observations work correctly.
		self.array = [[NSMutableArray alloc] init];
	}
	return self;
}

@end

@interface ObservableArrayTests : XCTestCase

@end

@implementation ObservableArrayTests
{
	ModelArrayObject1		*mao1;
	int						observerCallCount;

}

- (void)setUp
{
    [super setUp];

	mao1 = [[ModelArrayObject1 alloc] init];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void) testImmutableArrayBasics
{
	ModelArrayObject1 *modelObject = [[ModelArrayObject1 alloc] init];
	NSArray *array1 = [NSArray arrayWithObject:modelObject];
	
	// Observe thorugh it to force it to be an observable subclass
	ObservePropertyNoPropCheck(array1, #0.intProperty,
	{
		++blockSelf->observerCallCount;
	});

	// Very difficult to mess this stuff up, but might be possible?
	XCTAssertEqual([array1 count], 1, @"Immutable Array didn't initialize right. How does this happen?");
	XCTAssertEqual(array1[0], modelObject, @"Wrong object in array");

	modelObject.intProperty = 55;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called when observing through NSArray.");
	
}

- (void)testArrayBasics
{
	NSMutableArray *array1 = [[NSMutableArray alloc] init];
	
	// Observe it to force it to be an observable subclass
	ObservePropertyNoPropCheck(array1, 3.invalidKey,
	{
		++blockSelf->observerCallCount;
	});

	[array1 addObject:@"object1"];
	XCTAssertEqual([array1 count], 1, @"Can't add objects to array");
	
	[array1 insertObject:@"object2" atIndex:0];
	[array1 removeLastObject];
	XCTAssertEqual([array1 count], 1, @"Add/remove objects not working right.");
	XCTAssertEqual(array1[0], @"object2", @"Wrong object in array");
	
	[array1 insertObject:@"object3" atIndex:1];
	[array1 removeObjectAtIndex:0];
	XCTAssertEqual([array1 count], 1, @"Add/remove objects not working right.");
	
	[array1 replaceObjectAtIndex:0 withObject:@"object4"];
	XCTAssertEqual(array1[0], @"object4", @"ReplaceObjectAtIndex not working");
	
	[array1 addObjectsFromArray:@[@"object5", @"object6"]];
	XCTAssertEqual(array1.count, 3, @"addObjectsFromArray not working");
	XCTAssertEqual(array1[2], @"object6", @"addObjectsFromArray not working");

	[array1 removeObjectsInArray:@[@"object5", @"object6"]];
	XCTAssertEqual(array1.count, 1, @"removeObjectsInArray not working");
	XCTAssertEqual(array1[0], @"object4", @"removeObjectsInArray not working");
}

- (void) testArrayObservation
{
	[mao1.array addObjectsFromArray:@[@"object0", @"object1", @"object2", @"object3", @"object4"]];
	
	ObservePropertyNoPropCheck(mao1, array.3,
	{
		++blockSelf->observerCallCount;
	});
	
	[self->mao1 tell:self when:@"array.4" changes:^(ObservableArrayTests *blockSelf, ModelArrayObject1 *observed)
	{
		++blockSelf->observerCallCount;
	}];
	
	[mao1.array addObject:@"object5"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 0, @"Observation block got called when it shouldn't.");

	[mao1.array insertObject:@"object6" atIndex:0];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 0, @"Observation block got called when it shouldn't.");

	[mao1.array removeObjectAtIndex:4];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");
	
	[mao1.array removeObjectAtIndex:4];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block didn't get called.");
	XCTAssertEqual([mao1.array.allObservedProperties count], 0, @"Observations didn't get removed.");
}

- (void) testRemoveAllObjects
{
	NSMutableArray *array1 = [[NSMutableArray alloc] init];
	[array1 addObjectsFromArray:@[@"object0", @"object1", @"object2", @"object3", @"object4"]];
	
	// Make several observations on array1
	[Observe(ValidatePaths(array1)
	{
		++blockSelf->observerCallCount;
	}) observe:@"3.invalidKey"];
	[Observe(ValidatePaths(array1)
	{
		++blockSelf->observerCallCount;
	}) observe:@"#3"];
	[Observe(ValidatePaths(array1)
	{
		++blockSelf->observerCallCount;
	}) observe:@"*"];
	Observe(ValidatePaths(array1, count)
	{
		++blockSelf->observerCallCount;
	});
	
	[array1 removeAllObjects];
	
	// All the valid blocks should get called due to the removeAllObjects, but each observer should only be called once.
	XCTAssertEqual(self->observerCallCount, 0, @"Should be 0 before calling the callback");
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 4, @"Observation blocks didn't get called.");
	
	// "#3", "*" and "count" should still be observed, but "3" should get removed
	XCTAssertEqual([array1.allObservedProperties count], 3, @"Observation on 3 didn't get removed.");
}

- (void) testArrayObservationRemoval
{
	[mao1.array addObjectsFromArray:@[@"object0", @"object1", @"object2", @"object3", @"object4"]];
	
	ObservePropertyNoPropCheck(mao1, array.3,
	{
		++blockSelf->observerCallCount;
	});
	
	[mao1 stopTelling:self aboutChangesTo:@"array.3"];
	XCTAssertEqual([mao1.array.allObservedProperties count], 0, @"Observations didn't get removed.");
	
	ObservePropertyNoPropCheck(mao1, array.2,
	{
		++blockSelf->observerCallCount;
	});
	
	
	[mao1.array removeObjectAtIndex:0];
	[mao1 stopTelling:self aboutChangesTo:@"array.2"];
	XCTAssertEqual([mao1.array.allObservedProperties count], 0, @"Observations didn't get removed.");
}

- (void) testArrayIndexObservation
{
	[mao1 tell:self when:@"array.#4" changes:^(ObservableArrayTests *blockSelf, ModelArrayObject1 *observed)
	{
		++blockSelf->observerCallCount;
	}];
	
	[mao1.array addObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 0, @"Observation block got called when it shouldn't.");

	[mao1.array addObjectsFromArray:@[@"object2",@"object3",@"object4",@"object5"]];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");
	
	[mao1.array insertObject:@"object5" atIndex:1];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block didn't get called.");
	
	[mao1.array removeObjectAtIndex:1];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block didn't get called.");
	
	[mao1.array replaceObjectAtIndex:3 withObject:@"object6"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called when it shouldn't.");
	
	[mao1.array replaceObjectAtIndex:4 withObject:@"object7"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 4, @"Observation block didn't get called.");
	
	[mao1.array removeObjectAtIndex:4];
	XCTAssertEqual([mao1.array count], 4, @"Wrong number of objects in array");
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 5, @"Observation block didn't get called.");
	
	[mao1.array addObject:@"object8"];
	XCTAssertEqual([mao1.array count], 5, @"Wrong number of objects in array");
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 6, @"Observation block didn't get called.");

	[mao1.array removeLastObject];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 7, @"Observation block didn't get called.");
	[mao1.array removeLastObject];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 7, @"Observation block got called when it shouldn't.");

}

- (void) testArrayObserveAll
{
	ObservePropertyNoPropCheck(mao1, array.*,
	{
		++blockSelf->observerCallCount;
	});
	
	[mao1.array addObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");
	
	[mao1.array addObjectsFromArray:@[@"object2",@"object3",@"object4"]];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block didn't get called.");

	[mao1.array removeLastObject];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block didn't get called.");

	[mao1.array removeObjectAtIndex:0];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 4, @"Observation block didn't get called.");
	
	[mao1 stopTelling:self aboutChangesTo:@"array.*"];
	[mao1.array removeObjectAtIndex:0];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 4, @"Observation block got called when it shouldn't.");
}

- (void) testMultiArray
{
	NSMutableArray *depth1 = [[NSMutableArray alloc] init];
	NSMutableArray *depth2 = [[NSMutableArray alloc] init];
	
	[mao1.array addObject:depth1];
	[depth1 addObject:depth2];
	[depth2 addObject:@"object0"];
	
	[mao1 tell:self when:@"array.0.0.0" changes:^(ObservableArrayTests *blockSelf, ModelArrayObject1 *observed)
	{
		++blockSelf->observerCallCount;
	}];
	
	[depth2 removeAllObjects];
	
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");

}

- (void) testObserveCount
{
	ObserveProperty(mao1, array.count,
	{
		++blockSelf->observerCallCount;
	});
	
	[mao1.array addObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");

	[mao1.array addObjectsFromArray:@[@"object2",@"object3",@"object4"]];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block didn't get called.");
	
	[mao1.array removeLastObject];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block didn't get called.");
	
	[mao1.array replaceObjectAtIndex:0 withObject:@"object5"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called when it shouldn't.");
}

- (void) testCopying
{
	NSNumber *objects[] = { @1, @2 };
	NSMutableArray *sourceArray = [[NSMutableArray alloc] initWithObjects:objects count:2];

	NSArray *destArray = [sourceArray copy];
	XCTAssertEqualObjects(destArray[0], @1, @"Array copy failed somehow");
	XCTAssertEqualObjects(destArray[1], @2, @"Array copy failed somehow");

	NSMutableArray *mutableDestArray = [sourceArray mutableCopy];
	XCTAssertEqualObjects(mutableDestArray[0], @1, @"Array copy failed somehow");
	XCTAssertEqualObjects(mutableDestArray[1], @2, @"Array copy failed somehow");
}

- (void) testEncoding
{
	NSNumber *objects[] = { @1, @2 };
	NSMutableArray *sourceArray = [[NSMutableArray alloc] initWithObjects:objects count:2];
	
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:sourceArray];
	XCTAssertNotNil(data, @"Encoding an observable array appears to have failed");
	
	NSArray *rebuiltArray = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	XCTAssertNotNil(rebuiltArray, @"Decoding an observable array appears to have failed");
	XCTAssertEqualObjects(rebuiltArray[0], @1, @"Array coding failed somehow");
	XCTAssertEqualObjects(rebuiltArray[1], @2, @"Array coding failed somehow");
}

- (void) testWildcards
{
	ModelArrayObject1 *moBase = [ModelArrayObject1 new];
	__block int blockCallCount = 0;
	
	// Make a wildcard observation before adding objects (tests that mutations cause updates)
	[moBase tell:self when:@"array.*.intProperty" changes:
	^(ObservableArrayTests *blockSelf, ModelArrayObject1 *observed)
	{
		++blockCallCount;
	}];
	
	for (int index = 0; index < 10; ++index)
	{
		ModelArrayObject1 *mo = [ModelArrayObject1 new];
		[moBase.array addObject:mo];
	}
	
	// Make another wildcard observation after adding objects (tests initial setup)
	[moBase tell:self when:@"array.*.intProperty2" changes:
	^(ObservableArrayTests *blockSelf, ModelArrayObject1 *observed)
	{
		++blockCallCount;
	}];
	
	XCTAssertEqual(blockCallCount, 0, @"Observation can't be called yet.");
	ModelArrayObject1 *mo0 = moBase.array[0];
	mo0.intProperty = 5;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 1, @"Observation block didn't get called.");
	mo0.intProperty2 = 8;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 2, @"Observation block didn't get called.");
	
	ModelArrayObject1 *mo5 = moBase.array[5];
	mo5.intProperty = 7;
	mo5.intProperty2 = 3;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 4, @"Observation block didn't get called.");
	
	// Removing the last object in the array will cause both "*" observations to fire
	ModelArrayObject1 *mo9 = moBase.array[9];
	[moBase.array removeLastObject];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 6, @"Observation block didn't get called.");
	
	// But then mutating the removed object shouldn't fire anything
	mo9.intProperty = 9;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 6, @"Observation block shouldn't get called for mutation after removal.");

	// Add it back in, twice. Changing the int property should trigger as well, but get merged
	[moBase.array addObject:mo9];
	[moBase.array addObject:mo9];
	mo9.intProperty = 99;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 8, @"Observation block didn't get called.");
	
	// And then mutating the int prop should trigger the same observation twice (which then get merged)
	mo9.intProperty = 100;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 9, @"Observation block didn't get called.");
	
	// Removing fires both observations, then setting int fires the first (merged in to 2)
	[moBase.array removeLastObject];
	mo9.intProperty = 101;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 11, @"Observation block didn't get called.");
	
	// Then, setting the int should fire once (this tests that remove doesn't remove all observations in the
	// case where the same object is in an array multiple times)
	mo9.intProperty = 102;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 12, @"Observation block didn't get called.");


}

@end


