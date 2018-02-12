/****************************************************************************************************
	SubViewController.m
	Observable
	
    Created by Chall Fry on 10/1/13.
    Copyright (c) 2013-2018 eBay Software Foundation.
    
    Used in the ViewController test, this is a simple viewcontroller that sets up observation and doesn't
    remove it when it exits.
*/

#import "SubViewController.h"
#import "ModelObjects.h"

@interface SubViewController ()

@end

@implementation SubViewController
{
	ModelObject1 	*obj1;
}

- (id)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self)
	{
        // Custom initialization
		obj1 = [[ModelObject1 alloc] init];
		
		[obj1 tell:self when:@"intProperty" changes:^(SubViewController *me, ModelObject1 *obj)
				{
					NSLog(@"intProperty's value is now %d", obj.intProperty);
				}];
    }
    return self;
}

- (void) dealloc
{
	NSLog(@"SubViewController being deallocated");
}

- (void)viewDidLoad
{
    [super viewDidLoad];

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction) setIntButton:(id)sender
{
	obj1.intProperty = 55;
}

- (IBAction) closeButton:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:^{}];
}

@end
