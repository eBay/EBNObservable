/****************************************************************************************************
	ObservableArrayTests.m
	Observable
	
    Created by Chall Fry on 5/30/14.
    Copyright (c) 2013-2014 eBay Software Foundation.

    Unit tests.
*/

@import XCTest;

#import "EBNObservable.h"
#import "EBNObservableCollections.h"
#import "DebugUtils.h"


// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asyncronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);


@interface ModelArrayObject1 : EBNObservable

@property (strong) EBNObservableArray *array;

@end

@implementation ModelArrayObject1

- (instancetype) init
{
	if (self = [super init])
	{
		_array = [[EBNObservableArray alloc] init];
	}
	return self;
}

@end

@interface ObservableArrayTests : EBNTestCase

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

- (void)testArrayBasics
{
	EBNObservableArray *array1 = [[EBNObservableArray alloc] init];
	
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
}

- (void) testArrayObservation
{
	[mao1.array addObjectsFromArray:@[@"object0", @"object1", @"object2", @"object3", @"object4"]];
	
	ObservePropertyNoPropCheck(self->mao1, array.3,
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

- (void) testArrayObservationRemoval
{
	[mao1.array addObjectsFromArray:@[@"object0", @"object1", @"object2", @"object3", @"object4"]];
	
	ObservePropertyNoPropCheck(mao1, array.3,
	{
		++blockSelf->observerCallCount;
	});
	
	[mao1 stopTelling:self aboutChangesTo:@"array.3"];
	XCTAssertEqual([mao1.array.allObservedProperties count], 0, @"Observations didn't get removed.");
	
	ObservePropertyNoPropCheck(self->mao1, array.2,
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
	EBNObservableArray *depth1 = [[EBNObservableArray alloc] init];
	EBNObservableArray *depth2 = [[EBNObservableArray alloc] init];
	
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
	EBNObservableArray *sourceArray = [[EBNObservableArray alloc] initWithObjects:objects count:2];

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
	EBNObservableArray *sourceArray = [[EBNObservableArray alloc] initWithObjects:objects count:2];
	
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:sourceArray];
	XCTAssertNotNil(data, @"Encoding an observable array appears to have failed");
	
	NSArray *rebuiltArray = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	XCTAssertNotNil(rebuiltArray, @"Decoding an observable array appears to have failed");
	XCTAssertEqualObjects(rebuiltArray[0], @1, @"Array coding failed somehow");
	XCTAssertEqualObjects(rebuiltArray[1], @2, @"Array coding failed somehow");
}

@end
