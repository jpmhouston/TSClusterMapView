//
//  TSClusterOperation.m
//  TapShield
//
//  Created by Adam Share on 7/14/14.
//  Copyright (c) 2014 TapShield, LLC. All rights reserved.
//

#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)

#import "TSClusterOperation.h"
#import <MapKit/MapKit.h>
#import "ADMapCluster.h"
#import "ADClusterAnnotation.h"
#import "ADMapPointAnnotation.h"
#import "NSDictionary+MKMapRect.h"
#import "CLLocation+Utilities.h"
#import "ADClusterMapView.h"
#import "TSRefreshedAnnotationView.h"

@interface TSClusterOperation ()

@property (weak, nonatomic) ADClusterMapView *mapView;
@property (strong, nonatomic) ADMapCluster *rootMapCluster;

@property (assign, nonatomic) NSUInteger numberOfClusters;
@property (assign, nonatomic) MKMapRect clusteringRect;
@property (nonatomic, strong) NSSet *clusterAnnotations;

@end

@implementation TSClusterOperation

- (instancetype)initWithMapView:(ADClusterMapView *)mapView rect:(MKMapRect)rect rootCluster:(ADMapCluster *)rootCluster showNumberOfClusters:(NSUInteger)numberOfClusters clusterAnnotations:(NSSet *)clusterAnnotations completion:(ClusterOperationCompletionBlock)completion
{
    self = [super init];
    if (self) {
        self.mapView = mapView;
        self.rootMapCluster = rootCluster;
        self.finishedBlock = completion;
        self.clusterAnnotations = [clusterAnnotations copy];
        self.numberOfClusters = numberOfClusters;
        self.clusteringRect = rect;
    }
    return self;
}

- (void)main {
    
    @autoreleasepool {
        
        [self clusterInMapRect:_clusteringRect];
    }
}

int nearestEvenInt(int to) {
    return (to % 2 == 0) ? to : (to + 1);
}


- (void)clusterInMapRect:(MKMapRect)clusteredMapRect {
    
    //Creates grid to estimate number of clusters needed based on the spread of annotations across map rect
    //
    //If there are should be 20 max clusters, we create 20 even rects (plus buffer rects) within the given map rect
    //and search to see if a cluster is contained in that rect.
    //
    //This helps distribute clusters more evenly by limiting clusters presented relative to viewable region.
    //Zooming all the way out will now cluster down to one single annotation if all clusters are within one grid rect.
    NSUInteger numberOnScreen;
    if (_mapView.region.span.longitudeDelta > _mapView.clusterMinimumLongitudeDelta) {
        
        NSSet *mapRects = [self mapRectsFromMaxNumberOfClusters:_numberOfClusters mapRect:clusteredMapRect];
        
        //number of map rects that contain at least one annotation
        numberOnScreen = [_rootMapCluster numberOfMapRectsContainingChildren:mapRects];
        numberOnScreen = numberOnScreen * _numberOfClusters/mapRects.count;
        if (numberOnScreen > 1) {
            numberOnScreen = nearestEvenInt((int)numberOnScreen);
        }
        else {
            numberOnScreen = 1;
        }
    }
    else {
        //Show maximum number of clusters we're at the minimum level set
        numberOnScreen = _numberOfClusters;
    }
    
    //Can never have more than the available annotations in the pool
    if (numberOnScreen > _numberOfClusters) {
        numberOnScreen = _numberOfClusters;
    }
    
    
    if (self.isCancelled) {
        if (_finishedBlock) {
            _finishedBlock(clusteredMapRect, NO);
        }
        return;
    }
    
    NSMutableSet *unmatchedAnnotations = [[NSMutableSet alloc] initWithCapacity:_clusterAnnotations.count];
    for (ADClusterAnnotation *annotation in _clusterAnnotations) {
        if (!annotation.cluster) {
            [unmatchedAnnotations addObject:annotation];
        }
    }
    
    NSMutableSet *matchedAnnotations = [[NSMutableSet alloc] initWithSet:_clusterAnnotations];
    [matchedAnnotations minusSet:unmatchedAnnotations];
    
    //Clusters that need to be visible after the animation
    NSSet *clustersToShowOnMap = [_rootMapCluster find:numberOnScreen childrenInMapRect:clusteredMapRect];
    
    NSMutableSet *unMatchedClusters = [[NSMutableSet alloc] initWithSet:clustersToShowOnMap];
    
    //There will be only one annotation after clustering in so we want to know if the cluster was already matched to an annotation
    NSMutableSet *parentClustersMatched = [[NSMutableSet alloc] initWithCapacity:_numberOfClusters];
    NSMutableSet *removeAfterAnimation = [[NSMutableSet alloc] initWithCapacity:_numberOfClusters];
    
    for (ADClusterAnnotation *annotation in matchedAnnotations) {
        
        //These will start at cluster and split to their respective cluster coordinates
        NSMutableSet *children = [annotation.cluster findChildrenForClusterInSet:clustersToShowOnMap];
        if (children.count) {
            
            ADMapCluster *cluster = [children anyObject];
            annotation.cluster = cluster;
            annotation.coordinatePreAnimation = annotation.coordinate;
            
            [children removeObject:cluster];
            [unMatchedClusters removeObject:cluster];
            
            for (ADMapCluster *cluster in children) {
                ADClusterAnnotation *clusterlessAnnotation = [unmatchedAnnotations anyObject];
                clusterlessAnnotation.cluster = cluster;
                clusterlessAnnotation.coordinatePreAnimation = annotation.coordinate;
                

                [unmatchedAnnotations removeObject:clusterlessAnnotation];

                [unMatchedClusters removeObject:cluster];
            }
            
            continue;
        }
        
        //These will start as individual annotations and cluster into a single annotations
        ADMapCluster *cluster = [annotation.cluster findAncestorForClusterInSet:clustersToShowOnMap];
        
        if (cluster) {
            annotation.cluster = cluster;
            annotation.coordinatePreAnimation = annotation.coordinate;
            
            [unMatchedClusters removeObject:cluster];
            
            if ([parentClustersMatched containsObject:cluster]) {
                [removeAfterAnimation addObject:annotation];
            }
            
            [parentClustersMatched addObject:cluster];
            
            continue;
        }
        
        //Whoops what happened?
        NSLog(@"No ancestor or child found");
        [unmatchedAnnotations addObject:annotation];
        [annotation shouldReset];
    }
    
    //Annotations may not be on the map yet
    for (ADMapCluster *cluster in unMatchedClusters) {
        ADClusterAnnotation *annotation = [unmatchedAnnotations anyObject];
        if (!annotation) {
            NSLog(@"Not enough annotations??");
            break;
        }
        
        [unmatchedAnnotations removeObject:annotation];
        
        annotation.cluster = cluster;
        annotation.coordinatePreAnimation = cluster.clusterCoordinate;
    }
    
    matchedAnnotations = [NSMutableSet setWithSet:_clusterAnnotations];
    [matchedAnnotations minusSet:unmatchedAnnotations];
    
    //Create a circle around coordinate to display all single annotations that overlap
    [TSClusterOperation mutateCoordinatesOfClashingAnnotations:matchedAnnotations];
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        NSArray *selectedAnnotations = _mapView.selectedAnnotations;
        for(id annotation in selectedAnnotations) {
            [_mapView deselectAnnotation:annotation animated:NO];
        }
        
        for (ADClusterAnnotation *annotation in _clusterAnnotations) {
            if (CLLocationCoordinate2DIsValid(annotation.coordinatePreAnimation)) {
                annotation.coordinate = annotation.coordinatePreAnimation;
            }
        }
        
        for (ADClusterAnnotation * annotation in _clusterAnnotations) {
            if (annotation.cluster && annotation.needsRefresh) {
                [_mapView refreshClusterAnnotation:annotation];
            }
        }
        
        [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            
            for (ADClusterAnnotation * annotation in _clusterAnnotations) {
                if (annotation.cluster) {
                    annotation.coordinate = annotation.cluster.clusterCoordinate;
//                    [annotation.annotationView refreshView];
                }
            }
            
        } completion:^(BOOL finished) {
            
            for (ADClusterAnnotation * annotation in [unmatchedAnnotations setByAddingObjectsFromSet:removeAfterAnimation]) {
                [annotation reset];
            }
            
            if (_finishedBlock) {
                _finishedBlock(clusteredMapRect, YES);
            }
        }];
    }];
}

- (BOOL)annotation:(ADClusterAnnotation *)annotation belongsToClusters:(NSSet *)clusters {
    if (annotation.cluster) {
        for (ADMapCluster * cluster in clusters) {
            if ([cluster isAncestorOf:annotation.cluster] || [cluster isEqual:annotation.cluster]) {
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark - Spread close annotations

+ (void)mutateCoordinatesOfClashingAnnotations:(NSSet *)annotations {
    
    NSDictionary *coordinateValuesToAnnotations = [self groupAnnotationsByLocationValue:annotations];

    for (NSValue *coordinateValue in coordinateValuesToAnnotations.allKeys) {
        NSMutableArray *outletsAtLocation = coordinateValuesToAnnotations[coordinateValue];
        if (outletsAtLocation.count > 1) {
            CLLocationCoordinate2D coordinate;
            [coordinateValue getValue:&coordinate];
            [self repositionAnnotations:[[NSMutableSet alloc] initWithArray:outletsAtLocation]
             toAvoidClashAtCoordination:coordinate];
        }
    }
}

+ (NSDictionary *)groupAnnotationsByLocationValue:(NSSet *)annotations {
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    for (ADClusterAnnotation *pin in annotations) {
        
        if (!pin.cluster) {
            continue;
        }
        
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DRoundedLonLat(pin.cluster.clusterCoordinate, 5);
        NSValue *coordinateValue = [NSValue valueWithBytes:&coordinate objCType:@encode(CLLocationCoordinate2D)];
        
        NSMutableArray *annotationsAtLocation = result[coordinateValue];
        if (!annotationsAtLocation) {
            annotationsAtLocation = [NSMutableArray array];
            result[coordinateValue] = annotationsAtLocation;
        }
        
        [annotationsAtLocation addObject:pin];
    }
    return result;
}

+ (void)repositionAnnotations:(NSMutableSet *)annotations toAvoidClashAtCoordination:(CLLocationCoordinate2D)coordinate {
    
    double distance = 3 * annotations.count / 2.0;
    double radiansBetweenAnnotations = (M_PI * 2) / annotations.count;
    
    int i = 0;

    for (ADClusterAnnotation *annotation in annotations) {
        
        double heading = radiansBetweenAnnotations * i;
        CLLocationCoordinate2D newCoordinate = [self calculateCoordinateFrom:coordinate onBearing:heading atDistance:distance];
        
        annotation.cluster.clusterCoordinate = newCoordinate;
        
        i++;
    }
}

+ (CLLocationCoordinate2D)calculateCoordinateFrom:(CLLocationCoordinate2D)coordinate onBearing:(double)bearingInRadians atDistance:(double)distanceInMetres {
    
    double coordinateLatitudeInRadians = coordinate.latitude * M_PI / 180;
    double coordinateLongitudeInRadians = coordinate.longitude * M_PI / 180;
    
    double distanceComparedToEarth = distanceInMetres / 6378100;
    
    double resultLatitudeInRadians = asin(sin(coordinateLatitudeInRadians) * cos(distanceComparedToEarth) + cos(coordinateLatitudeInRadians) * sin(distanceComparedToEarth) * cos(bearingInRadians));
    double resultLongitudeInRadians = coordinateLongitudeInRadians + atan2(sin(bearingInRadians) * sin(distanceComparedToEarth) * cos(coordinateLatitudeInRadians), cos(distanceComparedToEarth) - sin(coordinateLatitudeInRadians) * sin(resultLatitudeInRadians));
    
    CLLocationCoordinate2D result;
    result.latitude = resultLatitudeInRadians * 180 / M_PI;
    result.longitude = resultLongitudeInRadians * 180 / M_PI;
    return result;
}

- (NSSet *)mapRectsFromMaxNumberOfClusters:(NSUInteger)amount mapRect:(MKMapRect)rect {
    
    if (amount == 0) {
        return [NSSet setWithObject:[NSDictionary dictionaryFromMapRect:rect]];
    }
    
    
    double x = rect.origin.x;
    double y = rect.origin.y;
    double width = rect.size.width;
    double height = rect.size.height;
    
    float weight = width/height;
    
    int columns = round(sqrt(amount*weight));
    int rows = ceil(amount / (double)columns);
    
    //create basic cluster grid
    double columnWidth = width/columns;
    double rowHeight = height/rows;
    
    //build array of MKMapRects
    NSMutableSet* set = [[NSMutableSet alloc] initWithCapacity:rows*columns];
    for (int i=0; i< columns; i++) {
        double newX = x + columnWidth*(i);
        for (int j=0; j< rows; j++) {
            double newY = y + rowHeight*(j);
            MKMapRect newRect = MKMapRectMake(newX, newY, columnWidth, rowHeight);
            [set addObject:[NSDictionary dictionaryFromMapRect:newRect]];
        }
    }
    
    return set;
}



@end
