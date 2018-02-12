/****************************************************************************************************
	ObservableSwiftTests.swift
	Observable
	
    Created by Chall Fry on 11/8/15.
    Copyright (c) 2013-2018 eBay Software Foundation.

    Unit tests.
*/

import XCTest

class SwiftModelA : NSObject
{
	@objc dynamic var intProperty : Int = 0;
	@objc dynamic var boolProperty : Bool = false;
}

class ObservableSwiftTests: XCTestCase
{
	var observerCallCount1 = 0;
	var propValInBlock = 0;
    
    override func setUp()
	{
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown()
	{
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testBasicObservation()
	{
		let modelA = SwiftModelA();
		
		let block = { [weak self] (observing: Optional<Any>, observed:Optional<Any>) -> Void in
			if (self != nil)
			{
				let obs = observed as! SwiftModelA;
				self!.observerCallCount1 += 1
				self!.propValInBlock = obs.intProperty;
			}
			
		};
		
		modelA.tell(self, when:"intProperty", changes:block);
		modelA.intProperty = 5;
		
		modelA.tell(self, when:"boolProperty") { (observing, observed) in
			let blockSelf = observing as! ObservableSwiftTests
			blockSelf.observerCallCount1 += 1
		};
		modelA.boolProperty = true;
		
		EBN_RunLoopObserverCallBack(nil, 0, nil);
		XCTAssertEqual(self.observerCallCount1, 2, "Observation block didn't get called.");
		XCTAssertEqual(self.propValInBlock, 5, "Property doesn't have the value it should.");
    }
    
	
}
