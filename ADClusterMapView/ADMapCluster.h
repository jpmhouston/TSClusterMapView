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

@interface ADMapCluster : NSObject

@property (nonatomic, strong) ADMapPointAnnotation * annotation;

@property (nonatomic, assign) CLLocationCoordinate2D clusterCoordinate;

@property (nonatomic, assign) BOOL showSubtitle;

@property (nonatomic, readonly) NSInteger depth;

@property (readonly) NSMutableArray * originalAnnotations;

@property (readonly) NSString * title;

@property (readonly) NSString * subtitle;

@property (readonly) NSUInteger clusterCount;

@property (readonly) NSArray *clusteredAnnotationTitles;

@property (readonly) NSArray *children;


/*!
 * @discussion Creates a KD-tree of clusters  http://en.wikipedia.org/wiki/K-d_tree
 * @param Set of clusterable annotations
 * @param 
 * @return A set containing children found in the rect. May return less than specified or none depending on results.
 */
+ (ADMapCluster *)rootClusterForAnnotations:(NSSet *)annotations gamma:(double)gamma clusterTitle:(NSString *)clusterTitle showSubtitle:(BOOL)showSubtitle;

/*!
 * @discussion Get a set number of children contained within a map rect
 * @param Max number of children to be returned
 * @param MKMapRect to search within
 * @return A set containing children found in the rect. May return less than specified or none depending on results.
 */
- (NSSet *)find:(NSInteger)N childrenInMapRect:(MKMapRect)mapRect;

/*!
 * @discussion Checks the receiver to see how many of the given rects contain coordinates of children
 * @param An NSSet of NSDictionary objects containing MKMapRect structs (Use NSDictionary+MKMapRect method)
 * @return Number of map rects containing coordinates of children
 */
- (NSUInteger)numberOfMapRectsContainingChildren:(NSSet *)mapRects;

/*!
 * @discussion Check the receiver to see if contains the given cluster within it's cluster children
 * @param An ADMapCluster object
 * @return YES if receiver found cluster in children
 */
- (BOOL)isAncestorOf:(ADMapCluster *)mapCluster;

/*!
 * @discussion Check the receiver to see if contains the given annotation within it's cluster
 * @param A clusterable MKAnnotation
 * @return YES if receiver found annotation in children
 */
- (BOOL)isRootClusterForAnnotation:(id<MKAnnotation>)annotation;

@end
