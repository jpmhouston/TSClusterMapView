# TSClusterMapView - MKMapView with clustering

This animated annotation clustering MKMapView subclass is based off of [ADClusterMapView][].

[ADClusterMapView]: https://github.com/applidium/ADClusterMapView

## Quick start

Add the content of the TSClusterMapView folder to your iOS project and import TSClusterMapView.h

```objective-c
#import "TSClusterMapView.h"
```

Subclass TSClusterMapView with your new or existing MKMapView

```objective-c
@interface YourMapView : TSClusterMapView <MKMapViewDelegate, TSClusterMapViewDelegate>
```

Add annotations to be clustered using the add clustered annotation methods and single annotations using the standard add annotation.

```objective-c
- (void)addClusteredAnnotation:(id<MKAnnotation>)annotation;

- (void)addClusteredAnnotations:(NSArray *)annotations;
```

