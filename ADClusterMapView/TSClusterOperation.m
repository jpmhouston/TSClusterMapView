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

- (void)clusterInMapRect:(MKMapRect)clusteredMapRect {
    
    
    NSUInteger numberOnScreen = _numberOfClusters;
    
    if (self.isCancelled) {
        if (_finishedBlock) {
            _finishedBlock(clusteredMapRect, NO, nil);
        }
        return;
    }
    
    //Clusters that need to be visible after the animation
    NSSet *clustersToShowOnMap = [_rootMapCluster find:numberOnScreen childrenInMapRect:clusteredMapRect annotationViewSize:[self mapRectAnnotationViewSize]];
    
    if (self.isCancelled) {
        if (_finishedBlock) {
            _finishedBlock(clusteredMapRect, NO, nil);
        }
        return;
    }
    
    //Sort out the current annotations to get an idea of what you're working with
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
    
    
    //
    NSMutableSet *unMatchedClusters = [[NSMutableSet alloc] initWithSet:clustersToShowOnMap];
    
    //There will be only one annotation after clustering in so we want to know if the parent cluster was already matched to an annotation
    NSMutableSet *parentClustersMatched = [[NSMutableSet alloc] initWithCapacity:_numberOfClusters];
    
    //These will be the annotations that converge to a point and will no longer be needed
    NSMutableSet *removeAfterAnimation = [[NSMutableSet alloc] initWithCapacity:_numberOfClusters];
    
    //These will be leftovers that didn't have any annotations available to match at the time.
    //Some annotations should become free after further sorting and matching.
    //At the end any unmatched annotations will be used.
    NSMutableSet *stillNeedsMatch = [[NSMutableSet alloc] initWithCapacity:10];
    
    if (self.isCancelled) {
        if (_finishedBlock) {
            _finishedBlock(clusteredMapRect, NO, nil);
        }
        return;
    }
    
    //Go through annotations that already have clusters and try and match them to new clusters
    for (ADClusterAnnotation *annotation in matchedAnnotations) {
        
        NSMutableSet *children = [annotation.cluster findChildrenForClusterInSet:clustersToShowOnMap];
        
        //Found children
        //These will start at cluster and split to their respective cluster coordinates
        if (children.count) {
            
            ADMapCluster *cluster = [children anyObject];
            annotation.cluster = cluster;
            annotation.coordinatePreAnimation = annotation.coordinate;
            
            [children removeObject:cluster];
            [unMatchedClusters removeObject:cluster];
            
            //There should be more than one child if it splits so we'll need to grab unused annotations.
            //Clusterless offscreen annotations will then start at the annotation on screen's point and split to the child coordinate.
            for (ADMapCluster *cluster in children) {
                ADClusterAnnotation *clusterlessAnnotation = [offscreenAnnotations anyObject];
                
                if (clusterlessAnnotation) {
                    clusterlessAnnotation.cluster = cluster;
                    clusterlessAnnotation.coordinatePreAnimation = annotation.coordinate;
                    
                    [unmatchedAnnotations removeObject:clusterlessAnnotation];
                    [offscreenAnnotations removeObject:clusterlessAnnotation];
                    
                    [unMatchedClusters removeObject:cluster];
                }
                else {
                    //Ran out of annotations off screen we'll come back after more have been sorted and reassign one that is available
                    [stillNeedsMatch addObject:@[cluster, annotation]];
                }
            }
            
            continue;
        }
        
        
        ADMapCluster *cluster = [annotation.cluster findAncestorForClusterInSet:clustersToShowOnMap];
        
        //Found an ancestor
        //These will start as individual annotations and converge into a single annotation during animation
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
        
        //No ancestor or child found
        //This will happen when the annotation is no longer in the visible map rect and
        //the section of the cluster tree does not include this annotation
        [unmatchedAnnotations addObject:annotation];
        [annotation shouldReset];
    }
    
    //Find annotations for remaining unmatched clusters
    //If there are available nearby, set the available annotation to animate to cluster position and take over.
    //After a full tree refresh all annotations will be unmatched but coordinates still may match up or be close by.
    for (ADMapCluster *cluster in [unMatchedClusters copy]) {
        
        ADClusterAnnotation *annotation;
        
        MKMapRect mRect = _mapView.visibleMapRect;
        MKMapPoint eastMapPoint = MKMapPointMake(MKMapRectGetMinX(mRect), MKMapRectGetMidY(mRect));
        MKMapPoint westMapPoint = MKMapPointMake(MKMapRectGetMaxX(mRect), MKMapRectGetMidY(mRect));
        //Don't want annotations flying across the map
        CLLocationDistance min = MKMetersBetweenMapPoints(eastMapPoint, westMapPoint)/2;
        
        NSMutableSet *unmatchedOnScreen = [NSMutableSet setWithSet:unmatchedAnnotations];
        [unmatchedOnScreen minusSet:offscreenAnnotations];
        for (ADClusterAnnotation *checkAnnotation in unmatchedOnScreen) {
            
            //Could be same
            if (CLLocationCoordinate2DIsApproxEqual(checkAnnotation.coordinate, cluster.clusterCoordinate, 0.00001)) {
                annotation = checkAnnotation;
                break;
            }
            
            //Find closest
            CLLocationDistance distance = MKMetersBetweenMapPoints(MKMapPointForCoordinate(checkAnnotation.coordinate),
                                                                   MKMapPointForCoordinate(cluster.clusterCoordinate));
            if (distance < min) {
                min = distance;
                annotation = checkAnnotation;
            }
        }
        
        if (annotation) {
            annotation.coordinatePreAnimation = annotation.coordinate;
            annotation.popInAnimation = NO;
            //already visible don't animate appearance
        }
        else if (offscreenAnnotations.count) {
            annotation = [offscreenAnnotations anyObject];
            annotation.coordinatePreAnimation = cluster.clusterCoordinate;
            annotation.popInAnimation = YES;
            //Not visible animate appearance
        }
        else {
            NSLog(@"Not enough annotations?!");
            break;
        }
        
        annotation.cluster = cluster;
        [unmatchedAnnotations removeObject:annotation];
        [offscreenAnnotations removeObject:annotation];
        [unMatchedClusters removeObject:cluster];
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
    
    if (unMatchedClusters.count) {
        NSLog(@"Unmatched Clusters!?");
    }
    
    //Create a circle around coordinate to display all single annotations that overlap
    [TSClusterOperation mutateCoordinatesOfClashingAnnotations:matchedAnnotations];
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        //Make sure they are in the offscreen position
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
        
        //Set pre animation position
        for (ADClusterAnnotation *annotation in _annotationPool) {
            if (CLLocationCoordinate2DIsValid(annotation.coordinatePreAnimation)) {
                annotation.coordinate = annotation.coordinatePreAnimation;
            }
        }
        
        
        for (ADClusterAnnotation * annotation in _annotationPool) {
            //Get the new or cached view from delegate
            if (annotation.cluster && annotation.needsRefresh) {
                [_mapView refreshClusterAnnotation:annotation];
            }
            
            //Pre animation setup for popInAnimation
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
            
            //Need to be removed after clustering they are no longer needed
            for (ADClusterAnnotation *annotation in removeAfterAnimation) {
                [annotation reset];
            }
            
            //If the number of clusters wanted on screen was reduced we can adjust the annotation pool accordingly to speed things up
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
    
    
    double width = rect.size.width;
    double height = rect.size.height;
    
    float weight = width/height;
    
    int columns = round(sqrt(amount*weight));
    int rows = ceil(amount / (double)columns);
    
    //create basic cluster grid
    double columnWidth = width/columns;
    double rowHeight = height/rows;
    
    
    double x = rect.origin.x;
    double y = rect.origin.y;
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


- (NSSet *)mapRectsForAnnotationViewSizeInRect:(MKMapRect)rect {
    
    MKMapRect viewRect = [self mapRectAnnotationViewSize];
    
    double x = rect.origin.x;
    double y = rect.origin.y;
    
    //create basic cluster grid
    double columnWidth = viewRect.size.width*2;
    double rowHeight = viewRect.size.height*2;
    
    int columns = ceil(rect.size.width/columnWidth);
    int rows = ceil(rect.size.height/rowHeight);
    
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


- (MKMapRect)mapRectForRect:(CGRect)rect {
    CLLocationCoordinate2D topleft = [_mapView convertPoint:CGPointMake(rect.origin.x, rect.origin.y) toCoordinateFromView:_mapView];
    CLLocationCoordinate2D bottomeright = [_mapView convertPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)) toCoordinateFromView:_mapView];
    MKMapPoint topleftpoint = MKMapPointForCoordinate(topleft);
    MKMapPoint bottomrightpoint = MKMapPointForCoordinate(bottomeright);
    
    return MKMapRectMake(topleftpoint.x, topleftpoint.y, bottomrightpoint.x - topleftpoint.x, bottomrightpoint.y - topleftpoint.y);
}


- (CGRect)annotationViewRect {
    
    return CGRectMake(0, 0, _mapView.clusterAnnotationViewSize.width, _mapView.clusterAnnotationViewSize.height);
}

- (MKMapRect)mapRectAnnotationViewSize {
    
    return [self mapRectForRect:[self annotationViewRect]];
}


- (NSUInteger)calculateNumberByGrid:(MKMapRect)clusteredMapRect {
    
    //This will be used if the size is unknown for cluster annotationViews
    //Creates grid to estimate number of clusters needed based on the spread of annotations across map rect.
    //
    //If there are should be 20 max clusters, we create 20 even rects (plus buffer rects) within the given map rect
    //and search to see if a cluster is contained in that rect.
    //
    //This helps distribute clusters more evenly by limiting clusters presented relative to viewable region.
    //Zooming all the way out will then be able to cluster down to one single annotation if all clusters are within one grid rect.
    
    NSDate *date = [NSDate date];
    NSUInteger numberOnScreen = _numberOfClusters;
    
    if (_mapView.region.span.longitudeDelta > _mapView.clusterMinimumLongitudeDelta) {
        
        //number of map rects that contain at least one annotation
        //divide by two because there are two sets of map rects - original area and shifted aread
        //to account for possible straddling of a rect border
        NSSet *mapRects = [self mapRectsFromMaxNumberOfClusters:_numberOfClusters mapRect:clusteredMapRect];
        
        date = [NSDate date];
        numberOnScreen = [_rootMapCluster numberOfMapRectsContainingChildren:mapRects];
        if (numberOnScreen < 1) {
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
    
    return numberOnScreen;
}

@end
