//
//  ADClusterAnnotation.m
//  AppLibrary
//
//  Created by Patrick Nollet on 01/07/11.
//  Copyright 2011 Applidium. All rights reserved.
//

#import "ADClusterAnnotation.h"
#import "TSRefreshedAnnotationView.h"


BOOL ADClusterCoordinate2DIsOffscreen(CLLocationCoordinate2D coord) {
    return (coord.latitude == kADCoordinate2DOffscreen.latitude && coord.longitude == kADCoordinate2DOffscreen.longitude);
}

@implementation ADClusterAnnotation

- (id)init {
    self = [super init];
    if (self) {
        _cluster = nil;
        self.coordinate = kADCoordinate2DOffscreen;
        _shouldBeRemovedAfterAnimation = NO;
        _title = @"Title";
    }
    return self;
}

- (void)setCluster:(ADMapCluster *)cluster {
    
    if (cluster && cluster!=_cluster) {
        _needsRefresh = YES;
    }
    else {
        _needsRefresh = NO;
    }
    
    _cluster = cluster;
}

- (NSString *)title {
    return self.cluster.title;
}

- (NSString *)subtitle {
    return self.cluster.subtitle;
}

- (void)setCoordinate:(CLLocationCoordinate2D)coordinate {
    
    _coordinate = coordinate;
    _coordinatePreAnimation = kCLLocationCoordinate2DInvalid;
}

- (void)reset {
    self.cluster = nil;
    self.coordinate = kADCoordinate2DOffscreen;
}

- (void)shouldReset {
    self.cluster = nil;
    self.coordinatePreAnimation = kADCoordinate2DOffscreen;
}

- (NSArray *)originalAnnotations {
    NSAssert(self.cluster != nil, @"This annotation should have a cluster assigned!");
    return self.cluster.originalAnnotations;
}

- (NSUInteger)clusterCount {
    
    return _cluster.clusterCount;
}

- (ADClusterAnnotationType)type {
    
    if (!self.clusterCount) {
        return ADClusterAnnotationTypeUnknown;
    }
    
    if (self.clusterCount > 1) {
        return ADClusterAnnotationTypeCluster;
    }
    
    return ADClusterAnnotationTypeLeaf;
}


@end
