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
@property (nonatomic, strong) NSMutableSet *annotationPool;
@property (nonatomic, strong) NSMutableSet *poolAnnotationRemoval;

@end

@implementation TSClusterOperation

- (instancetype)initWithMapView:(ADClusterMapView *)mapView rect:(MKMapRect)rect rootCluster:(ADMapCluster *)rootCluster showNumberOfClusters:(NSUInteger)numberOfClusters clusterAnnotations:(NSSet *)clusterAnnotations completion:(ClusterOperationCompletionBlock)completion
{
    self = [super init];
    if (self) {
        self.mapView = mapView;
        self.rootMapCluster = rootCluster;
        self.finishedBlock = completion;
        self.annotationPool = [clusterAnnotations copy];
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
            _finishedBlock(clusteredMapRect, NO, nil);
        }
        return;
    }
    
    NSMutableSet *offscreenAnnotations = [[NSMutableSet alloc] initWithCapacity:_annotationPool.count];
    for (ADClusterAnnotation *annotation in _annotationPool) {
        if (ADClusterCoordinate2DIsOffscreen(annotation.coordinate)) {
            [offscreenAnnotations addObject:annotation];
        }
    }
    
    NSMutableSet *unmatchedAnnotations = [[NSMutableSet alloc] initWithCapacity:_annotationPool.count];
    for (ADClusterAnnotation *annotation in _annotationPool) {
        if (!annotation.cluster) {
            [unmatchedAnnotations addObject:annotation];
        }
    }
    
    NSMutableSet *matchedAnnotations = [[NSMutableSet alloc] initWithSet:_annotationPool];
    [matchedAnnotations minusSet:unmatchedAnnotations];
    
    //Clusters that need to be visible after the animation
    NSSet *clustersToShowOnMap = [_rootMapCluster find:numberOnScreen childrenInMapRect:clusteredMapRect];
    
    NSMutableSet *unMatchedClusters = [[NSMutableSet alloc] initWithSet:clustersToShowOnMap];
    
    //There will be only one annotation after clustering in so we want to know if the cluster was already matched to an annotation
    NSMutableSet *parentClustersMatched = [[NSMutableSet alloc] initWithCapacity:_numberOfClusters];
    NSMutableSet *removeAfterAnimation = [[NSMutableSet alloc] initWithCapacity:_numberOfClusters];
    
    NSMutableSet *stillNeedsMatch = [[NSMutableSet alloc] initWithCapacity:10];
    
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
                ADClusterAnnotation *clusterlessAnnotation = [offscreenAnnotations anyObject];
                
                if (clusterlessAnnotation) {
                    clusterlessAnnotation.cluster = cluster;
                    clusterlessAnnotation.coordinatePreAnimation = annotation.coordinate;
                    
                    [unmatchedAnnotations removeObject:clusterlessAnnotation];
                    [offscreenAnnotations removeObject:clusterlessAnnotation];
                    
                    [unMatchedClusters removeObject:cluster];
                }
                else if (offscreenAnnotations) {
                    [stillNeedsMatch addObject:@[cluster, annotation]];
                }
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
        
        //No ancestor or child found probably off screen
        [unmatchedAnnotations addObject:annotation];
        [annotation shouldReset];
    }
    
    //Annotations may not be on the map yet if there are available nearby setup for animation to the new cluster coordinate
    for (ADMapCluster *cluster in unMatchedClusters) {
        
        ADClusterAnnotation *annotation;
        
        MKMapRect mRect = _mapView.visibleMapRect;
        MKMapPoint eastMapPoint = MKMapPointMake(MKMapRectGetMinX(mRect), MKMapRectGetMidY(mRect));
        MKMapPoint westMapPoint = MKMapPointMake(MKMapRectGetMaxX(mRect), MKMapRectGetMidY(mRect));
        //Don't want annotations flying across the map
        CLLocationDistance min = MKMetersBetweenMapPoints(eastMapPoint, westMapPoint)/2;
        
        NSMutableSet *unmatchedOnScreen = [NSMutableSet setWithSet:unmatchedAnnotations];
        [unmatchedOnScreen minusSet:offscreenAnnotations];
        for (ADClusterAnnotation *checkAnnotation in unmatchedOnScreen) {
            
            if (CLLocationCoordinate2DIsApproxEqual(checkAnnotation.coordinate, cluster.clusterCoordinate, 0.00001)) {
                annotation = checkAnnotation;
                break;
            }
            
            CLLocationDistance distance = MKMetersBetweenMapPoints(MKMapPointForCoordinate(checkAnnotation.coordinate), MKMapPointForCoordinate(cluster.clusterCoordinate));
            if (distance < min) {
                min = distance;
                annotation = checkAnnotation;
            }
        }
        
        if (annotation) {
            annotation.coordinatePreAnimation = annotation.coordinate;
            annotation.popInAnimation = NO;
        }
        else if (offscreenAnnotations.count) {
            annotation = [offscreenAnnotations anyObject];
            annotation.coordinatePreAnimation = cluster.clusterCoordinate;
            annotation.popInAnimation = YES;
        }
        else {
            NSLog(@"Not enough annotations??");
            break;
        }
        
        annotation.cluster = cluster;
        [unmatchedAnnotations removeObject:annotation];
        [offscreenAnnotations removeObject:annotation];
    }
    
    //Still need unmatched for a split into multiple from cluster
    if (stillNeedsMatch.count) {
        for (NSArray *array in stillNeedsMatch) {
            ADClusterAnnotation *clusterlessAnnotation = [unmatchedAnnotations anyObject];
            
            if (clusterlessAnnotation) {
                clusterlessAnnotation.cluster = array[0];
                clusterlessAnnotation.coordinatePreAnimation = ((ADClusterAnnotation *)array[1]).coordinate;
                
                [unmatchedAnnotations removeObject:clusterlessAnnotation];
                [offscreenAnnotations removeObject:clusterlessAnnotation];
                [unMatchedClusters removeObject:clusterlessAnnotation.cluster];
            }
        }
    }
    
    matchedAnnotations = [NSMutableSet setWithSet:_annotationPool];
    [matchedAnnotations minusSet:unmatchedAnnotations];
    
    //Create a circle around coordinate to display all single annotations that overlap
    [TSClusterOperation mutateCoordinatesOfClashingAnnotations:matchedAnnotations];
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        for (ADClusterAnnotation *annotation in unmatchedAnnotations) {
            [annotation reset];
        }
        
        //Make sure we close callout of cluster if needed
        NSArray *selectedAnnotations = _mapView.selectedAnnotations;
        for (ADClusterAnnotation *annotation in selectedAnnotations) {
            if ([annotation isKindOfClass:[ADClusterAnnotation class]]) {
                if ((annotation.type == ADClusterAnnotationTypeCluster &&
                    !CLLocationCoordinate2DIsApproxEqual(annotation.coordinate, annotation.coordinatePreAnimation, .000001)) ||
                    [removeAfterAnimation containsObject:annotation]) {
                    [_mapView deselectAnnotation:annotation animated:NO];
                }
            }
        }
        
        for (ADClusterAnnotation *annotation in _annotationPool) {
            if (CLLocationCoordinate2DIsValid(annotation.coordinatePreAnimation)) {
                annotation.coordinate = annotation.coordinatePreAnimation;
            }
        }
        
        for (ADClusterAnnotation * annotation in _annotationPool) {
            if (annotation.cluster && annotation.needsRefresh) {
                [_mapView refreshClusterAnnotation:annotation];
            }
            
            if (annotation.popInAnimation && _mapView.clusterAppearanceAnimated) {
                CGAffineTransform t = CGAffineTransformMakeScale(0.001, 0.001);
                t = CGAffineTransformTranslate(t, 0, -annotation.annotationView.frame.size.height);
                annotation.annotationView.transform  = t;
            }
            annotation.popInAnimation = NO;
        }
        
        TSClusterAnimationOptions *options = _mapView.clusterAnimationOptions;
        [UIView animateWithDuration:options.duration delay:0.0 usingSpringWithDamping:options.springDamping initialSpringVelocity:options.springVelocity options:options.viewAnimationOptions animations:^{
            for (ADClusterAnnotation * annotation in _annotationPool) {
                if (annotation.cluster) {
                    annotation.coordinate = annotation.cluster.clusterCoordinate;
                    [annotation.annotationView animateView];
                }
                annotation.annotationView.transform = CGAffineTransformIdentity;
            }
        } completion:^(BOOL finished) {
            
            for (ADClusterAnnotation *annotation in removeAfterAnimation) {
                [annotation reset];
            }
            
            NSSet *toRemove = [self poolAnnotationsToRemove:_numberOfClusters freeAnnotations:[unmatchedAnnotations setByAddingObjectsFromSet:removeAfterAnimation]];
            
            if (_finishedBlock) {
                _finishedBlock(clusteredMapRect, YES, toRemove);
            }
        }];
    }];
}

- (NSSet *)poolAnnotationsToRemove:(NSInteger)numberOfAnnotationsInPool freeAnnotations:(NSSet *)annotations {
    
    NSInteger difference = _annotationPool.count - (numberOfAnnotationsInPool*2);
    
    if (difference > 0) {
        if (annotations.count >= difference) {
            return [NSSet setWithArray:[annotations.allObjects subarrayWithRange:NSMakeRange(0, difference)]];
        }
    }
    
    return nil;
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
