/****************************************************************************************************
	TestWindowViewController.h
	Observable
	
    Created by Chall Fry on 9/9/13.
    Copyright (c) 2013-2014 eBay Software Foundation.
    
    A table view of tests that can be run to demonstrate Observable.
*/

#import "TestWindowViewController.h"
#import "EBNObservable.h"

#import "ModelObject1.h"
#import "SubViewController.h"

@interface TestWindowViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation TestWindowViewController
{
	IBOutlet UITableView 	*table;
	NSMutableArray			*tableCells;

	ModelObject1 			*modelObj2;
}

- (id)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self)
	{
		tableCells = [[NSMutableArray alloc] init];
		[self setupTableCells];
		
		modelObj2 = [[ModelObject1 alloc] init];
		ObserveProperty(modelObj2, stringProperty,
		{
			NSLog(@"Model2 new value is:%@", observed.stringProperty);
		});
    }
    return self;
}

- (void) setupTableCells
{
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Test 1";
	cell.detailTextLabel.text = @"Shows basic observation";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Test 2";
	cell.detailTextLabel.text = @"Shows observation macros";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Test 3";
	cell.detailTextLabel.text = @"Shows multiple observation";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Performance Test";
	cell.detailTextLabel.text = @"Checks performance of observations";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run ViewController Test";
	cell.detailTextLabel.text = @"Open a new view controller";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Apple KVO Compatability Test";
	cell.detailTextLabel.text = @"Observes the same property twice";
	[tableCells addObject:cell];

}

#pragma mark Table View Data Source

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return [tableCells count];
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return [tableCells objectAtIndex:indexPath.row];
}

#pragma mark Table View Delegate

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	switch (indexPath.row)
	{
	case 0:[self runTest1]; break;
	case 1:[self runTest2]; break;
	case 2:[self runTest3]; break;
	case 3:[self runPerfTest]; break;
	case 4:[self runVCTest]; break;
	case 5:[self testWithOS_KVO]; break;
	}
	
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark Tests

- (void) runTest1
{
	ModelObject1 *model1 = [[ModelObject1 alloc] init];
	[model1 tell:self when:@"intProperty" changes:^(TestWindowViewController *blockSelf, ModelObject1 *observed)
			{
				NSLog(@"New value is:%d", observed.intProperty);
			}];
			
			
	model1.intProperty = 5;
	[model1 setIntProperty:-1];
	
	[model1 stopTelling:self aboutChangesTo:@"intProperty"];
}

- (void) runTest2
{
	modelObj2.stringProperty = @"meh";
	ObserveProperty(modelObj2, intProperty,
	{
		NSLog(@"int Property is now %d", observed.intProperty);
	});
	
	NSLog(@"%@", [modelObj2 debugShowAllObservers]);
	
	StopObservingPath(modelObj2, intProperty);
}

- (void) runTest3
{
	ModelObject2 *model3 = [[ModelObject2 alloc] init];
	
	[model3 tell:self when:@"*" changes:^(TestWindowViewController *me, ModelObject2 *obj)
			{
				NSLog(@"Model3 new int prop:%d new string prop: %@", obj.intProperty, obj.stringProperty);
				NSLog(@"Model3 range property: %d, %d", (int) obj.rangeProperty.location, (int) obj.rangeProperty.length);
			}];
						
	model3.intProperty = 5;
	model3.stringProperty = @"stringthing";
	model3.intProperty = 17;
	[model3 setStringProperty:@"thisisastring"];
	
	model3.rangeProperty = NSMakeRange(33, 2);
}

- (void) runPerfTest
{
	ModelObject1 *model4 = [[ModelObject1 alloc] init];

	// Test 1: No observation, set the value 100000 times.
	double startTime = CFAbsoluteTimeGetCurrent();
	for (int index = 0; index < 100000; ++index)
	{
		model4.intProperty = index;
	}
	double noKVODurationSecs = CFAbsoluteTimeGetCurrent() - startTime;

	// Test 2: With observations
	startTime = CFAbsoluteTimeGetCurrent();

	// Put 10 observerations on the object
	for (int index = 0; index < 100; ++index)
	{
		[model4 tell:self when:@"intProperty" changes:^(TestWindowViewController *me, ModelObject1 *obj)
				{
					NSLog(@"Model4 new int prop:%d", obj.intProperty);
				}];
	}

	// And set the value 100000 times
	for (int index = 0; index < 100000; ++index)
	{
		model4.intProperty = index;
	}
	double kvoDurationSecs = CFAbsoluteTimeGetCurrent() - startTime;
	NSLog(@"With KVO: %f seconds. Without: %f seconds.", kvoDurationSecs, noKVODurationSecs);
}

- (void) runVCTest
{
	SubViewController *subVC = [[SubViewController alloc] init];
	[self presentViewController:subVC animated:YES completion:^{}];
}

- (void) testWithOS_KVO
{
	modelObj2.intProperty = 71;

	// Set up our KVO on "intProperty"
	[modelObj2 tell:self when:@"intProperty" changes:^(id observingObj, id observedObj)
			{
				NSLog(@"ModelObj2 intProperty changed. New value:%d", modelObj2.intProperty);
			}];
			
	// And set up Apple's KVO on the same property
	[modelObj2 addObserver:self forKeyPath:@"intProperty" options:NSKeyValueObservingOptionNew context:nil];
	
	// Change the property's value
	modelObj2.intProperty = 72;
	
	[modelObj2 removeObserver:self forKeyPath:@"intProperty"];
	[modelObj2 stopTelling:self aboutChangesTo:@"intProperty"];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
		context:(void *)context
{
    if ([keyPath isEqual:@"intProperty"])
	{
		NSLog(@"ModelObj2 iOS KVO hit for %@. New value is:%d", keyPath,
				[[change objectForKey:NSKeyValueChangeNewKey] intValue]);
    }
}


- (void) observedObjectHasBeenDealloced:(id) object
{
	NSLog(@"Object: %@ sent dealloc notification", [object debugDescription]);
}

@end
