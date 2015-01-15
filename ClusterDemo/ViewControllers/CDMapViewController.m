//
//  CDMapViewController.m
//  ClusterDemo
//
//  Created by Patrick Nollet on 09/10/12.
//  Copyright (c) 2012 Applidium. All rights reserved.
//

#import "CDMapViewController.h"
#import "ADBaseAnnotation.h"
#import "TSBathroomAnnotation.h"
#import "TSStreetLightAnnotation.h"
#import "TSDemoClusteredAnnotationView.h"

static NSString * const CDStreetLightJsonFile = @"CDStreetlights";
static NSString * const kStreetLightAnnotationImage = @"StreetLightAnnotation";

static NSString * const CDToiletJsonFile = @"CDToilets";
static NSString * const kBathroomAnnotationImage = @"BathroomAnnotation";


@implementation CDMapViewController

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _tabBar.tintColor = UIColorFromRGB(0x009fd6);

    _mapView.visibleMapRect = MKMapRectMake(135888858.533591, 92250098.902419, 190858.927912, 145995.678292);
    _mapView.clusterDiscriminationPower = 1.8;
    
    [self parseJsonData];
}


- (void)parseJsonData {
    
    _streetLightAnnotations = [[NSMutableArray alloc] initWithCapacity:10];
    _bathroomAnnotations = [[NSMutableArray alloc] initWithCapacity:10];
    NSLog(@"Loading data…");
    
    [[NSOperationQueue new] addOperationWithBlock:^{
        NSData * JSONData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:CDStreetLightJsonFile ofType:@"json"]];
        
        for (NSDictionary * annotationDictionary in [NSJSONSerialization JSONObjectWithData:JSONData options:kNilOptions error:NULL]) {
            TSStreetLightAnnotation * annotation = [[TSStreetLightAnnotation alloc] initWithDictionary:annotationDictionary];
            [_streetLightAnnotations addObject:annotation];
        }
        
        NSLog(@"Finished CDStreetLightJsonFile");
    }];
    
    [[NSOperationQueue new] addOperationWithBlock:^{
        NSData * JSONData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:CDToiletJsonFile ofType:@"json"]];
        
        for (NSDictionary * annotationDictionary in [NSJSONSerialization JSONObjectWithData:JSONData options:kNilOptions error:NULL]) {
            TSBathroomAnnotation * annotation = [[TSBathroomAnnotation alloc] initWithDictionary:annotationDictionary];
            [_bathroomAnnotations addObject:annotation];
        }
        
        NSLog(@"Finished CDToiletJsonFile");
    }];
}

#pragma mark - Tab Bar Delegate

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    
    if (item == _bathroomTabBarItem) {
        [_mapView addClusteredAnnotations:_bathroomAnnotations];
    }
    else if (item == _streetLightsTabBarItem) {
        [_mapView addClusteredAnnotations:_streetLightAnnotations];
    }
}

#pragma mark - MKMapViewDelegate
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    
    MKAnnotationView *view;
    
    if ([annotation isKindOfClass:[TSStreetLightAnnotation class]]) {
        view = (MKAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:NSStringFromClass([TSStreetLightAnnotation class])];
        if (!view) {
            view = [[MKAnnotationView alloc] initWithAnnotation:annotation
                                                   reuseIdentifier:NSStringFromClass([TSStreetLightAnnotation class])];
            view.image = [UIImage imageNamed:kStreetLightAnnotationImage];
            view.canShowCallout = YES;
            view.centerOffset = CGPointMake(view.centerOffset.x, -view.frame.size.height/2);
        }
    }
    else if ([annotation isKindOfClass:[TSBathroomAnnotation class]]) {
        view = (MKAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:NSStringFromClass([TSBathroomAnnotation class])];
        if (!view) {
            view = [[MKAnnotationView alloc] initWithAnnotation:annotation
                                                reuseIdentifier:NSStringFromClass([TSBathroomAnnotation class])];
            view.image = [UIImage imageNamed:kBathroomAnnotationImage];
            view.canShowCallout = YES;
            view.centerOffset = CGPointMake(view.centerOffset.x, -view.frame.size.height/2);
        }
    }
    
    return view;
}


#pragma mark - ADClusterMapView Delegate

- (MKAnnotationView *)mapView:(ADClusterMapView *)mapView viewForClusterAnnotation:(id<MKAnnotation>)annotation {
    
    TSDemoClusteredAnnotationView * view = (TSDemoClusteredAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:NSStringFromClass([TSDemoClusteredAnnotationView class])];
    if (!view) {
        view = [[TSDemoClusteredAnnotationView alloc] initWithAnnotation:annotation
                                                            reuseIdentifier:NSStringFromClass([TSDemoClusteredAnnotationView class])];
    }
    
    return view;
}

- (void)mapView:(ADClusterMapView *)mapView willBeginBuildingClusterTreeForMapPoints:(NSSet *)annotations {
    
    NSLog(@"Kd-tree will begin mapping item count %lu", (unsigned long)annotations.count);
}

- (void)mapView:(ADClusterMapView *)mapView didFinishBuildingClusterTreeForMapPoints:(NSSet *)annotations {
    
    NSLog(@"Kd-tree finished mapping item count %lu", (unsigned long)annotations.count);
}

- (void)mapViewWillBeginClusteringAnimation:(ADClusterMapView *)mapView{
    
     NSLog(@"Animation operation will begin");
}

- (void)mapViewDidCancelClusteringAnimation:(ADClusterMapView *)mapView {
    
    NSLog(@"Animation operation cancelled");
}

- (void)mapViewDidFinishClusteringAnimation:(ADClusterMapView *)mapView{
    
    NSLog(@"Animation operation finished");
}

- (void)userWillPanMapView:(ADClusterMapView *)mapView {
    
    NSLog(@"Map will pan from user interaction");
}

- (void)userDidPanMapView:(ADClusterMapView *)mapView {
    
    NSLog(@"Map did pan from user interaction");
}


@end
