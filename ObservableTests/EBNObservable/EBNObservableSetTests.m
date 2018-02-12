/****************************************************************************************************
	ObservableSetTests.m
	Observable
	
    Created by Chall Fry on 5/26/14.
    Copyright (c) 2013-2018 eBay Software Foundation.

    Unit tests.
*/

@import XCTest;

#import "EBNObservable.h"
#import "EBNObservableInternal.h"
#import "EBNObservableUnitTestSupport.h"

// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asyncronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);



@interface ModelSetObject1 : NSObject

@property (strong) NSMutableSet 		*mutableSet;
@property (assign) int					intProperty;
@property (assign) int					intProperty2;

@end

@implementation ModelSetObject1

- (instancetype) init
{
	if (self = [super init])
	{
		_mutableSet = [[NSMutableSet alloc] init];
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

- (void) setUp
{
    [super setUp];
	
	mo1 = [[ModelSetObject1 alloc] init];
	observerCallCount = 0;
}

- (void) tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void) testSetHashing
{
	// Put something in the set
	NSString *str = @"aString";
	[mo1.mutableSet addObject:str];
	
	// Hash it into a string we can use in keypaths
    NSString *hash = [NSSet ebn_keyForObject:str];
	
	// Get the object back from the hash string
	id objectFromHash = [mo1.mutableSet ebn_objectForKey:hash];
	
	XCTAssertEqualObjects(str, objectFromHash, @"Hashing an object and then retrieving from hash may be broken.");
	
	objectFromHash = [mo1.mutableSet ebn_objectForKey:@"notahashvalue"];
	XCTAssertNil(objectFromHash, @"Strings that aren't hashes should return nil from objectForKey.");
	objectFromHash = [mo1.mutableSet ebn_objectForKey:nil];
	XCTAssertNil(objectFromHash, @"Nil strings should return nil from objectForKey.");

	objectFromHash = [mo1.mutableSet ebn_valueForKey:hash];
	XCTAssertEqualObjects(str, objectFromHash, @"ebn_valueForKey may be broken for sets.");

	objectFromHash = [mo1.mutableSet ebn_valueForKey:@"count"];
	XCTAssertEqual(1, [objectFromHash intValue], @"ebn_valueForKey may be broken for sets.");
}


- (void) testObservation
{
	// Put something in the set
	NSString *str = @"aString";
	[mo1.mutableSet addObject:str];
	
	// Make a keypath string and start observing it
	NSString *keyPathStr = [NSString stringWithFormat:@"mutableSet.%@", [NSSet ebn_keyForObject:str]];
	[mo1 tell:self when:keyPathStr changes:^(ObservableSetTests *blockSelf, ModelSetObject1 *observed)
	{
		blockSelf->observerCallCount++;
	}];

	[mo1.mutableSet addObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 0, @"Observation block got called when it shouldn't have.");
	
	[mo1.mutableSet removeObject:str];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");
	
	[mo1.mutableSet addObject:str];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block didn't get called.");
	
	[mo1.mutableSet removeAllObjects];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block didn't get called.");

	[mo1.mutableSet addObjectsFromArray:@[@"aString"]];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 4, @"Observation block didn't get called.");

	NSSet *interSet = [NSSet setWithObject:@"anotherString"];
	[mo1.mutableSet intersectSet:interSet];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 5, @"Observation block didn't get called.");

	NSSet *unionSet = [NSSet setWithObject:str];
	[mo1.mutableSet unionSet:unionSet];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 6, @"Observation block didn't get called.");
	
	[mo1 stopTellingAboutChanges:self];
	[mo1.mutableSet addObject:str];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 6, @"Observation block got called when it shouldn't have.");
	
}

- (void) testObserveEverything
{
	ObservePropertyNoPropCheck(mo1, mutableSet.*,
	{
		blockSelf->observerCallCount++;
	});
	
	[mo1.mutableSet addObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block got called wrong number of times.");
	
	[mo1.mutableSet addObject:@"object2"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block got called wrong number of times.");

	// Same hash as previously added object
	[mo1.mutableSet addObject:@"object2"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block got called wrong number of times.");
	
	[mo1.mutableSet addObject:@"object3"];
	[mo1.mutableSet addObject:@"object4"];
	[mo1.mutableSet addObject:@"object5"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called.");

	[mo1.mutableSet minusSet:[NSSet setWithObject:@"object5"]];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 4, @"Observation block got called.");
	
	[mo1.mutableSet minusSet:[NSSet setWithObject:@"objectNotInSet"]];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 4, @"Observation block got called when it shouldn't have.");
	
	[mo1.mutableSet setSet:[NSSet set]];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 5, @"Observation block didn't get called.");
	
	[mo1 stopTellingAboutChanges:self];
	[mo1.mutableSet addObject:@"object6"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 5, @"Observation block got called when it shouldn't have.");

}

- (void) testObserveCount
{
	ObserveProperty(mo1, mutableSet.count,
	{
		++blockSelf->observerCallCount;
	});
	
	[mo1.mutableSet addObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");

	[mo1.mutableSet addObject:@"object2"];
	[mo1.mutableSet addObject:@"object3"];
	[mo1.mutableSet addObject:@"object4"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block got called wrong number of times.");
	
	[mo1.mutableSet addObject:@"object2"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block got called wrong number of times.");

	[mo1.mutableSet removeObject:@"object1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block didn't get called.");
		
	[mo1 stopTellingAboutChanges:self];
	[mo1.mutableSet addObject:@"object5"];
	[mo1.mutableSet removeAllObjects];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called when it shouldn't have.");
}

- (void) testCopying
{
	NSNumber *objects[] = { @1, @2 };
	NSSet *sourceSet = [[NSSet alloc] initWithObjects:objects count:2];
	NSSet *comparisonSet = [[NSSet alloc] initWithObjects:objects count:2];
	
	[sourceSet tell:self when:@"*.invalidKey" changes:
			^(ObservableSetTests *blockSelf, ModelSetObject1 *observed)
			{
				blockSelf->observerCallCount++;
			}];

	NSSet *destSet = [sourceSet copy];
	XCTAssertEqualObjects(destSet, comparisonSet, @"Set copy failed somehow");

	NSMutableSet *mutableDestSet = [sourceSet mutableCopy];
	XCTAssertEqualObjects(mutableDestSet, comparisonSet, @"Set copy failed somehow");
}

- (void) testMutableCopying
{
	NSNumber *objects[] = { @1, @2 };
	NSMutableSet *sourceSet = [[NSMutableSet alloc] initWithObjects:objects count:2];
	NSSet *comparisonSet = [[NSSet alloc] initWithObjects:objects count:2];

	[sourceSet tell:self when:[NSSet ebn_keyForObject:objects[0]] changes:
			^(ObservableSetTests *blockSelf, ModelSetObject1 *observed)
			{
				blockSelf->observerCallCount++;
			}];

	NSSet *destSet = [sourceSet copy];
	XCTAssertEqualObjects(destSet, comparisonSet, @"Set copy failed somehow");

	NSMutableSet *mutableDestSet = [sourceSet mutableCopy];
	XCTAssertEqualObjects(mutableDestSet, comparisonSet, @"Set copy failed somehow");

	[sourceSet removeAllObjects];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");
}

- (void) testEncoding
{
	NSNumber *objects[] = { @1, @2 };
	NSSet *sourceSet = [[NSSet alloc] initWithObjects:objects count:2];
	NSSet *comparisonSet = [[NSSet alloc] initWithObjects:objects count:2];
	
	// Force sourceSet to be an observable subclass
	[sourceSet tell:self when:@"*.invalidKey" changes:
			^(ObservableSetTests *blockSelf, ModelSetObject1 *observed)
			{
				blockSelf->observerCallCount++;
			}];
	
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:sourceSet];
	XCTAssertNotNil(data, @"Encoding an observable set appears to have failed");
	
	NSSet *rebuiltSet = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	XCTAssertNotNil(rebuiltSet, @"Decoding an observable set appears to have failed");
	XCTAssertEqualObjects(rebuiltSet, comparisonSet, @"Set coding failed somehow");
}

- (void) testMutableEncoding
{
	NSNumber *objects[] = { @1, @2 };
	NSMutableSet *sourceSet = [[NSMutableSet alloc] initWithObjects:objects count:2];
	NSSet *comparisonSet = [[NSSet alloc] initWithObjects:objects count:2];
	
	[sourceSet tell:self when:[NSSet ebn_keyForObject:objects[0]] changes:
			^(ObservableSetTests *blockSelf, ModelSetObject1 *observed)
			{
				blockSelf->observerCallCount++;
			}];

	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:sourceSet];
	XCTAssertNotNil(data, @"Encoding an observable set appears to have failed");
	
	NSMutableSet *rebuiltSet = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	XCTAssertNotNil(rebuiltSet, @"Decoding an observable set appears to have failed");
	XCTAssertEqualObjects(rebuiltSet, comparisonSet, @"Set coding failed somehow");
}

- (void) testWildcards
{
	ModelSetObject1 *moBase = [ModelSetObject1 new];
	__block int blockCallCount = 0;
	
	// Make a wildcard observation before adding objects (tests that mutations cause updates)
	[moBase tell:self when:@"mutableSet.*.intProperty" changes:
	^(ObservableSetTests *blockSelf, ModelSetObject1 *observed)
	{
		++blockCallCount;
	}];
	
	ModelSetObject1 *mo0 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mo0];
	ModelSetObject1 *mob1 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mob1];
	ModelSetObject1 *mo2 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mo2];
	ModelSetObject1 *mo3 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mo3];
	ModelSetObject1 *mo4 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mo4];
	ModelSetObject1 *mo5 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mo5];
	ModelSetObject1 *mo6 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mo6];
	ModelSetObject1 *mo7 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mo7];
	ModelSetObject1 *mo8 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mo8];
	ModelSetObject1 *mo9 = [ModelSetObject1 new]; [moBase.mutableSet addObject:mo9];

	
	// Make another wildcard observation after adding objects (tests initial setup)
	[moBase tell:self when:@"mutableSet.*.intProperty2" changes:
	^(ObservableSetTests *blockSelf, ModelSetObject1 *observed)
	{
		++blockCallCount;
	}];
	
	XCTAssertEqual(blockCallCount, 0, @"Observation can't be called yet.");
	mo0.intProperty = 5;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 1, @"Observation block didn't get called.");
	mo0.intProperty2 = 8;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 2, @"Observation block didn't get called.");
	
	mo5.intProperty = 7;
	mo5.intProperty2 = 3;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 4, @"Observation block didn't get called.");
	
	// Removing the object at @"9" cause both "*" observations to fire
	[moBase.mutableSet removeObject:mo9];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 6, @"Observation block didn't get called.");
	
	// But then mutating the removed object shouldn't fire anything
	mo9.intProperty = 9;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 6, @"Observation block shouldn't get called for mutation after removal.");

	// Add it back in, twice. Code should recognize the second set doesn't actually mutate
	[moBase.mutableSet addObject:mo9];
	[moBase.mutableSet addObject:mo9];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 8, @"Observation block didn't get called.");
	
	// And then mutating the int prop should trigger the same observation twice (which then get merged)
	mo9.intProperty = 100;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 9, @"Observation block didn't get called.");
	
	// Removing fires both observations, then setting int fires the first (merged in to 2)
	[moBase.mutableSet removeObject:mo9];
	mo9.intProperty = 101;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 11, @"Observation block didn't get called.");
}



@end
