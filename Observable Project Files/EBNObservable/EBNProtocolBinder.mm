/****************************************************************************************************
	EBNProtocolBinder.mm
	Observable
	
	Created by Chall Fry on 9/18/17.
    Copyright (c) 2013-2017 eBay Software Foundation.
	
*/

#import "EBNProtocolBinder.h"

#import <objc/runtime.h>
#import <UIKit/UIGeometry.h>
#import "EBNObservableInternal.h"

static NSMutableSet<NSString *> *EBN_GetProtocolProperties(Protocol *protocol);
static NSMutableSet<NSString *> *EBN_GetThisProtocolProperties(Protocol * protocol);
static void EBN_GetAllParentProtocols(Protocol *protocol, NSMutableSet<Protocol *> *parentSet);
static ObservationBlock EBN_BlockForCopyingProperty(id fromObject, SEL getterSelector, id toObject, SEL setterSelector);
template<typename T> ObservationBlock EBN_Template_PropertyCopyBlock(SEL getterSelector, Method getterMethod,
		SEL setterSelector, Method setterMethod);

@implementation NSObject (EBNProtocolBinder)

/****************************************************************************************************
	bindTo:withProtocol:
    
    Binds the properties in the given protocol from the observed object to the receiver. The receiver
	and observed must both conform to the given protocol.
	
	For Protocol A that declares property B:
		- The receiver must conform to A
		- Observed must conform to A
		- receiver.B is set to the value of observed.B immediately
		- receiver.B is updated to observed.B's latest value whenever observed.B changes
		- If B is an @optional property of protocol A, it's okay, but B is only bound if both receiver
			and observed implement B
		- The setter semantics are defined by the protocol itself.
*/
- (void) bindTo:(id) observed withProtocol:(Protocol *) protocol
{
	EBAssert([self conformsToProtocol:protocol], @"The receiver object must conform to the protocol you're trying to bind.");
	EBAssert([observed conformsToProtocol:protocol], @"The observed object must conform to the protocol you're trying to bind.");
	
	NSMutableSet *propertiesToObserve = EBN_GetProtocolProperties(protocol);
	for (NSString *propName in propertiesToObserve)
	{
		SEL selfSelector = ebn_selectorForPropertySetter([self class], propName);
		SEL observedSelector = ebn_selectorForPropertyGetter([observed class], propName);
		if (selfSelector && observedSelector)
		{
			ObservationBlock block = EBN_BlockForCopyingProperty(observed, observedSelector, self, selfSelector);
			[[observed tell:self when:propName changes:block] execute];
		}
	}
}

/****************************************************************************************************
	unbind:fromProtocol:
    
    Makes the receiver stop receiving updates from changes to properties in the given bound protocol.
	
	It's okay to call this if the protocol isn't currently bound.
*/
- (void) unbind:(id) observed fromProtocol:(Protocol *) protocol
{
	NSMutableSet *propertiesToStopObserving = EBN_GetProtocolProperties(protocol);
	[observed stopTelling:self aboutChangesToArray:[propertiesToStopObserving allObjects]];
}

@end

#pragma mark - Internal

/****************************************************************************************************
	EBN_GetProtocolProperties()

    Returns a set of all the properties declared in the given protocol, and all of the protocols that protocol adopts.
	
	Properties multiply declared in adopted protocols will be included once. Properties marked optional are included,
	as are computed properties and properties marked readonly or weak. Property-like setters and getters are NOT 
	included if they don't have a @property declaration.
*/
static NSMutableSet<NSString *> *EBN_GetProtocolProperties(Protocol *protocol)
{
	NSMutableSet<Protocol *> *allAdoptedProtocols = [NSMutableSet setWithObject:protocol];
	EBN_GetAllParentProtocols(protocol, allAdoptedProtocols);
	
	NSMutableSet<NSString *> *protocolProps = [NSMutableSet set];
	for (Protocol *parentProtocol in allAdoptedProtocols)
	{
		// Don't include the NSObject protocol properties of superclass, hash, description, debugDescription.
		if (protocol_isEqual(parentProtocol, @protocol(NSObject)))
			continue;
			
		NSMutableSet *parentProps = EBN_GetThisProtocolProperties(parentProtocol);
		[protocolProps unionSet:parentProps];
	}
			
	return protocolProps;
}


/****************************************************************************************************
	EBN_GetAllParentProtocols()

	RECURSIVE method to get all the protocols that a given protocol conforms to.
	
	protocol_copyProtocolList() gives us the direct parents of a protocol. Because of how protocols work,
	protocols can and do have 'diamond' inheritance where the same base protocol is adopted by multiple mid-tier
	protocols, which are in turn adopted by a leaf protocol.
	
	This method gathers all the parent protocols into a flat set.
*/

static void EBN_GetAllParentProtocols(Protocol *protocol, NSMutableSet<Protocol *> *parentSet)
{
	unsigned int protoCount = 0;
	Protocol * __unsafe_unretained *parentProtocols = protocol_copyProtocolList(protocol, &protoCount);
	if (parentProtocols)
	{
		for (unsigned int protoIndex = 0; protoIndex < protoCount; ++protoIndex)
		{
			Protocol *parentProtocol = parentProtocols[protoIndex];
			if (![parentSet containsObject:parentProtocol])
			{
				[parentSet addObject:parentProtocol];
				EBN_GetAllParentProtocols(parentProtocol, parentSet);				
			}
		}
		
		free(parentProtocols);
	}
}

/****************************************************************************************************
	EBN_GetThisProtocolProperties()
    
    Returns a set of all the properties declared in the given protocol. Does not include properties
	declared in protocols adopted by the given protocol. 
*/
static NSMutableSet<NSString *> *EBN_GetThisProtocolProperties(Protocol * protocol)
{
	NSMutableSet<NSString *> *results = [NSMutableSet set];
	
	unsigned int propCount = 0;
	objc_property_t *props = protocol_copyPropertyList(protocol, &propCount);
	if (props)
	{
		for (unsigned int propIndex = 0; propIndex < propCount; ++propIndex)
		{
			objc_property_t property = props[propIndex];
			NSString *propName = [NSString stringWithUTF8String:property_getName(property)];
			[results addObject:propName];
		}
	
		free(props);
	}
	
	return results;
}

/****************************************************************************************************
	EBN_BlockForCopyingProperty()
	
	Returns a ObservationBlock that can copy a property value from fromObject to toObject. Does not
	work with keypaths. FromObject must have a getter for the given property, and toObject must have a setter.
*/
ObservationBlock EBN_BlockForCopyingProperty(id fromObject, SEL getterSelector, id toObject, SEL setterSelector)
{
	Method getterMethod = class_getInstanceMethod([fromObject class], getterSelector);
	Method setterMethod = class_getInstanceMethod([toObject class], setterSelector);
	if (!getterMethod || !setterMethod)
		return nil;

	ObservationBlock resultBlock = nil;
	
	char typeOfSetter[32];
	method_getArgumentType(setterMethod, 2, typeOfSetter, 32);
	switch (typeOfSetter[0])
	{
	case _C_CHR:
		resultBlock = EBN_Template_PropertyCopyBlock<char>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_UCHR:
		resultBlock = EBN_Template_PropertyCopyBlock<unsigned char>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_SHT:
		resultBlock = EBN_Template_PropertyCopyBlock<short>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_USHT:
		resultBlock = EBN_Template_PropertyCopyBlock<unsigned short>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_INT:
		resultBlock = EBN_Template_PropertyCopyBlock<int>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_UINT:
		resultBlock = EBN_Template_PropertyCopyBlock<unsigned int>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_LNG:
		resultBlock = EBN_Template_PropertyCopyBlock<long>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_ULNG:
		resultBlock = EBN_Template_PropertyCopyBlock<unsigned long>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_LNG_LNG:
		resultBlock = EBN_Template_PropertyCopyBlock<long long>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_ULNG_LNG:
		resultBlock = EBN_Template_PropertyCopyBlock<unsigned long long>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_FLT:
		resultBlock = EBN_Template_PropertyCopyBlock<float>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_DBL:
		resultBlock = EBN_Template_PropertyCopyBlock<double>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_BFLD:
		// Pretty sure this can't happen, as bitfields can't be top-level and are only found inside structs/unions
		EBAssert(false, @"ProtocolBinder does not have a way to bind this property: %@.", getterSelector);
	break;
	case _C_BOOL:
		resultBlock = EBN_Template_PropertyCopyBlock<bool>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_PTR:
	case _C_CHARPTR:
	case _C_ATOM:		// Apparently never generated? Only docs I can find say treat same as charptr
	case _C_ARY_B:
		resultBlock = EBN_Template_PropertyCopyBlock<void *>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	
	case _C_ID:
		resultBlock = EBN_Template_PropertyCopyBlock<id>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_CLASS:
		resultBlock = EBN_Template_PropertyCopyBlock<Class>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;
	case _C_SEL:
		resultBlock = EBN_Template_PropertyCopyBlock<SEL>(getterSelector, getterMethod,
				setterSelector, setterMethod);
	break;

	case _C_STRUCT_B:
		if (!strncmp(typeOfSetter, @encode(NSRange), 32))
			resultBlock = EBN_Template_PropertyCopyBlock<NSRange>(getterSelector, getterMethod,
					setterSelector, setterMethod);
		else if (!strncmp(typeOfSetter, @encode(CGPoint), 32))
			resultBlock = EBN_Template_PropertyCopyBlock<CGPoint>(getterSelector, getterMethod,
					setterSelector, setterMethod);
		else if (!strncmp(typeOfSetter, @encode(CGRect), 32))
			resultBlock = EBN_Template_PropertyCopyBlock<CGRect>(getterSelector, getterMethod,
					setterSelector, setterMethod);
		else if (!strncmp(typeOfSetter, @encode(CGSize), 32))
			resultBlock = EBN_Template_PropertyCopyBlock<CGSize>(getterSelector, getterMethod,
					setterSelector, setterMethod);
		else if (!strncmp(typeOfSetter, @encode(UIEdgeInsets), 32))
			resultBlock = EBN_Template_PropertyCopyBlock<UIEdgeInsets>(getterSelector, getterMethod,
					setterSelector, setterMethod);
		else
		EBAssert(false, @"ProtocolBinder does not have a way to bind this property: %@.", getterSelector);
	break;
	
	case _C_UNION_B:
		// If you hit this assert, look at what we do above for structs, make something like that for
		// unions, and add your type to the if statement
		EBAssert(false, @"ProtocolBinder does not have a way to bind this property: %@.", getterSelector);
	break;
	
	default:
		EBAssert(false, @"ProtocolBinder does not have a way to bind this property: %@.", getterSelector);
	break;
	}
	
	return resultBlock;
}

/****************************************************************************************************
	EBN_Template_PropertyCopyBlock()
	
	Template method to make property copy block. Templatized over the type of property being copied.
	
	The returned block calls the property getter in fromObject, which returns a T. The block then calls the
	setter on toObject, giving it the value returned by the getter.
	
	Seriously, I have just described:
	
		toObject.property = fromObject.property;
*/
template<typename T> ObservationBlock EBN_Template_PropertyCopyBlock(SEL getterSelector, Method getterMethod,
		SEL setterSelector, Method setterMethod)
{
	// Copied into the observerBlock are: The selectors and methods for the getter and setter. 
	// Not copied in: the from and to objects.
	ObservationBlock newBlock = ^(id toObject, id fromObject)
	{
		T (*getterImplementation)(id, SEL) = (T (*)(id, SEL)) method_getImplementation(getterMethod);
		T newValue = getterImplementation(fromObject, getterSelector);

		void (*setterImplementation)(id, SEL, T) = (void (*)(id, SEL, T)) method_getImplementation(setterMethod);
		(setterImplementation)(toObject, setterSelector, newValue);
	};
	
	return newBlock;
}




