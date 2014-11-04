/****************************************************************************************************
	EBNObservableCollections.h
	Observable

    Created by Chall Fry on 5/13/14.
    Copyright (c) 2013-2014 eBay Software Foundation.
*/

#import <Foundation/Foundation.h>
#import "EBNObservableInternal.h"

@interface EBNObservableDictionary : NSMutableDictionary <EBNObservableProtocol>

@property (readonly)		NSUInteger count;

@end

@interface EBNObservableArray : NSMutableArray <EBNObservableProtocol>

@property (readonly)		NSUInteger count;

@end

@interface EBNObservableSet : NSMutableSet <EBNObservableProtocol>

@property (readonly)		NSUInteger count;

+ (NSString *) keyForObject:(id) object;
- (id) objectForKey:(NSString *) key;

@end
