//
//  PSPushPopPressView.m
//  PSPushPopPressView
//
//  Based on BSSPushPopPressView by Blacksmith Software.
//

#import "PSPushPopPressView.h"
#import <QuartzCore/QuartzCore.h>

#define kPSAnimationDuration 0.35f
#define kPSShadowFadeDuration 0.45f
#define kPSAnimationMoveToOriginalPositionDuration 0.5f
#define kPSFullscreenAnimationBounce 20
#define kPSEmbeddedAnimationBounceMultiplier 0.05f

@interface PSPushPopPressView() {
    // internal state variables
    UIView *initialSuperview_;
    BOOL beingDragged_;
    BOOL gesturesEnded_;
    BOOL scaleActive_;
    BOOL wasPinned_;
    
    CGAffineTransform _previousScaleTransform;
    CGAffineTransform _previousRotateTransform;
    CGAffineTransform _previousPanTransform;
}
@property (nonatomic, getter=isBeingDragged) BOOL beingDragged;
@property (nonatomic, getter=isFullscreen) BOOL fullscreen;
- (CGRect)windowBounds;
@end

@implementation PSPushPopPressView

@synthesize pushPopPressViewDelegate;
@synthesize beingDragged = beingDragged_;
@synthesize fullscreen = fullscreen_;
@synthesize initialFrame = initialFrame_;
@synthesize allowSingleTapSwitch = allowSingleTapSwitch_;
@synthesize ignoreStatusBar = ignoreStatusBar_;
@synthesize keepShadow = keepShadow_;

// adapt frame for fullscreen
- (void)detectOrientation {
    if (self.isFullscreen) {
        self.frame = [self windowBounds];
    }
}

- (void)awakeFromNib
{
    [self setup];
}

- (id)initWithFrame:(CGRect)frame_ {
    if ((self = [super initWithFrame:frame_])) {
        [self setup];
    }

    return self;
}

- (void)setup
{
    self.userInteractionEnabled = YES;
    self.multipleTouchEnabled = YES;
     _isAnimating = NO;
    scaleTransform_ = _previousScaleTransform = CGAffineTransformIdentity;
    rotateTransform_ = _previousRotateTransform = CGAffineTransformIdentity;
    panTransform_ = _previousPanTransform = CGAffineTransformIdentity;
    
    initialIndex_ = 0;
    allowSingleTapSwitch_ = YES;
    keepShadow_ = NO;
    
    UIPinchGestureRecognizer* pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchPanRotate:)];
    pinchRecognizer.cancelsTouchesInView = NO;
    pinchRecognizer.delaysTouchesBegan = NO;
    pinchRecognizer.delaysTouchesEnded = NO;
    pinchRecognizer.delegate = self;
    [self addGestureRecognizer: pinchRecognizer];
    
    UIRotationGestureRecognizer* rotationRecognizer = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(pinchPanRotate:)];
    rotationRecognizer.cancelsTouchesInView = NO;
    rotationRecognizer.delaysTouchesBegan = NO;
    rotationRecognizer.delaysTouchesEnded = NO;
    rotationRecognizer.delegate = self;
    [self addGestureRecognizer: rotationRecognizer];
    
    panRecognizer_ = [[UIPanGestureRecognizer alloc] initWithTarget: self action:@selector(pinchPanRotate:)];
    panRecognizer_.cancelsTouchesInView = NO;
    panRecognizer_.delaysTouchesBegan = NO;
    panRecognizer_.delaysTouchesEnded = NO;
    panRecognizer_.delegate = self;
    panRecognizer_.minimumNumberOfTouches = 2;
    panRecognizer_.maximumNumberOfTouches = 2;
    [self addGestureRecognizer:panRecognizer_];
    
    tapRecognizer_ = [[UITapGestureRecognizer alloc] initWithTarget: self action:@selector(tap:)];
    tapRecognizer_.delegate = self;
    tapRecognizer_.cancelsTouchesInView = NO;
    tapRecognizer_.delaysTouchesBegan = NO;
    tapRecognizer_.delaysTouchesEnded = NO;
    [self addGestureRecognizer:tapRecognizer_];
    
    doubleTouchRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
    doubleTouchRecognizer.delegate = self;
    doubleTouchRecognizer.cancelsTouchesInView = NO;
    doubleTouchRecognizer.delaysTouchesBegan = NO;
    doubleTouchRecognizer.delaysTouchesEnded = NO;
    doubleTouchRecognizer.numberOfTouchesRequired = 2;
    doubleTouchRecognizer.minimumPressDuration = 0.f;
    [self addGestureRecognizer:doubleTouchRecognizer];
    
    self.layer.shadowRadius = 15.0f;
    self.layer.shadowOffset = CGSizeMake(5.0f, 5.0f);
    self.layer.shadowOpacity = 0.4f;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.bounds].CGPath;
    self.layer.shadowOpacity = 0.0f;
    
    // manually track rotations and adapt fullscreen
    // needed if we rotate within a fullscreen animation and miss the autorotate event
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(detectOrientation) name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)dealloc {
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    pushPopPressViewDelegate = nil;
}

- (void) setFrame:(CGRect)frame
{
	[super setFrame:frame];
	
	if(![self.superview isEqual:[self rootView]])
		initialFrame_ = self.frame;
}

- (void)setInitialFrame:(CGRect)initialFrame {
    initialFrame_ = initialFrame;

    // if we're not in fullscreen, re-set frame
    if (!self.isFullscreen) {
        self.frame = initialFrame;
    }
}

- (UIView *)rootView {
    return self.window.rootViewController.view;
}

- (CGRect)windowBounds {
    // completely fullscreen
    CGRect windowBounds = [self rootView].bounds;

    if (self.ignoreStatusBar) {
        windowBounds = [UIScreen mainScreen].bounds;
        if (UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
            windowBounds.size.width = windowBounds.size.height;
            windowBounds.size.height = [UIScreen mainScreen].bounds.size.width;
        }
    }
    return windowBounds;
}

- (CGRect)superviewCorrectedInitialFrame {
    UIView *rootView = [self rootView];
    CGRect superviewCorrectedInitialFrame = [rootView convertRect:initialFrame_ fromView:initialSuperview_];
    return superviewCorrectedInitialFrame;
}

- (BOOL)detachViewToWindow:(BOOL)enable {
    BOOL viewChanged = NO;
    UIView *rootView = [self rootView];

    if (enable && !initialSuperview_) {
		initialIndex_ = [self.superview.subviews indexOfObject:self];
        initialSuperview_ = self.superview;
        CGRect newFrame = [self.superview convertRect:initialFrame_ toView:rootView];
        [rootView addSubview:self];
        [self setFrame:newFrame];
        viewChanged = YES;
    }else if(!enable) {
        if (initialSuperview_) {
            [initialSuperview_ insertSubview:self atIndex:initialIndex_];
            viewChanged = YES;
        }
        [self setFrame:initialFrame_];
        initialSuperview_ = nil;
    }
    return viewChanged;
}

- (void)updateShadowPath {
    self.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.bounds].CGPath;
}

- (void)applyShadowAnimated:(BOOL)animated {
	if (keepShadow_) return;
    if(animated) {
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
        anim.fromValue = [NSNumber numberWithFloat:0.0f];
        anim.toValue = [NSNumber numberWithFloat:1.0f];
        anim.duration = kPSShadowFadeDuration;
        [self.layer addAnimation:anim forKey:@"shadowOpacity"];
    }else {
        [self.layer removeAnimationForKey:@"shadowOpacity"];
    }

    [self updateShadowPath];
    self.layer.shadowOpacity = 1.0f;
}

- (void)removeShadowAnimated:(BOOL)animated {
	if (keepShadow_) return;
    // TODO: sometimes animates crazy, shadowOpacity animation losses shadowPath transform on certain conditions
    // shadow should also use a "lightSource", maybe it's easier to make a completely custom shadow view.
    if (animated) {
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
        anim.fromValue = [NSNumber numberWithFloat:1.0f];
        anim.toValue = [NSNumber numberWithFloat:0.0f];
        anim.duration = kPSShadowFadeDuration;
        [self.layer addAnimation:anim forKey:@"shadowOpacity"];
    }else {
        [self.layer removeAnimationForKey:@"shadowOpacity"];
    }

    self.layer.shadowOpacity = 0.0f;
}

- (void)setBeingDragged:(BOOL)newBeingDragged {
    if (newBeingDragged != beingDragged_) {
        beingDragged_ = newBeingDragged;

        if (beingDragged_) {
            [self applyShadowAnimated:YES];
        }else {
            //BOOL animate = !self.isFullscreen && !fullscreenAnimationActive_;
            [self removeShadowAnimated:NO];//TODO: removing this shadow animation fixes the (shadow) problem when coming back from fullscreen, that's a good give-and-take for me. The bool was nice writted but I think something messed up in other parts of the code and the check that creates the bool `animate' are messed up so I fixed that the simple way.
        }
    }
}

- (void)moveViewToOriginalPositionAnimated:(BOOL)animated bounces:(BOOL)bounces {
    CGFloat bounceX = panTransform_.tx * kPSEmbeddedAnimationBounceMultiplier * -1;
    CGFloat bounceY = panTransform_.ty * kPSEmbeddedAnimationBounceMultiplier * -1;

    // switch coordinates of gestureRecognizer in landscape
    if (UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
        CGFloat tmp = bounceY;
        bounceY = bounceX;
        bounceX = tmp;
    }

    self.fullscreen = NO;

    if ([self.pushPopPressViewDelegate respondsToSelector:@selector(pushPopPressViewWillAnimateToOriginalFrame:duration:)]) {
        [self.pushPopPressViewDelegate pushPopPressViewWillAnimateToOriginalFrame:self duration:kPSAnimationMoveToOriginalPositionDuration*1.5f];
    }

    [UIView animateWithDuration:animated ? kPSAnimationMoveToOriginalPositionDuration : 0.f delay: 0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         // always reset transforms
                         _isAnimating = YES;
                         rotateTransform_ = CGAffineTransformIdentity;
                         panTransform_ = CGAffineTransformIdentity;
                         scaleTransform_ = CGAffineTransformIdentity;
                         self.transform = CGAffineTransformIdentity;
                         
                         CGRect correctedInitialFrame = [self superviewCorrectedInitialFrame];

                         if (bounces) {
                             if (abs(bounceX) > 0 || abs(bounceY) > 0) {
                                 CGFloat widthDifference = (self.frame.size.width - correctedInitialFrame.size.width) * 0.05;
                                 CGFloat heightDifference = (self.frame.size.height - correctedInitialFrame.size.height) * 0.05;

                                 CGRect targetFrame = CGRectMake(correctedInitialFrame.origin.x + bounceX + (widthDifference / 2.0), correctedInitialFrame.origin.y + bounceY + (heightDifference / 2.0), correctedInitialFrame.size.width + (widthDifference * -1), correctedInitialFrame.size.height + (heightDifference * -1));
                                 [self setFrame:targetFrame];
                             }else {
                                 // there's reason behind this madness. shadow freaks out when we come from fullscreen, but not if we had transforms.
                                 fullscreenAnimationActive_ = YES;
                                 CGRect targetFrame = CGRectMake(correctedInitialFrame.origin.x + 3, correctedInitialFrame.origin.y + 3, correctedInitialFrame.size.width - 6, correctedInitialFrame.size.height - 6);
                                 //NSLog(@"targetFrame: %@ (superview: %@; initialSuperview: %@)", NSStringFromCGRect(targetFrame), self.superview, self.initialSuperview);
                                 [self setFrame:targetFrame];
                             }
                         }else {
                             [self setFrame:correctedInitialFrame];
                         }
                     }
                     completion: ^(BOOL finished) {
                         //NSLog(@"moveViewToOriginalPositionAnimated [complete] finished:%d, bounces:%d", finished, bounces);
                         fullscreenAnimationActive_ = NO;
                         if (bounces && finished) {
                             [UIView animateWithDuration: kPSAnimationMoveToOriginalPositionDuration/2 delay: 0.0
                                                 options:UIViewAnimationOptionAllowUserInteraction animations: ^{
                                                     CGRect correctedInitialFrame = [self superviewCorrectedInitialFrame];
                                                     [self setFrame:correctedInitialFrame];
                                                 } completion: ^(BOOL finished) {
                                                     if (finished && !self.isBeingDragged) {
                                                         [self detachViewToWindow:NO];
                                                     }
                                                      _isAnimating = NO;
                                                     if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewDidAnimateToOriginalFrame:)]) {
                                                         [self.pushPopPressViewDelegate pushPopPressViewDidAnimateToOriginalFrame: self];
                                                     }
                                                 }];
                         }else {
                             if (!self.isBeingDragged) {
                                 //[self detachViewToWindow:NO];
                             }
                              _isAnimating = NO;
                             if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewDidAnimateToOriginalFrame:)]) {
                                 [self.pushPopPressViewDelegate pushPopPressViewDidAnimateToOriginalFrame: self];
                             }
                         }
                     }];
}

- (void)moveToFullscreenAnimated:(BOOL)animated bounces:(BOOL)bounces {
    if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewWillAnimateToFullscreenWindowFrame:duration:)]) {
        [self.pushPopPressViewDelegate pushPopPressViewWillAnimateToFullscreenWindowFrame: self duration: kPSAnimationDuration];
    }

    BOOL viewChanged = [self detachViewToWindow:YES];
    self.fullscreen = YES;

    [UIView animateWithDuration: animated ? kPSAnimationDuration : 0.f delay: 0.0
     // view hierarchy change needs some time propagating, don't use UIViewAnimationOptionBeginFromCurrentState when just changed
                        options:(viewChanged ? 0 : UIViewAnimationOptionBeginFromCurrentState) | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         _isAnimating = YES;
                         scaleTransform_ = CGAffineTransformIdentity;
                         rotateTransform_ = CGAffineTransformIdentity;
                         panTransform_ = CGAffineTransformIdentity;
                         self.transform = CGAffineTransformIdentity;
                         CGRect windowBounds = [self windowBounds];
                         if (bounces) {
                             [self setFrame:CGRectMake(windowBounds.origin.x - kPSFullscreenAnimationBounce, windowBounds.origin.y - kPSFullscreenAnimationBounce, windowBounds.size.width + kPSFullscreenAnimationBounce*2, windowBounds.size.height + kPSFullscreenAnimationBounce*2)];
                         }else {
                             [self setFrame:windowBounds];
                         }
                     }
                     completion:^(BOOL finished) {                         
                         if (bounces && finished) {
                             CGRect windowBounds = [self windowBounds];
                             [self detachViewToWindow:YES];
                             [UIView animateWithDuration:kPSAnimationDuration delay:0.f options:UIViewAnimationOptionAllowUserInteraction animations:^{
                                 [self setFrame:windowBounds];
                             } completion:^(BOOL finished) {
                                 _isAnimating = NO;
                                 if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewDidAnimateToFullscreenWindowFrame:)]) {
                                     [self.pushPopPressViewDelegate pushPopPressViewDidAnimateToFullscreenWindowFrame: self];
                                 }
                                 anchorPointUpdated = NO;
                             }];
                         }else {
                             _isAnimating = NO;
                             if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewDidAnimateToFullscreenWindowFrame:)]) {
                                 [self.pushPopPressViewDelegate pushPopPressViewDidAnimateToFullscreenWindowFrame: self];
                             }
                             anchorPointUpdated = NO;
                         }
                     }];
}

- (void)alignViewAnimated:(BOOL)animated bounces:(BOOL)bounces {
    if (self.frame.size.width > [self windowBounds].size.width) {
        [self moveToFullscreenAnimated:animated bounces:bounces];
    } else {
        [self moveViewToOriginalPositionAnimated:animated bounces:bounces];
    }
}

// disrupt gesture recognizer, which continues to receive touch events even as we set minimumNumberOfTouches to two.
- (void)resetGestureRecognizers {
    for(UIGestureRecognizer *aGestRec in [self gestureRecognizers]){
        [aGestRec setEnabled:NO];
        [aGestRec setEnabled:YES];
    }
    
}

- (void)startedGesture:(UIGestureRecognizer *)gesture {
    [self detachViewToWindow:YES];
    UIPinchGestureRecognizer *pinch = [gesture isKindOfClass:[UIPinchGestureRecognizer class]] ? (UIPinchGestureRecognizer *)gesture : nil;
    gesturesEnded_ = NO;
    if (pinch) {
        scaleActive_ = YES;
    }
}

/*
 When one gesture ends, the whole view manipulation is ended. In case the user also started a pinch and the pinch is still active, we wait for the pinch to finish as we want to check for a fast pinch movement to open the view in fullscreen or not. If no pinch is active, we can end the manipulation as soon as the first gesture ended.
 */
- (void)endedGesture:(UIGestureRecognizer *)gesture {
    if (gesturesEnded_) return;

    UIPinchGestureRecognizer *pinch = [gesture isKindOfClass:[UIPinchGestureRecognizer class]] ? (UIPinchGestureRecognizer *)gesture : nil;
    if (scaleActive_ == YES && pinch == nil) return;

    gesturesEnded_ = YES;
    if (pinch) {
        scaleActive_ = NO;
        
        BOOL allowsFullScreenZooming = NO;
        if([self.pushPopPressViewDelegate respondsToSelector:@selector(pushPopPressViewShouldAllowFullScreenZooming:)])
            allowsFullScreenZooming = [self.pushPopPressViewDelegate pushPopPressViewShouldAllowFullScreenZooming:self];
        
        if(allowsFullScreenZooming && self.isFullscreen)
        {
            BOOL isScaleSmallerThanFullScreen = sqrt(pow(scaleTransform_.a, 2) + pow(scaleTransform_.c, 2)) < 1;
            if(isScaleSmallerThanFullScreen)
            {
                if(wasPinned_)
                {
                    [self moveToFullscreenAnimated:YES bounces:YES];
                    _previousPanTransform = CGAffineTransformIdentity;
                    _previousRotateTransform = CGAffineTransformIdentity;
                    _previousScaleTransform = CGAffineTransformIdentity;
                    wasPinned_ = NO;
                }
                else
                {
                    [self moveViewToOriginalPositionAnimated:YES bounces:YES];
                }
            }
            else
            {
                _previousPanTransform = panTransform_;
                _previousRotateTransform = rotateTransform_;
                _previousScaleTransform = scaleTransform_;
                wasPinned_ = YES;
            }
        }
        else
        {
            if (pinch.velocity >= 2.0f) {
                [self moveToFullscreenAnimated:YES bounces:YES];
            } else {
                [self alignViewAnimated:YES bounces:YES];
            }
        }
    } else {
        [self alignViewAnimated:YES bounces:YES];
    }
}

- (void)modifiedGesture:(UIGestureRecognizer *)gesture {
    if ([gesture isKindOfClass:[UIPinchGestureRecognizer class]]) {
        UIPinchGestureRecognizer *pinch = (UIPinchGestureRecognizer *)gesture;
        scaleTransform_ = CGAffineTransformScale(_previousScaleTransform, pinch.scale, pinch.scale);
    }
    else if ([gesture isKindOfClass:[UIRotationGestureRecognizer class]]) {
        UIRotationGestureRecognizer *rotate = (UIRotationGestureRecognizer *)gesture;
        rotateTransform_ = CGAffineTransformRotate(_previousRotateTransform, rotate.rotation);
    }
    else if ([gesture isKindOfClass:[UIPanGestureRecognizer class]]) {
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gesture;
        CGPoint translation = [pan translationInView: self.superview];
        panTransform_ = CGAffineTransformTranslate(_previousPanTransform, translation.x, translation.y);
    }

    BOOL shouldDisableTransformations = NO;
    if([self.pushPopPressViewDelegate respondsToSelector:@selector(pushPopPressViewShouldDisableTransformations:)]) {
        shouldDisableTransformations = [self.pushPopPressViewDelegate pushPopPressViewShouldDisableTransformations:self];
    }
    
    if(!shouldDisableTransformations)
        self.transform = CGAffineTransformConcat(CGAffineTransformConcat(scaleTransform_, rotateTransform_), panTransform_);
}

// scale and rotation transforms are applied relative to the layer's anchor point
// this method moves a gesture recognizer's view's anchor point between the user's fingers
- (void)adjustAnchorPointForGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    if (!anchorPointUpdated) {
        UIView *piece = gestureRecognizer.view;
        CGPoint locationInView = [gestureRecognizer locationInView:piece];
        CGPoint locationInSuperview = [gestureRecognizer locationInView:piece.superview];

        piece.layer.anchorPoint = CGPointMake(locationInView.x / piece.bounds.size.width, locationInView.y / piece.bounds.size.height);
        piece.center = locationInSuperview;
        anchorPointUpdated = YES; 
    }
}

- (void)pinchPanRotate:(UIGestureRecognizer *)gesture {
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            [self adjustAnchorPointForGestureRecognizer:gesture];
            [self startedGesture:gesture];
            break; 
        }
        case UIGestureRecognizerStatePossible: { 
            break;
        }
        case UIGestureRecognizerStateCancelled: {
            [self endedGesture:gesture];
            anchorPointUpdated = NO;
            break;
        } 
        case UIGestureRecognizerStateFailed: { 
            anchorPointUpdated = NO;
            break; 
        } 
        case UIGestureRecognizerStateChanged: {
            [self modifiedGesture:gesture];
            break;
        }
        case UIGestureRecognizerStateEnded: {
            anchorPointUpdated = NO;
            [self endedGesture:gesture];
            break;
        }
    }
}

- (void)doubleTapped:(UITapGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            break;
        }
        case UIGestureRecognizerStatePossible: {
            break;
        }
        case UIGestureRecognizerStateCancelled: {
            self.beingDragged = NO;
            [self resetGestureRecognizers];
            if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewDidFinishManipulation:)]) {
                [self.pushPopPressViewDelegate pushPopPressViewDidFinishManipulation:self];
            }
            break;
        }
        case UIGestureRecognizerStateFailed: {
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (NO == self.beingDragged) {
                if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewDidStartManipulation:)]) {
                    [self.pushPopPressViewDelegate pushPopPressViewDidStartManipulation:self];
                }
            }
            self.beingDragged = YES;
            break;
        }
        case UIGestureRecognizerStateEnded: {
            [self resetGestureRecognizers];
            if (self.beingDragged) {
                if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewDidFinishManipulation:)]) {
                    [self.pushPopPressViewDelegate pushPopPressViewDidFinishManipulation:self];
                }
            }
            self.beingDragged = NO;
            break;
        }
    }
}

- (void)tap:(UITapGestureRecognizer *)tap {
    if (self.allowSingleTapSwitch) {
        if (tap.state == UIGestureRecognizerStateEnded) {
            if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewDidReceiveTap:)]) {
                [self.pushPopPressViewDelegate pushPopPressViewDidReceiveTap: self];
            }

             if (!self.isFullscreen) {
                if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewShouldAllowTapToAnimateToFullscreenWindowFrame:)]) {
                    if ([self.pushPopPressViewDelegate pushPopPressViewShouldAllowTapToAnimateToFullscreenWindowFrame: self] == NO) return;
                }

                [self moveToFullscreenWindowAnimated:YES];
            } else {
                
                BOOL didZoomAndPinViewInFullScreen = !CGAffineTransformIsIdentity(CGAffineTransformConcat(_previousPanTransform, CGAffineTransformConcat(_previousRotateTransform, _previousScaleTransform)));
                if(didZoomAndPinViewInFullScreen)
                {
                    [self moveToFullscreenAnimated:YES bounces:YES];
                    _previousPanTransform = CGAffineTransformIdentity;
                    _previousRotateTransform = CGAffineTransformIdentity;
                    _previousScaleTransform = CGAffineTransformIdentity;
                    wasPinned_ = NO;
                    return;
                }
                
                if ([self.pushPopPressViewDelegate respondsToSelector: @selector(pushPopPressViewShouldAllowTapToAnimateToOriginalFrame:)]) {
                    if ([self.pushPopPressViewDelegate pushPopPressViewShouldAllowTapToAnimateToOriginalFrame: self] == NO) return;
                }

                [self moveToOriginalFrameAnimated:YES];
            }
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // if the gesture recognizers's view isn't one of our pieces, don't allow simultaneous recognition
    if (gestureRecognizer.view != self)
        return NO;

    // if the gesture recognizers are on different views, don't allow simultaneous recognition
    if (gestureRecognizer.view != otherGestureRecognizer.view)
        return NO;

    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] && [touch.view isKindOfClass: [UIButton class]]) {
        return NO;
    }
    
    BOOL allowsManipulation = YES;
    if([self.pushPopPressViewDelegate respondsToSelector:@selector(pushPopPressViewShouldAllowManipulation:)])
        allowsManipulation = [self.pushPopPressViewDelegate pushPopPressViewShouldAllowManipulation:self];
    
    if (![gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] && !allowsManipulation)
        return NO;
    
    return YES;
}

- (void)moveToFullscreenWindowAnimated:(BOOL)animated bounces:(BOOL)bounces {
    if (self.isFullscreen) return;
    
    [self moveToFullscreenAnimated:animated bounces:bounces];
}

- (void)moveToOriginalFrameAnimated:(BOOL)animated bounces:(BOOL)bounces {
    if (self.isFullscreen == NO) return;
    
    [self moveViewToOriginalPositionAnimated:animated bounces:bounces];
}

- (void)moveToFullscreenWindowAnimated:(BOOL)animated {
    if (self.isFullscreen) return;

    [self moveToFullscreenAnimated:animated bounces:YES];
}

- (void)moveToOriginalFrameAnimated:(BOOL)animated {
    if (self.isFullscreen == NO) return;

    [self moveViewToOriginalPositionAnimated:animated bounces:YES];
}

// enable/disable single tap detection
- (void)setAllowSingleTapSwitch:(BOOL)allowSingleTapSwitch {
    if (allowSingleTapSwitch_ != allowSingleTapSwitch) {
        allowSingleTapSwitch_ = allowSingleTapSwitch;
        tapRecognizer_.enabled = allowSingleTapSwitch;
    }
}

@end
