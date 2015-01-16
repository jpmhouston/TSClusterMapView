//
//  TSClusterAnimationOptions.h
//  ClusterDemo
//
//  Created by Adam Share on 1/16/15.
//  Copyright (c) 2015 Applidium. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TSClusterAnimationOptions : NSObject

@property (nonatomic, assign) float duration;
@property (nonatomic, assign) float springDamping;
@property (nonatomic, assign) float springVelocity;
@property (nonatomic, assign) UIViewAnimationOptions viewAnimationOptions;

+ (instancetype)defaultOptions;

@end
