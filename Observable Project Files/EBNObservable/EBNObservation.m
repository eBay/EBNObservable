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
		_weakObserved = observed;
		_weakObserver = observer;
		_weakObserver_forComparisonOnly = observer;
		_copiedBlock = [callBlock copy];
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
		_weakObserved = observed;
		_weakObserver = observer;
		_weakObserver_forComparisonOnly = observer;
		_copiedImmedBlock = [callBlock copy];
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
				self, class_getName([_weakObserver class]), _weakObserver, basename((char *) filePath), lineNum];
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
				self, class_getName([_weakObserver class]), _weakObserver];
}

/****************************************************************************************************
	observe:
	
	Tells the receiver to get to work, observing the given path. Once you've created an EBNObserver,
	you can repeatedly tell it to observe a bunch of paths; however, all of them need to have
	the same observer and observee objects.
*/
- (BOOL) observe:(NSString *) keyPath
{
	NSObject *observedObj = _weakObserved;
	id strongObserver = _weakObserver;
	if (observedObj && strongObserver)
	{
		return [observedObj ebn_observe:keyPath using:self];
	}
	return NO;
}

/****************************************************************************************************
	observeMultiple:
	
*/
- (BOOL) observeMultiple:(NSArray *) keyPaths
{
	BOOL result = YES;
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
- (BOOL) execute
{
	NSObject *blockSelf = _weakObserved;
	if (!blockSelf)
	{
		EBLogContext(kLoggingContextOther,
				@"Shouldn't be possible to run a observation block when the observed object is dealloced.");
		return false;
	}
	
	id blockObserver = _weakObserver;
	if (!blockObserver)
	{
		// If the observer has gone away, remove ourselves
		[blockSelf ebn_reapBlocks];
		return NO;
	}
	
	if (_copiedBlock)
		_copiedBlock(blockObserver, blockSelf);
	return YES;
}

/****************************************************************************************************
	executeWithPreviousValue:
	
	Runs the block. Checks that the observed and observing object are still around first.
*/
- (BOOL) executeWithPreviousValue:(id) prevValue
{
	NSObject *blockSelf = _weakObserved;
	if (!blockSelf)
	{
		EBLogContext(kLoggingContextOther,
				@"Shouldn't be possible to run a observation block when the observed object is dealloced.");
		return NO;
	}
	
	id blockObserver = _weakObserver;
	if (!blockObserver)
	{
		// If the observer has gone away, remove ourselves
		[blockSelf ebn_reapBlocks];
		return false;
	}
	
	if (_copiedImmedBlock)
		_copiedImmedBlock(blockObserver, blockSelf, prevValue);
	return true;
}

@end
