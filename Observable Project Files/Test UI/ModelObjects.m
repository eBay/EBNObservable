/****************************************************************************************************
	ModelObjects.m
	Observable
	
    Created by Chall Fry on 9/27/13.
    Copyright (c) 2013-2014 eBay Software Foundation.
    
    These are demonstration model objects, here so that we can demonstrate Observable.	
*/

#import "ModelObjects.h"

@implementation ModelObject1

- (instancetype) init
{
	if (self = [super init])
	{
		SyntheticProperty(intProperty);
		SyntheticProperty(intProperty2, stringProperty);
	}
	return self;
}


- (void) dealloc
{
	NSLog(@"Model Object being dealloced");
}

- (void) property:(NSString *)propName observationStateIs:(BOOL)isBeingObserved
{
	if (isBeingObserved)
		NSLog(@"<%p>: Property %@ is being observed.", self, propName);
	else
		NSLog(@"<%p>: Property %@ is no longer being observed.", self, propName);
}

@end


@implementation ModelObject2

@end

@implementation ModelObject3


@end

@implementation ModelObject4


@end