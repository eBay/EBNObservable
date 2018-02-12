/****************************************************************************************************
	Observable.swift
	Observable
	
	Created by Fry, Chall on 1/3/18.
    Copyright (c) 2013-2018 eBay Software Foundation.
    
    Swift wrappers for EBNObservable calls. 
    
    These methods extend NSObjectProtocol to make it easier to set up EBNObservations from Swift code.
	To use, write code similar to this:
	
		observedObject.tell(self, when:#keyPath(observedObjectClass.integerProperty)) { observer, observed in
			observer.stringProperty = String(observed.integerProperty)
		}
		
	Notes on use:
	
		1. Use #keyPath() for the path whenever you can. This ensures the keypath you specify actually exists and
			properties on the path haven't been renamed/deleted.
		2. However, you can't use #keyPath() for EBNObservable wildcards and collection selectors. In that case, try
			to use string composition with partial keyPath protection e.g.: #keyPath(rootObjectClass.objectProperty1) + ".*"
		3. EBNObservable weakifies/strongifies the observer and observed objects, and this wrapper code lets
			the language infer the types of the closure's parameters correctly. For these reasons, prefer using the 
			parameters supplied to the block over allowing the block to capture references in the enclosing scope.
		4. There's no good way to prevent strongly referencing the observed or observing objects in a observation block
			the way the EBNObservation macros in Obj-C do. @escaping helps, but it's still possible to refer to self
			in the block. Don't do this, I guess?
		5. Just like all other observations, the observed object and all non-terminal entries in the keypath need
			to be NSObject subclasses declared dynamic.
		6. The methods to stop observation don't need these shims. Just call "observedObject.stopTellingAboutChanges(self)"
			or similar methods defined in EBNObservable.h.
			
			
	Notes on implementation:
	
		1. These methods are an extension on NSObjectProtocol instead of a NSObject class extension because
			protocol extensions get the special Self associated type and class extensions don't. The code needs
			Self as a declared type in method definitions, and class extensions don't seem to have a way to do this.
		2. Use of the protocol extension is then restricted to NSObject subclasses because the observed object 
			really does need to be a NSObject subclass to be isa-swizzled by the Obj-C runtime.
		3. We use Strings for keypaths instead of the new Smart Keypaths as described in 
			(https://github.com/apple/swift-evolution/blob/master/proposals/0161-key-paths.md) because the new 
			keypath objects aren't (yet) decomposable nor are they string-convertable.
		4. The part where the changeBlock is declared as "@escaping (ObserverType, Self) -> Void)" is really important.
			It's what allows Swift to infer the closure param types correctly.
		5. The contravarianceBlock is a wrapper block that exists to type erase the changeBlock into an
			"(Any, Any) -> Void" because of how covariance and contravariance work. Go google those terms. 
			Short story is that we can't call the Obj-C method with the changeBlock directly and have it work, as 
			the Swift runtime crashes.	
*/

import Foundation

extension NSObjectProtocol where Self: NSObject {

	/**
		Usage: observed.tell(observer, when:"observedProperty") { observer, observed in changeBlock }
	*/
	@discardableResult func tell<ObserverType: NSObject>(_ observer: ObserverType, when keyPath: String,
	 		changeBlock: (@escaping (ObserverType, Self) -> Void)) -> EBNObservation? {
		let contravarianceBlock: ObservationBlock = { changeBlock($0 as! ObserverType, $1 as! Self) }
		return self.tell(observer, when: keyPath, changes: contravarianceBlock)
	}
	
	/**
		Usage: observed.tell(observer, when:["observedProperty1", "observedProperty2"]) { observer, observed in changeBlock }
	*/
	@discardableResult func tell<ObserverType: NSObject>(_ observer: ObserverType, when keyPaths: [String],
	 		changeBlock: (@escaping (ObserverType, Self) -> Void)) -> EBNObservation? {
		let contravarianceBlock: ObservationBlock = { changeBlock($0 as! ObserverType, $1 as! Self) }
		return self.tell(observer, whenAny: keyPaths, changes: contravarianceBlock)
	}
}

