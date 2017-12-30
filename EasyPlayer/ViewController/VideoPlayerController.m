
#import "VideoPlayerController.h"
#import "UIColor+HexColor.h"
#import "VideoPanel.h"
#import "PureLayout.h"
#import "AudioManager.h"
#import "RootViewController.h"

@interface VideoPlayerController () <VideoPanelDelegate> {
    VideoPanel *panel;
}

@property (nonatomic, strong)VideoPanel *panel;

@end

@implementation VideoPlayerController

@synthesize panel;

#pragma mark - init

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if ([[UIDevice currentDevice].systemVersion floatValue] >=7.0) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    
    self.navigationItem.title = @"播放";
    self.view.backgroundColor = [UIColor colorFromHex:0xfefefe];
    
    [[AudioManager sharedInstance] activateAudioSession];
    
    UISegmentedControl *segment = [[UISegmentedControl alloc] initWithItems:@[@"一分屏", @"四分屏", @"九分屏"]];
    segment.translatesAutoresizingMaskIntoConstraints = NO;
    segment.selectedSegmentIndex = 0;
    [segment addTarget:self action:@selector(layoutChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:segment];
    [segment autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:10];
    [segment autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:10];
    [segment autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:4];
    [segment autoSetDimension:ALDimensionHeight toSize:35.0];
    
    panel = [[VideoPanel alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.width)];
    panel.delegate = self;
    [self.view addSubview:panel];
    [panel setLayout:IVL_One];
    
    [self startPlay:self.url];
    
    [self regestAppStatusNotification];
}

- (void)layoutChanged:(id)sender {
    UISegmentedControl *segment = (UISegmentedControl *)sender;
    
    if (segment.selectedSegmentIndex == 0) {
        [self.panel setLayout:IVL_One];
    } else if (segment.selectedSegmentIndex == 1) {
        [self.panel setLayout:IVL_Four];
    } else {
        [self.panel setLayout:IVL_Nine];
    }
}

- (void)startPlay:(NSString *)url {
    VideoView *videoView = [panel nextAvailableContainer];
    videoView.url = url;
    [videoView startPlay];
}

- (void)goBack:(id)sender {
    [panel stopAll];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    
    CGRect rc = self.view.bounds;
    panel.frame = CGRectMake(0, (rc.size.height - rc.size.width - 90) / 2, rc.size.width, rc.size.width);
}

- (void)enterBackground {
    [[AudioManager sharedInstance] deactivateAudioSession];
    [panel stopAll];
}

- (void)becomeActive {
    [[AudioManager sharedInstance] activateAudioSession];
    [panel restore];
}

- (void)activeViewDidiUpdateStream:(VideoView *)view {
    
}

- (void)didSelectVideoView:(VideoView *)view {
    BOOL enable = view.videoStatus == Rendering;
    NSLog(@"%d", enable);
}

- (void)activeVideoViewRendStatusChanged:(VideoView *)view {
    
}

- (void)videoViewWillAddNewRes:(VideoView *)view {
     __weak VideoPlayerController *weakSelf = self;
    RootViewController *vc = [[RootViewController alloc] init];
    vc.previewMore = ^(NSString *url){
        [weakSelf startPlay:url];
    };
    
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self.navigationController presentViewController:nav animated:YES completion:nil];
}

- (void)videoViewWillAnimateToFullScreen:(VideoView *)view {
    [self changeScreenMode:YES];
}

- (void)videoViewWillAnimateToNomarl:(VideoView *)view {
    [self changeScreenMode:NO];
}

- (void)changeScreenMode:(BOOL)fullScreen {
    
}

- (void)regestAppStatusNotification {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(enterBackground)
                                                 name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(becomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)removeAppStutusNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc {
    [[AudioManager sharedInstance] deactivateAudioSession];
    [self removeAppStutusNotification];
}

@end
