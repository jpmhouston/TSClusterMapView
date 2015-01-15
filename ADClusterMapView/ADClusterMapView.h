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
#import "TSClusterAnnotationView.h"

extern NSString * const TSMapViewWillChangeRegion;
extern NSString * const TSMapViewDidChangeRegion;

@class ADClusterMapView;
@protocol ADClusterMapViewDelegate <MKMapViewDelegate, UIGestureRecognizerDelegate>
@optional

/*!
 * @discussion Set the annotation view for clustered annotations. To take advantage of a refresh call during clustering return a subclass of TSClusteredAnnotationView
 * @param mapView The map view that requested the annotation view.
 * @param annotation The object representing the annotation that is about to be displayed.
 * @return The annotation view to display for the specified annotation or nil if you want to display a standard annotation view.
 */
- (MKAnnotationView *)mapView:(ADClusterMapView *)mapView viewForClusterAnnotation:(id <MKAnnotation>)annotation;

/*!
 * @discussion MapView will begin creating Kd-tree from new annotations. Use this delegate to alert the user of a refresh for large data sets with long build times.
 * @param mapView The map view that will begin clustering.
 */
- (void)mapView:(ADClusterMapView *)mapView willBeginBuildingClusterTreeForMapPoints:(NSSet *)annotations;

/*!
 * @discussion MapView did finish creating Kd-tree from new annotations. Remove any UI associated with loading annotations, cluster animation will begin.
 * @param mapView The map view that will begin clustering.
 */
- (void)mapView:(ADClusterMapView *)mapView didFinishBuildingClusterTreeForMapPoints:(NSSet *)annotations;

/*!
 * @discussion Animation operation will begin for mapView. Follows a mapView:regionDidChangeAnimated: or mapViewDidFinishBuildingClusterTree. Operation may cancel before finishing from new clustering parameters.
 * @param mapView The map view that will begin clustering.
 */
- (void)mapViewWillBeginClusteringAnimation:(ADClusterMapView *)mapView;

/*!
 * @discussion Animation operation was cancelled due to map movement or new tree.
 * @param mapView The map view that did cancel clustering.
 */
- (void)mapViewDidCancelClusteringAnimation:(ADClusterMapView *)mapView;

/*!
 * @discussion Animation operation did finish successfully.
 * @param mapView The map view that did finish clustering.
 */
- (void)mapViewDidFinishClusteringAnimation:(ADClusterMapView *)mapView;

/*!
 * @discussion Convenience delegate to determine if map will pan by user gesture
 * @param mapView The map view that will begin panning.
 */
- (void)userWillPanMapView:(ADClusterMapView *)mapView;
/*!
 * @discussion Convenience delegate to determine if map did pan by user gesture
 * @param mapView The map view that did finish panning.
 */
- (void)userDidPanMapView:(ADClusterMapView *)mapView;

@end


typedef NS_ENUM(NSInteger, ADClusterBufferSize) {
    ADClusterBufferNone = 0,
    ADClusterBufferSmall = 2,
    ADClusterBufferMedium = 4,
    ADClusterBufferLarge = 8
};

@interface ADClusterMapView : MKMapView <MKMapViewDelegate, UIGestureRecognizerDelegate, ADClusterMapViewDelegate>

/*!
 * @discussion Finds the cluster visible on the map that contains a single annotation
 * @param annotation The annotation that was added to the map view.
 * @return The visible ADClusterAnnotation instance containing the annotation originally added.
 */
- (ADClusterAnnotation *)currentClusterAnnotationForAddedAnnotation:(id<MKAnnotation>)annotation;

/*!
 * @discussion Adds an annotation to the map and clusters if needed (threadsafe). Only rebuilds entire cluster tree if there are less than 500 clustered annotations or the annotation coordinate is an outlier from current clustered data set.
 * @param annotation The annotation to be added to map
 */
- (void)addClusteredAnnotation:(id<MKAnnotation>)annotation;

/*!
 * @discussion Adds multiple annotations to the map and clusters if needed (threadsafe). Rebuilds entire cluster tree.
 * @param annotations The array of MKAnnotation objects to be added to map
 */
- (void)addClusteredAnnotations:(NSArray *)annotations;

/*!
 * @discussion Add annotation with option to force a full tree refresh (threadsafe).
 * @param annotation The MKAnnotation to be added to map
 * @param refresh A Boolean that specifies whether the cluster tree should rebuild or quickly insert into existing tree. Cluster tree refresh can cause a delay with large data sets but provides more accurate clustering.
 */
- (void)addClusteredAnnotation:(id<MKAnnotation>)annotation clusterTreeRefresh:(BOOL)refresh;

/*!
 * @discussion Force a refresh of clustering tree
 */
- (void)needsRefresh;

/*!
 * @discussion Asks delegate for a new MKAnnotationView. Used before cluster animation to update annotation views.
 */
- (void)refreshClusterAnnotation:(ADClusterAnnotation *)annotation;

/**
 Visible cluster annotations. Will contain clusters just outside visible rect included in buffer zone.
 */
@property (readonly) NSArray * visibleClusterAnnotations;

/**
 Max number of clusters visible at once. Default: 20
 */
@property (assign, nonatomic) NSUInteger clustersOnScreen;

/**
 Creates a buffer zone surrounding visible map of clustered annotations. This helps simulate seemless loading of annotations and helps prevent annotations from appearing and dissapearing close to the edge. NOTE: For older devices or larger data sets try reducing the buffer size Default: ADClusterBufferMedium
 */
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

/**
 Title for cluster annotations. Default @"%d elements"
 */
@property (strong, nonatomic) NSString *clusterTitle;


@property (nonatomic, strong, readonly) NSOperationQueue *treeOperationQueue;

@end