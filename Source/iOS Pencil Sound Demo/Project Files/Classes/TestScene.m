//
//  MyScene.m
//  iOS Pencil Sound Demo
//
//  Created by n.miari on 4/14/14.
//  Copyright (c) 2014 Nicolas Miari. All rights reserved.
//

#import "TestScene.h"

#import "SoundManager.h"


// .............................................................................

@implementation TestScene
{

    CFTimeInterval      _currentTime;
    CFTimeInterval      _dt;            // time since last frame
    
    UITouch*            _touch;
    
    BOOL                _dragging;
    CGPoint             _dragLastPosition;
    CFTimeInterval      _dragLastTime;
    CGFloat             _dragCurrentSpeed;
    
    CFTimeInterval      _lastTime;
    
    CFTimeInterval      _blinkCounter;
    
    BOOL                _dirty;
    
    BOOL                _transitioning;
    
    BOOL                _playingSound;
}

// .............................................................................

-(id) initWithSize:(CGSize) size
{
    if ((self = [super initWithSize:size])) {
        /* Setup your scene here */
        
        [self setBackgroundColor:[UIColor whiteColor]];
        
        SKLabelNode* myLabel = [SKLabelNode labelNodeWithFontNamed:@"Avenir"];
        
        [myLabel setText:@"(Drag Anywhere)"];
        [myLabel setFontSize:30.0f];
        [myLabel setFontColor:[UIColor darkGrayColor]];
        [myLabel setPosition:CGPointMake(CGRectGetMidX(self.frame), CGRectGetMidY(self.frame))];
        
        [self addChild:myLabel];
    }
    
    return self;
}

// .............................................................................

-(void) touchesBegan:(NSSet*) touches
           withEvent:(UIEvent*) event
{
    if (_touch) {
        // Single touch
        
        return;
    }
    
    
    _touch   = [touches anyObject];

    CGPoint location = [_touch locationInNode:self];
    
    
    _dragCurrentSpeed = 0.0f;
    _dragLastPosition = location;
    _dragLastTime     = _currentTime;
}

// .............................................................................

- (void) touchesMoved:(NSSet*) touches
            withEvent:(UIEvent*) event
{
    for (UITouch* touch in touches) {
        
        if (touch != _touch) {
            continue;
        }
        
        _dragging = YES;
        
        CGPoint dragNewPosition = [_touch locationInNode:self];
    
        CGPoint deltaDrag = CGPointMake(dragNewPosition.x - _dragLastPosition.x,
                                        dragNewPosition.y - _dragLastPosition.y);
        
        CGFloat dragLength = sqrtf((deltaDrag.x * deltaDrag.x) + (deltaDrag.y * deltaDrag.y));
        
        CFTimeInterval dragTime = _currentTime - _dragLastTime;
        
        CGFloat dragSpeed;
        
        if (dragTime > 0.001f) {
            dragSpeed = dragLength / dragTime;
        }
        else{
            dragSpeed = 0.0f;
        }
        
        
        _dragCurrentSpeed = 0.75*_dragCurrentSpeed + 0.25*dragSpeed;

        
        // Overwrite for next call:
        _dragLastPosition = dragNewPosition;
        _dragLastTime     = _currentTime;
        
        
        SoundManager* soundManager = [SoundManager defaultManager];
        
        if (!_playingSound) {
            // Not playing
            
            if (dragSpeed >= 10.0f) {
                
                [soundManager playNoise];
                
                [soundManager setNoiseGain:0.0f];
                
                _playingSound = YES;
            }
        }
        
        // Skip further touches
        return;
    }
}

// .............................................................................

- (void) touchesEnded:(NSSet*) touches
            withEvent:(UIEvent*) event
{
    for (UITouch* touch in touches) {
        if (touch != _touch) {
            continue;
        }
        
        _touch = nil;
        
        if (_playingSound) {
            
            [[SoundManager defaultManager] stopNoise];
            
            _playingSound = NO;
        }
    }
}

// .............................................................................

- (void) touchesCancelled:(NSSet*) touches
                withEvent:(UIEvent*) event
{
    [self touchesEnded:touches
             withEvent:event];
}

// .............................................................................

-(void) update:(CFTimeInterval) currentTime
{
    _currentTime = currentTime;
    
    if (_lastTime) {
        
        _dt = currentTime - _lastTime;
    }
    else{
        // First frame - fake deltaTime:
        
        _dt = 1.0f / 60.0f;
    }
    
    _lastTime = currentTime;

    
    if (_playingSound && _dragging) {
        
        SoundManager* soundManager = [SoundManager defaultManager];
        
        CGFloat gain = _dragCurrentSpeed/20000.0;
        
        if (gain > 0.25f) {
            gain = 0.25f;
        }
        
        [soundManager setNoiseGain:gain];
        [soundManager setBandpassFilterBandwidth:400.0f];
        [soundManager setBandpassFilterCenterFrequency:2700.0f + gain*20500.0f];
        
        
        // Fade out speed
        _dragCurrentSpeed *= 0.5f;
    }
}

@end
