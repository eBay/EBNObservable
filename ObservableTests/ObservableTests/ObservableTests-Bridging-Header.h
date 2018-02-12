//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//


#import "EBNObservable.h"
#import "EBNObservation.h"



// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asyncronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, int activity, void *info);