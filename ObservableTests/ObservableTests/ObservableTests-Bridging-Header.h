/****************************************************************************************************
	ObservableTests-Bridging-Header.h
	Observable
	
	Created by Chall Fry on 11/8/15.
    Copyright (c) 2013-2015 eBay Software Foundation.

	Use this file to import your target's public headers that you would like to expose to Swift.
*/

#import "EBNObservable.h"
#import "EBNObservation.h"
#import "EBNObservableCollections.h"




// This punches the hole that allows us to force the observer notifications
// instead of being dependent on the run loop. Asyncronous issues
// have to be handled without this.
void EBN_RunLoopObserverCallBack(CFRunLoopObserverRef observer, int activity, void *info);

