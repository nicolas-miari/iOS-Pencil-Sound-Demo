/*
    SoundManager.m
    iOS Pencil Sound Demo

    Created by Nicolás Miari on 4/14/14.

    Copyright (c) Nicolás Miari. All rights reserved.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
*/
@import AVFoundation;               // Core Audio

#import "SoundManager.h"            // Own header


// .............................................................................

#define kMaxConcurrentSounds        1u


// .............................................................................

static Boolean                          initializedAudioSession  = false;
static Boolean                          initializedAudioGraph    = false;

static AUGraph                          processingGraph;			// Graph instance

static double                           graphSampleRate;

static NSTimeInterval                   ioBufferDuration;

static AURenderCallbackStruct           inputCallbackStructArray[kMaxConcurrentSounds];

static AUNode                           mixerNode;                  // Mixer node (source)
static AUNode                           converterNode0;             // Stream converter (mixer -> bandpass)
static AUNode                           bandpassNode;               // Bandpass filter node
static AUNode                           converterNode1;             // Stream converter (bandpass -> I/O)
static AUNode                           remoteIONode;               // I/O node (output)

static AudioUnit                        mixerUnit;
static AudioUnit                        converterUnit0;
static AudioUnit                        bandpassUnit;
static AudioUnit                        converterUnit1;
static AudioUnit                        remoteIOUnit;

static AudioStreamBasicDescription      stereoStreamFormat;
static AudioStreamBasicDescription      monoStreamFormat;


// .............................................................................
// C function prototypes (forward declarations)


static OSStatus noiseRenderCallback(void*                         inRefCon,
                                    AudioUnitRenderActionFlags*   ioActionFlags,
                                    const AudioTimeStamp*         inTimeStamp,
                                    UInt32                        inBusNumber,
                                    UInt32                        inNumberFrames,
                                    AudioBufferList*			  ioData );

void setMixerInputBusGain(AudioUnitElement busNumber, Float32 gain);

void setMixerOutputGain(Float32 gain);

void setMixerInputBusEnabled(AudioUnitElement busNumber, Boolean enabled);

Boolean initializeAudioSession(void);

Boolean initializeAudioProcessingGraph(void);


// .............................................................................
// C Function definitions

static OSStatus noiseRenderCallback (void*                         inRefCon,
                                     AudioUnitRenderActionFlags*   ioActionFlags,
                                     const AudioTimeStamp*         inTimeStamp,
                                     UInt32                        inBusNumber,
                                     UInt32                        inNumberFrames,
                                     AudioBufferList*			   ioData )
{
	// Called on every mixer bus every time the system needs more audio data
    //  to play (buffers).
    
	static AudioUnitSampleType* outSamplesChannelLeft;
	static AudioUnitSampleType* outSamplesChannelRight;
	
	outSamplesChannelLeft  = (AudioUnitSampleType*) ioData->mBuffers[0].mData;
	outSamplesChannelRight = (AudioUnitSampleType*) ioData->mBuffers[1].mData;
	
    
    for(UInt32 frameNumber = 0; frameNumber < inNumberFrames; ++frameNumber){
        
        // Just provide a random number for the sample on each channel:
        // (white noise)
        
        outSamplesChannelLeft [frameNumber] = (int)random();
        outSamplesChannelRight[frameNumber] = (int)random();
    }
    
	return noErr;
}

// .............................................................................

void setMixerInputBusGain(AudioUnitElement busNumber, Float32 gain)
{
    // Sets the gain (volume) for a specified mixer bus (track)
    
    OSStatus result = AudioUnitSetParameter (mixerUnit,
											 kMultiChannelMixerParam_Volume,
											 kAudioUnitScope_Input,
											 busNumber,
											 gain,
											 0);
    
    if (result != noErr) {
        NSLog(@"Failed to set mixer bus no. %lu gain to %f", (unsigned long)busNumber, gain);
    }
}

// .............................................................................

void setMixerOutputGain(Float32 gain)
{
    // Sets the gain (volume) for the mixer's output (master)
    
    OSStatus result = AudioUnitSetParameter (mixerUnit,
											 kMultiChannelMixerParam_Volume,
											 kAudioUnitScope_Output,
											 0,
											 gain,
											 0);
    
    if (result != noErr) {
        NSLog(@"Failed to set mixer output gain to %f", gain);
    }
}

// .............................................................................

void setMixerInputBusEnabled(AudioUnitElement busNumber, Boolean enabled)
{
    OSStatus result;
	
	result = AudioUnitSetParameter(mixerUnit,
								   kMultiChannelMixerParam_Enable,
								   kAudioUnitScope_Input,
								   (AudioUnitElement) busNumber,
								   (enabled ? 1 : 0),
								   0);
	if (result != noErr) {
		NSLog(@"Failed to %@ mixer bus number %lu", enabled ? @"enable" : @"disable", (unsigned long)busNumber);
	}
}

// .............................................................................

Boolean initializeAudioSession(void)
{
    if (initializedAudioSession == true) {
        
        // (avoid multiple initialization)
        return true;
    }
    
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // 1. Setup audio session proper
    
    
    AVAudioSession* session = [AVAudioSession sharedInstance];
    
    NSError* audioSessionError = nil;
    
    
    // Sample rate
    
    graphSampleRate = 44100.0; // [Hertz]
    
    [session setPreferredSampleRate:graphSampleRate error:&audioSessionError];

    if (audioSessionError) {
        NSLog(@"Error Setting Audio Session Preferred Hardware Smple Rate");
        return false;
    }
    
    // Get actual sample rate (might be different than what we requested)
    graphSampleRate = [session sampleRate];
    
    
    // Category
    
    [session setCategory:AVAudioSessionCategoryAmbient error:&audioSessionError];

    if (audioSessionError) {
        NSLog(@"Error Setting Audio Session Category");
        return false;
    }
    
    [session setActive:YES error:&audioSessionError];
    
    if (audioSessionError) {
        NSLog(@"Error Setting Audio Session Active");
        return false;
    }
    
    
    // IO buffer duration
    
    ioBufferDuration = 0.005;	// 5ms (= 256 samples @44.1 kHz)
    // -> default is 23ms (= 1024 Samples @ 44.1 kHz)
    
    [session setPreferredIOBufferDuration:(Float32)ioBufferDuration error:&audioSessionError];
    
    if (audioSessionError) {
        NSLog(@"Error Setting Audio Session Preferred IO Buffer Duration");
        return false;
    }
    
    // Get actual buffer duration (might be different than what we requested)
    ioBufferDuration = [session IOBufferDuration];
    
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // 2. Setup Stream Formats
    
    /* (must be done right after audio session, because it depends
         on sample rate)
     */
    
    
    /* The AudioUnitSampleType data type is the recommended type for sample data
     in audio units. This obtains the byte size of the type for use in
     filling-in the ASBD.
     */
    size_t bytesPerSample = sizeof (AudioUnitSampleType);
    
    
    // Fill the application audio format struct's fields to define a linear PCM,
    //  stereo, noninterleaved stream at the hardware sample rate.
    stereoStreamFormat.mFormatID          = kAudioFormatLinearPCM;              // Pulse-Code-Modulation
    stereoStreamFormat.mFormatFlags       = kAudioFormatFlagsAudioUnitCanonical;
    stereoStreamFormat.mBytesPerPacket    = (uint32_t) bytesPerSample;
    stereoStreamFormat.mFramesPerPacket   = 1;
    stereoStreamFormat.mBytesPerFrame     = (uint32_t) bytesPerSample;
    stereoStreamFormat.mChannelsPerFrame  = 2;                                  // 1:mono; 2:stereo
    stereoStreamFormat.mBitsPerChannel    = (uint32_t) (8*bytesPerSample);
    stereoStreamFormat.mSampleRate        = graphSampleRate;
    
    // Same for monoaural:
    monoStreamFormat.mFormatID            = kAudioFormatLinearPCM;
    monoStreamFormat.mFormatFlags         = kAudioFormatFlagsAudioUnitCanonical;
    monoStreamFormat.mBytesPerPacket      = (uint32_t) bytesPerSample;
    monoStreamFormat.mFramesPerPacket     = 1;
    monoStreamFormat.mBytesPerFrame       = (uint32_t) bytesPerSample;
    monoStreamFormat.mChannelsPerFrame    = 1;                                  // 1:mono; 2:stereo
    monoStreamFormat.mBitsPerChannel      = (uint32_t) (8 * bytesPerSample);
    monoStreamFormat.mSampleRate          = graphSampleRate;
    
    
    initializedAudioSession = true;
    
    return true;
}

// .............................................................................

Boolean initializeAudioProcessingGraph(void)
{
    OSStatus result = NewAUGraph(&processingGraph);
    
    
    // 1. Create graph object
    
    if (result != noErr) {
        NSLog(@"NewAUGraph() failed.");
        return false;
    }
    
    
    
    // 2. Add a node to the graph for each audio unit (add them in sound flow
    //     order, for easier reading of debug logs)
    
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // Multichannel Mixer Unit
    
    AudioComponentDescription mixerUnitDescription = { 0 };
    
    mixerUnitDescription.componentType         = kAudioUnitType_Mixer;
    mixerUnitDescription.componentSubType      = kAudioUnitSubType_MultiChannelMixer;
    mixerUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    mixerUnitDescription.componentFlags		   = 0;
    mixerUnitDescription.componentFlagsMask    = 0;
    
    result = AUGraphAddNode(processingGraph, &mixerUnitDescription, &mixerNode);

    if (result != noErr) {
        NSLog(@"AUGraphNewNode() failed for multichannel mixer");
        return false;
    }
    
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // Converter unit 0
    
    AudioComponentDescription converterUnitDescription = { 0 };
    
    converterUnitDescription.componentType          = kAudioUnitType_FormatConverter;
    converterUnitDescription.componentSubType       = kAudioUnitSubType_AUConverter;
    converterUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    converterUnitDescription.componentFlags         = 0;
    converterUnitDescription.componentFlagsMask     = 0;
    
    result = AUGraphAddNode(processingGraph, &converterUnitDescription, &converterNode0);

    if (result != noErr) {
        NSLog(@"AUGraphNewNode() failed for converter unit 0");
        return false;
    }
    
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // Bandpass Filter Unit
    
    AudioComponentDescription bandpassFilterUnitDescription = { 0 };
    
    bandpassFilterUnitDescription.componentType         = kAudioUnitType_Effect;
    bandpassFilterUnitDescription.componentSubType      = kAudioUnitSubType_BandPassFilter;
    bandpassFilterUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    bandpassFilterUnitDescription.componentFlags        = 0;
    bandpassFilterUnitDescription.componentFlagsMask    = 0;
    
    result = AUGraphAddNode(processingGraph, &bandpassFilterUnitDescription, &bandpassNode);
    
    if (result != noErr) {
        NSLog(@"AUGraphNewNode() failed for bandpass unit");
        return false;
    }
    
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // Converter unit 1
    
    // (AudioComponentDescription already setup; reuse it)
    
    result = AUGraphAddNode(processingGraph, &converterUnitDescription, &converterNode1);
    
    if (result != noErr) {
        NSLog(@"AUGraphNewNode() failed for converter unit 1");
        return false;
    }
    
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // Remote I/O Unit
    
    AudioComponentDescription ioUnitDescription = { 0 };
    
    ioUnitDescription.componentType         = kAudioUnitType_Output;
    ioUnitDescription.componentSubType      = kAudioUnitSubType_RemoteIO;
    ioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags	    = 0;
    ioUnitDescription.componentFlagsMask    = 0;
    
    result = AUGraphAddNode(processingGraph, &ioUnitDescription, &remoteIONode);
    
    if (result != noErr) {
        NSLog(@"AUGraphNewNode() failed for I/O unit");
        return false;
    }
    
    
    // .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .
    
    // Open the Audio Processing Graph and configure units
    
    
    result = AUGraphOpen(processingGraph);
    
    if (result != noErr) {
        NSLog(@"AUGraphOpen() failed.");
    }
    
    /* Following this call, the audio units are instantiated but not initialized
     (no resource allocation occurs and the audio units are not in a state to
     process audio). Now that the units are instantiated, we can tweak them
     */
    
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // Get audio unit instances from nodes
    
    // 1. Mixer
    result = AUGraphNodeInfo(processingGraph, mixerNode, NULL, &mixerUnit);
    
    if ( result != noErr ){
        NSLog(@"AUGraphNodeInfo() failed.");
        return false;
    }
    
    // 2. Converter0 (mixer -> bandpass filer)
    result = AUGraphNodeInfo(processingGraph, converterNode0, NULL, &converterUnit0);
    
    if ( result != noErr ){
        NSLog(@"AUGraphNodeInfo() failed.");
        return false;
    }
    
    // 3. Bandpass filter
    result = AUGraphNodeInfo(processingGraph, bandpassNode, NULL, &bandpassUnit);
    
    if ( result != noErr ){
        NSLog(@"AUGraphNodeInfo() failed.");
        return false;
    }
    
    // 4. Converter1 (bandpass filter -> remote i/o)
    result = AUGraphNodeInfo(processingGraph, converterNode1, NULL, &converterUnit1);
    
    if ( result != noErr ){
        NSLog(@"AUGraphNodeInfo() failed.");
        return false;
    }
    
    // 5. Remote I/O
    result = AUGraphNodeInfo(processingGraph, remoteIONode, NULL, &remoteIOUnit);
    
    if ( result != noErr ){
        NSLog(@"AUGraphNodeInfo() failed.");
        return false;
    }
    
    
    // Configure each audio unit...
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // Multichannel mixer
    
    
    UInt32 mixerBusCount = 1;
    
    result = AudioUnitSetProperty(mixerUnit,
                                  kAudioUnitProperty_ElementCount,
                                  kAudioUnitScope_Input,
                                  0,
                                  &mixerBusCount,
                                  sizeof(mixerBusCount));
    
    if (result != noErr){ NSLog(@"AudioUnitSetProperty (set mixer unit bus count) failed."); }
    
    
    // Increase the maximum frames per slice allows the mixer unit to
    //  accommodate the larger slice size used when the screen is locked.
    
    UInt32 maximumFramesPerSlice = 4096u;
    
    result = AudioUnitSetProperty(mixerUnit,
                                  kAudioUnitProperty_MaximumFramesPerSlice,
                                  kAudioUnitScope_Global,
                                  0,
                                  &maximumFramesPerSlice,
                                  sizeof(maximumFramesPerSlice));
    
    if (result != noErr) {
        NSLog(@"AudioUnitSetProperty() failed to set mixer unit input stream format");
        return false;
    }
    
    
    // Configure all buses
    
    for (UInt32 busNumber = 0; busNumber < mixerBusCount; busNumber++) {
        
        // Start with all buses muted and disabled:
        
        setMixerInputBusGain(busNumber, 0.0f);
        setMixerInputBusEnabled(busNumber, false);
        
        
        // Attach the input render callback and context
        
        inputCallbackStructArray[busNumber].inputProc       = &noiseRenderCallback;
        inputCallbackStructArray[busNumber].inputProcRefCon = NULL;
        
        
        result = AUGraphSetNodeInputCallback(processingGraph,
                                             mixerNode,
                                             busNumber,
                                             &inputCallbackStructArray[busNumber]);
        
        if (result != noErr) {
            NSLog(@"AUGraphSetNodeInputCallback() failed for bus no. %u", (unsigned int)busNumber);
            return false;
        }
        
        
        //	Set All Buses to Stereo. (for monoaural files, copy the only channel
        //  into both L and R buffers)
        
        result = AudioUnitSetProperty (mixerUnit,
                                       kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input,
                                       busNumber,
                                       &stereoStreamFormat,
                                       sizeof (stereoStreamFormat));
        
        if ( result != noErr ){
            NSLog(@"AudioUnitSetProperty (set mixer unit input bus stream format) failed.");
            return false;
        }
    }
    
    
    // Set the mixer unit's output sample rate format. This is the only aspect
    //  of the output stream format that must be explicitly set.
    
    result = AudioUnitSetProperty (mixerUnit,
                                   kAudioUnitProperty_SampleRate,
                                   kAudioUnitScope_Output,
                                   0,
                                   &graphSampleRate,
                                   sizeof (graphSampleRate));
    
    if ( result != noErr ){
        NSLog(@"AudioUnitSetProperty (set mixer unit output stream format) failed.");
        return false;
    }
    
    
    // . .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..
    // Bandpass filter
    
    // Properties
    
    result = AudioUnitSetProperty (bandpassUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input,
                                   0,                           // "in element"?
                                   &stereoStreamFormat,
                                   sizeof (stereoStreamFormat));
    
    result = AudioUnitSetProperty (bandpassUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Output,
                                   0,                           // "in element"?
                                   &stereoStreamFormat,
                                   sizeof (stereoStreamFormat));
    
    result = AudioUnitSetProperty(bandpassUnit,
                                  kAudioUnitProperty_SampleRate,
                                  kAudioUnitScope_Input,
                                  0,
                                  &graphSampleRate,
                                  sizeof (graphSampleRate));
    
    // Parameters
    
    Float32 centerFrequency = 20.0f;  // [20, Nyquist)
    
    result = AudioUnitSetParameter(bandpassUnit,
                                   kBandpassParam_CenterFrequency,
                                   kAudioUnitScope_Global,
                                   0,
                                   centerFrequency,
                                   0);
    
    if ( result != noErr ){ NSLog(@"AudioUnitSetProperty (bandpass center freq) failed."); }
    
    
    Float32 bandwidth = 500.0f; // [100, 12000]
    
    result = AudioUnitSetParameter(bandpassUnit,
                                   kBandpassParam_Bandwidth,
                                   kAudioUnitScope_Global,
                                   0,
                                   bandwidth,
                                   0);
    
    if ( result != noErr ){ NSLog(@"AudioUnitSetProperty (bandpass bandwidth) failed."); }
    
    // Get filter's audio format, in order to
    //  setup both stream converters:
    
    AudioStreamBasicDescription filterAudioFormat = { 0 };
    UInt32 filterAudioFormatSize = sizeof(AudioStreamBasicDescription);
	
    
    result = AudioUnitGetProperty(bandpassUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Global,
                                  0,
                                  &filterAudioFormat,
                                  &filterAudioFormatSize);
    
    if ( result != noErr ){ NSLog(@"AudioUnitGetProperty (bandpass stream format) failed."); }
    
    
    
    result = AudioUnitSetProperty(converterUnit0,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &stereoStreamFormat,
                                  sizeof(stereoStreamFormat));
    
    result = AudioUnitSetProperty(converterUnit0,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &filterAudioFormat,
                                  sizeof(filterAudioFormat));
    
    
    result = AudioUnitSetProperty(converterUnit1,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &filterAudioFormat,
                                  sizeof(filterAudioFormat));
    
    result = AudioUnitSetProperty(converterUnit1,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &stereoStreamFormat,
                                  sizeof(stereoStreamFormat));
    
    
    
    // .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .
    // 3.3 Interconnect the Audio Unit Nodes
    
    
    // Connect mixer to converter0
    result = AUGraphConnectNodeInput(processingGraph,       // (in) graph
                                     mixerNode,             // (in) src node
                                     0,                     // (in) src output number
                                     converterNode0,        // (in) dst node
                                     0);                    // (in) dst input number
    if ( result != noErr ){
        NSLog(@"AUGraphConnectNodeInput() Failed for mixer->converter0");
    }
    
    
    // Connect converter0 to bandpass
    result = AUGraphConnectNodeInput(processingGraph,       // (in) graph
                                     converterNode0,        // (in) src node
                                     0,                     // (in) src output number
                                     bandpassNode,          // (in) dst node
                                     0);                    // (in) dst input number
    if ( result != noErr ){
        NSLog(@"AUGraphConnectNodeInput() Failed for converter0->bandpass");
    }
    
    
    // Connect bandpass to converter1
    result = AUGraphConnectNodeInput(processingGraph,       // (in) graph
                                     bandpassNode,          // (in) src node
                                     0,                     // (in) src output number
                                     converterNode1,        // (in) dst node
                                     0);                    // (in) dst input number
    if ( result != noErr ){
        NSLog(@"AUGraphConnectNodeInput() Failed for bandpass->converter1");
    }
    
    
    // Connect converter1 to i/o
    result = AUGraphConnectNodeInput(processingGraph,
                                     converterNode1,
                                     0,
                                     remoteIONode,
                                     0);
    if ( result != noErr ){
        NSLog(@"AUGraphConnectNodeInput() Failed for converter1->output");
    }
    
    
    // .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .. .
    // Finally, initialize audio graph
    
    result = AUGraphInitialize(processingGraph);
    
    if (result == noErr) {
        
        initializedAudioGraph = YES;
        
        return true;
    }
    else{
        NSLog(@"AUGraphInitialize() failed.");
        
        return false;
    }
}


// .............................................................................

@implementation SoundManager
{
    BOOL    _rendering;
}


// .............................................................................

+ (instancetype) defaultManager
{
    static id defaultInstance = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultInstance = [self new];
    });
    
    return defaultInstance;
}

// .............................................................................

#pragma mark - Initialization


- (instancetype) init
{
    if ((self = [super init])) {
        
        if(!initializeAudioSession()){
            return (self = nil);
        };
        
        if(!initializeAudioProcessingGraph()){
            return (self = nil);
        };
        
        if(AUGraphStart(processingGraph) != noErr){
            NSLog(@"Error Starting Graph!");
            
            return (self = nil);
        }
        
        [self registerNotifications];
    }
    
    return self;
}

// .............................................................................

- (void) registerNotifications
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    
    // UIApplication events:
    
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillResignActive:)
                               name:UIApplicationWillResignActiveNotification
                             object:nil];
    
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActive:)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
    
    
    // These replace/expand the AVAudioSessionDelegate (deprecated since iOS 6.0):
    
    [notificationCenter addObserver:self
                           selector:@selector(audioSessionInterruption:)
                               name:AVAudioSessionInterruptionNotification
                             object:nil];
    
    [notificationCenter addObserver:self
                           selector:@selector(audioSessionRouteChange:)
                               name:AVAudioSessionRouteChangeNotification
                             object:nil];
    
    [notificationCenter addObserver:self
                           selector:@selector(audioSessionMediaServicesWereLost:)
                               name:AVAudioSessionMediaServicesWereLostNotification
                             object:nil];
    
    [notificationCenter addObserver:self
                           selector:@selector(audioSessionMediaServicesWereReset:)
                               name:AVAudioSessionMediaServicesWereResetNotification
                             object:nil];
}

// .............................................................................

#pragma mark - Notification Handlers


- (void) applicationWillResignActive:(NSNotification*) notification
{
    [self pauseRender];
}

// .............................................................................

- (void) applicationDidBecomeActive:(NSNotification*) notification
{
    [self resumeRender];
}

// .............................................................................

- (void) audioSessionInterruption:(NSNotification*) notification
{
    /* See:
     https://developer.apple.com/library/ios/documentation/AVFoundation/Reference/AVAudioSession_ClassReference/Reference/Reference.html#//apple_ref/doc/uid/TP40008240-CH1-DontLinkElementID_3
     */
    
    NSLog (@"Audio session was interrupted.");
    
    
    if (_rendering) {
		
		// Stop Graph
		[self pauseRender];
	}
}

// .............................................................................

- (void) audioSessionRouteChange:(NSNotification*) notification
{
    // TODO: Implement.
    
    /* See:
     https://developer.apple.com/library/ios/documentation/AVFoundation/Reference/AVAudioSession_ClassReference/Reference/Reference.html#//apple_ref/doc/uid/TP40008240-CH1-DontLinkElementID_3
     */
    
    /*
    if ([self isPlaying] == NO) {
        return NSLog (@"Audio route change while application audio is stopped.");
    }
    */
    
    NSDictionary* userInfo = [notification userInfo];
    
    
    NSNumber* reasonObject = [userInfo objectForKey:AVAudioSessionRouteChangeReasonKey];
    NSUInteger reason = [reasonObject unsignedIntegerValue];
    
    switch (reason) {
        default:
        case AVAudioSessionRouteChangeReasonUnknown:
            NSLog(@"<> AVAudioSessionRouteChangeReasonUnknown <>");
            break;
            
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            NSLog(@"<> AVAudioSessionRouteChangeReasonNewDeviceAvailable <>");
            break;
            
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
        {
            NSLog(@"<> AVAudioSessionRouteChangeReasonOldDeviceUnavailable <>");
            
            /* "Old device unavailable" indicates that a headset or headphones
             were unplugged, or that the device was removed from a dock
             connector that supports audio output. In such a case, pause or
             stop audio (as advised by the iOS Human Interface Guidelines).
             */
            
            // TODO: Set gain to 0.0f
            
            AVAudioSessionRouteDescription* previousRoute;
            previousRoute = [userInfo objectForKey:AVAudioSessionRouteChangePreviousRouteKey];
            
            for (AVAudioSessionPortDescription* portDescription in [previousRoute outputs]) {
                if([[portDescription portType] isEqualToString:AVAudioSessionPortHeadphones]){
                    // User unplugged headphones;
                    
                    // TODO: Set gain to 0.0f, etc.
                }
            }
        }
            break;
            
        case AVAudioSessionRouteChangeReasonCategoryChange:
            NSLog(@"<> AVAudioSessionRouteChangeReasonCategoryChange <>");
            break;
            
        case AVAudioSessionRouteChangeReasonOverride:
            NSLog(@"<> AVAudioSessionRouteChangeReasonOverride <>");
            break;
            
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            NSLog(@"<> AVAudioSessionRouteChangeReasonWakeFromSleep <>");
            break;
            
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            NSLog(@"<> AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory <>");
            break;
            
        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
            NSLog(@"<> AVAudioSessionRouteChangeReasonRouteConfigurationChange <>");
            break;
    }
}

// .............................................................................

- (void) audioSessionMediaServicesWereLost:(NSNotification*) notifcation
{
    // TODO: Implement.
    
    /* See:
     https://developer.apple.com/library/ios/documentation/AVFoundation/Reference/AVAudioSession_ClassReference/Reference/Reference.html#//apple_ref/doc/uid/TP40008240-CH1-DontLinkElementID_3
     */
}

// .............................................................................

- (void) audioSessionMediaServicesWereReset:(NSNotification*) notification
{
    // TODO: Implement.
    
    /* See:
     https://developer.apple.com/library/ios/documentation/AVFoundation/Reference/AVAudioSession_ClassReference/Reference/Reference.html#//apple_ref/doc/uid/TP40008240-CH1-DontLinkElementID_3
     */
}

// .............................................................................

#pragma mark - Custom Property Accessors


- (void) setBandpassFilterCenterFrequency:(AudioUnitParameterValue) centerFrequency
{
    OSStatus result = AudioUnitSetParameter(bandpassUnit,
                                            kBandpassParam_CenterFrequency,
                                            kAudioUnitScope_Global,
                                            0,
                                            centerFrequency,
                                            0);
    if (result != noErr) {
        NSLog(@"AudioUnitSetParameter() failed for kBandpassParam_CenterFrequency");
    }
}

// .............................................................................

- (AudioUnitParameterValue) bandpassFilterCenterFrequency
{
    AudioUnitParameterValue centerFrequency;
    OSStatus result;
    
    result = AudioUnitGetParameter(bandpassUnit,
                                   kBandpassParam_CenterFrequency,
                                   kAudioUnitScope_Global,
                                   0,
                                   &centerFrequency);
    
    if (result != noErr) {
        NSLog(@"AudioUniGetParameter() failed for kBandpassParam_CenterFrequency");
    }
    
    return centerFrequency;
}

// .............................................................................

- (void) setBandpassFilterBandwidth:(AudioUnitParameterValue) bandwidth
{
    OSStatus result = AudioUnitSetParameter(bandpassUnit,
                                            kBandpassParam_Bandwidth,
                                            kAudioUnitScope_Global,
                                            0,
                                            bandwidth,
                                            0);
    if (result != noErr) {
        NSLog(@"AudioUnitSetParameter() failed for kBandpassParam_Bandwidth");
    }
}

// .............................................................................

- (AudioUnitParameterValue) bandpassFilterBandwidth
{
    AudioUnitParameterValue bandpassFilterBandwidth;
    OSStatus result;
    
    result = AudioUnitGetParameter(bandpassUnit,
                                   kBandpassParam_Bandwidth,
                                   kAudioUnitScope_Global,
                                   0,
                                   &bandpassFilterBandwidth);
    
    if (result != noErr) {
        NSLog(@"AudioUniGetParameter() failed for kBandpassParam_Bandwidth");
    }
    
    return bandpassFilterBandwidth;
}

// .............................................................................

#pragma mark - Operation


- (void) pauseRender
{
    Boolean  isRunning = NO;
    OSStatus result    = noErr;
    
    result = AUGraphIsRunning(processingGraph, &isRunning);
    
    if (result == noErr) {
        // Query succeeded
        
        if (isRunning == true) {
            
            result = AUGraphStop(processingGraph);
            
            if (result != noErr) {
                NSLog(@"AUGraphStop() Failed with code: %u", (int)result);
            }
            else{
                _rendering = NO;
            }
        }
    }
    else{
        // Query failed
        
        NSLog(@"AUGraphIsRunning() Failed with code: %u", (int)result);
    }
}

// .............................................................................

- (void) resumeRender
{
    Boolean  isRunning = NO;
    OSStatus result    = noErr;
    
    result = AUGraphIsRunning(processingGraph, &isRunning);
    
    if (result == noErr) {
        // Query succeeded
        
        if (isRunning == false) {
            
            result = AUGraphStart(processingGraph);
            
            if (result != noErr) {
                NSLog(@"AUGraphStart() Failed with code: %u", (int)result);
            }
            else{
                _rendering = YES;
            }
        }
    }
    else{
        // Query failed
        
        NSLog(@"AUGraphIsRunning() Failed with code: %u", (int)result);
    }
}

// .............................................................................

- (void) playNoise
{
    // Wraps the C function
    
    setMixerInputBusEnabled(0, true);
}

// .............................................................................

- (void) stopNoise
{
    // Wraps the C function
    
    setMixerInputBusEnabled(0, false);
}

// .............................................................................

- (void) setNoiseGain:(CGFloat) gain
{
    // Wraps the C function
    
    setMixerInputBusGain(0, (Float32) gain);
}

// .............................................................................

@end
