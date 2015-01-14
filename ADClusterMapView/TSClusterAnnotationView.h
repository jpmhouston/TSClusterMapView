//
//  TSBaseAnnotationView.h
//  TapShield
//
//  Created by Adam Share on 4/2/14.
//  Copyright (c) 2014 TapShield, LLC. All rights reserved.
//

#import <MapKit/MapKit.h>
#import "ADClusterAnnotation.h"

@interface TSClusterAnnotationView : MKAnnotationView

@property (strong, nonatomic) UILabel *label;

/*!
 * @discussion Called during a clustering event to allow for a refresh of the view. Use to update a label representing the number of annotations or change the image based on the annotation associated.
 */
- (void)refreshView;

@end
