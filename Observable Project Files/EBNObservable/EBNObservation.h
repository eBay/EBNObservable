/****************************************************************************************************
	EBNObservation.h
	Observable
	
	Created by Chall Fry on 5/3/14.
    Copyright (c) 2013-2018 eBay Software Foundation.
	
*/

#import <Foundation/Foundation.h>

@class EBNKeypathEntryInfo;

#define EBNStringify(x) @#x

	// Don't use this directly. This macro puts a bunch of strange stuff in an if (0) block to perform
	// several kinds of compile-time validation.
#define EBNValidateObservationBlock(observerObj, observedObj, blockContents) \
({\
	if (0) \
	{\
		__attribute__((unused)) __typeof__(self) blockSelf = nil; \
		__attribute__((unused)) __typeof__(observerObj) observer = nil; \
		__attribute__((unused)) __typeof__(observedObj) observed = nil; \
		__attribute__((unused)) id prevValue = nil; \
		_Pragma("clang diagnostic push") \
		_Pragma("clang diagnostic ignored \"-Wshadow\"") \
		__attribute__((unavailable("Don't use self directly in Observable blocks. Use \"blockSelf\" instead."), unused)) __typeof__(self) self = nil; \
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
	EBNValidateObservationBlock(self, _internalObserved, blockContents); \
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
			immedBlock:^(__typeof__(self) blockSelf, __typeof__(_internalObserved) observed) blockContents]; \
	[_newblock setDebugStringWithFn:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__]; \
	EBNValidateObservationBlock(self, _internalObserved, blockContents); \
	_newblock; \
})


/**
	This is the type of the block you use to observe properties. Note that, technically, the block
	is the entity getting notified of changes, however, the lifetime of the observation is tied to the 
	object lifetime of the observer. Also, Observable does the weak/strong dance so you don't have to.
	
	
	@param observingObj The object getting notified of changes
	@param observedObj  The object being watched
 */
typedef void (^ObservationBlock)(id _Nonnull observingObj, id _Nonnull observedObj);


/**
	This object encapsulates a single observation that can be applied to keypaths to observe things.
	
	An observation object (primarily) contains:
		- A weak link to the observed object.
		- A weak link to the observing object.
		- The block to execute.
		
	Observation objects primarily deal with the managing the lifetime of the observation, meaning they remove
	themselves if either the observed or observing object is deallocated. 
	
	A side effect of the above is that a single observation is 'rooted' at its observed object, and all keypaths
	it is asked to observe will be relative to that object.
*/
@interface EBNObservation : NSObject <NSCopying>

	/// Custom info shown in the debugger about this observation
@property (strong, nullable) NSString	*debugString;

	/// Marks the observation object as being a LazyLoader observer, that is, an observation set up
	/// by LazyLoader to invalidate some other property when the observed property changes value.
@property (assign) BOOL					isForLazyLoader;

	/// Causes an immediate debug break when any of the properties this observation is observing change.
	/// This is very useful when an observation that's observing a list of properties is firing unexpectedly, and you
	/// need to figure out which property is being changed, and by whom.
@property (assign) BOOL					willDebugBreakOnChange;

	/// Causes a debug break when this observation's block is about to be called.
	/// The ObserveProperty() macros confuse Xcode's breakpoint setting mechanics (the contents of the observation
	/// block are expanded multiple times within the macro--don't ask) meanins XCode doesn't know where to put
	/// the breakpoint. This lets you break just before these blocks so you can debug through them.
	@property (assign) BOOL				willDebugBreakOnInvoke;


/**
	Initializes a EBNObservation, for use with the given observed and observer objects.

	@param observed  The object being watched
	@param observer  The object doing the watching
	@param callBlock The block to call when something changes

	@return an EBNObservation object
 */
- (nullable instancetype) initForObserved:(nullable NSObject *) observed observer:(nullable id) observer
		block:(nonnull ObservationBlock) callBlock;

/**
	Initializes a EBNObservation, for use with the given observed and observer objects.

	@param observed  The object being watched
	@param observer  The object doing the watching
	@param callBlock The block to call immediately when something changes

	@return an EBNObservation object
 */
- (nullable instancetype) initForObserved:(nullable NSObject *) observed observer:(nullable id) observer
		immedBlock:(nullable ObservationBlock) callBlock;

/**
	Tells the receiver to begin observing changes to the given keypath.

	@param keyPath A keypath rooted at the receiver.

	@return Returns the receiver, to allow chaining.
 */
- (nonnull EBNObservation *) observe:(nonnull NSString *) keyPath;

/**
	Tells the receiver to begin observing changes to multiple keypaths. All keypaths must be rooted
	at the receiver.

	@param keyPaths An array of keypaths.

	@return Returns the receiver, to allow chaining.
 */
- (nonnull EBNObservation *) observeMultiple:(nonnull NSArray *) keyPaths;

/**
	Ends all observations the receiver was running on its observed object.
*/
- (void) stopObservations;

/**
	Transforms a delayed-mode observation into an immediate-mode one. Use this if you need to receive
	observation callbacks on the thread where the change happens.
*/
- (nullable EBNObservation *) makeImmediateMode;

/**
	Checks that the observing and observed objects haven't been dealloc'ed, and then immediately executes 
	the (normally delayed) block associated with this observation object.

	@return self if the block was executed, else nil
 */
- (nullable EBNObservation *) execute;

/**
	Schedules the observation to fire at the end of the next runloop. Does not fire immediate mode
	observations.
	
	@return self if the block was scheduled, else nil
*/
- (nullable EBNObservation *) schedule;

/**
	If this is an immediate-fire block, runs the block.
	Checks that the observed and observing object are still around first.
	No effect for delayed-fire blocks.
*/
- (BOOL) executeImmedBlockWithPreviousValue:(nullable id) prevValue;

/**
	Checks that the observing and observed objects haven't been dealloc'ed, and then executes the
	block associated with this observation object.

	@param prevValue Passed into the block as the prevValue parameter

	@return TRUE if the block was executed, else FALSE
 */
- (BOOL) executeWithPreviousValue:(nullable id) prevValue;

/**
	Will cause a debug break when any property change that schedules this observation to be invoked occurs.
*/
- (nullable EBNObservation *) debugBreakOnChange;

/**
	Causes a debug break at a point just before this observation is going to be invoked.
*/
- (nullable EBNObservation *) debugBreakOnInvoke;


/**
	For use by macros. Meant to gather __FILE__ and __LINE__ into the debug string for the observation.

	@param fnName   Name of the current function, from the __PRETTY_FUNCTION__ builtin
	@param filePath Name of the current file, from the __FILE__ builtin
	@param lineNum  Current line num in the file, from the __LINE__ builtin
 */
- (void) setDebugStringWithFn:(nullable const char *) fnName file:(nullable const char *) filePath line:(int) lineNum;

@end

/**
	This function can be used directly to set up observations, but its real purpose is to work in concert 
	with the ValidatePaths macro and the Observe macro, with syntax that looks like this:
	
	ObserveNoSelfCheck(ValidatePaths(observedObj, keypathList, ...) { observerBlockContents } );
	
	There is no comma after the ValidatePaths macro. Dumb syntax, I know, but it is much more compact, and more similar
	to how ObserveProperty() works.
	
	This function/macro pair should be used in cases where the block can't be part of a macro, due to 
	internal commas or a need to reference self instead of blockSelf. This variant gives you safety checks
	for the observed keypaths, but not for the block contents.
	
	@param observer					The object doing the observing, usually 'self'.
	@param observedObj				The object to observe.
	@param keypathArray				A NSArray of NSStrings, each string a KVC style keypath.
	@param block					The block to invoke when any of the keypaths changes value.

*/
EBNObservation * _Nullable ObserveNoSelfCheck(id _Nonnull observer, id _Nonnull observedObj,
		NSArray * _Nonnull keypathArray, ObservationBlock _Nonnull block);
EBNObservation * _Nullable ObserveImmedNoSelfCheck(id _Nonnull observer, id _Nonnull observedObj, 
		NSArray * _Nonnull keypathArray, ObservationBlock _Nonnull block);


/**
	This function can be used directly to set up observations, but its real purpose is to work in concert 
	with the ValidatePaths macro and the Observe macro, with syntax that looks like this:
	
	ObserveDebug(ValidatePaths(observedObj, keypathList, ...) { observerBlockContents } );
	
	There is no comma after the ValidatePaths macro. Dumb syntax, I know, but it is much more compact, and more similar
	to how ObserveProperty() works.
	
	This variant is designed to have a syntax nearly identical to the Observe(ValidateKeypaths()) pair.
	Changing Observe to ObserveDebug makes debug breakpoints work inside the observation block. 
	ObserveDebug will only compile on debug builds, and will cause errors on release builds.
	
	@param observer					The object doing the observing, usually 'self'.
	@param observedObj				The object to observe.
	@param keypathArray				A NSArray of NSStrings, each string a KVC style keypath.
	@param block					The block to invoke when any of the keypaths changes value.
*/

EBNObservation * _Nullable ObserveDebug(id _Nonnull observer, id _Nonnull observedObj, NSArray * _Nonnull keypathArray,
		ObservationBlock _Nonnull block)
#if DEBUG
	;
#else
	__attribute__((unavailable));
#endif

EBNObservation * _Nullable ObserveImmedDebug(id _Nonnull observer, id _Nonnull observedObj, 
		NSArray * _Nonnull keypathArray, ObservationBlock _Nonnull block)
#if DEBUG
	;
#else
	__attribute__((unavailable));
#endif



