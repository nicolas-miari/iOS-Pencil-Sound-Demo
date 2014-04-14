//
//  SoundManager.h
//  iOS Pencil Sound Demo
//
//  Created by Nicolás Miari on 4/14/14.
//  Copyright (c) 2014 Nicolas Miari. All rights reserved.
//

@import AudioUnit;

@interface SoundManager : NSObject

///
@property (nonatomic, readwrite) AudioUnitParameterValue bandpassFilterCenterFrequency;

///
@property (nonatomic, readwrite) AudioUnitParameterValue bandpassFilterBandwidth;


/*!
 */
+ (instancetype) defaultManager;


/*!
 */
- (void) playNoise;


/*!
 */
- (void) stopNoise;

/*!
 */
- (void) setNoiseGain:(CGFloat) gain;

@end
