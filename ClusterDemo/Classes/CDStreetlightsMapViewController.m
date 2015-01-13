//
//  CDStreetlightsMapViewController.m
//  ClusterDemo
//
//  Created by Patrick Nollet on 11/10/12.
//  Copyright (c) 2012 Applidium. All rights reserved.
//

#import "CDStreetlightsMapViewController.h"
#import "ADClusterableAnnotation.h"

@implementation CDStreetlightsMapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self removeOtherAnnotationsFromMap];
}

- (void)addOtherAnnotations {
    
    _otherAnnotations = [[NSMutableArray alloc] init];
    
    NSLog(@"Loading other data…");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSData * JSONData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"CDToilets" ofType:@"json"]];
        
        for (NSDictionary * annotationDictionary in [NSJSONSerialization JSONObjectWithData:JSONData options:kNilOptions error:NULL]) {
            ADClusterableAnnotation * annotation = [[ADClusterableAnnotation alloc] initWithDictionary:annotationDictionary];
            [_otherAnnotations addObject:annotation];
        }
        
        [self addRandomAnnotation];
    });
}

- (void)addRandomAnnotation {
    
    ADClusterableAnnotation * annotation = [_otherAnnotations firstObject];
    if (annotation) {
        [_otherAnnotations removeObject:annotation];
    }
    
    [self.mapView addClusteredAnnotation:annotation clusterTreeRefresh:NO];
    
    [self performSelector:@selector(addRandomAnnotation) withObject:nil afterDelay:15];
}

- (void)removeOtherAnnotationsFromMap {
    
    NSLog(@"Removing other data…");
    [self.mapView removeAnnotations:self.otherAnnotations];
    
    [self performSelector:@selector(addOtherAnnotations) withObject:nil afterDelay:15];
}



- (NSString *)pictoName {
    return @"CDStreetlight.png";
}

- (NSString *)clusterPictoName {
    return @"CDStreetlightCluster.png";
}

- (NSString *)seedFileName {
    return @"CDStreetlights";
}
@end
