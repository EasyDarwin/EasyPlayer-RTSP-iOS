

#import "VideoPlayerController.h"
#import "UIColor+HexColor.h"
#import "VideoPanel.h"
#import "PureLayout.h"
#import "AudioManager.h"
#import "RootViewController.h"

@interface VideoPlayerController () <VideoPanelDelegate>
{
    VideoPanel *panel;
//    UIToolbar *toolbar;
}
@property (nonatomic, strong)VideoPanel *panel;
@end

@implementation VideoPlayerController
@synthesize panel;

- (void)viewDidLoad
{
    [super viewDidLoad];
    if ([[UIDevice currentDevice].systemVersion floatValue] >=7.0)
    {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    
    self.view.backgroundColor = [UIColor colorFromHex:0xfefefe];
    [[AudioManager sharedInstance] activateAudioSession];
    panel = [[VideoPanel alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.width)];
    panel.delegate = self;
    [self.view addSubview:panel];
    [panel setLayout:IVL_Four];

    [self startPlay:self.url];
    
    UISegmentedControl *segment = [[UISegmentedControl alloc] initWithItems:@[@"一分屏", @"四分屏"]];
    segment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:segment];
    segment.selectedSegmentIndex = 1;
    [segment autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [segment autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [segment autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:88];
    [segment autoSetDimension:ALDimensionHeight toSize:35.0];
    [segment addTarget:self action:@selector(layoutChanged:) forControlEvents:UIControlEventValueChanged];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonSystemItemAdd target:self action:@selector(goBack:)];
    [self regestAppStatusNotification];
    
//    toolbar = [[UIToolbar alloc] init];
//    [self.view addSubview:toolbar];
//    UIBarButtonItem *audioButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ic_action_audio_enabled"] style:UIBarButtonItemStylePlain target:self action:@selector(audioButtonClicked:)];
//    UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
//    [toolbar setItems:@[flexItem, audioButton, flexItem]];
}

- (void)audioButtonClicked:(id)sender
{
    
}

- (void)layoutChanged:(id)sender
{
    UISegmentedControl *segment = (UISegmentedControl *)sender;
    [self.panel setLayout:(segment.selectedSegmentIndex == 0 ? IVL_One : IVL_Four)];
}

- (void)startPlay:(NSString *)url
{
    VideoContainerView *container = [panel nextAvailableContainer];
    container.videoView.url = url;
    [container.videoView startPlay];
}

- (void)goBack:(id)sender
{
    [panel stopAll];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillDisappear:(BOOL)animated
{
  
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect rc = self.view.bounds;
    panel.frame = CGRectMake(0, (rc.size.height - rc.size.width - 90) / 2, rc.size.width, rc.size.width);
//    toolbar.frame = CGRectMake(0, rc.size.height - 44, rc.size.width, 44);
//    VideoView *videoView = panel.activeView;
//    if (videoView.fullScreen)
//    {
//        videoView.frame = rc;
//    }
}

- (void)enterBackground
{
    [[AudioManager sharedInstance] deactivateAudioSession];
    [panel stopAll];
}

- (void)becomeActive
{
    [[AudioManager sharedInstance] activateAudioSession];
    [panel restore];
}

- (void)activeViewDidiUpdateStream:(VideoView *)view
{
    
}

- (void)didSelectVideoView:(VideoView *)view
{
    BOOL enable = view.videoStatus == Rendering;
}

- (void)activeVideoViewRendStatusChanged:(VideoView *)view
{
    
}

- (void)videoViewWillAddNewRes:(VideoView *)view
{
     __weak VideoPlayerController *weakSelf = self;
    RootViewController *vc = [[RootViewController alloc] init];
    vc.previewMore = ^(NSString *url){
        [weakSelf startPlay:url];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self.navigationController presentViewController:nav animated:YES completion:nil];
}

- (void)videoViewWillAnimateToFullScreen:(VideoView *)view
{
    [self changeScreenMode:YES];
}

- (void)videoViewWillAnimateToNomarl:(VideoView *)view
{
    [self changeScreenMode:NO];
}

- (void)changeScreenMode:(BOOL)fullScreen
{
    
}

- (void)regestAppStatusNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(enterBackground)
                                                 name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(becomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)removeAppStutusNotification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc
{
    [[AudioManager sharedInstance] deactivateAudioSession];
    [self removeAppStutusNotification];
}
@end
