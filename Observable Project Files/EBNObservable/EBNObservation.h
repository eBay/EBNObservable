/****************************************************************************************************
	EBNObservation.h
	Observable
	
	Created by Chall Fry on 5/3/14.
    Copyright (c) 2013-2014 eBay Software Foundation.
	
*/

#import <Foundation/Foundation.h>

#define EBNStringify(x) @#x

	// Don't use this directly. This macro puts a bunch of strange stuff in an if (0) block to perform
	// several kinds of compile-time validation.
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


/**
	Creates an EBNObservation object for observing property keypaths rooted at observedObj.
	Once created, use the observe: methods of EBNObservation to set the keypaths you want to
	observe.
	
	This macro tries to ensure at compile time that  the given block doesn't access self
	or observedObj--either of these would cause a retain loop. Instead, use 'blockSelf' and
	'observed' within the block. These variables are put through a weak-strong flow for you.


	@param observedObj   The object being observed
	@param blockContents A bunch of code wrapped within {}

	@return The newly created block, an EBNObservation object
 */
#define NewObservationBlock(observedObj, blockContents) \
({\
	__typeof__(observedObj) _internalObserved = observedObj; \
	EBNObservation *_newblock = [[EBNObservation alloc] initForObserved:_internalObserved observer:self \
			block:^(__typeof__(self) blockSelf, __typeof__(_internalObserved) observed) blockContents]; \
	[_newblock setDebugStringWithFn:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__]; \
	EBNValidateObservationBlock(_internalObserved, blockContents); \
	_newblock; \
})


/**
	Creates an EBNObservation block that is called immediately upon modification of the path.
	Generally, don't use this. Immediate blocks lose lots of advantages and can introduce subtle bugs.
	Their one use case is where you absolutely need the previous value of a property.
	@param observedObj   The object being observed

	@param blockContents A bunch of code wrapped within {}

	@return The newly created block, an EBNObservation object
 */
#define NewObservationBlockImmed(observedObj, blockContents) \
({\
	__typeof__(observedObj) _internalObserved = observedObj; \
	EBNObservation *_newblock = [[EBNObservation alloc] initForObserved:_internalObserved observer:self \
			immedBlock:^(__typeof__(self) blockSelf, __typeof__(_internalObserved) observed, id prevValue) blockContents]; \
	[_newblock setDebugStringWithFn:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__]; \
	EBNValidateObservationBlock(_internalObserved, blockContents); \
	_newblock; \
})


/**
	This is the type of the block you use to observe properties. Note that, technically, the block
	is the entity getting notified of changes, however, the lifetime of the observation is tied to the 
	object lifetime of the observer. Also, Observable does the weak/strong dance so you don't have to.
	
	
	@param observingObj The object getting notified of changes
	@param observedObj  The object being watched
 */
typedef void (^ObservationBlock)(id observingObj, id observedObj);


/**
	This is an immediate-mode observation block. Immediate mode observations will get called as soon
	as their observed value changes. That is, they'll get called from within the overridden setter method.
	
	Generally you shouldn't use this, as the delayed form has several advantages. But, if you *really* need 
	the previous value, it's here.

	@param observingObj  The object getting notified of changes
	@param observedObj   The object being watched
	@param previousValue The previous value of the property
 */
typedef void (^ObservationBlockImmed)(id observingObj, id observedObj, id previousValue);


@interface EBNObservation : NSObject

@property (strong) NSString				*debugString;

/**
	Initializes a EBNObservation, for use with the given observed and observer objects.

	@param observed  The object being watched
	@param observer  The object doing the watching
	@param callBlock The block to call when something changes

	@return an EBNObservation object
 */
- (instancetype) initForObserved:(NSObject *) observed observer:(id) observer block:(ObservationBlock) callBlock;

/**
	Initializes a EBNObservation, for use with the given observed and observer objects.

	@param observed  The object being watched
	@param observer  The object doing the watching
	@param callBlock The block to call immediately when something changes

	@return an EBNObservation object
 */
- (instancetype) initForObserved:(NSObject *) observed observer:(id) observer immedBlock:(ObservationBlockImmed) callBlock;

/**
	Tells the receiver to begin observing changes to the given keypath.

	@param keyPath A keypath rooted at the receiver.

	@return TRUE if observation was set up successfully
 */
- (bool) observe:(NSString *) keyPath;

/**
	Tells the receiver to being observing changes to multiple keypaths. All keypaths must be rooted 
	at the receiver.

	@param keyPaths An array of keypaths.

	@return TRUE if observations were set up successfully
 */
- (bool) observeMultiple:(NSArray *) keyPaths;

/**
	Checks that the observing and observed objects haven't been dealloc'ed, and then executes 
	the block associated with this observation object.

	@return TRUE if the block was executed, else FALSE
 */
- (bool) execute;

/**
	Checks that the observing and observed objects haven't been dealloc'ed, and then executes the
	immediate mode block associated with this observation object.

	@param prevValue Passed into the block as the prevValue parameter

	@return TRUE if the block was executed, else FALSE
 */
- (bool) executeWithPreviousValue:(id) prevValue;

/**
	For use by macros. Meant to gather __FILE__ and __LINE__ into the debug string for the observation.

	@param fnName   Name of the current function, from the __PRETTY_FUNCTION__ builtin
	@param filePath Name of the current file, from the __FILE__ builtin
	@param lineNum  Current line num in the file, from the __LINE__ builtin
 */
- (void) setDebugStringWithFn:(const char *) fnName file:(const char *) filePath line:(int) lineNum;

@end

