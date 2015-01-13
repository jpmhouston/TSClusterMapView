//
//  ADClusterMapView.m
//  ADClusterMapView
//
//  Created by Patrick Nollet on 30/06/11.
//  Copyright 2011 Applidium. All rights reserved.
//

#import <QuartzCore/CoreAnimation.h>
#import "ADClusterMapView.h"
#import "ADClusterAnnotation.h"
#import "ADMapPointAnnotation.h"
#import "NSDictionary+MKMapRect.h"
#import "CLLocation+Utilities.h"
#import "TSClusterOperation.h"

NSString * const TSMapViewWillChangeRegion = @"TSMapViewWillChangeRegion";
NSString * const TSMapViewDidChangeRegion = @"TSMapViewDidChangeRegion";


@interface ADClusterMapView ()

@property (nonatomic, weak) id <ADClusterMapViewDelegate>  secondaryDelegate;

@property (nonatomic, strong) NSMutableSet *originalAnnotations;

@property (nonatomic, assign) BOOL shouldReselectAnnotation;

@property (nonatomic, strong) id<MKAnnotation> previouslySelectedAnnotation;

//Clustering
@property (nonatomic, strong) ADMapCluster *rootMapCluster;

@property (nonatomic, strong) NSMutableSet *singleAnnotationsPool;
@property (nonatomic, strong) NSMutableSet *clusterAnnotationsPool;
@property (nonatomic, strong) NSMutableSet *clusterableAnnotationsAdded;

@property (nonatomic, assign) BOOL isSettingAnnotations;

@property (nonatomic, assign) MKMapRect previousVisibleMapRectClustered;

@property (nonatomic, strong) NSOperationQueue *operationQueue;

@property (nonatomic, strong) NSSet *clusterAnnotations;

@property (nonatomic, strong) TSClusterOperation *clusterOperation;

@end

@implementation ADClusterMapView

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self initHelpers];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initHelpers];
    }
    return self;
}

- (void)initHelpers {
    
    [self setDefaults];
    
    self.operationQueue = [[NSOperationQueue alloc] init];
    [self.operationQueue setMaxConcurrentOperationCount:1];
    [self.operationQueue setName:@"Clustering Queue"];
    
    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(didPanMap:)];
    [panRecognizer setDelegate:self];
    [self addGestureRecognizer:panRecognizer];
}

- (void)didMoveToSuperview {
    
    [super didMoveToSuperview];
    
    //No longer relevant to display stop operations
    if (!self.superview) {
        [_operationQueue cancelAllOperations];
    }
}

- (void)setDefaults {
    
    self.clustersOnScreen = 20;
    self.clusterDiscriminationPower = 1.0;
    self.clusterShouldShowSubtitle = YES;
    self.clusterEdgeBufferSize = ADClusterBufferMedium;
    self.clusterMinimumLongitudeDelta = 0.005;
    self.clusterTitle = @"%d elements";
}

- (void)setClusterEdgeBufferSize:(ADClusterBufferSize)clusterEdgeBufferSize {
    
    if (clusterEdgeBufferSize < 0) {
        clusterEdgeBufferSize = 0;
    }
    
    _clusterEdgeBufferSize = clusterEdgeBufferSize;
}

- (void)setClustersOnScreen:(NSUInteger)clustersOnScreen {
    
    _clustersOnScreen = clustersOnScreen;
    
    [self needsRefresh];
}

- (void)needsRefresh {
    
    [self createKDTreeAndCluster:_clusterableAnnotationsAdded];
}

#pragma mark - Add/Remove Annotations

- (void)addClusteredAnnotation:(id<MKAnnotation>)annotation {
    
    BOOL refresh = NO;
    
    if (_clusterableAnnotationsAdded.count < 200) {
        refresh = YES;
    }
    
    [self addClusteredAnnotation:annotation clusterTreeRefresh:refresh];
}

- (void)addClusteredAnnotation:(id<MKAnnotation>)annotation clusterTreeRefresh:(BOOL)refresh {
    
    if (!annotation) {
        return;
    }
    
    if (_clusterableAnnotationsAdded) {
        [_clusterableAnnotationsAdded removeObject:annotation];
        [_clusterableAnnotationsAdded addObject:annotation];
    }
    else {
        _clusterableAnnotationsAdded = [[NSMutableSet alloc] initWithObjects:annotation, nil];
    }
    
    //Insertion may fail if a match is not found at an acceptable depth
    if (!refresh && [_rootMapCluster mapView:self rootClusterDidAddAnnotation:[[ADMapPointAnnotation alloc] initWithAnnotation:annotation]]) {
        [self clusterVisibleMapRectWithNewRootCluster:YES];
    }
    else {
        [self createKDTreeAndCluster:_clusterableAnnotationsAdded];
    }
}

- (void)addClusteredAnnotations:(NSArray *)annotations {
    
    if (!annotations || !annotations.count) {
        return;
    }
    
    if (_clusterableAnnotationsAdded) {
        [_clusterableAnnotationsAdded minusSet:[NSSet setWithArray:annotations]];
        [_clusterableAnnotationsAdded addObjectsFromArray:annotations];
    }
    else {
        _clusterableAnnotationsAdded = [[NSMutableSet alloc] initWithArray:annotations];
    }
    
    [self createKDTreeAndCluster:[NSSet setWithSet:_clusterableAnnotationsAdded]];
}

- (void)removeAnnotation:(id<MKAnnotation>)annotation {
    
    if ([_clusterableAnnotationsAdded containsObject:annotation]) {
        [_clusterableAnnotationsAdded removeObject:annotation];
        [self createKDTreeAndCluster:_clusterableAnnotationsAdded];
    }
    
    [super removeAnnotation:annotation];
}

- (void)removeAnnotations:(NSArray *)annotations {
    
    NSUInteger previousCount = _clusterableAnnotationsAdded.count;
    NSSet *set = [NSSet setWithArray:annotations];
    [_clusterableAnnotationsAdded minusSet:set];
    
    if (_clusterableAnnotationsAdded.count != previousCount) {
        [self createKDTreeAndCluster:_clusterableAnnotationsAdded];
    }
    
    [super removeAnnotations:annotations];
}

#pragma mark - Annotations

- (NSArray *)visibleClusterAnnotations {
    NSMutableArray * displayedAnnotations = [[NSMutableArray alloc] init];
    for (ADClusterAnnotation * annotation in [_singleAnnotationsPool setByAddingObjectsFromSet:_clusterAnnotationsPool]) {
        NSAssert([annotation isKindOfClass:[ADClusterAnnotation class]], @"Unexpected annotation!");
        if (annotation.coordinate.latitude != kADCoordinate2DOffscreen.latitude && annotation.coordinate.longitude != kADCoordinate2DOffscreen.longitude) {
            [displayedAnnotations addObject:annotation];
        }
    }
    
    return displayedAnnotations;
}

- (NSArray *)annotations {
    
    NSMutableSet *set = [NSMutableSet setWithArray:[super annotations]];
    [set minusSet:_clusterAnnotations];
    
    return [_originalAnnotations.allObjects arrayByAddingObjectsFromArray:set.allObjects];
}


#pragma mark - UIGestureRecognizerDelegate methods

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)didPanMap:(UIGestureRecognizer*)gestureRecognizer {
    
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan){
        [self userWillPanMapView:self];
    }
    
    if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        [self userDidPanMapView:self];
    }
}


#pragma mark - Objective-C Runtime and subclassing methods
- (void)setDelegate:(id<ADClusterMapViewDelegate>)delegate {
    /*
     For an undefined reason, setDelegate is called multiple times. The first time, it is called with delegate = nil
     Therefore _secondaryDelegate may be nil when [_secondaryDelegate respondsToSelector:aSelector] is called (result : NO)
     There is some caching done in order to avoid calling respondsToSelector: too much. That's why if we don't take care the runtime will guess that we always have [_secondaryDelegate respondsToSelector:] = NO
     Therefore we clear the cache by setting the delegate to nil.
     */
    [super setDelegate:nil];
    _secondaryDelegate = delegate;
    [super setDelegate:self];
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    BOOL respondsToSelector = [super respondsToSelector:aSelector] || [_secondaryDelegate respondsToSelector:aSelector];
    return respondsToSelector;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    if ([_secondaryDelegate respondsToSelector:[anInvocation selector]]) {
        [anInvocation invokeWithTarget:_secondaryDelegate];
    } else {
        [super forwardInvocation:anInvocation];
    }
}


#pragma mark - Clustering


- (NSUInteger)numberOfClusters {
    
    return _clustersOnScreen + (_clustersOnScreen*_clusterEdgeBufferSize);
}


- (void)initAnnotationPools:(NSUInteger)numberOfAnnotationsInPool {
    
    NSArray *toRemove = _clusterAnnotations.allObjects;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [super removeAnnotations:toRemove];
    }];
    
    _singleAnnotationsPool = [[NSMutableSet alloc] initWithCapacity: numberOfAnnotationsInPool];
    _clusterAnnotationsPool = [[NSMutableSet alloc] initWithCapacity: numberOfAnnotationsInPool];
    for (int i = 0; i < numberOfAnnotationsInPool; i++) {
        ADClusterAnnotation * annotation = [[ADClusterAnnotation alloc] init];
        annotation.type = ADClusterAnnotationTypeLeaf;
        [_singleAnnotationsPool addObject:annotation];
        annotation = [[ADClusterAnnotation alloc] init];
        annotation.type = ADClusterAnnotationTypeCluster;
        [_clusterAnnotationsPool addObject:annotation];
    }
    
    _clusterAnnotations = [_singleAnnotationsPool setByAddingObjectsFromSet:_clusterAnnotationsPool];
    
    NSArray *toAdd = _clusterAnnotations.allObjects;
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [super addAnnotations:toAdd];
    }];
}

- (void)createKDTreeAndCluster:(NSSet *)annotations {
    
    if (!annotations) {
        return;
    }
    
    
    _isSettingAnnotations = YES;
    //NSLog(@"isSettingAnnotations");
    
    _originalAnnotations = [[NSMutableSet alloc] initWithSet:annotations];
    
    NSInteger numberOfAnnotationsInPool = 2 * [self numberOfClusters]; //We manage a pool of annotations. In case we have N splits and N joins in a single animation we have to double up the actual number of annotations that belongs to the pool.
    if (_clusterAnnotations.count != numberOfAnnotationsInPool * 2) {
        [self initAnnotationPools:numberOfAnnotationsInPool];
    }
    
    [_operationQueue cancelAllOperations];
    [_operationQueue addOperationWithBlock:^{
        // use wrapper annotations that expose a MKMapPoint property instead of a CLLocationCoordinate2D property
        NSMutableSet * mapPointAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count];
        for (id<MKAnnotation> annotation in annotations) {
            ADMapPointAnnotation * mapPointAnnotation = [[ADMapPointAnnotation alloc] initWithAnnotation:annotation];
            [mapPointAnnotations addObject:mapPointAnnotation];
        }
        
        _rootMapCluster = [ADMapCluster rootClusterForAnnotations:mapPointAnnotations
                                                          mapView:self];
        
        [self clusterVisibleMapRectWithNewRootCluster:YES];
        
        _isSettingAnnotations = NO;
    }];
}


- (void)clusterVisibleMapRectWithNewRootCluster:(BOOL)isNewCluster {
    
    if (!self.superview) {
        return;
    }
    
    if (isNewCluster) {
        _previousVisibleMapRectClustered = MKMapRectNull;
    }
    
    //Create buffer room for map drag outside visible rect before next regionDidChange
    MKMapRect clusteredMapRect = [self visibleMapRectWithBuffer:_clusterEdgeBufferSize];
    
    if (_clusterEdgeBufferSize) {
        if (!MKMapRectIsNull(_previousVisibleMapRectClustered) &&
            !MKMapRectIsEmpty(_previousVisibleMapRectClustered)) {
            
            //did the map pan far enough or zoom? Compare to rounded size as decimals fluctuate
            MKMapRect halfBufferRect = MKMapRectInset(_previousVisibleMapRectClustered, (_previousVisibleMapRectClustered.size.width - self.visibleMapRect.size.width)/4, (_previousVisibleMapRectClustered.size.height - self.visibleMapRect.size.height)/4);
            if (MKMapRectSizeIsEqual(clusteredMapRect, _previousVisibleMapRectClustered) &&
                MKMapRectContainsRect(halfBufferRect, self.visibleMapRect)
                ) {
                return;
            }
        }
    }
    
    //NSLog(@"clusterInMapRect");
    
    if (_clusterOperation.isExecuting) {
        [_clusterOperation cancel];
    }
    
    [self mapViewWillBeginClusteringAnimation:self];
    
    _clusterOperation = [[TSClusterOperation alloc] initWithMapView:self
                                                               rect:clusteredMapRect
                                                        rootCluster:_rootMapCluster
                                               showNumberOfClusters:[self numberOfClusters]
                                                 clusterAnnotations:self.clusterAnnotations
                                                         completion:^(MKMapRect clusteredRect, BOOL finished) {
                                                             
                                                             if (finished) {
                                                                 _previousVisibleMapRectClustered = clusteredRect;
                                                                 
                                                                 [self mapViewDidFinishClusteringAnimation:self];
                                                             }
                                                             else {
                                                                 [self mapViewDidCancelClusteringAnimation:self];
                                                             }
                                                         }];
    [_operationQueue addOperation:_clusterOperation];
    [_operationQueue setSuspended:NO];
}


- (MKMapRect)visibleMapRectWithBuffer:(ADClusterBufferSize)bufferSize; {
    
    if (!bufferSize) {
        return self.visibleMapRect;
    }
    
    double width = self.visibleMapRect.size.width;
    double height = self.visibleMapRect.size.height;
    
    //Up Down Left Right - UpLeft UpRight DownLeft DownRight
    NSUInteger directions = 8;
    //Large (8) = One full screen size in all directions
    
    MKMapRect mapRect = self.visibleMapRect;
    mapRect = MKMapRectUnion(mapRect, MKMapRectOffset(self.visibleMapRect, -width*bufferSize/directions, -height*bufferSize/directions));
    mapRect = MKMapRectUnion(mapRect, MKMapRectOffset(self.visibleMapRect, width*bufferSize/directions, height*bufferSize/directions));
    
    return mapRect;
}



#pragma mark - MKMapViewDelegate
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if (![annotation isKindOfClass:[ADClusterAnnotation class]]) {
        if ([_secondaryDelegate respondsToSelector:@selector(mapView:viewForAnnotation:)]) {
            return [_secondaryDelegate mapView:self viewForAnnotation:annotation];
        } else {
            return nil;
        }
    }
    // only leaf clusters have annotations
    if (((ADClusterAnnotation *)annotation).type == ADClusterAnnotationTypeLeaf || ![_secondaryDelegate respondsToSelector:@selector(mapView:viewForClusterAnnotation:)]) {
        if ([_secondaryDelegate respondsToSelector:@selector(mapView:viewForAnnotation:)]) {
            return [_secondaryDelegate mapView:self viewForAnnotation:annotation];
        }
        else {
            return nil;
        }
    } else {
        return [self mapView:self viewForClusterAnnotation:annotation];
    }
}

- (void)mapView:(MKMapView *)mapView regionWillChangeAnimated:(BOOL)animated {
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:regionWillChangeAnimated:)]) {
        [_secondaryDelegate mapView:self regionWillChangeAnimated:animated];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:TSMapViewWillChangeRegion object:nil];
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    
    if (MKMapRectContainsPoint(self.visibleMapRect, MKMapPointForCoordinate(kADCoordinate2DOffscreen))) {
        return;
    }
    
    if (!_isSettingAnnotations){
        [self clusterVisibleMapRectWithNewRootCluster:NO];
    }
    if (_previouslySelectedAnnotation) {
        _shouldReselectAnnotation = YES;
    }
    for (id<MKAnnotation> annotation in [self selectedAnnotations]) {
        [self deselectAnnotation:annotation animated:YES];
    }
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:regionDidChangeAnimated:)]) {
        [_secondaryDelegate mapView:self regionDidChangeAnimated:animated];
    }
    if (_shouldReselectAnnotation) {
        _shouldReselectAnnotation = NO;
        [self selectAnnotation:_previouslySelectedAnnotation animated:YES];
        _previouslySelectedAnnotation = nil;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:TSMapViewDidChangeRegion object:nil];
}

- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view {
    
    if ([view.annotation isKindOfClass:[ADClusterAnnotation class]]) {
        if (((ADClusterAnnotation *)view.annotation).type == ADClusterAnnotationTypeLeaf &&
            !_shouldReselectAnnotation &&
            ((ADClusterAnnotation *)view.annotation).cluster) {
            _previouslySelectedAnnotation = [((ADClusterAnnotation *)view.annotation).originalAnnotations firstObject];
        }
    }
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:didSelectAnnotationView:)]) {
        [_secondaryDelegate mapView:mapView didSelectAnnotationView:view];
    }
}

- (void)mapView:(MKMapView *)mapView didDeselectAnnotationView:(MKAnnotationView *)view {
    
    if (!_shouldReselectAnnotation) {
        _previouslySelectedAnnotation = nil;
    }
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:didDeselectAnnotationView:)]) {
        [_secondaryDelegate mapView:mapView didDeselectAnnotationView:view];
    }
}

- (ADClusterAnnotation *)clusterAnnotationForOriginalAnnotation:(id<MKAnnotation>)annotation {
    NSAssert(![annotation isKindOfClass:[ADClusterAnnotation class]], @"Unexpected annotation!");
    for (ADClusterAnnotation * clusterAnnotation in self.visibleClusterAnnotations) {
        if ([clusterAnnotation.cluster isRootClusterForAnnotation:annotation]) {
            return clusterAnnotation;
        }
    }
    return nil;
}



#pragma mark - ADClusterMapView Delegate 

- (MKAnnotationView *)mapView:(ADClusterMapView *)mapView viewForClusterAnnotation:(id <MKAnnotation>)annotation {
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:viewForClusterAnnotation:)]) {
        return [_secondaryDelegate mapView:self viewForClusterAnnotation:annotation];
    }
    
    return nil;
}

- (void)mapView:(ADClusterMapView *)mapView willBeginBuildingClusterTreeForMapPoints:(NSSet *)annotations {
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:willBeginBuildingClusterTreeForMapPoints:)]) {
        [_secondaryDelegate mapView:mapView willBeginBuildingClusterTreeForMapPoints:annotations];
    }
}

- (void)mapView:(ADClusterMapView *)mapView didFinishBuildingClusterTreeForMapPoints:(NSSet *)annotations {
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:didFinishBuildingClusterTreeForMapPoints:)]) {
        [_secondaryDelegate mapView:mapView didFinishBuildingClusterTreeForMapPoints:annotations];
    }
}

- (void)mapViewWillBeginClusteringAnimation:(ADClusterMapView *)mapView{
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapViewWillBeginClusteringAnimation:)]) {
        [_secondaryDelegate mapViewWillBeginClusteringAnimation:mapView];
    }
}

- (void)mapViewDidCancelClusteringAnimation:(ADClusterMapView *)mapView {
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapViewDidCancelClusteringAnimation:)]) {
        [_secondaryDelegate mapViewDidCancelClusteringAnimation:mapView];
    }
}

- (void)mapViewDidFinishClusteringAnimation:(ADClusterMapView *)mapView{
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapViewDidFinishClusteringAnimation:)]) {
        [_secondaryDelegate mapViewDidFinishClusteringAnimation:mapView];
    }
}

- (void)userWillPanMapView:(ADClusterMapView *)mapView {
    
    if ([_secondaryDelegate respondsToSelector:@selector(userWillPanMapView:)]) {
        [_secondaryDelegate userWillPanMapView:mapView];
    }
}

- (void)userDidPanMapView:(ADClusterMapView *)mapView {
    
    if ([_secondaryDelegate respondsToSelector:@selector(userDidPanMapView:)]) {
        [_secondaryDelegate userDidPanMapView:mapView];
    }
}

@end
