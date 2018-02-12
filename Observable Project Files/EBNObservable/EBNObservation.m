/****************************************************************************************************
	EBNObservation.m
	Observable
	
	Created by Chall Fry on 5/3/14.
    Copyright (c) 2013-2018 eBay Software Foundation.
	
*/

#import <objc/runtime.h>
#import <libgen.h>

#import "EBNObservation.h"
#import "EBNObservableInternal.h"


@implementation EBNObservation


@synthesize willDebugBreakOnChange = _willDebugBreakOnChange;

/****************************************************************************************************
	scheduleBlocks:
	
	Schedules multiple blocks to be run at the end of the current runloop. 
	
	This method should act similarly but be more efficient than calling schedule on each block
	in a for loop. This method only takes the sync once.
	
	Returns TRUE if any of the blocks couldn't be scheduled because their observed object has been
	deallocated, in which case the
*/
+ (BOOL) scheduleBlocks:(NSArray<EBNKeypathEntryInfo *> *) blocks
{
	// Adding blocks to the global collections of "run later" blocks must be done inside
	// the sync. The sync is outside the loop for speed.
	BOOL reapAfterIterating = NO;
	@synchronized(EBNObservableSynchronizationToken)
	{
		for (EBNKeypathEntryInfo *entry in blocks)
		{
			EBNObservation *blockInfo = entry->_blockInfo;
			if (blockInfo->_copiedBlock)
			{
				NSObject *strongObserved = blockInfo->_weakObserved;
				if (strongObserved)
				{
					[EBN_ObserverBlocksToRunAfterThisEvent addObject:blockInfo];
					[EBN_ObservedObjectKeepAlive addObject:strongObserved];
				}
				else
				{
					reapAfterIterating = YES;
				}
			}
		}
	}
	
	return reapAfterIterating;
}

/****************************************************************************************************
	initForObserved:observer:block:
	
	Creates and returns a block that 'wraps' an ObserverBlock.
*/
- (instancetype) initForObserved:(id) observed observer:(id) observer
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
- (instancetype) initForObserved:(id) observed observer:(id) observer
		immedBlock:(ObservationBlock) callBlock
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
	makeImmediateMode
    
    Turns a delayed-mode observation into an immediate-mode one.
*/
- (EBNObservation *) makeImmediateMode
{
	_copiedImmedBlock = _copiedBlock;
	_copiedBlock = nil;
	
	return self;
}

/****************************************************************************************************
	copyWithZone:
	
*/
- (EBNObservation *) copyWithZone:(NSZone *) zone
{
	EBNObservation *result = [[[self class] alloc] init];
	
	result.debugString = self.debugString;
	result.isForLazyLoader = self.isForLazyLoader;
	result->_weakObserved = _weakObserved;
	result->_weakObserver = _weakObserver;
	result->_weakObserver_forComparisonOnly = _weakObserver_forComparisonOnly;
	result->_copiedBlock = _copiedBlock;
	result->_copiedImmedBlock = _copiedImmedBlock;
	
	return result;
}

/****************************************************************************************************
	observe:
	
	Tells the receiver to get to work, observing the given path. Once you've created an EBNObserver,
	you can repeatedly tell it to observe a bunch of paths; however, all of them need to have
	the same observer and observed objects.
*/
- (EBNObservation *) observe:(NSString *) keyPath
{
	NSObject *observedObj = _weakObserved;
	id strongObserver = _weakObserver;
	if (observedObj && strongObserver)
	{
		[observedObj ebn_observe:keyPath using:self];
	}
	return self;
}

/****************************************************************************************************
	observeMultiple:
	
	Tells the receiver to begin observing all the given keypaths. 
*/
- (EBNObservation *) observeMultiple:(NSArray *) keyPaths
{
	for (NSString *keyPath in keyPaths)
	{
		[self observe:keyPath];
	}
	
	return self;
}

/****************************************************************************************************
	stopObservations
	
	If you saved your EBNObservation when you registered, you can use this method to
	remove all KVO notifications that would call that block.

	Deregisters all observation keypaths that this observation block was given.
	
	Deregistering observations is ALWAYS done by searching for observations that match criteria, and all
	observations that match the given criteria will be removed.
	
	Must be sent to the same object that you sent the "tell:" method to when you set up the observation,
	but matches any keypath. That is, this won't remove an observation whose keypath goes through or
	ends at this object, only ones that start at this object.
*/
- (void) stopObservations
{
	NSObject *blockObserved = _weakObserved;
	if (!blockObserved)
		return;

	NSMutableSet *entriesToRemove = [[NSMutableSet alloc] init];

	NSMutableDictionary *observedKeysDict = [blockObserved ebn_observedKeysDict:NO];
	if (observedKeysDict)
	{
		@synchronized(observedKeysDict)
		{
			for (NSString *propertyKey in [observedKeysDict allKeys])
			{
				NSMutableArray *observers = observedKeysDict[propertyKey];
				
				for (EBNKeypathEntryInfo *entryInfo in observers)
				{
					// Match on the entries where the block that gets run is the indicated block
					if (entryInfo->_blockInfo == self && entryInfo->_keyPathIndex == 0)
					{
						[entriesToRemove addObject:entryInfo];
					}
				}
			}
		}
	}
	
	for (EBNKeypathEntryInfo *entryInfo in entriesToRemove)
	{
		[entryInfo ebn_updateKeypathAtIndex:0 from:self to:nil];
	}
}

#pragma mark Running the Observation Blocks

/****************************************************************************************************
	execute
	
	If this is a 'normal' observation with delayed-fire mechanics, runs the block immediately.
	Checks that the observed and observing object are still around first.
	
	Note that many blocks are written to assume they'll only be run on the main thread, and that they
	won't be run re-entrantly on it either. Calling this method in a way that violates those assumptions
	is an error.
	
	Returns self (the EBNObservation object), unless we find that the observer or observed objects have
	been dealloc'ed, in which case we return nil.
*/
- (EBNObservation *) execute
{
	BOOL observationIsValid = YES;
	if (_copiedBlock)
	{
		NSObject *blockObserved = _weakObserved;
		if (!blockObserved)
		{
			EBLogContext(kLoggingContextOther,
					@"Shouldn't be possible to run a observation block when the observed object is dealloced.");
			observationIsValid = NO;
		}
		
		id blockObserver = _weakObserver;
		if (!blockObserver)
		{
			observationIsValid = NO;
		}
		
		if (observationIsValid)
		{
			if (_willDebugBreakOnInvoke && EBNIsADebuggerConnected())
			{
				EBLogStdOut(@"debugBreakOnInvoke breakpoint hit! %@", _debugString.length ? _debugString : @"");
		
				// This line will cause a break in the debugger! If you stop here in the debugger, it is
				// because someone set debugBreakOnInvoke on this observation and it's about to invoked.
				DEBUG_BREAKPOINT;
			}
			
			_copiedBlock(blockObserver, blockObserved);
		}
		else
		{
			return nil;
		}
	}
	
	return self;
}

/****************************************************************************************************
	schedule
	
	If this is a 'normal' block with delayed-fire mechanics, schedules this block for running at the end 
	of the current runloop.
	
	If the block is also scheduled as a result of  an element in one of its observed paths changing 
	during this iteration of the main thread's runloop, the block will only be called once (the calls
	get coalesced).
	
	Does nothing for immediate mode observations.
	
	Returns self, for chaining method calls, unless the observed object has been deallocated, in which
	case we return nil.
*/
- (EBNObservation *) schedule
{
	// Schedule any delayed blocks; also keep the observed object alive until the delayed block is called.
	if (_copiedBlock)
	{
		NSObject *strongObserved = _weakObserved;
		if (strongObserved)
		{
			@synchronized(EBNObservableSynchronizationToken)
			{
				[EBN_ObserverBlocksToRunAfterThisEvent addObject:self];
				[EBN_ObservedObjectKeepAlive addObject:strongObserved];
			}
		}
		else
		{
			return nil;
		}
	}
	
	return self;
}

/****************************************************************************************************
	executeImmedBlockWithPreviousValue:
	
	If this is an immediate-fire block, runs the block.
	Checks that the observed and observing object are still around first.
	No effect for delayed-fire blocks.
*/
- (BOOL) executeImmedBlockWithPreviousValue:(id) prevValue
{
	BOOL observationIsValid = YES;

	if (_copiedImmedBlock)
	{
		NSObject *blockObserved = _weakObserved;
		if (!blockObserved)
		{
			EBLogContext(kLoggingContextOther,
					@"Shouldn't be possible to run a observation block when the observed object is dealloced.");
			observationIsValid = NO;
		}
		
		id blockObserver = _weakObserver;
		if (!blockObserver)
		{
			// If the observer has gone away, remove ourselves
			[blockObserved ebn_reapBlocks];
			observationIsValid = NO;
		}
		
		if (observationIsValid)
		{
			if (_willDebugBreakOnInvoke && EBNIsADebuggerConnected())
			{
				EBLogStdOut(@"debugBreakOnInvoke breakpoint hit! %@", _debugString.length ? _debugString : @"");
		
				// This line will cause a break in the debugger! If you stop here in the debugger, it is
				// because someone set debugBreakOnInvoke on this observation and it's about to invoked.
				DEBUG_BREAKPOINT;
			}
			
			_copiedImmedBlock(blockObserver, blockObserved);
		}
	}
	
	return observationIsValid;
}

/****************************************************************************************************
	executeWithPreviousValue:
	
	If this is an immediate-fire block, runs the block immediately.
	If this is a delayed-fire block, schedules the block.
	Checks that the observed and observing object are still around first.
*/
- (BOOL) executeWithPreviousValue:(id) prevValue
{
	BOOL observationIsValid = [self schedule] && [self executeImmedBlockWithPreviousValue:prevValue];
	return observationIsValid;
}

/****************************************************************************************************
	ObserveNoSelfCheck
	
	Observe variant that skips safety checks on the observation block. Use when the macro fails
	(usually due to commas in the block).
*/
EBNObservation *ObserveNoSelfCheck(id observer, id observedObj, NSArray *keypathArray, ObservationBlock block)
{
	EBNObservation *observation = [[EBNObservation alloc] initForObserved:observedObj observer:observer
			block:block];
	[observation observeMultiple:keypathArray];
	return observation;
}

#pragma mark Debugging Support

/****************************************************************************************************
	ObserveDebug()
	
	Observe variant that doesn't mess up Xcode breakpoints set within the block.
	Using this variant loses the safety of checking for direct access to self within the block
	
*/
EBNObservation *ObserveDebug(id observer, id observedObj, NSArray *keypathArray, ObservationBlock block)
{
	return ObserveNoSelfCheck(observer, observedObj, keypathArray, block);
}


/****************************************************************************************************
	setDebugStringWithFn:file:line
	
	Creates and returns a block that 'wraps' an ObserverBlock.
*/
- (void) setDebugStringWithFn:(const char *) fnName file:(const char *) filePath line:(int) lineNum
{
	if (fnName && filePath)
	{
		id strongObserver = _weakObserver;
		if (strongObserver)
		{
			self.debugString = [NSString stringWithFormat:@"%p: for <%s: %p> declared at %s:%d",
								self, class_getName([strongObserver class]), strongObserver, basename((char *) filePath), lineNum];
		}
	}
}

/****************************************************************************************************
	debugDescription
	
	For debugging. Who doesn't like debugging?
*/
- (NSString *) debugDescription
{
	NSString *debugString = @"";

	if (self.debugString)
	{
		debugString = [NSString stringWithFormat:@"%@", self.debugString];
	}
	else
	{
		id strongObserver = _weakObserver;
		if (strongObserver)
		{
			debugString = [NSString stringWithFormat:@"A block at:%p for <%s: %p ", self, class_getName([strongObserver class]), strongObserver];
		}
	}

	return debugString;
}

/****************************************************************************************************
	debugBreakOnChange
	
	Wraps what is essentially a property setter in a way where it can be easily call-chained. e.g.:
	
	ObserveProperty(observedThing, propertyName, { ... }).debugBreakOnChange;

	Returns self to support method-chaining.
*/
- (EBNObservation *) debugBreakOnChange
{
	_willDebugBreakOnChange = YES;
	return self;
}

/****************************************************************************************************
	debugBreakOnInvoke
	
	Wraps what is essentially a property setter in a way where it can be easily call-chained. e.g.:
	
	ObserveProperty(observedThing, propertyName, { ... }).debugBreakOnInvoke;
	
	Returns self to support method-chaining.
*/
- (EBNObservation *) debugBreakOnInvoke
{
	_willDebugBreakOnInvoke = YES;
	return self;
}

@end
