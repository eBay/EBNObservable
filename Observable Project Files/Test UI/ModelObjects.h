/****************************************************************************************************
	ModelObjects.h
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

typedef int (*fnType)(void);

@interface ModelObject1 : NSObject

@property unsigned int intProperty;
@property unsigned int intProperty2;
@property (strong) NSString *stringProperty;

@end

@interface ModelObject2 : ModelObject1

@property (strong) NSString *stringProperty2;
@property NSRange rangeProperty;

@property (readonly) NSString *stringProperty3;


@property (assign) fnType fnProperty;
@end

@interface ModelObject3 : NSObject

@property unsigned int intProperty;

@end

@interface ModelObject4 : NSObject

@property int			intProperty1;
@property int			intProperty2;
@property int			intProperty3;
@property int			intProperty4;
@property int			intProperty5;
@property int			intProperty6;
@property int			intProperty7;
@property int			intProperty8;
@property int			intProperty9;
@property int			intProperty10;
@property int			intProperty11;
@property int			intProperty12;
@property int			intProperty13;
@property int			intProperty14;
@property int			intProperty15;
@property int			intProperty16;
@property int			intProperty17;
@property int			intProperty18;
@property int			intProperty19;
@property int			intProperty20;
@property int			intProperty21;
@property int			intProperty22;
@property int			intProperty23;
@property int			intProperty24;
@property int			intProperty25;
@property int			intProperty26;
@property int			intProperty27;
@property int			intProperty28;
@property int			intProperty29;
@property int			intProperty30;
@property int			intProperty31;
@property int			intProperty32;
@property int			intProperty33;
@property int			intProperty34;
@property int			intProperty35;
@property int			intProperty36;
@property int			intProperty37;
@property int			intProperty38;
@property int			intProperty39;
@property int			intProperty40;
@property int			intProperty41;
@property int			intProperty42;
@property int			intProperty43;
@property int			intProperty44;
@property int			intProperty45;
@property int			intProperty46;
@property int			intProperty47;
@property int			intProperty48;
@property int			intProperty49;
@property int			intProperty50;
@property int			intProperty51;
@property int			intProperty52;
@property int			intProperty53;
@property int			intProperty54;
@property int			intProperty55;
@property int			intProperty56;
@property int			intProperty57;
@property int			intProperty58;
@property int			intProperty59;
@property int			intProperty60;
@property int			intProperty61;
@property int			intProperty62;
@property int			intProperty63;
@property int			intProperty64;
@property int			intProperty65;
@property int			intProperty66;
@property int			intProperty67;
@property int			intProperty68;
@property int			intProperty69;
@property int			intProperty70;
@property int			intProperty71;
@property int			intProperty72;
@property int			intProperty73;
@property int			intProperty74;
@property int			intProperty75;
@property int			intProperty76;
@property int			intProperty77;
@property int			intProperty78;
@property int			intProperty79;
@property int			intProperty80;
@property int			intProperty81;
@property int			intProperty82;
@property int			intProperty83;
@property int			intProperty84;
@property int			intProperty85;
@property int			intProperty86;
@property int			intProperty87;
@property int			intProperty88;
@property int			intProperty89;
@property int			intProperty90;
@property int			intProperty91;
@property int			intProperty92;
@property int			intProperty93;
@property int			intProperty94;
@property int			intProperty95;
@property int			intProperty96;
@property int			intProperty97;
@property int			intProperty98;
@property int			intProperty99;
@property int			intProperty100;

@end









