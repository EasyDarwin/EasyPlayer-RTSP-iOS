//
//  AppDelegate.m
//  EasyPlayer
//
//  Created by tsinglink on 2017/11/14.
//  Copyright © 2017年 cs. All rights reserved.
//

#import "AppDelegate.h"
#import "PlayerDataReader.h"
#import "RootViewController.h"
#import "NSUserDefaultsUnit.h"
#import "URLUnit.h"

#import <RTRootNavigationController/RTRootNavigationController.h>
#import <IQKeyboardManager/IQKeyboardManager.h>
#import <Bugly/Bugly.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    if ([URLUnit urlModels].count == 0) {
        URLModel *model = [[URLModel alloc] initDefault];
        model.url = EasyDefaultRTSPURL;
        [URLUnit addURLModel:model];
        
        [NSUserDefaultsUnit setFFMpeg:YES];     // 默认软解码
        [NSUserDefaultsUnit setAutoAudio:YES];  // 默认自动播放音频
    }
    
    [PlayerDataReader startUp];
    
    int days = EasyRTSP_Activate("EasyPlayer key is free!");
    NSLog(@"key有效期：%d", days);
    [NSUserDefaultsUnit setActiveDay:days];
    
    // Bugly
    [Bugly startWithAppId:@"8a4c2e394d"];
    
    // IQKeyboardManager
    IQKeyboardManager *keyboardManager = [IQKeyboardManager sharedManager]; // 获取类库的单例变量
    keyboardManager.enable = YES; // 控制整个功能是否启用
    keyboardManager.shouldResignOnTouchOutside = YES; // 控制点击背景是否收起键盘
    keyboardManager.shouldToolbarUsesTextFieldTintColor = YES; // 控制键盘上的工具条文字颜色是否用户自定义
//    keyboardManager.toolbarManageBehavior = IQAutoToolbarBySubviews; // 有多个输入框时，可以通过点击Toolbar 上的“前一个”“后一个”按钮来实现移动到不同的输入框
    keyboardManager.enableAutoToolbar = YES; // 控制是否显示键盘上的工具条
    keyboardManager.toolbarDoneBarButtonItemText = @"完成";
    keyboardManager.shouldShowToolbarPlaceholder = YES; // 是否显示占位文字
    keyboardManager.placeholderFont = [UIFont boldSystemFontOfSize:17]; // 设置占位文字的字体
    keyboardManager.keyboardDistanceFromTextField = 10.0f; // 输入框距离键盘的距离
    
    // UI逻辑
    [self setupNavigationBarAppearance];

    CGRect frame = CGRectMake(0, 0, EasyScreenWidth, EasyScreenHeight);
    self.window = [[UIWindow alloc] initWithFrame:frame];
    self.window.backgroundColor = UIColorFromRGB(0xf5f5f5);
    [self.window makeKeyAndVisible];
    
    // 设置UI
    RootViewController *vc = [[RootViewController alloc] initWithStoryboard];
    RTRootNavigationController *rootVC = [[RTRootNavigationController alloc] init];
    [rootVC setViewControllers:@[ vc ]];
    
    self.window.rootViewController = rootVC;
    
    NSString *pname = [[NSProcessInfo processInfo] processName];
    NSLog(@"进程名：%@", pname);
    
    return YES;
}

#pragma mark - 导航栏样式

// 全局导航栏样式：蓝色渐变背景（top-bg）、白色标题和按钮、无底部分割线。
// 用 appearance 统一设置，RTRootNavigationController 为每个页面单独创建的导航栏、以及模态弹出的导航栏都会生效。
//
// iOS 15 起，页面滚动到顶部（scroll edge）时导航栏使用 scrollEdgeAppearance，没设置则背景透明，
// 只用 setBackgroundImage: 的话导航栏会变成白色、白色标题看不见，所以四种状态都设置成同一个样式。
- (void)setupNavigationBarAppearance {
    UIImage *background = [UIImage imageNamed:@"top-bg"];
    UIColor *foreground = [UIColor whiteColor];
    NSDictionary *titleAttributes = @{ NSForegroundColorAttributeName: foreground };

    UINavigationBar *bar = [UINavigationBar appearance];
    bar.tintColor = foreground; // 返回箭头、按钮的颜色
    // 不透明：页面内容从导航栏下方开始布局。原来设置不透明背景图时系统也会自动设为不透明，各页面布局依赖这一点
    bar.translucent = NO;

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = UIColorFromRGB(EasyThemeColor); // 背景图加载失败时的兜底色
    appearance.backgroundImage = background;
    appearance.backgroundImageContentMode = UIViewContentModeScaleToFill; // 横向渐变图拉伸铺满，包括状态栏区域
    appearance.shadowColor = [UIColor clearColor]; // 去掉导航栏底部的灰色分割线
    appearance.titleTextAttributes = titleAttributes;

    bar.standardAppearance = appearance;
    bar.scrollEdgeAppearance = appearance;
    bar.compactAppearance = appearance;
    bar.compactScrollEdgeAppearance = appearance;
}

@end
