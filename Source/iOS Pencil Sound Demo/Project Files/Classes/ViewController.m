//
//  ViewController.m
//  iOS Pencil Sound Demo
//
//  Created by Nicolás Miari on 4/14/14.
//  Copyright (c) 2014 Nicolas Miari. All rights reserved.
//

#import "ViewController.h"
#import "TestScene.h"


// .............................................................................

@implementation ViewController
{
    
}


// .............................................................................

- (void) viewDidLoad
{
    [super viewDidLoad];

    // Configure the view.
    SKView* skView = (SKView*) [self view];
    
    //[skView setShowsFPS:YES];
    //[skView setShowsNodeCount:YES];
    
    // Create and configure the scene.
    SKScene* scene = [TestScene sceneWithSize:skView.bounds.size];

    [scene setScaleMode:SKSceneScaleModeAspectFill];
    
    
    // Present the scene.
    [skView presentScene:scene];
}

// .............................................................................

- (BOOL) shouldAutorotate
{
    return YES;
}

// .............................................................................

- (NSUInteger) supportedInterfaceOrientations
{
    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone){
        
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    else{
        return UIInterfaceOrientationMaskAll;
    }
}

// .............................................................................

- (void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

// .............................................................................

@end
