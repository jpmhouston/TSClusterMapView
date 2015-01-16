//
//  ADMapCluster.h
//  ADClusterMapView
//
//  Created by Patrick Nollet on 27/06/11.
//  Copyright 2011 Applidium. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "ADMapPointAnnotation.h"

@class ADClusterMapView;

@interface ADMapCluster : NSObject

typedef void(^KdtreeCompletionBlock)(ADMapCluster *mapCluster);

@property (nonatomic, strong) ADMapPointAnnotation *annotation;

@property (nonatomic, assign) CLLocationCoordinate2D clusterCoordinate;

@property (nonatomic, assign) BOOL showSubtitle;

@property (nonatomic, readonly) NSInteger depth;

@property (readonly) NSMutableArray *originalAnnotations;

@property (readonly) NSMutableArray *originalMapPointAnnotations;

@property (readonly) NSString *title;

@property (readonly) NSString *subtitle;

@property (assign, nonatomic, readonly) NSInteger clusterCount;

@property (readonly) NSArray *clusteredAnnotationTitles;

@property (readonly) NSArray *children;

@property (readonly) NSMutableSet *allChildClusters;

@property (weak, nonatomic) ADMapCluster *parentCluster;


/*!
 * @discussion Creates a KD-tree of clusters http://en.wikipedia.org/wiki/K-d_tree
 * @param annotations Set of ADMapPointAnnotation objects
 * @param mapView The ADClusterMapView that will send the delegate callback
 * @return A new ADMapCluster object.
 */
+ (void)rootClusterForAnnotations:(NSSet *)annotations mapView:(ADClusterMapView *)mapView completion:(KdtreeCompletionBlock)completion ;


/*!
 * @discussion Creates a KD-tree of clusters http://en.wikipedia.org/wiki/K-d_tree
 * @param annotations Set of ADMapPointAnnotation objects
 * @param gamma Descrimination power
 * @param title Title of cluster
 * @param showSubtitle A Boolean to show subtitle from titles of children
 * @return A new ADMapCluster object.
 */
+ (void)rootClusterForAnnotations:(NSSet *)annotations discriminationPower:(double)gamma title:(NSString *)clusterTitle showSubtitle:(BOOL)showSubtitle completion:(KdtreeCompletionBlock)completion ;

/*!
 * @discussion Adds a single map point annotation to an existing KD-tree map cluster root
 * @param mapView The ADClusterMapView that will send the delegate callback
 * @param mapPointAnnotation A single ADMapPointAnnotation object
 * @return YES if tree was updated, NO if full root should be updated
 */
- (void)mapView:(ADClusterMapView *)mapView addAnnotation:(ADMapPointAnnotation *)mapPointAnnotation completion:(void(^)(BOOL added))completion;


/*!
 * @discussion Removes a single map point annotation to an existing KD-tree map cluster root
 * @param mapView The ADClusterMapView that will send the delegate callback
 * @param mapPointAnnotation A single ADMapPointAnnotation object
 * @return YES if tree was updated, NO if full root should be updated
 */
- (void)mapView:(ADClusterMapView *)mapView removeAnnotation:(id<MKAnnotation>)annotation completion:(void(^)(BOOL added))completion;;

/*!
 * @discussion Get a set number of children contained within a map rect
 * @param number Max number of children to be returned
 * @param mapRect MKMapRect to search within
 * @return A set containing children found in the rect. May return less than specified or none depending on results.
 */
- (NSSet *)find:(NSInteger)number childrenInMapRect:(MKMapRect)mapRect;

/*!
 * @discussion Checks the receiver to see how many of the given rects contain coordinates of children
 * @param mapRects An NSSet of NSDictionary objects containing MKMapRect structs (Use NSDictionary+MKMapRect method)
 * @return Number of map rects containing coordinates of children
 */
- (NSUInteger)numberOfMapRectsContainingChildren:(NSSet *)mapRects;

/*!
 * @discussion Check the receiver to see if contains the given cluster within it's cluster children
 * @param mapCluster An ADMapCluster object
 * @return YES if receiver found cluster in children
 */
- (BOOL)isAncestorOf:(ADMapCluster *)mapCluster;

/*!
 * @discussion Check the receiver to see if contains the given annotation within it's cluster
 * @param annotation A clusterable MKAnnotation
 * @return YES if receiver found annotation in children
 */
- (BOOL)isRootClusterForAnnotation:(id<MKAnnotation>)annotation;

/*!
 * @discussion Finds the cluster object associated with the annotation
 * @param annotation A clustered MKAnnotation
 * @return The ADMapCluster object that contains the annotation
 */
- (ADMapCluster *)clusterForAnnotation:(id<MKAnnotation>)annotation;



//- (BOOL)isAncestorForClusterInSet:(NSSet *)set;
//- (BOOL)isChildOfClusterInSet:(NSSet *)clusters;

- (NSMutableSet *)findChildrenForClusterInSet:(NSSet *)set;
- (ADMapCluster *)findAncestorForClusterInSet:(NSSet *)set;

@end
