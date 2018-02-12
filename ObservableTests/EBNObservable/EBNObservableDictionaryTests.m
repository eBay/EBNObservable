/****************************************************************************************************
	ObservableDictionaryTests.m
	Observable
	
    Created by Chall Fry on 4/19/14.
    Copyright (c) 2013-2018 eBay Software Foundation.

    Unit tests.
*/

@import XCTest;

#import "EBNObservable.h"
#import "EBNObservableUnitTestSupport.h"


// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asynchronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);


@interface DictModelObject1 : NSObject

@property (strong) NSMutableDictionary *dict;
@property (assign) int					intProperty;
@property (assign) int					intProperty2;

@end

@implementation DictModelObject1

- (instancetype) init
{
	if (self = [super init])
	{
		_dict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

@end



@interface ObservableDictionaryTests : XCTestCase

@property	NSMutableDictionary *dict1;
@property	NSMutableDictionary *dict2;
@property	NSMutableDictionary *dict3;
@property	NSMutableDictionary *dict4;
@property	NSMutableDictionary *dict5;
@property	NSMutableDictionary *dict6;

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
	
	NSDictionary *dict = [[NSDictionary alloc] init];
	Class origClassName = object_getClass(dict);
	ObservePropertyNoPropCheck(dict, key1.invalidKey, { blockSelf->observerCallCount++; });
	
	// Check the class hierarchy--at this point all dicts should be Observable shadow classes
	XCTAssertNotEqual(origClassName, object_getClass(dict),
			@"The actual class for this object should (probably) now be __NSDictionary0_EBNShadowClass.");
	XCTAssertEqual(class_getSuperclass(object_getClass(dict)), origClassName,
			@"Superclass should now equal the original classname.");

	XCTAssertEqual(dict.count, 0, @"Empty dictionaries should be empty? IDK what say here.");
	
	self.dict1 = [[NSMutableDictionary alloc] init];
	self.dict2 = [[NSMutableDictionary alloc] initWithCapacity:3];
	self.dict3 = [[NSMutableDictionary alloc] initWithDictionary:@{@"key1" : @"object1"}];
	self.dict4 = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@"object1", @"key1", nil];
	self.dict5 = [[NSMutableDictionary alloc] initWithObjects:@[@"object1"] forKeys:@[@"key1"]];
	self.dict6 = [NSMutableDictionary dictionary];
	
	origClassName = object_getClass(self.dict1);
	
	ObservePropertyNoPropCheck(self, dict1.key1, { blockSelf->observerCallCount++; });
	ObservePropertyNoPropCheck(self, dict2.key1, { blockSelf->observerCallCount++; });
	ObservePropertyNoPropCheck(self, dict3.key1, { blockSelf->observerCallCount++; });
	ObservePropertyNoPropCheck(self, dict4.key1, { blockSelf->observerCallCount++; });
	ObservePropertyNoPropCheck(self, dict5.key1, { blockSelf->observerCallCount++; });
	ObservePropertyNoPropCheck(self, dict6.key1, { blockSelf->observerCallCount++; });
	
	// Check the class hierarchy--at this point all dicts should be Observable shadow classes
	XCTAssertNotEqual(origClassName, object_getClass(self.dict1),
			@"The actual class for this object should (probably) now be __NSDictionaryM_EBNShadowClass.");
	XCTAssertEqual(class_getSuperclass(object_getClass(self.dict1)), origClassName,
			@"Superclass should now equal the original classname.");
	
	// Does it still act as a dictionary?
	[self.dict1 setObject:@"object1" forKey:@"key1"];
	[self.dict2 setObject:@"object1" forKey:@"key1"];
	[self.dict3 setObject:@"object1" forKey:@"key1"];
	[self.dict4 setObject:@"object1" forKey:@"key1"];
	[self.dict5 setObject:@"object1" forKey:@"key1"];
	[self.dict6 setObject:@"object1" forKey:@"key1"];
	XCTAssertEqual(@"object1", [self.dict1 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [self.dict2 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [self.dict3 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [self.dict4 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [self.dict5 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(@"object1", [self.dict6 objectForKey:@"key1"], @"This dictionary can't get/set objects.");
	XCTAssertEqual(1, [self.dict1 count], @"This dictionary seems confused as to how many objects it has");
	
	int loopCount = 0;
	for (NSString *keyEnum in self.dict1)
	{
		++loopCount;
		XCTAssertEqual(keyEnum, @"key1", @"How do we get the *wrong* key here?");
	}
	XCTAssertEqual(loopCount, 1, @"Fast Enumeration may be broken in the dictionary.");
	[self.dict1 removeObjectForKey:@"notarealkey"];
	XCTAssertEqual([self.dict1 count], 1, @"Removing a fake key shouldn't change how many real keys are in the dict.");
	[self.dict1 removeObjectForKey:@"key1"];
	XCTAssertEqual([self.dict1 count], 0, @"Removing keys from the dict may be broken.");
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

- (void) testRemoveAll
{
	ObservePropertyNoPropCheck(mo1, dict.*,
	{
		blockSelf->observerCallCount++;
	});
	
	[mo1.dict setObject:@"object1" forKey:@"key1"];
	[mo1.dict setObject:@"object2" forKey:@"key2"];
	[mo1.dict setObject:@"object3" forKey:@"key3"];
	[mo1.dict setObject:@"object4" forKey:@"key4"];
	[mo1.dict setObject:@"object5" forKey:@"key5"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 1, @"Observation block didn't get called.");
	
	[mo1.dict removeAllObjects];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 2, @"Observation block didn't get called.");
	XCTAssertEqual(mo1.dict.count, 0, @"RemoveAll didn't actually remove objects.");
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

- (void) testCopying
{
	NSNumber *objects[] = { @1, @2 };
	NSDictionary *sourceDictionary = [[NSDictionary alloc] initWithObjects:objects forKeys:objects count:2];
	NSDictionary *comparisonDictionary = [[NSDictionary alloc] initWithObjects:objects forKeys:objects count:2];

	// Check the orig class name, start an observation, check that the class changed--that is, we isa-swizzled
	Class origClassName = object_getClass(sourceDictionary);
	ObservePropertyNoPropCheck(sourceDictionary, validKey.invalidKey,
	{
		++blockSelf->observerCallCount;
	});
	XCTAssertNotEqual(origClassName, object_getClass(sourceDictionary),
			@"The actual class for this object should (probably) now be __NSDictionaryI_EBNShadowClass.");

	NSDictionary *destDictionary = [sourceDictionary copy];
	XCTAssertEqualObjects(destDictionary, comparisonDictionary, @"Dictionary copy failed somehow");

	NSMutableDictionary *mutableDestDictionary = [sourceDictionary mutableCopy];
	XCTAssertEqualObjects(mutableDestDictionary, comparisonDictionary, @"Dictionary mutableCopy failed somehow");
	
	[mutableDestDictionary setObject:@"obj" forKey:@"key33"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 0, @"Observation block shouldn't get called when copy mutates. "
			@"Observations should not follow copies.");
}

- (void) testMutableCopying
{
	NSNumber *objects[] = { @1, @2 };
	NSMutableDictionary *sourceDictionary = [[NSMutableDictionary alloc]
			initWithObjects:objects forKeys:objects count:2];
	NSDictionary *comparisonDictionary = [[NSDictionary alloc] initWithObjects:objects forKeys:objects count:2];

	// Check the orig class name, start an observation, check that the class changed--that is, we isa-swizzled
	Class origClassName = object_getClass(sourceDictionary);
	ObserveProperty(sourceDictionary, count,
	{
		++blockSelf->observerCallCount;
	});
	XCTAssertNotEqual(origClassName, object_getClass(sourceDictionary),
			@"The actual class for this object should (probably) now be __NSDictionaryM_EBNShadowClass.");

	NSDictionary *destDictionary = [sourceDictionary copy];
	XCTAssertEqualObjects(destDictionary, comparisonDictionary, @"Dictionary copy failed somehow");

	NSMutableDictionary *mutableDestDictionary = [sourceDictionary mutableCopy];
	XCTAssertEqualObjects(mutableDestDictionary, comparisonDictionary, @"Dictionary copy failed somehow");
	
	[mutableDestDictionary setObject:@"obj" forKey:@"key33"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 0, @"Observation block shouldn't get called when copy mutates. "
			@"Observations should not follow copies.");
}

- (void) testEncoding
{
	NSNumber *objects[] = { @1, @2 };
	NSDictionary *sourceDictionary = [[NSDictionary alloc] initWithObjects:objects forKeys:objects count:2];
	NSDictionary *comparisonDictionary = [[NSDictionary alloc] initWithObjects:objects forKeys:objects count:2];
	
	// Check the orig class name, start an observation, check that the class changed--that is, we isa-swizzled
	Class origClassName = object_getClass(sourceDictionary);
	ObservePropertyNoPropCheck(sourceDictionary, firstKey.someProperty,
	{
		++blockSelf->observerCallCount;
	});
	XCTAssertNotEqual(origClassName, object_getClass(sourceDictionary),
			@"The actual class for this object should (probably) now be __NSDictionaryI_EBNShadowClass.");
	
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:sourceDictionary];
	XCTAssertNotNil(data, @"Encoding an observable dict appears to have failed");
	
	NSDictionary *rebuiltDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	XCTAssertNotNil(rebuiltDictionary, @"Decoding an observable dictionary appears to have failed");
	XCTAssertEqualObjects(rebuiltDictionary, comparisonDictionary, @"Dictionary coding failed somehow");
	XCTAssertEqual(origClassName, object_getClass(rebuiltDictionary),
			@"The actual class for this object should (probably) now be __NSDictionaryM");
}

- (void) testMutableEncoding
{
	NSNumber *objects[] = { @1, @2 };
	NSMutableDictionary *sourceDictionary = [[NSMutableDictionary alloc]
			initWithObjects:objects forKeys:objects count:2];
	NSDictionary *comparisonDictionary = [[NSDictionary alloc] initWithObjects:objects forKeys:objects count:2];
	
	// Check the orig class name, start an observation, check that the class changed--that is, we isa-swizzled
	Class origClassName = object_getClass(sourceDictionary);
	ObserveProperty(sourceDictionary, count,
	{
		++blockSelf->observerCallCount;
	});
	XCTAssertNotEqual(origClassName, object_getClass(sourceDictionary),
			@"The actual class for this object should (probably) now be __NSDictionaryM_EBNShadowClass.");

	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:sourceDictionary];
	XCTAssertNotNil(data, @"Encoding an observable dict appears to have failed");
	
	NSMutableDictionary *rebuiltDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	XCTAssertNotNil(rebuiltDictionary, @"Decoding an observable dictionary appears to have failed");
	XCTAssertEqualObjects(rebuiltDictionary, comparisonDictionary, @"Dictionary coding failed somehow");
	XCTAssertEqual(origClassName, object_getClass(rebuiltDictionary),
			@"The actual class for this object should (probably) now be __NSDictionaryM");

	[rebuiltDictionary setObject:@"obj" forKey:@"key33"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(self->observerCallCount, 0, @"Observation block shouldn't get called when copy mutates. "
			@"Observations should not follow copies.");
}

- (void) testWildcards
{
	DictModelObject1 *moBase = [DictModelObject1 new];
	__block int blockCallCount = 0;
	
	// Make a wildcard observation before adding objects (tests that mutations cause updates)
	[moBase tell:self when:@"dict.*.intProperty" changes:
	^(ObservableDictionaryTests *blockSelf, DictModelObject1 *observed)
	{
		++blockCallCount;
	}];
	
	for (int index = 0; index < 10; ++index)
	{
		DictModelObject1 *mo = [DictModelObject1 new];
		[moBase.dict setObject:mo forKey:[NSString stringWithFormat:@"%d", index]];
	}
	
	// Make another wildcard observation after adding objects (tests initial setup)
	[moBase tell:self when:@"dict.*.intProperty2" changes:
	^(ObservableDictionaryTests *blockSelf, DictModelObject1 *observed)
	{
		++blockCallCount;
	}];
	
	XCTAssertEqual(blockCallCount, 0, @"Observation can't be called yet.");
	DictModelObject1 *mo0 = moBase.dict[@"0"];
	mo0.intProperty = 5;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 1, @"Observation block didn't get called.");
	mo0.intProperty2 = 8;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 2, @"Observation block didn't get called.");
	
	DictModelObject1 *mo5 = moBase.dict[@"5"];
	mo5.intProperty = 7;
	mo5.intProperty2 = 3;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 4, @"Observation block didn't get called.");
	
	// Removing the object at @"9" cause both "*" observations to fire
	DictModelObject1 *mo9 = moBase.dict[@"9"];
	[moBase.dict removeObjectForKey:@"9"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 6, @"Observation block didn't get called.");
	
	// But then mutating the removed object shouldn't fire anything
	mo9.intProperty = 9;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 6, @"Observation block shouldn't get called for mutation after removal.");

	// Add it back in, twice. Code should recognize the second set doesn't actually mutate
	[moBase.dict setObject:mo9 forKey:@"9"];
	[moBase.dict setObject:mo9 forKey:@"9"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 8, @"Observation block didn't get called.");
	
	// Add it again, with a different key, which fires both observations
	[moBase.dict setObject:mo9 forKey:@"10"];
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 10, @"Observation block didn't get called.");
	
	// And then mutating the int prop should trigger the same observation twice (which then get merged)
	mo9.intProperty = 100;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 11, @"Observation block didn't get called.");
	
	// Removing fires both observations, then setting int fires the first (merged in to 2)
	[moBase.dict removeObjectForKey:@"9"];
	mo9.intProperty = 101;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 13, @"Observation block didn't get called.");
	
	// Then, setting the int should fire once (this tests that remove doesn't remove all observations in the
	// case where the same object is in an array multiple times)
	mo9.intProperty = 102;
	EBN_RunLoopObserverCallBack(nil, kCFRunLoopAfterWaiting, nil);
	XCTAssertEqual(blockCallCount, 14, @"Observation block didn't get called.");


}

@end
