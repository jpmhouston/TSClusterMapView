//
//  CDMapViewController.h
//  ClusterDemo
//
//  Created by Patrick Nollet on 09/10/12.
//  Copyright (c) 2012 Applidium. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ADClusterMapView.h"

@interface CDMapViewController : UIViewController <ADClusterMapViewDelegate, UITabBarDelegate>

@property (strong, nonatomic) IBOutlet ADClusterMapView * mapView;

@property (weak, nonatomic) IBOutlet UITabBar *tabBar;
@property (weak, nonatomic) IBOutlet UITabBarItem *bathroomTabBarItem;
@property (weak, nonatomic) IBOutlet UITabBarItem *streetLightsTabBarItem;


@property (strong, nonatomic) NSMutableArray *streetLightAnnotations;
@property (strong, nonatomic) NSMutableArray *bathroomAnnotations;

@end
