/****************************************************************************************************
	EBNObservation.h
	Observable
	
	Created by Chall Fry on 5/3/14.
    Copyright (c) 2013-2014 eBay Software Foundation.
	
*/

#import <Foundation/Foundation.h>

#define EBNStringify(x) @#x

#define EBNValidateObservationBlock(observedObj, blockContents) \
({\
	if (0) \
	{\
		__attribute__((unused)) __typeof__(self) blockSelf = nil; \
		__attribute__((unused)) __typeof__(observedObj) observed = nil; \
		__attribute__((unused)) id prevValue = nil; \
		_Pragma("clang diagnostic push") \
		_Pragma("clang diagnostic ignored \"-Wshadow\"") \
		__attribute__((unavailable("Don't use self directly in Observable blocks. Use \"blockSelf\" instead."), unused)) __typeof__(self) self = nil; \
		__attribute__((unavailable("Don't access the observed object directly in Observable blocks: Use \"observed\" instead."), unused)) __typeof__(observedObj) observedObj = nil; \
		_Pragma("clang diagnostic pop") \
		blockContents; \
	} \
})

	// Creates an EBNObservation object for observing property keypaths rooted at observedObj.
	// Once created, use the observe: methods of EBNObservation to set the keypaths you want to
	// observe.
	//
	// This macro tries to ensure at compile time that  the given block doesn't access self
	// or observedObj--either of these would cause a retain loop. Instead, use 'blockSelf' and
	// 'observed' within the block. These variables are put through a weak-strong flow for you.
#define NewObservationBlock(observedObj, blockContents) \
({\
	__typeof__(observedObj) _internalObserved = observedObj; \
	EBNValidateObservationBlock(_internalObserved, blockContents); \
	EBNObservation *_newblock = [[EBNObservation alloc] initForObserved:_internalObserved observer:self \
			block:^(__typeof__(self) blockSelf, __typeof__(_internalObserved) observed) blockContents]; \
	[_newblock setDebugStringWithFn:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__]; \
	_newblock; \
})

	// Similar to above, but creates a block that is called immediately upon modification of the path.
	// Generally, don't use this. Immediate blocks lose lots of advantages and can introduce subtle bugs.
	// Their one use case is where you absolutely need the previous value of a property.
#define NewObservationBlockImmed(observedObj, blockContents) \
({\
	__typeof__(observedObj) _internalObserved = observedObj; \
	EBNValidateObservationBlock(_internalObserved, blockContents); \
	EBNObservation *_newblock = [[EBNObservation alloc] initForObserved:_internalObserved observer:self \
			immedBlock:^(__typeof__(self) blockSelf, __typeof__(_internalObserved) observed, id prevValue) blockContents]; \
	[_newblock setDebugStringWithFn:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__]; \
	_newblock; \
})


@class EBNObservable;

	// This is the type of the blocks you use to observe properties
typedef void (^ObservationBlock)(id observingObj, id observedObj);

	// This is an immediate-mode observation block. Generally you shouldn't use this. But, if
	// you *really* need the previous value, it's here.
typedef void (^ObservationBlockImmed)(id observingObj, id observedObj, id previousValue);


@interface EBNObservation : NSObject

@property (strong) NSString				*debugString;

- (instancetype) initForObserved:(EBNObservable *) observed observer:(id) observer
		block:(ObservationBlock) callBlock;
- (instancetype) initForObserved:(EBNObservable *) observed observer:(id) observer
		immedBlock:(ObservationBlockImmed) callBlock;

- (bool) observe:(NSString *) keyPath;
- (bool) observeMultiple:(NSArray *) keyPaths;

- (bool) execute;
- (bool) executeWithPreviousValue:(id) prevValue;

	// For use by macros that use __FILE__ and __LINE__
- (void) setDebugStringWithFn:(const char *) fnName file:(const char *) filePath line:(int) lineNum;

@end

