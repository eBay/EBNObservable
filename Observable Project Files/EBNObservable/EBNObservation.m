/****************************************************************************************************
	EBNObservation.m
	Observable
	
	Created by Chall Fry on 5/3/14.
    Copyright (c) 2013-2014 eBay Software Foundation.
	
*/

#import "DebugUtils.h"

#import <objc/runtime.h>
#import <libgen.h>
#import "EBNObservation.h"
#import "EBNObservableInternal.h"

@implementation EBNObservation

/****************************************************************************************************
	initForObserved:observer:block:
	
	Creates and returns a block that 'wraps' an ObserverBlock.
*/
- (instancetype) initForObserved:(EBNObservable *) observed observer:(id) observer
		block:(ObservationBlock) callBlock
{
	if (self = [super init])
	{
		self->_weakObserved = observed;
		self->_weakObserver = observer;
		self->_weakObserver_forComparisonOnly = observer;
		self->_copiedBlock = [callBlock copy];
	}
	
	return self;
}

/****************************************************************************************************
	initForObserved:observer:immedBlock:
	
	Creates and returns a block that 'wraps' an ObserverBlock.
*/
- (instancetype) initForObserved:(EBNObservable *) observed observer:(id) observer
		immedBlock:(ObservationBlockImmed) callBlock
{
	if (self = [super init])
	{
		self->_weakObserved = observed;
		self->_weakObserver = observer;
		self->_weakObserver_forComparisonOnly = observer;
		self->_copiedImmedBlock = [callBlock copy];
	}
	
	return self;
}

/****************************************************************************************************
	setDebugStringWithFn:file:line
	
	Creates and returns a block that 'wraps' an ObserverBlock.
*/
- (void) setDebugStringWithFn:(const char *) fnName file:(const char *) filePath line:(int) lineNum
{
	if (fnName && filePath)
	{
		self.debugString = [NSString stringWithFormat:@"%p: for <%s: %p> declared at %s:%d",
				self, class_getName([self->_weakObserver class]), self->_weakObserver, basename((char *) filePath), lineNum];
	}

}

/****************************************************************************************************
	debugDescription
	
	For debugging. Who doesn't like debugging?
*/
- (NSString *) debugDescription
{
	if (self.debugString)
		return [NSString stringWithFormat:@"%@", self.debugString];
	else
		return [NSString stringWithFormat:@"A block at:%p for <%s: %p ",
				self, class_getName([self->_weakObserver class]), self->_weakObserver];
}

/****************************************************************************************************
	observe:
	
*/
- (bool) observe:(NSString *) keyPath
{
	NSObject *observedObj = self->_weakObserved;
	id strongObserver = self->_weakObserver;
	if (observedObj && strongObserver)
	{
		return [observedObj observe_ebn:keyPath using:self];
	}
	return false;
}

/****************************************************************************************************
	observeMultiple:
	
*/
- (bool) observeMultiple:(NSArray *) keyPaths
{
	bool result = true;
	for (NSString *keyPath in keyPaths)
	{
		result = [self observe:keyPath];
	}
	
	return result;
}

/****************************************************************************************************
	execute
	
	Runs the block. Checks that the observed and observing object are still around first.
*/
- (bool) execute
{
	NSObject *blockSelf = self->_weakObserved;
	if (!blockSelf)
	{
		EBLogContext(kLoggingContextOther,
				@"Shouldn't be possible to run a observation block when the observed object is dealloced.");
		return false;
	}
	
	id blockObserver = self->_weakObserver;
	if (!blockObserver)
	{
		// If the observer has gone away, remove ourselves
		[blockSelf reapBlocks_ebn];
		return false;
	}
	
	if (self->_copiedBlock)
		self->_copiedBlock(blockObserver, blockSelf);
	return true;
}

/****************************************************************************************************
	executeWithPreviousValue:
	
	Runs the block. Checks that the observed and observing object are still around first.
*/
- (bool) executeWithPreviousValue:(id) prevValue
{
	NSObject *blockSelf = self->_weakObserved;
	if (!blockSelf)
	{
		EBLogContext(kLoggingContextOther,
				@"Shouldn't be possible to run a observation block when the observed object is dealloced.");
		return false;
	}
	
	id blockObserver = self->_weakObserver;
	if (!blockObserver)
	{
		// If the observer has gone away, remove ourselves
		[blockSelf reapBlocks_ebn];
		return false;
	}
	
	if (self->_copiedImmedBlock)
		self->_copiedImmedBlock(blockObserver, blockSelf, prevValue);
	return true;
}

@end
