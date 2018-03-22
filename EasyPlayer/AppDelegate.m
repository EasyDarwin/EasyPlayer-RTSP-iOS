//
//  AppDelegate.m
//  EasyPlayer
//
//  Created by tsinglink on 2017/11/14.
//  Copyright © 2017年 cs. All rights reserved.
//

#import "AppDelegate.h"
#import "RtspDataReader.h"
#import "RootViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [RtspDataReader startUp];
    
    int err = EasyRTSP_Activate(
"79393674362F2B32734B794157484A617059326D792F564659584E3555477868655756796846634D5671442F532B424859585A7062695A4359574A76633246414D6A41784E6B566863336C4559584A33615735555A5746745A57467A65513D3D");
    NSLog(@"---->>>  %d", err);
    
    [[UINavigationBar appearance] setBarTintColor:MAIN_COLOR];
    NSDictionary *dic2 = [NSDictionary dictionaryWithObject:[UIColor whiteColor] forKey:NSForegroundColorAttributeName];
    [[UINavigationBar appearance] setTitleTextAttributes:dic2];
    [[UINavigationBar appearance] setTintColor:[UIColor whiteColor]];
    
    self.window = [[UIWindow alloc]initWithFrame:[[UIScreen mainScreen]bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[RootViewController alloc]init]];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    
//    NSString *pname = [[NSProcessInfo processInfo] processName];
//    NSLog(@"----->>>>  %@", pname);
    
    return YES;
}

@end
