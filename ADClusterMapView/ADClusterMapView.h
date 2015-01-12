//
//  ADClusterMapView.h
//  ADClusterMapView
//
//  Created by Patrick Nollet on 30/06/11.
//  Copyright 2011 Applidium. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "ADMapCluster.h"
#import "ADClusterAnnotation.h"

extern NSString * const TSMapViewWillChangeRegion;
extern NSString * const TSMapViewDidChangeRegion;

@class ADClusterMapView;
@protocol ADClusterMapViewDelegate <MKMapViewDelegate, UIGestureRecognizerDelegate>
@optional

- (MKAnnotationView *)mapView:(ADClusterMapView *)mapView viewForClusterAnnotation:(id <MKAnnotation>)annotation; // default: same as returned by mapView:viewForAnnotation:
- (NSString *)clusterTitleForMapView:(ADClusterMapView *)mapView; // default : @"%d elements"


/*!
 * @discussion MapView will begin clustering operation
 * @param Current ADClusterMapView
 */
- (void)mapViewWillBeginClustering:(ADClusterMapView *)mapView;

/*!
 * @discussion MapView did finish clustering operation
 * @param Current ADClusterMapView
 */
- (void)mapViewDidFinishClustering:(ADClusterMapView *)mapView;

/*!
 * @discussion Convenience delegate to determine if map will pan by user gesture
 * @param Current ADClusterMapView
 */
- (void)userWillPanMapView:(ADClusterMapView *)mapView;
/*!
 * @discussion Convenience delegate to determine if map did pan by user gesture
 * @param Current ADClusterMapView
 */
- (void)userDidPanMapView:(ADClusterMapView *)mapView;

@end


typedef NS_ENUM(NSInteger, ADClusterBufferSize) {
    ADClusterBufferNone = 0,
    ADClusterBufferSmall = 2,
    ADClusterBufferMedium = 4,
    ADClusterBufferLarge = 8
};

@interface ADClusterMapView : MKMapView <MKMapViewDelegate, UIGestureRecognizerDelegate>

/*!
 * @discussion Finds the cluster that contains a single annotation
 * @param MKAnnotation of annotation within a cluster
 * @return the ADClusterAnnotation instance containing the annotation originally added.
 */
- (ADClusterAnnotation *)clusterAnnotationForOriginalAnnotation:(id<MKAnnotation>)annotation;

/*!
 * @discussion Adds an annotation to the map and clusters if needed (threadsafe)
 * @param MKAnnotation to be added to map
 */
- (void)addClusteredAnnotation:(id<MKAnnotation>)annotation;

/*!
 * @discussion Adds multiple annotations to the map and clusters if needed (threadsafe)
 * @param NSArray of MKAnnotation types to be added to map
 */
- (void)addClusteredAnnotations:(NSArray *)annotations;


/*!
 * @discussion Force a refresh of clusters
 */
- (void)needsRefresh;


/**
 Annotations positioned by to be viewed
 */
@property (readonly) NSArray * displayedAnnotations;

/**
 Max number of clusters visible at once. Default: 32
 */
@property (assign, nonatomic) NSUInteger clustersOnScreen;

/**
 Creates a buffer zone surrounding visible map of clustered annotations. This helps simulate seemless loading of annotations and helps prevent annotations from appearing and dissapearing close to the edge. NOTE: For older devices or larger data sets try reducing the buffer size Default: ADClusterBufferMedium
 */
//multiply by 9 for the visible rect plus 8 directions of possible screen travel (up, down, up-left, down-left, etc.)
@property (assign, nonatomic) ADClusterBufferSize clusterEdgeBufferSize;

/** 
 This parameter emphasize the discrimination of annotations which are far away from the center of mass. Default: 1.0 (no discrimination applied)
 */
@property (assign, nonatomic) double clusterDiscriminationPower;

/** 
 Cluster annotation creates subtitle from list of contained titles. Default: YES
 */
@property (assign, nonatomic) BOOL clusterShouldShowSubtitle;

/**
 Will always shows max number of clusters past this span delta level (zoom). Default: .005
 */
@property (assign, nonatomic) CLLocationDegrees clusterMinimumLongitudeDelta;

@end