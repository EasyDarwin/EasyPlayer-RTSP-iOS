
#import "VideoView.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>
#import "UIColor+HexColor.h"
#import "KxMovieGLView.h"
#import "AudioManager.h"
#import "PathUnit.h"
#import "NSUserDefaultsUnit.h"
#import "WHToast.h"
#import "Masonry.h"
#import <os/lock.h>

@interface VideoView() <UIScrollViewDelegate> {
    UIScrollView *scrollView;
    KxMovieGLView *kxGlView;
    UIActivityIndicatorView *activityIndicatorView;
    
    BOOL firstFrame;                // 得到第一帧，调整相关UI
    BOOL transforming;
    
    // 视频帧的宽高：只在主线程读写（layoutSubviews / stopPlay）
    int displayWidth;
    int displayHeight;
    // 解码线程自己记的上一帧宽高，只用来判断分辨率有没有变
    int _decodedWidth;
    int _decodedHeight;

    NSMutableArray *_audioFrames;   // 解码的音频数据
    os_unfair_lock _audioFramesLock;// _audioFrames 被主线程、解码线程、音频渲染线程三方访问
    
    NSData  *_currentAudioFrame;    // 当前播放的音频帧
    NSUInteger _currentAudioFramePos;
    
    CGFloat _moviePosition;         // 当前播放视频的时间戳（毫秒为单位）

    BOOL _ownsAudioOutput;          // 是否由自己接管了 AudioManager 的输出（只在主线程读写）
}

@property (nonatomic, strong) dispatch_source_t timer;  // 只在主线程创建 / 取消
@property (nonatomic, assign) int frameLength;

@property (nonatomic, strong) UIView *statusView;
@property (nonatomic, strong) UIButton *playButton;     // 播放按钮

@property (nonatomic, strong) UIView *btnView;
@property (nonatomic, strong) UILabel *kbpsLabel;       // kbps
@property (nonatomic, strong) UIButton *audioButton;    // 声音按钮
@property (nonatomic, strong) UIButton *recordButton;   // 录像按钮
@property (nonatomic, strong) UIButton *screenshotButton;// 截屏按钮

@property (nonatomic, strong) UIView *backView;

@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGesture;
@property (nonatomic, assign) CFTimeInterval playStartTime;
@property (nonatomic, assign, readwrite) BOOL hasReceivedFirstFrame;
@property (nonatomic, assign, readwrite) NSTimeInterval firstFrameCostMs;

- (void)showActivity;
- (void)hideActivity;

- (void)fillAudioData:(SInt16 *)outData numFrames:(UInt32)numFrames numChannels:(UInt32)numChannels;
- (void)startKbpsTimer;
- (void)cancelKbpsTimer;
- (void)detachReaderAndStop;

@end

@implementation VideoView

#pragma mark - init

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor blackColor];
        
        [self addGesture];
        [self addItemView];
        
        firstFrame = YES;
        self.videoStatus = Stopped;
        _showActiveStatus = YES;
        
        self.useHWDecoder = ![NSUserDefaultsUnit isFFMpeg];
        self.audioPlaying = YES;
        
        _audioFrames = [[NSMutableArray alloc] init];
        _audioFramesLock = OS_UNFAIR_LOCK_INIT;
    }
    
    return self;
}

- (void) addGesture {
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    self.tapGesture.delegate = self;
    [self addGestureRecognizer:self.tapGesture];
}

- (void) addItemView {
    scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    [self addSubview:scrollView];
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.backgroundColor = [UIColor blackColor];
    scrollView.delegate = self;
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrollView.zoomScale = 1;
    scrollView.minimumZoomScale = 1;
    scrollView.maximumZoomScale = 4.0;
    scrollView.bouncesZoom = NO;
    scrollView.bounces = NO;
    scrollView.scrollEnabled = NO;
    
    kxGlView = [[KxMovieGLView alloc] initWithFrame:CGRectMake(0, 0, 320, 240)];
    [scrollView addSubview:kxGlView];
    
    // 点击视频，隐藏底部按钮
    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideStatusView)];
    gesture.numberOfTapsRequired = 1;
    [kxGlView addGestureRecognizer:gesture];
    
    _addButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_addButton setImage:[UIImage imageNamed:@"ic_action_add"] forState:UIControlStateNormal];
    _addButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_addButton];
    
    activityIndicatorView = [[UIActivityIndicatorView alloc] init];
    activityIndicatorView.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhite;
    activityIndicatorView.hidesWhenStopped = YES;
    [self addSubview:activityIndicatorView];
    [activityIndicatorView makeConstraints:^(MASConstraintMaker *make) {
        make.size.equalTo(CGSizeMake(10, 10));
        make.centerX.equalTo(self.mas_centerX);
        make.centerY.equalTo(self.mas_centerY);
    }];
    
    CGFloat size = 45;
    
    _statusView = [[UIView alloc] init];
    _statusView.backgroundColor = UIColorFromRGB(0xf5f5f5);
    _statusView.hidden = YES;
    [self addSubview:_statusView];
    [_statusView makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(@0);
        make.height.equalTo(@(size));
    }];
    
    _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_playButton setImage:[UIImage imageNamed:@"play"] forState:UIControlStateNormal];
    [_playButton setImage:[UIImage imageNamed:@"pause"] forState:UIControlStateSelected];
    [_playButton addTarget:self action:@selector(playButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [_statusView addSubview:_playButton];
    [_playButton makeConstraints:^(MASConstraintMaker *make) {
        make.width.equalTo(@(size));
        make.top.left.bottom.equalTo(@0);
    }];
    
    _btnView = [[UIView alloc] init];
    _btnView.backgroundColor = [UIColor clearColor];
    [_statusView addSubview:_btnView];
    [_btnView makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.right.equalTo(@0);
        make.left.equalTo(self.playButton.mas_right).offset(20);
    }];
    
    _kbpsLabel = [[UILabel alloc] init];
    _kbpsLabel.text = @"0kbps";
    _kbpsLabel.textColor = UIColorFromRGB(SelectBtnColor);
    _kbpsLabel.font = [UIFont systemFontOfSize:12];
    [_btnView addSubview:_kbpsLabel];
    [_kbpsLabel makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(@0);
        make.left.equalTo(@0);
        make.width.equalTo(@64);
    }];
    
    self.audioButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.audioButton setImage:[UIImage imageNamed:@"ic_action_audio_enabled"] forState:UIControlStateDisabled];
    [self.audioButton setImage:[UIImage imageNamed:@"ic_action_audio_enabled"] forState:UIControlStateNormal];
    [self.audioButton setImage:[UIImage imageNamed:@"ic_action_audio_pressed"] forState:UIControlStateSelected];
    [self.audioButton addTarget:self action:@selector(audioButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    self.audioButton.enabled = NO;
    _audioButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [_btnView addSubview:self.audioButton];
    [self.audioButton makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(@0);
    }];
    
    _recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_recordButton setImage:[UIImage imageNamed:@"ic_action_record_enabled"] forState:UIControlStateDisabled];
    [_recordButton setImage:[UIImage imageNamed:@"ic_action_record_enabled"] forState:UIControlStateNormal];
    [_recordButton setImage:[UIImage imageNamed:@"ic_action_record_pressed"] forState:UIControlStateSelected];
    [_recordButton addTarget:self action:@selector(recordButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    _recordButton.enabled = NO;
    _recordButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [_btnView addSubview:_recordButton];
    [_recordButton makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(@0);
        make.left.equalTo(self.audioButton.mas_right);
    }];
    
    _screenshotButton = [[UIButton alloc] init];
    [_screenshotButton setImage:[UIImage imageNamed:@"ic_action_camera_enabled"] forState:UIControlStateDisabled];
    [_screenshotButton setImage:[UIImage imageNamed:@"ic_action_camera_enabled"] forState:UIControlStateNormal];
    [_screenshotButton setImage:[UIImage imageNamed:@"ic_action_camera_pressed"] forState:UIControlStateHighlighted];
    [_screenshotButton addTarget:self action:@selector(screenshotButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    _screenshotButton.enabled = NO;
    _screenshotButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [_btnView addSubview:_screenshotButton];
    [_screenshotButton makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(@0);
        make.left.equalTo(self.recordButton.mas_right);
    }];
    
    _landspaceButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_landspaceButton setImage:[UIImage imageNamed:@"LandspaceVideo"] forState:UIControlStateNormal];
    [_landspaceButton setImage:[UIImage imageNamed:@"PortraitVideo"] forState:UIControlStateSelected];
    [_landspaceButton addTarget:self action:@selector(landspaceButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    _landspaceButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [_btnView addSubview:_landspaceButton];
    [_landspaceButton makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(@0);
        make.left.equalTo(self.screenshotButton.mas_right);
    }];
    
    NSArray *views = @[ self.audioButton, self.recordButton, self.screenshotButton, self.landspaceButton ];
    [views mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(@0);
    }];
    [views mas_distributeViewsAlongAxis:MASAxisTypeHorizontal withFixedSpacing:0 leadSpacing:64 tailSpacing:0];
    
    _backView = [[UIView alloc] init];
    _backView.backgroundColor = UIColorFromRGBA(0x000000, 0.4);
    _backView.hidden = YES;
    [self addSubview:_backView];
    [_backView makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.top.equalTo(@0);
        make.height.equalTo(@44);
    }];
    
    UIButton *backBtn = [[UIButton alloc] init];
    [backBtn setImage:[UIImage imageNamed:@"nav_back"] forState:UIControlStateNormal];
    [backBtn addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];
    [_backView addSubview:backBtn];
    [backBtn makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(@0);
        make.left.equalTo(@15);
        make.width.equalTo(@44);
    }];
}

// 点击视频，隐藏底部按钮
- (void) hideStatusView {
    _statusView.hidden = !_statusView.hidden;
    
    // btnView没有隐藏，则不是分屏
    if (!self.btnView.isHidden) {
        if (_landspaceButton.isSelected) {// 横屏时
            _backView.hidden = _statusView.hidden;
        }
    }
}

- (void) changeHorizontalScreen:(BOOL) horizontal {
    _landspaceButton.selected = horizontal;
    
    [self updateHeight];
}

#pragma mark - override

// 把 videoSize 等比缩放后居中放进 container
static CGRect VideoViewAspectFitRect(CGSize videoSize, CGSize container) {
    CGFloat scale = MIN(container.width / videoSize.width, container.height / videoSize.height);
    CGFloat width = videoSize.width * scale;
    CGFloat height = videoSize.height * scale;
    return CGRectMake((container.width - width) / 2, (container.height - height) / 2, width, height);
}

// NaN / inf 进了 layer 会直接抛 CALayerInvalidGeometry；CGRectNull 的 origin 是 inf，也在这里被拦掉
static BOOL VideoViewRectIsValid(CGRect rect) {
    return isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
           isfinite(rect.size.width) && isfinite(rect.size.height) &&
           rect.size.width >= 0 && rect.size.height >= 0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    _addButton.frame = self.bounds;
    
    // 还没加到父视图、转屏过程中 bounds 可能是 0，此时算不出有意义的 frame
    CGSize bounds = scrollView.bounds.size;
    if (bounds.width <= 0 || bounds.height <= 0) {
        return;
    }
    
    // 视频宽高只读这一次，后面全用局部变量
    CGSize videoSize = CGSizeMake(displayWidth, displayHeight);
    BOOL hasVideoSize = videoSize.width > 0 && videoSize.height > 0;
    
    CGSize contentSize = bounds;
    // 保持 CGRectNull 表示这次不动 kxGlView
    CGRect glFrame = CGRectNull;
    
    if (_landspaceButton.selected) {
        // 横屏：横向视频拉满；竖向视频按高度铺满、水平居中
        glFrame = (CGRect){CGPointZero, bounds};
        if (hasVideoSize && videoSize.width < videoSize.height) {
            CGFloat width = bounds.height * videoSize.width / videoSize.height;
            contentSize = CGSizeMake(width, bounds.height);
            glFrame = CGRectMake((bounds.width - width) / 2, 0, width, bounds.height);
        }
    } else if (_showAllRegon) {
        // 不放大：比窗口小按原尺寸居中，宽超出压到窗口宽，高超出截到窗口高
        if (hasVideoSize) {
            CGFloat width = MIN(videoSize.width, bounds.width);
            CGFloat height = MIN(videoSize.height * width / videoSize.width, bounds.height);
            glFrame = CGRectMake(round((bounds.width - width) / 2),
                                 round((bounds.height - height) / 2),
                                 width,
                                 height);
        }
    } else {
        // 等比缩放居中；还没拿到首帧时按 16:9 占位
        glFrame = VideoViewAspectFitRect(hasVideoSize ? videoSize : CGSizeMake(16, 9), bounds);
    }
    
    // 值没变就不赋：kxGlView 尺寸一变就要在 GL 队列上重建帧缓冲，contentSize 变了会回调 scrollViewDidScroll
    if (!CGSizeEqualToSize(scrollView.contentSize, contentSize)) {
        scrollView.contentSize = contentSize;
    }
    if (VideoViewRectIsValid(glFrame) && !CGRectEqualToRect(kxGlView.frame, glFrame)) {
        kxGlView.frame = glFrame;
    }
    
    if (!_landspaceButton.selected && !_showAllRegon) {
        [self reCalculateArcPos];
    }
}

#pragma mark - 播放控制

- (void)startAudio {
    self.audioPlaying = YES;
    [AudioManager sharedInstance].sampleRate = _reader.mediaInfo.u32AudioSamplerate;
    [AudioManager sharedInstance].channel = _reader.mediaInfo.u32AudioChannel;
    [[AudioManager sharedInstance] play];
    __weak VideoView *weakSelf = self;
    [AudioManager sharedInstance].source = self;
    [AudioManager sharedInstance].outputBlock = ^(SInt16 *outData, UInt32 numFrames, UInt32 numChannels) {
        [weakSelf fillAudioData:outData numFrames:numFrames numChannels:numChannels];
    };
    _ownsAudioOutput = YES;
}

- (void)stopAudio {
    // source 是 weak：dealloc 期间读到的永远是 nil，只比较 source == self 会漏掉停止，
    // 所以 source 为 nil 时再看自己是否接管过输出；source 是别的窗口时不能动它的声音
    id source = [AudioManager sharedInstance].source;
    if (source == self || (source == nil && _ownsAudioOutput)) {
        // 先断开回调，再 pause，避免音频线程还在 fillAudioData 时 Uninitialize 卡住主线程
        [AudioManager sharedInstance].outputBlock = nil;
        [AudioManager sharedInstance].source = nil;
        [[AudioManager sharedInstance] pause];
    }
    _ownsAudioOutput = NO;
    // 不要走 setter：dealloc / 停播时 setter 会 dispatch_async 强引用 self，对象半销毁后再碰 audioButton 会崩
    _audioPlaying = NO;
}

- (void)startPlay {
    if (!self.url || self.url.length == 0) {
        return;
    }
    _playButton.selected = YES;
    
    // _currentAudioFramePos 只归音频渲染线程管，这里不能在主线程改它：
    // 渲染线程正在拷贝时被清零，会按旧偏移 + 整帧长度越界读
    _moviePosition = 0;
    self.playStartTime = CACurrentMediaTime();
    self.hasReceivedFirstFrame = NO;
    self.firstFrameCostMs = 0;
    
    [self stopPlay];
    
    self.videoStatus = Connecting;
    [self showActivity];
    self.addButton.hidden = YES;
    
    __weak VideoView *weakSelf = self;
    _reader = [[PlayerDataReader alloc] initWithUrl:self.url];
    _reader.useHWDecoder = self.useHWDecoder;
    _reader.transportMode = self.transportMode;
    _reader.sendOption = self.sendOption;
    
    if ([NSUserDefaultsUnit isAutoRecord]) {
        _reader.recordFilePath = [PathUnit recordWithURL:_url];
        _recordButton.selected = YES;
    }
    
    // 获得媒体类型
    _reader.fetchMediaInfoSuccessBlock = ^(void){
        weakSelf.videoStatus = Rendering;
        [weakSelf updateUI];
        
        if ([NSUserDefaultsUnit isAutoAudio]) {
            [weakSelf startAudio];
        }
    };
    
    // 获得解码后的音频帧／视频帧
    _reader.frameOutputBlock = ^(KxMovieFrame *frame, unsigned int length) {
        [weakSelf addFrame:frame];
        [weakSelf sendPacket:length];
    };
    _reader.rtspEventBlock = ^(NSInteger eventCode, NSString *message, NSInteger data, NSInteger count, NSInteger total) {
        if ([weakSelf.delegate respondsToSelector:@selector(videoView:didReceiveRTSPEvent:message:data:count:total:)]) {
            [weakSelf.delegate videoView:weakSelf didReceiveRTSPEvent:eventCode message:message data:data count:count total:total];
        }
    };
    [self startKbpsTimer];
    [_reader start];
}

// 定时器以前在解码线程的 sendPacket 里懒创建，停播时又在主线程取消：
// 两个线程同时读写 nonatomic 的 timer，会重复创建或释放已释放的 source；
// 取消之后解码线程还可能再建一个，而 handler 强引用 self，VideoView 就永远释放不掉。
// 现在只在主线程创建和取消，handler 在主队列上执行，并且只持有 weak。
- (void)startKbpsTimer {
    [self cancelKbpsTimer];
    self.frameLength = 0;

    __weak VideoView *weakSelf = self;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_walltime(NULL, 0), 1.0 * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(timer, ^{
        __strong VideoView *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.kbpsLabel.text = [NSString stringWithFormat:@"%dkbps", strongSelf.frameLength * 8 / 1000];
        strongSelf.frameLength = 0;
    });
    dispatch_resume(timer);
    self.timer = timer;
}

- (void)cancelKbpsTimer {
    if (self.timer) {
        dispatch_source_cancel(self.timer);
        self.timer = nil;
    }
}

- (void)detachReaderAndStop {
    PlayerDataReader *oldReader = _reader;
    _reader = nil;

    // 先摘回调，解码线程 / RTSP 回调线程就不会再回到 self
    oldReader.recordFilePath = nil;
    oldReader.frameOutputBlock = nil;
    oldReader.fetchMediaInfoSuccessBlock = nil;
    oldReader.rtspEventBlock = nil;

    [self cancelKbpsTimer];
    [kxGlView flush];
    [self stopAudio];
    [oldReader stopAsync];
}

- (void)stopPlay {
    BOOL shouldSnapshot = !firstFrame && displayWidth > 0 && displayHeight > 0;

    _playButton.selected = NO;
    [self hideActivity];
    self.videoStatus = Stopped;

    [self detachReaderAndStop];

    // 停播截图不能同步读 GL：viewWillDisappear 在主线程，curImage 里 dispatch_sync(_glQueue) 会和页面销毁互相锁死
    if (shouldSnapshot) {
        [self screenShotName:YES];
    }
    
    // 用 os_unfair_lock 代替 @synchronized：临界区只有几条数组操作，
    // 主线程在这里的等待被压到音频渲染线程那一小段之内
    os_unfair_lock_lock(&_audioFramesLock);
    [_audioFrames removeAllObjects];
    os_unfair_lock_unlock(&_audioFramesLock);
    
    [self updateUI];
    [self flush];
}

- (void)dealloc {
    [self detachReaderAndStop];
}

- (void)flush {
    firstFrame = YES;
    scrollView.zoomScale = 1.0;
    scrollView.scrollEnabled = NO;
}

- (void)updateUI {
    self.audioButton.enabled = self.videoStatus == Rendering ? YES : NO;
    _recordButton.enabled = self.videoStatus == Rendering ? YES : NO;
    _screenshotButton.enabled = self.videoStatus == Rendering ? YES : NO;
}

#pragma mark - 解码后的音频帧／视频帧

- (void)addFrame:(KxMovieFrame *)frame {
    if (frame.type == KxMovieFrameTypeVideo) {
        if (self.videoStatus != Rendering) {
            return;
        }
        
        KxVideoFrame *videoFrame = (KxVideoFrame *)frame;
        [kxGlView render:videoFrame];
        _moviePosition = videoFrame.position;
        
        // 不能在这里直接写 displayWidth / displayHeight：主线程 layoutSubviews 判完非 0 之后再读，
        // 中间被解码线程改掉就会除出 NaN / inf，frame 赋给 layer 直接抛 CALayerInvalidGeometry。
        // 宽高随 block 带到主线程再写
        int width = (int)videoFrame.width;
        int height = (int)videoFrame.height;
        BOOL needsLayout = NO;
        if (width != _decodedWidth || height != _decodedHeight) {
            _decodedWidth = width;
            _decodedHeight = height;
            needsLayout = YES;
        }
        
        if (firstFrame) {
            firstFrame = NO;
            needsLayout = YES;
            if (!self.hasReceivedFirstFrame && self.playStartTime > 0) {
                self.hasReceivedFirstFrame = YES;
                self.firstFrameCostMs = (CACurrentMediaTime() - self.playStartTime) * 1000.0;
            }
        }
        
        if (needsLayout) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateDisplayLayoutWithWidth:width height:height];
            });
        }
    } else if (frame.type == KxMovieFrameTypeAudio) {
        os_unfair_lock_lock(&_audioFramesLock);
        if (self.audioPlaying) {
            [_audioFrames addObject:frame];
        } else {
            [_audioFrames removeAllObjects];
        }
        os_unfair_lock_unlock(&_audioFramesLock);
    }
}

- (void)updateDisplayLayoutWithWidth:(int)width height:(int)height {
    if (self.videoStatus != Rendering) return;

    displayWidth = width;
    displayHeight = height;

    scrollView.scrollEnabled = YES;
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    [self hideActivity];
    [self setNeedsLayout];
}

#pragma mark - 流量检测

// 解码线程调用：只累加字节数，定时器由主线程在 startPlay 里创建
- (void) sendPacket:(unsigned int)u32AVFrameLen {
    self.frameLength += u32AVFrameLen;
}

#pragma mark - 填充音频数据

- (void)fillAudioData:(SInt16 *) outData numFrames: (UInt32) numFrames numChannels: (UInt32) numChannels {
    @autoreleasepool {
        while (numFrames > 0) {
            if (_currentAudioFrame == nil) {
                // 这里跑在 CoreAudio 的渲染线程上，锁里只做取帧／出队，
                // memset 和日志都挪到解锁之后，尽量缩短其他线程的等待
                BOOL silenceAndExit = NO;
                BOOL skipThisFrame = NO;
                CGFloat skippedDiffer = 0;
                CGFloat skippedPosition = 0;
                
                os_unfair_lock_lock(&_audioFramesLock);
                NSUInteger count = _audioFrames.count;
                if (count > 0) {
                    KxAudioFrame *frame = _audioFrames[0];
                    CGFloat differ = _moviePosition - frame.position;
                    
                    // 似乎没有作用
                    if (differ < -0.1) {
                        silenceAndExit = YES;
                    } else {
                        [_audioFrames removeObjectAtIndex:0];
                        
                        if (differ > 0.1 && count > 1) {
                            skipThisFrame = YES;
                            skippedDiffer = differ;
                            skippedPosition = frame.position;
                        } else {
                            _currentAudioFramePos = 0;
                            _currentAudioFrame = frame.samples;
                        }
                    }
                }
                os_unfair_lock_unlock(&_audioFramesLock);
                
                if (silenceAndExit) {
                    memset(outData, 0, numFrames * numChannels * sizeof(SInt16));
                    break; // silence and exit
                }
                
                if (skipThisFrame) {
                    NSLog(@"differ = %.4f", skippedDiffer);
                    NSLog(@"audio skip movPos = %.4f audioPos = %.4f", _moviePosition, skippedPosition);
                    continue;
                }
            }
            
            if (_currentAudioFrame) {
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(SInt16);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                if (bytesToCopy < bytesLeft) {
                    _currentAudioFramePos += bytesToCopy;
                } else {
                    _currentAudioFrame = nil;
                }
            } else {
                memset(outData, 0, numFrames * numChannels * sizeof(SInt16));
                break;
            }
        }
    }
}

#pragma mark - public method

- (void)beginTransform {
    scrollView.contentOffset = CGPointZero;
    scrollView.zoomScale = 1;
    transforming = YES;
}

- (void)endTransform {
    transforming = NO;
}

- (void) hideBtnView {
    self.btnView.hidden = YES;
    _backView.hidden = YES;
}

#pragma mark - private method

- (void)updateStreamCount {
    [self.delegate videoViewDidiUpdateStream:self];
}

- (void)reCalculateArcPos {
    if (_landspaceButton.selected) {
        return;
    }
    
    CGFloat maxDiffer = scrollView.contentSize.width - scrollView.frame.size.width;
    if (maxDiffer <= 0 || self.videoStatus != Rendering) {
        return;
    } else {
        if (!firstFrame) {
            
        }
    }
}

- (void)showActivity {
    [self bringSubviewToFront:activityIndicatorView];
    [activityIndicatorView startAnimating];
}

- (void)hideActivity {
    [activityIndicatorView stopAnimating];
}

- (void) updateHeight {
    if (_landspaceButton.selected) {
        [_statusView updateConstraints:^(MASConstraintMaker *make) {
            make.height.equalTo(@56);
        }];
        
        _backView.hidden = NO;
    } else {
        [_statusView updateConstraints:^(MASConstraintMaker *make) {
            make.height.equalTo(@45);
        }];
        
        _backView.hidden = YES;
    }
    
    [_statusView layoutSubviews];
}

#pragma mark - 按钮事件

- (void)audioButtonClicked:(id)sender {
    self.audioButton.selected = !self.audioButton.selected;
    
    if (self.audioButton.selected) {
        [self startAudio];
    } else {
        self.audioPlaying = NO;
        // 走 stopAudio：分屏时只有自己接管了输出才停，不能把别的窗口的声音一起关掉
        [self stopAudio];
    }
}

- (void)recordButtonClicked:(id)sender {
    _recordButton.selected = !_recordButton.selected;
    
    if (_recordButton.selected) {
        _reader.recordFilePath = [PathUnit recordWithURL:_url];
    } else {
        _reader.recordFilePath = nil;
    }
}

- (void) screenshotButtonClicked:(id)sender {
    if (_screenShotPath) {
        return;
    } else {
        [self screenShotName:NO];
    }
}

- (void) playButtonClicked:(id)sender {
    if (self.videoStatus == Stopped) {
        [self startPlay];
    } else {
        [self stopPlay];
    }
}

- (void) landspaceButtonClicked:(id)sender {
    _landspaceButton.selected = !_landspaceButton.selected;
    
    [self.delegate videoViewBeginActive:self];
    if (_landspaceButton.selected) {
        [self.delegate videoViewWillAnimateToFullScreen:self];
    } else {
        [self.delegate videoViewWillAnimateToNomarl:self];
    }
    
    [self updateHeight];
}

- (void) back {
    [self.delegate back];
}

#pragma mark - 手势操作

- (void)handleTapGesture:(UITapGestureRecognizer *)tapGesture {
    [self.delegate videoViewBeginActive:self];
}

#pragma mark - setter

- (void)setVideoStatus:(IVideoStatus)videoStatus {
    if (_videoStatus == videoStatus) {
        return;
    }
    _videoStatus = videoStatus;

    if (![self.delegate respondsToSelector:@selector(videoView:didChangeStatus:)]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf.delegate videoView:strongSelf didChangeStatus:videoStatus];
    });
}

// 异步 block 里不能捕获 self，强弱引用都不行：
// - 强引用：调用时 self 如果正在 dealloc，retain 不生效，主队列执行时 self 已释放，
//   objc_msgSend 访问野指针（旧版就是这样崩的：主队列 block → objc_msgSend SEGV）；
// - __weak：对正在 dealloc 的对象建 weak 引用，runtime 直接 abort。
// 所以只把按钮交给主线程，按钮由 block 持有，和 VideoView 的生命周期无关。
- (void)setAudioPlaying:(BOOL)audioPlaying {
    _audioPlaying = audioPlaying;
    _reader.enableAudio = audioPlaying;

    UIButton *button = _audioButton;
    if ([NSThread isMainThread]) {
        button.selected = audioPlaying;
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        button.selected = audioPlaying;
    });
}

- (void)setUrl:(NSString *)url {
    _url = url;
    
    _addButton.hidden = [_url length] == 0 ? NO : YES;
    
    if (url && [_url length] > 0) {
        _statusView.hidden = NO;
    } else {
        _statusView.hidden = YES;
    }
}

- (void)setShowActiveStatus:(BOOL)showActiveStatus {
    _showActiveStatus = showActiveStatus;
    self.layer.borderWidth = _active && _showActiveStatus ? 1 : 0;
}

- (void)setShowAllRegon:(BOOL)showAllRegon {
    _showAllRegon = showAllRegon;
    scrollView.scrollEnabled = _showAllRegon;
}

#pragma mark - getter

- (void) screenShotName:(BOOL)isSnapshot {
    if (!isSnapshot) {
        if (_screenShotPath.length > 0) {
            return;
        }
        _screenShotPath = @"__pending__";
    }

    KxMovieGLView *glView = kxGlView;
    NSString *url = [_url copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *currentImage = [glView curImage];
        NSString *path = isSnapshot ? [PathUnit snapshotWithURL:url] : [PathUnit screenShotWithURL:url];
        if (currentImage && path.length > 0) {
            NSData *imageData = UIImagePNGRepresentation(currentImage);
            if (imageData.length > 0) {
                [imageData writeToFile:path atomically:YES];
            }
        }

        if (!isSnapshot) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.screenShotPath = nil;
                if (currentImage) {
                    [WHToast showMessage:@"截图保存成功" duration:1 finishHandler:nil];
                }
            });
        }
    });
}

#pragma mark - UIScrollViewDelegate

- (UIView*)viewForZoomingInScrollView:(UIScrollView *)aScrollView {
    return nil;
}

- (void)scrollViewDidScroll:(UIScrollView *)aScrollView {
    if (transforming) {
        return;
    }
    
    CGPoint point = aScrollView.contentOffset;
    CGFloat maxX = aScrollView.contentSize.width - aScrollView.frame.size.width;
    if (point.x < 0.5) {
        point.x = 0.0;
        aScrollView.contentOffset = point;
    } else if ( point.x > maxX) {
        point.x = maxX;
        aScrollView.contentOffset = point;
    } else if (point.y < 0.5) {
        point.y = 0.0;
        aScrollView.contentOffset = point;
    } else if ( point.y > (aScrollView.contentSize.height - aScrollView.frame.size.height)) {
        point.y = aScrollView.contentSize.height - aScrollView.frame.size.height;
        aScrollView.contentOffset = point;
    }
    
    [self reCalculateArcPos];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([[touch view] isKindOfClass:[UIControl class]]) {
        return NO;
    }
    
    return YES;
}

@end
