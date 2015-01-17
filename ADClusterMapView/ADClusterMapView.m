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

#define DATA_REFRESH_MAX 1000

static NSString * const kTSClusterAnnotationViewID = @"kTSClusterAnnotationViewID-private";
NSString * const KDTreeClusteringProgress = @"KDTreeClusteringProgress";

@interface ADClusterMapView ()

@property (nonatomic, weak) id <ADClusterMapViewDelegate>  secondaryDelegate;

//Clustering
@property (nonatomic, strong) ADMapCluster *rootMapCluster;

@property (nonatomic, strong) NSMutableSet *clusterAnnotationsPool;
@property (nonatomic, strong) NSMutableSet *clusterableAnnotationsAdded;

@property (nonatomic, assign) MKMapRect previousVisibleMapRectClustered;

@property (nonatomic, strong) NSOperationQueue *clusterOperationQueue;

@property (nonatomic, strong) TSClusterOperation *clusterOperation;

@property (nonatomic, strong) NSCache *annotationViewCache;

@property (nonatomic, strong) NSOperationQueue *treeOperationQueue;

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
    
    _clusterAnimationOptions = [TSClusterAnimationOptions defaultOptions];
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
        [_treeOperationQueue cancelAllOperations];
    }
}

- (void)setDefaults {
    
    self.clusterPreferredCountVisible = 20;
    self.clusterDiscriminationPower = 1.0;
    self.clusterShouldShowSubtitle = YES;
    self.clusterEdgeBufferSize = ADClusterBufferMedium;
    self.clusterMinimumLongitudeDelta = 0.005;
    self.clusterTitle = @"%d elements";
    self.clusterZoomsOnTap = YES;
    self.clusterAppearanceAnimated = YES;
}

- (void)setClusterEdgeBufferSize:(ADClusterBufferSize)clusterEdgeBufferSize {
    
    if (clusterEdgeBufferSize < 0) {
        clusterEdgeBufferSize = 0;
    }
    
    _clusterEdgeBufferSize = clusterEdgeBufferSize;
}

- (void)setClusterPreferredCountVisible:(NSUInteger)clustersOnScreen {
    
    _clusterPreferredCountVisible = clustersOnScreen;
    
    [self clusterVisibleMapRectForceRefresh:YES];
}

- (NSUInteger)numberOfClusters {
    
    NSUInteger adjusted = _clusterPreferredCountVisible + (_clusterPreferredCountVisible*_clusterEdgeBufferSize);
    if (_clusterPreferredCountVisible > 6) {
        return adjusted;
    }
    return _clusterPreferredCountVisible;
}

- (void)needsRefresh {
    
    [self createKDTreeAndCluster:_clusterableAnnotationsAdded];
}

#pragma mark - Add/Remove Annotations

- (void)addClusteredAnnotation:(id<MKAnnotation>)annotation {
    
    BOOL refresh = NO;
    
    if (_clusterableAnnotationsAdded.count < DATA_REFRESH_MAX) {
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
    
    if (refresh || _treeOperationQueue.operationCount > 3) {
        [self needsRefresh];
        return;
    }
    
    
    __weak ADClusterMapView *weakSelf = self;
    [_treeOperationQueue addOperationWithBlock:^{
        //Attempt to insert in existing root cluster - will fail if small data set or an outlier
        [_rootMapCluster mapView:self addAnnotation:[[ADMapPointAnnotation alloc] initWithAnnotation:annotation] completion:^(BOOL added) {
            
            ADClusterMapView *strongSelf = weakSelf;
            
            if (added) {
                [strongSelf clusterVisibleMapRectForceRefresh:YES];
            }
            else {
                [strongSelf needsRefresh];
            }
        }];
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
        if (_clusterableAnnotationsAdded.count < DATA_REFRESH_MAX || _treeOperationQueue.operationCount > 3) {
            [self needsRefresh];
        }
        else {
            
            
            __weak ADClusterMapView *weakSelf = self;
            [_treeOperationQueue addOperationWithBlock:^{
                [weakSelf.rootMapCluster mapView:self removeAnnotation:annotation completion:^(BOOL removed) {
                    
                    ADClusterMapView *strongSelf = weakSelf;
                    
                    if (removed) {
                        [strongSelf clusterVisibleMapRectForceRefresh:YES];
                    }
                    else {
                        [strongSelf needsRefresh];
                    }
                }];
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
    [self cacheAnnotationView:viewToCache];
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

- (void)cacheAnnotationView:(MKAnnotationView *)annotationView {
    
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
    
    annotations = [annotations copy];
    
    [_treeOperationQueue cancelAllOperations];
    
    __weak ADClusterMapView *weakSelf = self;
    [_treeOperationQueue addOperationWithBlock:^{
        
        // use wrapper annotations that expose a MKMapPoint property instead of a CLLocationCoordinate2D property
        NSMutableSet * mapPointAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count];
        for (id<MKAnnotation> annotation in annotations) {
            ADMapPointAnnotation * mapPointAnnotation = [[ADMapPointAnnotation alloc] initWithAnnotation:annotation];
            [mapPointAnnotations addObject:mapPointAnnotation];
        }
        
        [ADMapCluster rootClusterForAnnotations:mapPointAnnotations mapView:self completion:^(ADMapCluster *mapCluster) {
            
            ADClusterMapView *strongSelf = weakSelf;
            
            strongSelf.rootMapCluster = mapCluster;
            
            [strongSelf clusterVisibleMapRectForceRefresh:YES];
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


- (void)clusterVisibleMapRectForceRefresh:(BOOL)isNewCluster {
    
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
    
    [_clusterOperationQueue cancelAllOperations];
    
    [self mapViewWillBeginClusteringAnimation:self];
    
    __weak ADClusterMapView *weakSelf = self;
    TSClusterOperation *operation = [[TSClusterOperation alloc] initWithMapView:self
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
    [_clusterOperationQueue addOperation:operation];
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
        [self cacheAnnotationView:[view updateWithAnnotationView:delegateAnnotationView]];
        
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
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:regionWillChangeAnimated:)]) {
        [_secondaryDelegate mapView:self regionWillChangeAnimated:animated];
    }
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    
//    if (MKMapRectContainsPoint(self.visibleMapRect, MKMapPointForCoordinate(kADCoordinate2DOffscreen))) {
//        return;
//    }
    
    [self clusterVisibleMapRectForceRefresh:NO];
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:regionDidChangeAnimated:)]) {
        [_secondaryDelegate mapView:self regionDidChangeAnimated:animated];
    }
}

- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view {
    
    if (_clusterZoomsOnTap &&
        [view isKindOfClass:[TSClusterAnnotationView class]] &&
        ((ADClusterAnnotation *)view.annotation).type == ADClusterAnnotationTypeCluster){
        
        [self deselectAnnotation:view.annotation animated:NO];
        
        MKMapRect zoomTo = ((ADClusterAnnotation *)view.annotation).cluster.mapRect;
        zoomTo = [self mapRectThatFits:zoomTo edgePadding:UIEdgeInsetsMake(0, view.frame.size.width/2, 0, view.frame.size.width/2)];
        
        if (MKMapRectSizeIsGreaterThanOrEqual(zoomTo, self.visibleMapRect)) {
            zoomTo = MKMapRectInset(zoomTo, zoomTo.size.width/4, zoomTo.size.width/4);
        }
        
        [self setVisibleMapRect:zoomTo animated:YES];
    }
    
    if ([_secondaryDelegate respondsToSelector:@selector(mapView:didSelectAnnotationView:)]) {
        [_secondaryDelegate mapView:mapView didSelectAnnotationView:view];
    }
}

- (void)mapView:(MKMapView *)mapView didDeselectAnnotationView:(MKAnnotationView *)view {
    
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
