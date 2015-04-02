/****************************************************************************************************
	ObservableSetTests.m
	Observable
	
    Created by Chall Fry on 5/26/14.
    Copyright (c) 2013-2014 eBay Software Foundation.

    Unit tests.
*/

@import XCTest;

#import "EBNObservable.h"
#import "EBNObservableCollections.h"

// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asyncronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);



@interface ModelSetObject1 : EBNObservable

@property (strong) EBNObservableSet *observableSet;

@end

@implementation ModelSetObject1

- (instancetype) init
{
	if (self = [super init])
	{
		_observableSet = [[EBNObservableSet alloc] init];
	}
	return self;
}

@end



@interface ObservableSetTests : XCTestCase

@end

@implementation ObservableSetTests
{
	ModelSetObject1		*mo1;
	int					observerCallCount;
}

- (void)setUp
{
    [super setUp];
	
	mo1 = [[ModelSetObject1 alloc] init];
	observerCallCount = 0;
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testSetHashing
{
	// Put something in the set
	NSString *str = @"aString";
	[mo1.observableSet addObject:str];
	
	// Hash it into a string we can use in keypaths
    NSString *hash = [EBNObservableSet keyForObject:str];
	
	// Get the object back from the hash string
	id objectFromHash = [mo1.observableSet objectForKey:hash];
	
	XCTAssertEqualObjects(str, objectFromHash, @"Hashing an object and then retrieving from hash may be broken.");
}

- (void) testObservation
{
	// Put something in the set
	NSString *str = @"aString";
	[mo1.observableSet addObject:str];
	
	NSString *keyPathStr = [NSString stringWithFormat:@"observableSet.%@", [EBNObservableSet keyForObject:str]];
	
	[mo1 tell:self when:keyPathStr changes:^(ObservableSetTests *blockSelf, ModelSetObject1 *observed)
	{
		blockSelf->observerCallCount++;
		NSLog(@"we did it.");
	}];

	[mo1.observableSet addObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 0, @"Observation block got called when it shouldn't have.");
	
	[mo1.observableSet removeObject:str];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");
	
	[mo1 stopTellingAboutChanges:self];
	[mo1.observableSet addObject:str];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block got called when it shouldn't have.");
	
}

- (void) testObserveEverything
{
	ObservePropertyNoPropCheck(mo1, observableSet.*,
	{
		blockSelf->observerCallCount++;
	});
	
	[mo1.observableSet addObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block got called wrong number of times.");
	
	[mo1.observableSet addObject:@"object2"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block got called wrong number of times.");

	// Same hash as previously added object
	[mo1.observableSet addObject:@"object2"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block got called wrong number of times.");
	
	[mo1.observableSet addObject:@"object3"];
	[mo1.observableSet addObject:@"object4"];
	[mo1.observableSet addObject:@"object5"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called.");
	
	[mo1 stopTellingAboutChanges:self];
	[mo1.observableSet addObject:@"object6"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called when it shouldn't have.");

}

- (void) testObserveCount
{
	ObserveProperty(mo1, observableSet.count,
	{
		++blockSelf->observerCallCount;
	});
	
	[mo1.observableSet addObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");

	[mo1.observableSet addObject:@"object2"];
	[mo1.observableSet addObject:@"object3"];
	[mo1.observableSet addObject:@"object4"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block got called wrong number of times.");
	
	[mo1.observableSet addObject:@"object2"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block got called wrong number of times.");

	[mo1.observableSet removeObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block didn't get called.");
		
	[mo1 stopTellingAboutChanges:self];
	[mo1.observableSet addObject:@"object5"];
	[mo1.observableSet removeAllObjects];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called when it shouldn't have.");
}


@end
