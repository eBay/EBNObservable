/****************************************************************************************************
	ObservableDictionaryTests.m
	Observable
	
    Created by Chall Fry on 4/19/14.
    Copyright (c) 2013-2014 eBay Software Foundation.

    Unit tests.
*/

#import <XCTest/XCTest.h>
#import "EBNObservable.h"
#import "EBNObservableCollections.h"

// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asyncronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);


@interface DictModelObject1 : EBNObservable

@property (strong) EBNObservableDictionary *dict;

@end

@implementation DictModelObject1

- (instancetype) init
{
	if (self = [super init])
	{
		_dict = [[EBNObservableDictionary alloc] init];
	}
	return self;
}

@end



@interface ObservableDictionaryTests : XCTestCase
@end

@implementation ObservableDictionaryTests
{
	DictModelObject1		*mo1;
	int					observerCallCount;
}

- (void)setUp
{
    [super setUp];

	mo1 = [[DictModelObject1 alloc] init];
	observerCallCount = 0;
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void) testDictionaryBasics
{
	// Admittedly, some of these tests are sort of specious
	
	EBNObservableDictionary *dict1 = [[EBNObservableDictionary alloc] init];
	EBNObservableDictionary *dict2 = [[EBNObservableDictionary alloc] initWithCapacity:3];
	EBNObservableDictionary *dict3 = [[EBNObservableDictionary alloc] initWithDictionary:@{@"key1" : @"object1"}];
	EBNObservableDictionary *dict4 = [[EBNObservableDictionary alloc] initWithObjectsAndKeys:@"object1", @"key1", nil];
	EBNObservableDictionary *dict5 = [[EBNObservableDictionary alloc] initWithObjects:@[@"object1"] forKeys:@[@"key1"]];
	EBNObservableDictionary *dict6 = [EBNObservableDictionary dictionary];
		
	// Does it still act as a dictionary? Just making sure the plumbing to the sub-dict doesn't break
	[dict1 setObject:@"object1" forKey:@"key1"];
	[dict2 setObject:@"object1" forKey:@"key1"];
	[dict3 setObject:@"object1" forKey:@"key1"];
	[dict4 setObject:@"object1" forKey:@"key1"];
	[dict5 setObject:@"object1" forKey:@"key1"];
	[dict6 setObject:@"object1" forKey:@"key1"];
	XCTAssertEqual(@"object1", [dict1 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [dict2 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [dict3 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [dict4 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [dict5 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [dict6 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(1, [dict1 count], @"This dictionary seems confused as to how many objects it has");
	
	int loopCount = 0;
	for (NSString *keyEnum in dict1)
	{
		++loopCount;
		XCTAssertEqual(keyEnum, @"key1", @"How do we get the *wrong* key here?");
	}
	XCTAssertEqual(loopCount, 1, @"Fast Enumeration may be broken in the dictionary.");
	[dict1 removeObjectForKey:@"notarealkey"];
	XCTAssertEqual([dict1 count], 1, @"Removing a fake key shouldn't change how many real keys are in the dict.");
	[dict1 removeObjectForKey:@"key1"];
	XCTAssertEqual([dict1 count], 0, @"Removing keys from the dict may be broken.");
}

- (void) testObservation
{
	ObservePropertyNoPropCheck(mo1, dict.key1,
	{
		blockSelf->observerCallCount++;
	});

	[mo1.dict setObject:@"object1" forKey:@"key1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block got called.");
	
	[mo1 stopTellingAboutChanges:self];
	[mo1.dict setObject:@"object2" forKey:@"key1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block got called when it shouldn't have.");
	
}

- (void) testObserveEverything
{
	ObservePropertyNoPropCheck(mo1, dict.*,
	{
		blockSelf->observerCallCount++;
	});
	
	[mo1.dict setObject:@"object1" forKey:@"key1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block got called.");
	
	[mo1.dict setObject:@"object1" forKey:@"key2"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block got called.");
	
	[mo1.dict setObject:@"object3" forKey:@"key3"];
	[mo1.dict setObject:@"object4" forKey:@"key4"];
	[mo1.dict setObject:@"object5" forKey:@"key5"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called.");
	
	[mo1 stopTellingAboutChanges:self];
	[mo1.dict setObject:@"object2" forKey:@"key1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called when it shouldn't have.");

}

- (void) testObserveCount
{
	ObserveProperty(mo1, dict.count,
	{
		++blockSelf->observerCallCount;
	});
	
	[mo1.dict setObject:@"object1" forKey:@"key1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");

	[mo1.dict setObject:@"object2" forKey:@"key2"];
	[mo1.dict setObject:@"object3" forKey:@"key3"];
	[mo1.dict setObject:@"object4" forKey:@"key4"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block didn't get called.");
	
	[mo1.dict removeObjectForKey:@"key2"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block didn't get called.");

	[mo1.dict removeObjectForKey:@"key5"];	// doesn't exist
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called when it shouldn't.");
	
	[mo1.dict setObject:@"object5" forKey:@"key1"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called when it shouldn't.");
	
	[mo1 stopTellingAboutChanges:self];
	[mo1.dict setObject:@"object6" forKey:@"key2"];
	[mo1.dict setObject:@"object6" forKey:@"key6"];
	[mo1.dict removeAllObjects];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 3, @"Observation block got called when it shouldn't have.");
}



@end
