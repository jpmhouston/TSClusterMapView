//
//  TSBaseAnnotationView.m
//  TapShield
//
//  Created by Adam Share on 4/2/14.
//  Copyright (c) 2014 TapShield, LLC. All rights reserved.
//

#import "TSClusterAnnotationView.h"

@implementation TSClusterAnnotationView

- (id)initWithAnnotation:(id<MKAnnotation>)annotation reuseIdentifier:(NSString *)reuseIdentifier {
    
    self = [super initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
        self.accessibilityValue = @"";
        self.accessibilityLabel = @"Map Annotation";
    }
    return self;
    
}

- (void)setAnnotation:(id<MKAnnotation>)annotation {
    
    [super setAnnotation:annotation];
    
    if ([annotation isKindOfClass:[ADClusterAnnotation class]]) {
        ((ADClusterAnnotation *)annotation).annotationView = self;
    }
    
    [self refreshView];
}

- (void)refreshView {
    
    //Subclass and add your cluster view updates here
}

- (NSString *)accessibilityValue {
    
    return self.annotation.title;
}

@end
