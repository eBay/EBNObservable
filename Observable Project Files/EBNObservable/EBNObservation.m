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
		self->weakObserved = observed;
		self->weakObserver = observer;
		self->copiedBlock = [callBlock copy];
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
		self->weakObserved = observed;
		self->weakObserver = observer;
		self->copiedImmedBlock = [callBlock copy];
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
				self, class_getName([self->weakObserver class]), self->weakObserver, basename((char *) filePath), lineNum];
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
				self, class_getName([self->weakObserver class]), self->weakObserver];
}

/****************************************************************************************************
	observe:
	
*/
- (bool) observe:(NSString *) keyPath
{
	EBNObservable *observedObj = weakObserved;
	id strongObserver = weakObserver;
	if (observedObj && strongObserver)
	{
		return [observedObj observe:keyPath using:self];
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
	EBNObservable *blockSelf = weakObserved;
	if (!blockSelf)
	{
		EBLogContext(kLoggingContextOther,
				@"Shouldn't be possible to run a observation block when the observed object is dealloced.");
		return false;
	}
	
	id blockObserver = weakObserver;
	if (!blockObserver)
	{
		// If the observer has gone away, remove ourselves
		[blockSelf reapBlocks];
		return false;
	}
	
	if (copiedBlock)
		copiedBlock(blockObserver, blockSelf);
	return true;
}

/****************************************************************************************************
	executeWithPreviousValue:
	
	Runs the block. Checks that the observed and observing object are still around first.
*/
- (bool) executeWithPreviousValue:(id) prevValue
{
	EBNObservable *blockSelf = weakObserved;
	if (!blockSelf)
	{
		EBLogContext(kLoggingContextOther,
				@"Shouldn't be possible to run a observation block when the observed object is dealloced.");
		return false;
	}
	
	id blockObserver = weakObserver;
	if (!blockObserver)
	{
		// If the observer has gone away, remove ourselves
		[blockSelf reapBlocks];
		return false;
	}
	
	if (copiedImmedBlock)
		copiedImmedBlock(blockObserver, blockSelf, prevValue);
	return true;
}

@end
