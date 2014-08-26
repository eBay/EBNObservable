/****************************************************************************************************
	ModelObject1.h
	Observable
	
    Created by Chall Fry on 9/27/13.
    Copyright (c) 2013-2014 eBay Software Foundation.
    
    These are demonstration model objects, here so that we can demonstrate Observable.	
*/

#import "EBNLazyLoader.h"

struct BitfieldStruct
{
	unsigned int field1 : 1;
};


@interface ModelObject1 : EBNLazyLoader

@property unsigned int intProperty;
@property unsigned int intProperty2;
@property (strong) NSString *stringProperty;

@end

@interface ModelObject2 : ModelObject1

@property (strong) NSString *stringProperty2;
@property NSRange rangeProperty;

@property (readonly) NSString *stringProperty3;

	// This could work if we add code to EBNObservable.mm to understand the type encoding.
// @property struct BitfieldStruct bitfieldProperty;

@property int (* fnProperty)();
@end