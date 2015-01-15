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
            if (numberOnScreen > _numberOfClusters) {
                numberOnScreen = _numberOfClusters;
            }
        }
        else {
            numberOnScreen = 1;
        }
    }
    else {
        //Show maximum number of clusters we're at the minimum level set
        numberOnScreen = _numberOfClusters;
    }
    
    
    if (self.isCancelled) {
        if (_finishedBlock) {
            _finishedBlock(clusteredMapRect, NO);
        }
        return;
    }
    
    NSSet *clustersToShowOnMap = [_rootMapCluster find:numberOnScreen childrenInMapRect:clusteredMapRect];
    
    // Build an array with available annotations (eg. not moving or not staying at the same place on the map)
    NSMutableSet * availableSingleAnnotations = [[NSMutableSet alloc] init];
    NSMutableSet * availableClusterAnnotations = [[NSMutableSet alloc] init];
    NSMutableSet * selfDividingSingleAnnotations = [[NSMutableSet alloc] init];
    NSMutableSet * selfDividingClusterAnnotations = [[NSMutableSet alloc] init];
    ALog();
    for (ADClusterAnnotation * annotation in _clusterAnnotations) {
        BOOL isAncestor = NO;
        if (annotation.cluster) { // if there is a cluster associated to the current annotation
            for (ADMapCluster * cluster in clustersToShowOnMap) { // is the current annotation cluster an ancestor of one of the clustersToShowOnMap?
                if ([annotation.cluster isAncestorOf:cluster]) {
                    if (cluster.annotation) {
                        [selfDividingSingleAnnotations addObject:annotation];
                    } else {
                        [selfDividingClusterAnnotations addObject:annotation];
                    }
                    isAncestor = YES;
                    break;
                }
            }
        }
        if (!isAncestor) { // if not an ancestor
            if (![self annotation:annotation belongsToClusters:clustersToShowOnMap]) { // check if this annotation will be used later. If not, it is flagged as "available".
                if (annotation.type == ADClusterAnnotationTypeLeaf) {
                    [availableSingleAnnotations addObject:annotation];
                } else {
                    [availableClusterAnnotations addObject:annotation];
                }
            }
        }
    }
    
    if (self.isCancelled) {
        if (_finishedBlock) {
            _finishedBlock(clusteredMapRect, NO);
        }
        return;
    }
    
    
    //Begin Setting Clusters = No turning back now!
    NSMutableArray *afterAnimation = [[NSMutableArray alloc] init];
    
    // Let ancestor annotations divide themselves
    ALog();
    for (ADClusterAnnotation * annotation in [selfDividingSingleAnnotations setByAddingObjectsFromSet:selfDividingClusterAnnotations]) {
        BOOL willNeedAnAvailableAnnotation = NO;
        CLLocationCoordinate2D originalAnnotationCoordinate = annotation.coordinate;
        ADMapCluster * originalAnnotationCluster = annotation.cluster;
        for (ADMapCluster * cluster in clustersToShowOnMap) {
            if ([originalAnnotationCluster isAncestorOf:cluster]) {
                if (!willNeedAnAvailableAnnotation) {
                    willNeedAnAvailableAnnotation = YES;
                    annotation.cluster = cluster;
                    if (cluster.annotation) { // replace this annotation by a leaf one
                        NSAssert(annotation.type != ADClusterAnnotationTypeLeaf, @"Inconsistent annotation type!");
                        ADClusterAnnotation * singleAnnotation = [availableSingleAnnotations anyObject];
                        [availableSingleAnnotations removeObject:singleAnnotation];
                        singleAnnotation.cluster = annotation.cluster;
//                        [nonAnimated addObject:@{annotationKey: singleAnnotation, coordinatesKey: [NSValue valueWithMKCoordinate:originalAnnotationCoordinate]}];
                        singleAnnotation.coordinatePreAnimation = originalAnnotationCoordinate;
                        
                        [availableClusterAnnotations addObject:annotation];
                    }
                } else {
                    ADClusterAnnotation * availableAnnotation;
                    if (cluster.annotation) {
                        availableAnnotation = [availableSingleAnnotations anyObject];
                        [availableSingleAnnotations removeObject:availableAnnotation];
                        
                    } else {
                        availableAnnotation = [availableClusterAnnotations anyObject];
                        [availableClusterAnnotations removeObject:availableAnnotation];
                    }
                    availableAnnotation.cluster = cluster;
//                    [nonAnimated addObject:@{annotationKey: availableAnnotation, coordinatesKey: [NSValue valueWithMKCoordinate:originalAnnotationCoordinate]}];
                    availableAnnotation.coordinatePreAnimation = originalAnnotationCoordinate;
                }
            }
        }
    }
    
    // Converge annotations to ancestor clusters
    ALog();
    for (ADMapCluster * cluster in clustersToShowOnMap) {
        BOOL didAlreadyFindAChild = NO;
        ALog();
        for (ADClusterAnnotation * annotation in _clusterAnnotations) {
            if (annotation.cluster) {
                if ([cluster isAncestorOf:annotation.cluster]) {
                    if (annotation.type == ADClusterAnnotationTypeLeaf) { // replace this annotation by a cluster one
                        ALog();
                        ADClusterAnnotation * clusterAnnotation = [availableClusterAnnotations anyObject];
                        [availableClusterAnnotations removeObject:clusterAnnotation];
                        clusterAnnotation.cluster = cluster;
                        // Setting the coordinate makes us call viewForAnnotation: right away, so make sure the cluster is set
//                        [nonAnimated addObject:@{annotationKey: clusterAnnotation, coordinatesKey: [NSValue valueWithMKCoordinate:annotation.coordinate]}];
                        clusterAnnotation.coordinatePreAnimation = annotation.coordinate;
                        [availableSingleAnnotations addObject:annotation];
                    } else {
                        ALog();
                        annotation.cluster = cluster;
                    }
                    if (didAlreadyFindAChild) {
                        ALog();
                        annotation.shouldBeRemovedAfterAnimation = YES;
                    }
                    if (ADClusterCoordinate2DIsOffscreen(annotation.coordinate)) {
                        ALog();
//                        [nonAnimated addObject:@{annotationKey: annotation, coordinatesKey: [NSValue valueWithMKCoordinate:annotation.cluster.clusterCoordinate]}];
                        annotation.coordinatePreAnimation = annotation.cluster.clusterCoordinate;
                    }
                    didAlreadyFindAChild = YES;
                }
            }
        }
    }
    
    
    ALog();
    for (ADClusterAnnotation * annotation in [availableSingleAnnotations setByAddingObjectsFromSet:availableClusterAnnotations]) {
        if (annotation.cluster) { // This is here for performance reason (annotation reset causes the refresh of the annotation because of KVO)
            [annotation shouldReset];
        }
    }
    
    //Create a circle around coordinate to display all single annotations that overlap
    [TSClusterOperation mutateCoordinatesOfClashingAnnotations:_clusterAnnotations];
    
    // Add not-yet-annotated clusters
    ALog();
    for (ADMapCluster * cluster in clustersToShowOnMap) {
        BOOL isAlreadyAnnotated = NO;
        for (ADClusterAnnotation * annotation in _clusterAnnotations) {
                if ([cluster isEqual:annotation.cluster]) {
                    isAlreadyAnnotated = YES;
                    break;
                }
        }
        if (!isAlreadyAnnotated) {
            if (cluster.annotation) {
                ADClusterAnnotation * annotation = [availableSingleAnnotations anyObject];
                [availableSingleAnnotations removeObject:annotation]; // update the availableAnnotations
                annotation.cluster = cluster;
                annotation.coordinatePreAnimation = cluster.clusterCoordinate;
//                [afterAnimation addObject:annotation];
            } else {
                ADClusterAnnotation * annotation = [availableClusterAnnotations anyObject];
                [availableClusterAnnotations removeObject:annotation]; // update the availableAnnotations
                annotation.cluster = cluster;
                annotation.coordinatePreAnimation = cluster.clusterCoordinate;
//                [afterAnimation addObject:annotation];
            }
        }
    }
    
    ALog();
    for (ADClusterAnnotation * annotation in [availableSingleAnnotations setByAddingObjectsFromSet:availableClusterAnnotations]) {
         // This is here for performance reason (annotation reset causes the refresh of the annotation because of KVO)
        annotation.shouldBeRemovedAfterAnimation = YES;
        [afterAnimation addObject:annotation];
    }
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        ALog();
        for (ADClusterAnnotation *annotation in _clusterAnnotations) {
            annotation.coordinate = annotation.coordinatePreAnimation;
        }
        
        ALog();
        for (ADClusterAnnotation * annotation in _clusterAnnotations) {
            if (annotation.cluster && annotation.needsRefresh) {
                [_mapView refreshClusterAnnotation:annotation];
            }
        }
        
        [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            
            ALog();
            for (ADClusterAnnotation * annotation in _clusterAnnotations) {
                if (annotation.cluster) {
                    annotation.coordinate = annotation.cluster.clusterCoordinate;
//                    [annotation.annotationView refreshView];
                }
            }
            
        } completion:^(BOOL finished) {
            
            ALog();
            for (ADClusterAnnotation * annotation in afterAnimation) {
                if (annotation.shouldBeRemovedAfterAnimation) {
                    [annotation reset];
                }
                else {
                    annotation.coordinate = annotation.coordinatePostAnimation;
                }
                
//                ADClusterAnnotation * annotation = [dic objectForKey:annotationKey];
//                if ([dic objectForKey:coordinatesKey]) {
//                    annotation.cluster = [dic objectForKey:clusterKey];
//                    annotation.coordinate = [[dic objectForKey:coordinatesKey] MKCoordinateValue];
//                }
//                else {
//                    [annotation reset];
//                }
            }
            
            ALog();
            for (ADClusterAnnotation * annotation in _clusterAnnotations) {
                if ([annotation isKindOfClass:[ADClusterAnnotation class]]) {
                    if (annotation.shouldBeRemovedAfterAnimation) {
                        [annotation reset];
                    }
                    annotation.shouldBeRemovedAfterAnimation = NO;
                }
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
    ALog();
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
    ALog();
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
    ALog();
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
