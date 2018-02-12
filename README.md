# Observable: a Block-Based KVO Implementation #


---
Observable is a simple way to get notified about changes to properties of other objects. At its simplest, you can write code like:

```C
	Observe(ValidatePaths(modelObject, aStringProperty) { myLabel.text = modelObject.aStringProperty; });
```
and your label's text will update whenever the model object's string property changes. 
Observable is designed to be much easier to use than Apple's KVO. It's also much easier to debug and about as lightweight.

Observable is much less finicky than Apple's KVO implementation; deallocing an observed or observing object won't throw exceptions; neither will doubly stopping an observation. Observable also supports observable container classes. These are subclasses of NSMutableArray, Set, and Dictionary that can be observed. 

Plus, Observable has a LazyLoader subclass that lets you create lazily loaded computed properties and declare a list of dependent properties that cause the computed property to invalidate its value.

## Audience ##
iOS developers, although the code could pretty easily be ported to Mac OS X. Observable requires iOS 9 and ARC.

More specifically, Observable is for people looking for a better way to hook up their model objects to controllers, and have become frustrated with Apple's KVO.

## Documentation ##

Observable is fully documented, including documentation on how it works internally, what the edge cases are, and how to debug code that uses it. 

## Creator ##

My name is Chall Fry. I wrote this. Ben Yarger helped write test cases and did QE work. Mark Yuan helped get eBay to open-source it.
