//
//  TSBaseAnnotationView.h
//  TapShield
//
//  Created by Adam Share on 4/2/14.
//  Copyright (c) 2014 TapShield, LLC. All rights reserved.
//

#import <MapKit/MapKit.h>
#import "ADClusterAnnotation.h"

@interface TSRefreshedAnnotationView : MKAnnotationView

/*!
 * @discussion Added to UIView animation block during a clustering event to allow for an animated refresh of the view. Because clustered annotations are only added to the map once while underlying annotations are interchanged, the mapView:viewForAnnotation: method may only be called once. Use to update a label representing the number of annotations or change the image based on the annotation associated.
 */
- (void)refreshView;

@end
