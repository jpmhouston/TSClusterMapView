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

static NSString * const kTSClusterAnnotationViewID = @"kTSClusterAnnotationViewID-private";


@interface ADClusterMapView ()

@property (nonatomic, weak) id <ADClusterMapViewDelegate>  secondaryDelegate;

@property (nonatomic, assign) BOOL shouldReselectAnnotation;

@property (nonatomic, strong) id<MKAnnotation> previouslySelectedAnnotation;

//Clustering
@property (nonatomic, strong) ADMapCluster *rootMapCluster;

@property (nonatomic, strong) NSMutableSet *clusterAnnotationsPool;
@property (nonatomic, strong) NSMutableSet *clusterableAnnotationsAdded;

@property (nonatomic, assign) BOOL isBuildingRootCluster;

@property (nonatomic, assign) MKMapRect previousVisibleMapRectClustered;

@property (nonatomic, strong) NSOperationQueue *clusterOperationQueue;

@property (nonatomic, strong) TSClusterOperation *clusterOperation;

@property (nonatomic, strong) NSCache *annotationViewCache;

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
    
    self.clusterOperationQueue = [[NSOperationQueue alloc] init];
    [self.clusterOperationQueue setMaxConcurrentOperationCount:1];
    [self.clusterOperationQueue setName:@"Clustering Queue"];
    
    _treeOperationQueue = [[NSOperationQueue alloc] init];
    [_treeOperationQueue setMaxConcurrentOperationCount:1];
    [_treeOperationQueue setName:@"Tree Building Queue"];
    
    _annotationViewCache = [[NSCache alloc] init];
    
    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(didPanMap:)];
    [panRecognizer setDelegate:self];
    [self addGestureRecognizer:panRecognizer];
}

- (void)didMoveToSuperview {
    
    [super didMoveToSuperview];
    
    //No longer relevant to display stop operations
    if (!self.superview) {
        [_clusterOperationQueue cancelAllOperations];
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

- (NSUInteger)numberOfClusters {
    
    return _clustersOnScreen + (_clustersOnScreen*_clusterEdgeBufferSize);
}

- (void)needsRefresh {
    
    [self createKDTreeAndCluster:_clusterableAnnotationsAdded];
}

#pragma mark - Add/Remove Annotations

- (void)addClusteredAnnotation:(id<MKAnnotation>)annotation {
    
    BOOL refresh = NO;
    
    if (_clusterableAnnotationsAdded.count < 500) {
        refresh = YES;
    }
    
    [self addClusteredAnnotation:annotation clusterTreeRefresh:refresh];
}

- (void)addClusteredAnnotation:(id<MKAnnotation>)annotation clusterTreeRefresh:(BOOL)refresh {
    
    if (!annotation || [_clusterableAnnotationsAdded containsObject:annotation]) {
        return;
    }
    
    if (_clusterableAnnotationsAdded) {
        [_clusterableAnnotationsAdded addObject:annotation];
    }
    else {
        _clusterableAnnotationsAdded = [[NSMutableSet alloc] initWithObjects:annotation, nil];
    }
    
    if (refresh) {
        [self needsRefresh];
        return;
    }
    
    //Attempt to insert in existing root cluster - will fail if small data set or an outlier
    __weak ADClusterMapView *weakSelf = self;
    [_rootMapCluster mapView:self addAnnotation:[[ADMapPointAnnotation alloc] initWithAnnotation:annotation] completion:^(BOOL added) {
        
        ADClusterMapView *strongSelf = weakSelf;
        
        if (added) {
            [strongSelf clusterVisibleMapRectWithNewRootCluster:YES];
        }
        else {
            [strongSelf needsRefresh];
        }
    }];
}

- (void)addClusteredAnnotations:(NSArray *)annotations {
    
    if (!annotations || !annotations.count) {
        return;
    }
    
    NSInteger count = _clusterableAnnotationsAdded.count;
    
    if (_clusterableAnnotationsAdded) {
        [_clusterableAnnotationsAdded unionSet:[NSSet setWithArray:annotations]];
    }
    else {
        _clusterableAnnotationsAdded = [[NSMutableSet alloc] initWithArray:annotations];
    }
    
    if (count != _clusterableAnnotationsAdded.count) {
        [self needsRefresh];
    }
}

- (void)removeAnnotation:(id<MKAnnotation>)annotation {
    
    if (!annotation) {
        return;
    }
    
    if ([_clusterableAnnotationsAdded containsObject:annotation]) {
        [_clusterableAnnotationsAdded removeObject:annotation];
        
        //Small data set just rebuild
        if (_clusterableAnnotationsAdded.count < 500) {
            [self needsRefresh];
        }
        else {
            __weak ADClusterMapView *weakSelf = self;
            [_rootMapCluster mapView:self removeAnnotation:annotation completion:^(BOOL removed) {
                
                ADClusterMapView *strongSelf = weakSelf;
                
                if (removed) {
                    [strongSelf clusterVisibleMapRectWithNewRootCluster:YES];
                }
                else {
                    [strongSelf needsRefresh];
                }
            }];
        }
    }
    
    [super removeAnnotation:annotation];
}

- (void)removeAnnotations:(NSArray *)annotations {
    
    if (!annotations) {
        return;
    }
    
    NSUInteger previousCount = _clusterableAnnotationsAdded.count;
    NSSet *set = [NSSet setWithArray:annotations];
    [_clusterableAnnotationsAdded minusSet:set];
    
    if (_clusterableAnnotationsAdded.count != previousCount) {
        [self needsRefresh];
    }
    
    [super removeAnnotations:annotations];
}

#pragma mark - Annotations

- (void)refreshClusterAnnotation:(ADClusterAnnotation *)annotation {
    
    MKAnnotationView *viewToAdd = [self refreshAnnotationViewForAnnotation:annotation];
    MKAnnotationView *viewToCache = [annotation.annotationView updateWithAnnotationView:viewToAdd];
    [self addAnnotationViewToCache:viewToCache];
}

- (NSArray *)visibleClusterAnnotations {
    NSMutableArray * displayedAnnotations = [[NSMutableArray alloc] init];
    for (ADClusterAnnotation * annotation in [_clusterAnnotationsPool copy]) {
        if (annotation.coordinate.latitude != kADCoordinate2DOffscreen.latitude &&
            annotation.coordinate.longitude != kADCoordinate2DOffscreen.longitude) {
            [displayedAnnotations addObject:annotation];
        }
    }
    
    return displayedAnnotations;
}

- (NSArray *)annotations {
    
    NSMutableSet *set = [NSMutableSet setWithArray:[super annotations]];
    [set minusSet:_clusterAnnotationsPool];
    
    return [_clusterableAnnotationsAdded.allObjects arrayByAddingObjectsFromArray:set.allObjects];
}

- (ADClusterAnnotation *)currentClusterAnnotationForAddedAnnotation:(id<MKAnnotation>)annotation {
    
    for (ADClusterAnnotation *clusterAnnotation in self.visibleClusterAnnotations) {
        if ([clusterAnnotation.cluster isRootClusterForAnnotation:annotation]) {
            return clusterAnnotation;
        }
    }
    return nil;
}



#pragma mark - MKAnnotationView Cache

- (MKAnnotationView *)dequeueReusableAnnotationViewWithIdentifier:(NSString *)identifier {
    
    MKAnnotationView *view = [super dequeueReusableAnnotationViewWithIdentifier:identifier];
    
    if (!view) {
        view = [self annotationViewFromCacheWithKey:identifier];
    }
    return view;
}

- (MKAnnotationView *)annotationViewFromCacheWithKey:(NSString *)identifier {
    
    if ([identifier isEqualToString:kTSClusterAnnotationViewID]) {
        return nil;
    }
    
    MKAnnotationView *view;
    NSMutableSet *set = [_annotationViewCache objectForKey:identifier];
    if (set.count) {
        view = [set anyObject];
        [set removeObject:view];
    }
    
    [view prepareForReuse];
    
    return view;
}

- (void)addAnnotationViewToCache:(MKAnnotationView *)annotationView {
    
    if (!annotationView) {
        return;
    }
    
    annotationView.annotation = nil;
    
    NSString *reuseIdentifier = annotationView.reuseIdentifier;
    if ([reuseIdentifier isEqualToString:kTSClusterAnnotationViewID]) {
        reuseIdentifier = NSStringFromClass([annotationView class]);
    }
    
    NSMutableSet *set = [_annotationViewCache objectForKey:reuseIdentifier];
    if (set) {
        [set addObject:annotationView];
    }
    else {
        set = [[NSMutableSet alloc] initWithCapacity:10];
        [set addObject:annotationView];
        [_annotationViewCache setObject:set forKey:reuseIdentifier];
    }
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

- (void)createKDTreeAndCluster:(NSSet *)annotations {
    
    if (!annotations) {
        return;
    }
    
    _isBuildingRootCluster = YES;
    //NSLog(@"isSettingAnnotations");
    
    NSOperationQueue *queue = [NSOperationQueue currentQueue];
    if (!queue || queue == [NSOperationQueue mainQueue]) {
        queue = [NSOperationQueue new];
    }
    [queue addOperationWithBlock:^{
        
        // use wrapper annotations that expose a MKMapPoint property instead of a CLLocationCoordinate2D property
        NSMutableSet * mapPointAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count];
        for (id<MKAnnotation> annotation in annotations) {
            ADMapPointAnnotation * mapPointAnnotation = [[ADMapPointAnnotation alloc] initWithAnnotation:annotation];
            [mapPointAnnotations addObject:mapPointAnnotation];
        }
        
        __weak ADClusterMapView *weakSelf = self;
        [ADMapCluster rootClusterForAnnotations:mapPointAnnotations mapView:self completion:^(ADMapCluster *mapCluster) {
            
            ADClusterMapView *strongSelf = weakSelf;
            
            strongSelf.rootMapCluster = mapCluster;
            
            [strongSelf clusterVisibleMapRectWithNewRootCluster:YES];
            
            strongSelf.isBuildingRootCluster = NO;
        }];
    }];
}


- (void)initAnnotationPools:(NSUInteger)numberOfAnnotationsInPool {
    
    if (!numberOfAnnotationsInPool) {
        return;
    }
    
    //Count for splits
    numberOfAnnotationsInPool*=2;
    
    NSArray *toAdd;
    
    if (!_clusterAnnotationsPool) {
        _clusterAnnotationsPool = [[NSMutableSet alloc] initWithCapacity:numberOfAnnotationsInPool];
        for (int i = 0; i < numberOfAnnotationsInPool; i++) {
            ADClusterAnnotation * annotation = [[ADClusterAnnotation alloc] init];
            [_clusterAnnotationsPool addObject:annotation];
        }
        
        toAdd = _clusterAnnotationsPool.allObjects;
    }
    else if (numberOfAnnotationsInPool > _clusterAnnotationsPool.count) {
        
        NSUInteger difference = numberOfAnnotationsInPool - _clusterAnnotationsPool.count;
        NSMutableArray *mutableAdd = [[NSMutableArray alloc] initWithCapacity:difference];
        
        for (int i = 0; i < difference; i++) {
            ADClusterAnnotation * annotation = [[ADClusterAnnotation alloc] init];
            [_clusterAnnotationsPool addObject:annotation];
            [mutableAdd addObject:annotation];
        }
        
        toAdd = mutableAdd;
    }
    
    if (toAdd.count) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [super addAnnotations:toAdd];
        }];
    }
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
    
    [self initAnnotationPools:[self numberOfClusters]];
    
    if (_clusterOperation.isExecuting) {
        [_clusterOperation cancel];
    }
    
    [self mapViewWillBeginClusteringAnimation:self];
    
    __weak ADClusterMapView *weakSelf = self;
    _clusterOperation = [[TSClusterOperation alloc] initWithMapView:self
                                                               rect:clusteredMapRect
                                                        rootCluster:_rootMapCluster
                                               showNumberOfClusters:[self numberOfClusters]
                                                 clusterAnnotations:self.clusterAnnotationsPool
                                                         completion:^(MKMapRect clusteredRect, BOOL finished, NSSet *poolAnnotationsToRemove) {
                                                             
                                                             ADClusterMapView *strongSelf = weakSelf;
                                                             
                                                             [strongSelf poolAnnotationsToRemove:poolAnnotationsToRemove];
                                                             
                                                             if (finished) {
                                                                 strongSelf.previousVisibleMapRectClustered = clusteredRect;
                                                                 
                                                                 [strongSelf mapViewDidFinishClusteringAnimation:strongSelf];
                                                             }
                                                             else {
                                                                 [strongSelf mapViewDidCancelClusteringAnimation:strongSelf];
                                                             }
                                                         }];
    [_clusterOperationQueue addOperation:_clusterOperation];
    [_clusterOperationQueue setSuspended:NO];
}

- (void)poolAnnotationsToRemove:(NSSet *)remove {
    
    if (!remove.count) {
        return;
    }
    
    [super removeAnnotations:remove.allObjects];
    
    [_clusterAnnotationsPool minusSet:remove];
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
        }
        return nil;
    }
    
    TSClusterAnnotationView *view;
    MKAnnotationView *delegateAnnotationView = [self refreshAnnotationViewForAnnotation:annotation];
    if (delegateAnnotationView) {
        view = (TSClusterAnnotationView *)[self dequeueReusableAnnotationViewWithIdentifier:NSStringFromClass([TSClusterAnnotationView class])];
        [self addAnnotationViewToCache:[view updateWithAnnotationView:delegateAnnotationView]];
        
        if (!view) {
            view = [[TSClusterAnnotationView alloc] initWithAnnotation:annotation
                                                       reuseIdentifier:NSStringFromClass([TSClusterAnnotationView class])
                                              containingAnnotationView:delegateAnnotationView];
        }
    }
    
    return view;
}

- (MKAnnotationView *)refreshAnnotationViewForAnnotation:(id<MKAnnotation>)annotation  {
    
    MKAnnotationView *delegateAnnotationView;
    
    // only leaf clusters have annotations
    if (((ADClusterAnnotation *)annotation).type == ADClusterAnnotationTypeLeaf && ((ADClusterAnnotation *)annotation).cluster) {
        annotation = [((ADClusterAnnotation *)annotation).originalAnnotations firstObject];
        if ([_secondaryDelegate respondsToSelector:@selector(mapView:viewForAnnotation:)]) {
            delegateAnnotationView = [_secondaryDelegate mapView:self viewForAnnotation:annotation];
        }
    }
    else if (![_secondaryDelegate respondsToSelector:@selector(mapView:viewForClusterAnnotation:)]) {
        if ([_secondaryDelegate respondsToSelector:@selector(mapView:viewForAnnotation:)]) {
            delegateAnnotationView = [_secondaryDelegate mapView:self viewForAnnotation:annotation];
        }
    }
    else {
        delegateAnnotationView = [self mapView:self viewForClusterAnnotation:annotation];
    }
    
    //If dequeued it won't have an annotation set;
    if (!delegateAnnotationView.annotation) {
        delegateAnnotationView.annotation = annotation;
    }
    
    return delegateAnnotationView;
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
    
    [self clusterVisibleMapRectWithNewRootCluster:NO];
    
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
