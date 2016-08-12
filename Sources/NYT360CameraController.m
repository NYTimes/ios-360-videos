//
//  NYT360CameraController.m
//  NYT360Video
//
//  Created by Thiago on 7/13/16.
//  Copyright © 2016 The New York Times Company. All rights reserved.
//

#import "NYT360CameraController.h"
#import "NYT360EulerAngleCalculations.h"
#import "NYT360CameraPanGestureRecognizer.h"

static const NSTimeInterval NYT360CameraControllerPreferredMotionUpdateInterval = (1.0 / 60.0);

static inline CGPoint subtractPoints(CGPoint a, CGPoint b) {
    return CGPointMake(b.x - a.x, b.y - a.y);
}

@interface NYT360CameraController ()

@property (nonatomic) SCNView *view;
@property (nonatomic) id<NYT360MotionManagement> motionManager;
@property (nonatomic, strong, nullable) NYT360MotionManagementToken motionUpdateToken;
@property (nonatomic) SCNNode *camera;

@property (nonatomic, assign) CGPoint rotateStart;
@property (nonatomic, assign) CGPoint rotateCurrent;
@property (nonatomic, assign) CGPoint rotateDelta;
@property (nonatomic, assign) CGPoint currentPosition;

@end

@implementation NYT360CameraController

#pragma mark - Initializers

- (instancetype)initWithView:(SCNView *)view motionManager:(id<NYT360MotionManagement>)motionManager {
    self = [super init];
    if (self) {
        
        NSAssert(view.pointOfView != nil, @"NYT360CameraController must be initialized with a view with a non-nil pointOfView node.");
        NSAssert(view.pointOfView.camera != nil, @"NYT360CameraController must be initialized with a view with a non-nil camera node for view.pointOfView.");
        
        _camera = view.pointOfView;
        _view = view;
        _currentPosition = CGPointMake(0, 0);
        _allowedPanningAxes = NYT360PanningAxisHorizontal | NYT360PanningAxisVertical;
        
        _panRecognizer = [[NYT360CameraPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        _panRecognizer.delegate = self;
        [_view addGestureRecognizer:_panRecognizer];
        
        _motionManager = motionManager;
    }
    
    return self;
}

#pragma mark - Observing Device Motion

- (void)startMotionUpdates {
    NSTimeInterval interval = NYT360CameraControllerPreferredMotionUpdateInterval;
    self.motionUpdateToken = [self.motionManager startUpdating:interval];
}

- (void)stopMotionUpdates {
    if (self.motionUpdateToken == nil) { return; }
    [self.motionManager stopUpdating:self.motionUpdateToken];
    self.motionUpdateToken = nil;
}

#pragma mark - Camera Angle Direction

- (double)cameraAngleDirection {
    float x = 0, y = 0, z = -1;
    SCNMatrix4 worldMatrix = _camera.worldTransform;

    float qx = worldMatrix.m11 * x + worldMatrix.m12 * y + worldMatrix.m13 * z + worldMatrix.m14;
    float qz = worldMatrix.m31 * x + worldMatrix.m32 * y + worldMatrix.m33 * z + worldMatrix.m34;

    return atan2(qx, qz);
}

#pragma mark - Camera Angle Updates

- (void)updateCameraAngle {
#ifdef DEBUG
    if (!self.motionManager.isDeviceMotionActive) {
        NSLog(@"Warning: %@ called while %@ is not receiving motion updates", NSStringFromSelector(_cmd), NSStringFromClass(self.class));
    }
#endif
    
    CMRotationRate rotationRate = self.motionManager.deviceMotion.rotationRate;
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    NYT360EulerAngleCalculationResult result;
    result = NYT360DeviceMotionCalculation(self.currentPosition, rotationRate, orientation, self.allowedPanningAxes, NYT360EulerAngleCalculationNoiseThresholdDefault);
    self.currentPosition = result.position;
    self.camera.eulerAngles = result.eulerAngles;
}

#pragma mark - Panning Options

- (void)setAllowedPanningAxes:(NYT360PanningAxis)allowedPanningAxes {
    // TODO: [jaredsinclair] Consider adding an animated version of this method.
    if (_allowedPanningAxes != allowedPanningAxes) {
        _allowedPanningAxes = allowedPanningAxes;
        NYT360EulerAngleCalculationResult result = NYT360UpdatedPositionAndAnglesForAllowedAxes(self.currentPosition, allowedPanningAxes);
        self.currentPosition = result.position;
        self.camera.eulerAngles = result.eulerAngles;

    }
}

#pragma mark - Private

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint point = [recognizer locationInView:self.view];
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            self.rotateStart = point;
            break;
        case UIGestureRecognizerStateChanged:
            self.rotateCurrent = point;
            self.rotateDelta = subtractPoints(self.rotateStart, self.rotateCurrent);
            self.rotateStart = self.rotateCurrent;
            NYT360EulerAngleCalculationResult result = NYT360PanGestureChangeCalculation(self.currentPosition, self.rotateDelta, self.view.bounds.size, self.allowedPanningAxes);
            self.currentPosition = result.position;
            self.camera.eulerAngles = result.eulerAngles;
            break;
        default:
            break;
    }
}

@end
