/****************************************************************************************************
	TestWindowViewController.h
	Observable
	
    Created by Chall Fry on 9/9/13.
    Copyright (c) 2013-2018 eBay Software Foundation.
    
    A table view of tests that can be run to demonstrate Observable.
*/

#import "TestWindowViewController.h"
#import "EBNObservable.h"
#import "EBNObservableInternal.h"

#import "ModelObjects.h"
#import "SubViewController.h"

@interface TestWindowViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation TestWindowViewController
{
	IBOutlet UITableView 	*table;
	NSMutableArray			*tableCells;

	ModelObject2 			*modelObj2;
	
	ModelObject4			*modelObj4;
	BOOL					runningTortureTest;
}

- (id)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self)
	{
		tableCells = [[NSMutableArray alloc] init];
		[self setupTableCells];
		
		modelObj2 = [[ModelObject2 alloc] init];
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
	cell.textLabel.text = @"Run Basic Demo";
	cell.detailTextLabel.text = @"Shows basic observation";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Macro Demo";
	cell.detailTextLabel.text = @"Shows observation macros";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Multiple Observation Demo";
	cell.detailTextLabel.text = @"Shows multiple observation";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Performance Test";
	cell.detailTextLabel.text = @"Checks performance of observations";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run ViewController Demo";
	cell.detailTextLabel.text = @"Open a new view controller";
	[tableCells addObject:cell];

	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Apple KVO Compatability Demo";
	cell.detailTextLabel.text = @"Observes the same property twice";
	[tableCells addObject:cell];
	
	cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = @"Run Multithread Torture Test";
	cell.detailTextLabel.text = @"Does everything, all at once";
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
	case 0:[self runBasicObservationDemo]; break;
	case 1:[self runMacroDemo]; break;
	case 2:[self runMultipleObservationDemo]; break;
	case 3:[self runPerfTest]; break;
	case 4:[self runVCTest]; break;
	case 5:[self testWithOS_KVO]; break;
	case 6:[self runMultithreadTortureTest]; break;
	}
	
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark Demos

- (void) runBasicObservationDemo
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

- (void) runMacroDemo
{
	modelObj2.stringProperty = @"meh";
	ObserveProperty(modelObj2, intProperty,
	{
		NSLog(@"int Property is now %d", observed.intProperty);
	});
	
	NSLog(@"%@", [modelObj2 debugShowAllObservers]);
	
	StopObservingPath(modelObj2, intProperty);
}

- (void) runMultipleObservationDemo
{
	ModelObject2 *model2 = [[ModelObject2 alloc] init];
	
	[model2 tell:self when:@"*" changes:^(TestWindowViewController *me, ModelObject2 *obj)
	{
		NSLog(@"Model2 new int prop:%d new string prop: %@", obj.intProperty, obj.stringProperty);
		NSLog(@"Model2 range property: %d, %d", (int) obj.rangeProperty.location, (int) obj.rangeProperty.length);
	}];
	
	model2.intProperty = 5;
	model2.stringProperty = @"stringthing";
	model2.intProperty = 17;
	[model2 setStringProperty:@"thisisastring"];
	
	model2.rangeProperty = NSMakeRange(33, 2);
}

- (void) runPerfTest
{
	double startTime;
	
	ModelObject3 *model3 = [[ModelObject3 alloc] init];

	// Test 1: No observation, set the value 100000 times.
	startTime = CFAbsoluteTimeGetCurrent();
	for (int index = 0; index < 100000; ++index)
	{
		model3.intProperty = index;
	}
	double noKVODurationSecs = CFAbsoluteTimeGetCurrent() - startTime;

	// Test 2: With observations
	startTime = CFAbsoluteTimeGetCurrent();

	// Put 100 observerations on the object
	__block int totalObservationCount = 0;
	for (int index = 0; index < 100; ++index)
	{
		[model3 tell:self when:@"intProperty" changes:^(TestWindowViewController *me, ModelObject3 *obj)
				{
					++totalObservationCount;
				}];
	}

	// And set the value 100000 times
	for (int index = 0; index < 100000; ++index)
	{
		model3.intProperty = index;
	}
	double kvoDurationSecs = CFAbsoluteTimeGetCurrent() - startTime;
	NSLog(@"With KVO: %f seconds. Without: %f seconds.", kvoDurationSecs, noKVODurationSecs);
	

	// Test 2: make a Model Object 4, which has 100 int properties
	startTime = CFAbsoluteTimeGetCurrent();
	ModelObject4 *model4 = [[ModelObject4 alloc] init];
	
	// Start and then stop observing all of them. Individually.
	[self observe100PropertiesOfModel4:model4];
	[self stopObserving100PropertiesOfModel4:model4];
	
	// Or, use the * forms
//	[model4 tell:self when:@"*" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
//	[model4 stopTellingAboutChanges:self];

	double observe100DurationSecs = CFAbsoluteTimeGetCurrent() - startTime;
	NSLog(@"%f seconds to observe 100 properties, or %f per property.", observe100DurationSecs, observe100DurationSecs / 100);
	
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

- (void) runMultithreadTortureTest
{
	modelObj4 = [[ModelObject4 alloc] init];
	runningTortureTest = YES;
	
	[NSTimer scheduledTimerWithTimeInterval:20 target:self selector:@selector(timerDone:)
			userInfo:nil repeats:NO];
	
	for (int numThreads = 0; numThreads < 10; ++numThreads)
	{
		[NSThread detachNewThreadSelector:@selector(tortureTest_startEndObservations) toTarget:self withObject:nil];
		[NSThread detachNewThreadSelector:@selector(tortureTest_setValues) toTarget:self withObject:nil];
	}
}

- (void) tortureTest_startEndObservations
{
	while (runningTortureTest)
	{
//		NSLog(@"Observing and then stopping all properties.");
		[self observe100PropertiesOfModel4:modelObj4];
		[self stopObserving100PropertiesOfModel4:modelObj4];
	}
}

- (void) tortureTest_setValues
{
	int newValueForAllProperties = 0;
	
	while (runningTortureTest)
	{
//		NSLog(@"Setting the value of all properties to %d", newValueForAllProperties);
		[self setAll100PropertiesOfModel4: modelObj4 toValue:newValueForAllProperties];
		newValueForAllProperties++;
	}
}

- (void) timerDone:(NSTimer *) timer
{
	runningTortureTest = NO;
	
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(),
	^{
		NSLog(@"Torture Test complete.");
	});
	
	[modelObj4 stopTellingAboutChanges:self];
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

- (void) observe100PropertiesOfModel4:(ModelObject4 *) model4
{
	[model4 tell:self when:@"intProperty1" changes:^(TestWindowViewController *me, ModelObject4 *obj)
	{
		NSLog(@"intProperty1 changed value. New value is %d", obj.intProperty1);
	}];
	
	[model4 tell:self when:@"intProperty2" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty3" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty4" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty5" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty6" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty7" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty8" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty9" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty10" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty11" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty12" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty14" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty15" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty16" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty17" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty18" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty19" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty20" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty21" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty22" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty24" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty25" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty26" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty27" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty28" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty29" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty30" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty31" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty32" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty33" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty34" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty35" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty36" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty37" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty38" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty39" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty30" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty40" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty41" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty42" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty43" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty44" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty45" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty46" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty47" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty48" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty49" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty50" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty51" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty52" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty53" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty54" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty55" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty56" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty57" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty58" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty59" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty60" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty61" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty62" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty63" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty64" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty65" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty66" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty67" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty68" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty69" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty70" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty71" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty72" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty73" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty74" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty75" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty76" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty77" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty78" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty79" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty80" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty81" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty82" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty83" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty84" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty85" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty86" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty87" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty88" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty89" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty90" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty91" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty92" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty93" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty94" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty95" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty96" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty97" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty98" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty99" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
	[model4 tell:self when:@"intProperty100" changes:^(TestWindowViewController *me, ModelObject4 *obj) { }];
}

- (void) stopObserving100PropertiesOfModel4:(ModelObject4 *) model4
{
	// We could just call stopTellingAboutChanges:, but that defeats the performance-testing purpose
	[model4 stopTelling:self aboutChangesTo:@"intProperty1"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty2"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty3"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty4"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty5"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty6"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty7"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty8"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty9"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty10"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty11"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty12"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty14"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty15"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty16"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty17"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty18"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty19"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty20"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty21"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty22"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty24"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty25"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty26"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty27"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty28"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty29"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty30"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty31"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty32"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty33"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty34"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty35"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty36"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty37"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty38"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty39"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty30"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty40"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty41"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty42"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty43"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty44"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty45"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty46"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty47"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty48"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty49"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty50"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty51"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty52"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty53"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty54"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty55"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty56"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty57"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty58"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty59"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty60"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty61"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty62"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty63"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty64"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty65"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty66"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty67"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty68"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty69"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty70"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty71"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty72"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty73"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty74"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty75"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty76"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty77"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty78"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty79"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty80"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty81"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty82"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty83"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty84"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty85"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty86"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty87"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty88"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty89"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty90"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty91"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty92"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty93"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty94"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty95"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty96"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty97"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty98"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty99"];
	[model4 stopTelling:self aboutChangesTo:@"intProperty100"];
}

- (void) setAll100PropertiesOfModel4:(ModelObject4 *) model4 toValue:(int) newValue
{
	model4.intProperty1 = newValue;
	model4.intProperty2 = newValue;
	model4.intProperty3 = newValue;
	model4.intProperty4 = newValue;
	model4.intProperty5 = newValue;
	model4.intProperty6 = newValue;
	model4.intProperty7 = newValue;
	model4.intProperty8 = newValue;
	model4.intProperty9 = newValue;
	model4.intProperty10 = newValue;
	model4.intProperty11 = newValue;
	model4.intProperty12 = newValue;
	model4.intProperty13 = newValue;
	model4.intProperty14 = newValue;
	model4.intProperty15 = newValue;
	model4.intProperty16 = newValue;
	model4.intProperty17 = newValue;
	model4.intProperty18 = newValue;
	model4.intProperty19 = newValue;
	model4.intProperty20 = newValue;
	model4.intProperty21 = newValue;
	model4.intProperty22 = newValue;
	model4.intProperty23 = newValue;
	model4.intProperty24 = newValue;
	model4.intProperty25 = newValue;
	model4.intProperty26 = newValue;
	model4.intProperty27 = newValue;
	model4.intProperty28 = newValue;
	model4.intProperty29 = newValue;
	model4.intProperty30 = newValue;
	model4.intProperty31 = newValue;
	model4.intProperty32 = newValue;
	model4.intProperty33 = newValue;
	model4.intProperty34 = newValue;
	model4.intProperty35 = newValue;
	model4.intProperty36 = newValue;
	model4.intProperty37 = newValue;
	model4.intProperty38 = newValue;
	model4.intProperty39 = newValue;
	model4.intProperty40 = newValue;
	model4.intProperty41 = newValue;
	model4.intProperty42 = newValue;
	model4.intProperty34 = newValue;
	model4.intProperty44 = newValue;
	model4.intProperty45 = newValue;
	model4.intProperty46 = newValue;
	model4.intProperty47 = newValue;
	model4.intProperty48 = newValue;
	model4.intProperty49 = newValue;
	model4.intProperty50 = newValue;
	model4.intProperty51 = newValue;
	model4.intProperty52 = newValue;
	model4.intProperty53 = newValue;
	model4.intProperty54 = newValue;
	model4.intProperty55 = newValue;
	model4.intProperty56 = newValue;
	model4.intProperty57 = newValue;
	model4.intProperty58 = newValue;
	model4.intProperty59 = newValue;
	model4.intProperty60 = newValue;
	model4.intProperty61 = newValue;
	model4.intProperty62 = newValue;
	model4.intProperty63 = newValue;
	model4.intProperty46 = newValue;
	model4.intProperty65 = newValue;
	model4.intProperty66 = newValue;
	model4.intProperty67 = newValue;
	model4.intProperty68 = newValue;
	model4.intProperty69 = newValue;
	model4.intProperty70 = newValue;
	model4.intProperty71 = newValue;
	model4.intProperty72 = newValue;
	model4.intProperty73 = newValue;
	model4.intProperty74 = newValue;
	model4.intProperty75 = newValue;
	model4.intProperty76 = newValue;
	model4.intProperty77 = newValue;
	model4.intProperty78 = newValue;
	model4.intProperty79 = newValue;
	model4.intProperty80 = newValue;
	model4.intProperty81 = newValue;
	model4.intProperty82 = newValue;
	model4.intProperty83 = newValue;
	model4.intProperty84 = newValue;
	model4.intProperty85 = newValue;
	model4.intProperty86 = newValue;
	model4.intProperty87 = newValue;
	model4.intProperty88 = newValue;
	model4.intProperty89 = newValue;
	model4.intProperty90 = newValue;
	model4.intProperty91 = newValue;
	model4.intProperty92 = newValue;
	model4.intProperty93 = newValue;
	model4.intProperty94 = newValue;
	model4.intProperty95 = newValue;
	model4.intProperty96 = newValue;
	model4.intProperty97 = newValue;
	model4.intProperty98 = newValue;
	model4.intProperty99 = newValue;
}

@end
