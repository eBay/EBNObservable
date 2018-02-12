/****************************************************************************************************
	EBNProtocolBinder.h
	Observable
	
	Created by Chall Fry on 9/18/17.
    Copyright (c) 2013-2017 eBay Software Foundation.
	
*/

#import <Foundation/Foundation.h>

@interface NSObject (EBNProtocolBinder)

/**
	Establishes a binding between the receiver and the observed object, for all the properties in the given protocol.
	For each property in the protocol, the receiver will be kept up to date with changes to that property that occur
	in the observed object.
	
	Both the observed object and the receiver must conform to the given protocol. Only declared properties are bound.
	Property-like methods are not bound. Properties declared in protocols adopted by the given protocol are bound, 
	with the exception of properties declared in the NSObject protocol.

	For Protocol A that declares property B:
		- The receiver must conform to A
		- Observed must conform to A
		- receiver.B is set to the value of observed.B immediately
		- receiver.B is updated to observed.B's latest value whenever observed.B changes
		- If B is an @optional property of protocol A, it's okay, but B is only bound if both receiver
			and observed implement B
		- The setter semantics are defined by the protocol itself.
*/
- (void) bindTo:(nonnull id) observed withProtocol:(nonnull Protocol *) protocol;


/**
	Unbinds the receiver from the observed obejct, for all the properties in the given protocol. Properties
	in the receiver will no longer update in response to changes made to the observed object.
	
	Unbinding a protocol that was not bound is okay, and should not cause errors.
	
	You can do crazy things like unbind a protocol that is a parent of the protocol that was bound, which
	will leave you in a state where some properties are bound and others aren't. I just...I can't imagine a case
	where doing this is something someone would do on purpose. The point is that ProtocolBinder doesn't keep track
	of which protocols you've bound, internally it gathers up all the properties the protocol declares and binds
	them individually.
*/
- (void) unbind:(nullable id) observed fromProtocol:(nonnull Protocol *) protocol;

@end
