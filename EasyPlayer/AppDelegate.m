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
    
    int err = EasyRTSP_Activate("6D75724D7A502B32734B7941725370636F3956524576464659584E355547786865575679556C525455495258444661672F704C2B4947566863336B3D");
    NSLog(@"---->>>  %d", err);
    
    [[UINavigationBar appearance] setBarTintColor:MAIN_COLOR];
    NSDictionary *dic2 = [NSDictionary dictionaryWithObject:[UIColor whiteColor] forKey:NSForegroundColorAttributeName];
    [[UINavigationBar appearance] setTitleTextAttributes:dic2];
    [[UINavigationBar appearance] setTintColor:[UIColor whiteColor]];
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen]bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[RootViewController alloc] init]];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    
    NSString *pname = [[NSProcessInfo processInfo] processName];
    NSLog(@"----->>>>  %@", pname);
    
    return YES;
}

@end
