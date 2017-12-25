
#import "VideoView.h"

#import <QuartzCore/QuartzCore.h>
#import <AudioToolbox/AudioToolbox.h>

#import "PureLayout.h"
#import "KxMovieGLView.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import "UIColor+HexColor.h"
#import "AudioManager.h"

@interface VideoView() <UIScrollViewDelegate> {
    BOOL firstFrame;
    
    int displayWidth;
    int displayHeight;
    
    UIActivityIndicatorView *activityIndicatorView;
    UILabel *loadingLabel;
    
    BOOL snapshoting;
    
    UIScrollView *scrollView;
    BOOL transforming;
    
    BOOL needChangeViewFrame;
    
    dispatch_queue_t requestQueue;
    
    KxMovieGLView *kxGlView;
    RtspDataReader *reader;
    CADisplayLink *displayLink;
    UIButton *audioButton;
    NSTimeInterval _tickCorrectionTime;
    NSTimeInterval _tickCorretionPosition;
    CGFloat _moviePosition;
    
    NSMutableArray *rgbFrameArray;
    NSMutableArray *_audioFrames;
    
    NSData  *_currentAudioFrame;
    NSUInteger _currentAudioFramePos;
}

@property (nonatomic, readwrite)BOOL audioPlaying;
@property (nonatomic, readwrite)CGFloat bufferdDuration;
@property (nonatomic, strong)UITapGestureRecognizer *tapGesture;
@property (nonatomic, strong)UITapGestureRecognizer *doubleTapGesture;

- (void)showActivity;
- (void)hideActivity;

- (void)showError:(NSString *)text;

- (void)fillAudioData:(SInt16 *) outData numFrames: (UInt32) numFrames numChannels: (UInt32) numChannels;
@end

@implementation VideoView

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor blackColor];
        
        firstFrame = YES;
        self.videoStatus = Stopped;
        needChangeViewFrame = NO;
        _showActiveStatus = YES;
        
        self.useHWDecoder = YES;
        
        self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
        [self addGestureRecognizer:self.tapGesture];
        self.tapGesture.delegate = self;
        self.doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTapGesture:)];
        [self addGestureRecognizer:self.doubleTapGesture];
        self.doubleTapGesture.numberOfTapsRequired = 2;
        self.doubleTapGesture.delegate = self;
        [self.tapGesture requireGestureRecognizerToFail:self.doubleTapGesture];
        
        scrollView = [[UIScrollView alloc] initWithFrame:frame];
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
        
        _addButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self addSubview:_addButton];
        [_addButton setImage:[UIImage imageNamed:@"ic_action_add.png"] forState:UIControlStateNormal];
        
        UIView *statusView = [UIView newAutoLayoutView];
        [self addSubview:statusView];
        [statusView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
        [statusView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
        [statusView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
        [statusView autoSetDimension:ALDimensionHeight toSize:22.0];
        statusView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.35];
        
        audioButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [statusView addSubview:audioButton];
        [audioButton autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:1.0];
        [audioButton autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:2.0];
        [audioButton autoSetDimensionsToSize:CGSizeMake(20, 20)];
        [audioButton setImage:[UIImage imageNamed:@"ic_action_audio"] forState:UIControlStateDisabled];
        [audioButton setImage:[UIImage imageNamed:@"ic_action_audio_enabled"] forState:UIControlStateNormal];
        [audioButton setImage:[UIImage imageNamed:@"ic_action_audio_pressed"] forState:UIControlStateSelected];
        [audioButton addTarget:self action:@selector(audioButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        audioButton.enabled = NO;
        
        activityIndicatorView = [UIActivityIndicatorView newAutoLayoutView];
        [statusView addSubview:activityIndicatorView];
        [activityIndicatorView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:10.0];
        [activityIndicatorView autoSetDimensionsToSize:CGSizeMake(10,10)];
        activityIndicatorView.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhite;
        [activityIndicatorView autoAlignAxisToSuperviewAxis:ALAxisHorizontal];
        activityIndicatorView.hidesWhenStopped = YES;
        
        loadingLabel = [UILabel newAutoLayoutView];
        [statusView addSubview:loadingLabel];
        loadingLabel.text = @"正在缓冲...";
        loadingLabel.backgroundColor = [UIColor clearColor];
        loadingLabel.textColor = [UIColor whiteColor];
        loadingLabel.font = [UIFont systemFontOfSize:11];
        loadingLabel.hidden = YES;
        [loadingLabel autoPinEdge:ALEdgeLeading toEdge:ALEdgeTrailing ofView:activityIndicatorView withOffset:5.0];
        [loadingLabel autoAlignAxisToSuperviewAxis:ALAxisHorizontal];
        
        rgbFrameArray = [[NSMutableArray alloc] init];
        _audioFrames = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)startPlay {
    if (self.url.length == 0) {
        return;
    }
    _tickCorrectionTime = 0;
    _tickCorretionPosition = 0;
    _moviePosition = 0;
    _currentAudioFramePos = 0;
    _bufferdDuration = 0;
    
    [self stopPlay];
    self.videoStatus = Connecting;
    [self showActivity];
    self.addButton.hidden = YES;
    [self.delegate videoViewWillTryToConnect:self];
    
    __weak VideoView *weakSelf = self;
    reader = [[RtspDataReader alloc] initWithUrl:self.url];
    reader.useHWDecoder = self.useHWDecoder;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString* _dir = [documentsDirectory stringByAppendingPathComponent:@"record"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:_dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:_dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSDate *date = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"YYYYMMddhhmmss"];
    NSString *DateTime = [formatter stringFromDate:date];
    reader.recordFilePath = [_dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", DateTime]];
    
    reader.fetchMediaInfoSuccessBlock = ^(void){
        weakSelf.videoStatus = Rendering;
        [weakSelf updateUI];
//        [weakSelf startAudio];
        [weakSelf presentFrame];
    };
    
    reader.frameOutputBlock = ^(KxMovieFrame *frame) {
        [weakSelf addFrame:frame];
    };
    [reader start];
}

- (void)updateUI {
    audioButton.enabled = self.videoStatus == Rendering ? YES : NO;
}

- (void)presentFrame {
    CGFloat duration = 0;
    if (self.videoStatus == Rendering) {
        NSTimeInterval time = 0.01;
        KxVideoFrame *frame = [self popVideoFrame];
        if (frame != nil) {
            duration = [self displayFrame:frame];
            NSTimeInterval correction = [self tickCorrection];
            NSTimeInterval interval = MAX(duration + correction, 0.01);
            if (interval >= 0.035) {
                interval = interval / 2;
            }
            
            time = interval;
        }
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^{
            [self presentFrame];
        });
    }
}

- (CGFloat)tickCorrection {
    if (_moviePosition == 0) {
        return 0;
    }
    
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (_tickCorrectionTime == 0) {
        _tickCorrectionTime = now;
        _tickCorretionPosition = _moviePosition;
        return 0;
    }
    
    NSTimeInterval dPos = _moviePosition - _tickCorretionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPos - dTime;
    if (correction > 0) {
//        NSLog(@"tick correction reset %0.2f", correction);
        correction = 0;
    }
    
    if (_bufferdDuration >= 0.3) {
//        NSLog(@"bufferdDuration = %f play faster", _bufferdDuration);
        correction = -1;
    }
    
    return correction;
}

- (void)addFrame:(KxMovieFrame *)frame {
    if (frame.type == KxMovieFrameTypeVideo) {
        @synchronized(rgbFrameArray) {
            if (self.videoStatus != Rendering) {
                [rgbFrameArray removeAllObjects];
                return;
            }
            [rgbFrameArray addObject:frame];
//            NSLog(@"rgbFrameArray = %d", rgbFrameArray.count);
            _bufferdDuration = frame.position - ((KxVideoFrameRGB *)rgbFrameArray.firstObject).position;
        }
    } else if (frame.type == KxMovieFrameTypeAudio) {
        @synchronized(_audioFrames) {
            if (!self.audioPlaying ) {
                [_audioFrames removeAllObjects];
                return;
            }
            
            [_audioFrames addObject:frame];
        }
    }
}

- (KxVideoFrame *)popVideoFrame {
    KxVideoFrame *frame = nil;
    @synchronized(rgbFrameArray) {
        if ([rgbFrameArray count] > 0) {
            frame = [rgbFrameArray firstObject];
            [rgbFrameArray removeObjectAtIndex:0];
        }
    }
    
    return frame;
}

- (void)fillAudioData:(SInt16 *) outData numFrames: (UInt32) numFrames numChannels: (UInt32) numChannels {
    @autoreleasepool {
        while (numFrames > 0) {
            if (_currentAudioFrame == nil) {
                @synchronized(_audioFrames) {
                    NSUInteger count = _audioFrames.count;
                    if (count > 0) {
                        KxAudioFrame *frame = _audioFrames[0];
                        CGFloat differ = _moviePosition - frame.position;
                        
                        [_audioFrames removeObjectAtIndex:0];
                        
                        if (differ > 5 && count > 1) {
                            NSLog(@"audio skip movPos = %.4f audioPos = %.4f", _moviePosition, frame.position);
                            continue;
                        }
                        
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.samples;
                    }
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

- (void)setAudioPlaying:(BOOL)audioPlaying {
    reader.enableAudio = audioPlaying;
    _audioPlaying = audioPlaying;
    audioButton.selected = audioPlaying;
}

- (void) setIsRecord:(BOOL)isRecord {
    _isRecord = isRecord;
    
    if (!_isRecord) {
        reader.recordFilePath = nil;
    }
}

- (void)stopAudio {
    if ([AudioManager sharedInstance].source == self) {
        [[AudioManager sharedInstance] stop];
        [AudioManager sharedInstance].outputBlock = nil;
    }
    self.audioPlaying = NO;
}

- (void)startAudio {
    self.audioPlaying = YES;
    [AudioManager sharedInstance].sampleRate = reader.mediaInfo.u32AudioSamplerate;
    [AudioManager sharedInstance].channel = reader.mediaInfo.u32AudioChannel;
    [[AudioManager sharedInstance] play];
    __weak VideoView *weakSelf = self;
    [AudioManager sharedInstance].source = self;
    [AudioManager sharedInstance].outputBlock = ^(SInt16 *outData, UInt32 numFrames, UInt32 numChannels){
        [weakSelf fillAudioData:outData numFrames:numFrames numChannels:numChannels];
    };
}

- (void)audioButtonClicked:(id)sender {
    if (!self.audioPlaying) {
        [self startAudio];
    } else {
        self.audioPlaying = NO;
        [[AudioManager sharedInstance] pause];
        [AudioManager sharedInstance].outputBlock = nil;
    }
}

- (void)setUrl:(NSString *)url {
    _url = url;
    _addButton.hidden = [_url length] == 0 ? NO : YES;
}

- (void)stopPlay {
    [self hideActivity];
    [displayLink invalidate];
    displayLink = nil;
    self.videoStatus = Stopped;
    [self stopAudio];
    [reader stop];
    
    @synchronized(rgbFrameArray) {
        [rgbFrameArray removeAllObjects];
    }
    
    @synchronized(_audioFrames) {
        [_audioFrames removeAllObjects];
    }
    
    [self updateUI];
    [self flush];
}

- (void)changeStream {
    
}

- (void)updateStreamCount {
    [self.delegate videoViewDidiUpdateStream:self];
}

- (void)setShowAllRegon:(BOOL)showAllRegon {
    _showAllRegon = showAllRegon;
    scrollView.scrollEnabled = _showAllRegon;
}

- (void)startRecord {
//    _firstFrameRecord = -1;
//    [_avCom startRecord];
//    if (self.bounds.size.width > self.recordDurationLabel.frame.size.width) {
//        self.recordDurationLabel.hidden = NO;
//    }
//    self.recordDurationLabel.text = nil;
//    
//    [self.timer invalidate];
//    self.timer = nil;
//    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5
//                                                  target:self
//                                                selector:@selector(recordFlagImageSpin:)
//                                                userInfo:nil repeats:YES];
}

- (void)stopRecord {
//    [_avCom stopRecord];
//    self.recordDurationLabel.hidden = YES;
//    self.recordDurationLabel.text = nil;
//    [self.timer invalidate];
//    self.timer = nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _addButton.frame = CGRectMake((self.bounds.size.width - 30) / 2, (self.bounds.size.height - 30) / 2, 30, 30);
    
    if (self.fullScreen) {
        kxGlView.frame = scrollView.bounds;
        scrollView.contentSize = scrollView.frame.size;
    } else {
        if (_showAllRegon) {
            CGRect rc = scrollView.frame;
            scrollView.contentSize = rc.size;
            if (displayWidth != 0 && displayHeight != 0) {
                int x = displayWidth > self.bounds.size.width ? 0 : (int)(fabs(self.bounds.size.width - displayWidth) / 2.0 + 0.5);
                int cx = MIN(displayWidth, self.bounds.size.width);
                int cy = MIN(displayHeight*cx/displayWidth, self.bounds.size.height);
                int y = (self.bounds.size.height - cy) / 2.0 + 0.5;
                
                CGRect imageRect;
                imageRect.origin = CGPointMake(x, y);
                imageRect.size = CGSizeMake(cx, cy);
                kxGlView.frame = imageRect;
            }
        } else {
            CGRect rc = scrollView.bounds;
            CGFloat width = rc.size.height * 16.0 / 9.0;
            if (displayHeight != 0 && displayWidth != 0) {
                width = rc.size.height * (float)displayWidth / (float)displayHeight;
                if (width < rc.size.width) {
                    width = rc.size.width;
                }
            }
            
            CGFloat height = rc.size.height;
            kxGlView.frame = CGRectMake(0, 0, width, height);
            scrollView.contentSize = CGSizeMake(width, height);
            NSLog(@"displayWidth = %d displayHeight = %d %f %f frameWidht = %f frameHeight = %f", displayWidth, displayHeight, width, height, self.frame.size.width, self.frame.size.height);
            scrollView.contentOffset = CGPointMake((width - rc.size.width) / 2, 0);
            
            [self reCalculateArcPos];
        }
    }
}

- (void)reCalculateArcPos {
    if (self.fullScreen) {
        return;
    }
    
//    CGPoint point = scrollView.contentOffset;
    CGFloat maxDiffer = scrollView.contentSize.width - scrollView.frame.size.width;
    if (maxDiffer <= 0 || self.videoStatus != Rendering) {
        return;
    } else {
        if (!firstFrame) {
            
        }
    }
}

- (void)beginTransform {
    scrollView.contentOffset = CGPointZero;
    scrollView.zoomScale = 1;
    transforming = YES;
}

- (void)endTransform {
    transforming = NO;
}

- (UIView*)viewForZoomingInScrollView:(UIScrollView *)aScrollView {
    return nil;
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)aScrollView withView:(UIView *)view {
    
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)aScrollView {
    
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

- (CGFloat)displayFrame:(KxVideoFrame *)frame {
    if (frame.width != displayWidth || displayHeight != frame.height) {
        needChangeViewFrame = YES;
    }
    displayWidth = (int)frame.width;
    displayHeight = (int)frame.height;
    if (self.videoStatus == Rendering) {
        if (firstFrame) {
            needChangeViewFrame = YES;
            firstFrame = NO;
            scrollView.scrollEnabled = YES;
            [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
            [self hideActivity];
        }
    }
    if (needChangeViewFrame) {
        [self setNeedsLayout];
        needChangeViewFrame = NO;
    }
    
    [kxGlView render:frame];
    
    _moviePosition = frame.position;
    
    return frame.duration;
}

- (void)displayImage:(UIImage *)image width:(uint)width height:(int)height {
    if (width != displayWidth || displayHeight != height) {
        needChangeViewFrame = YES;
    }
    
    displayWidth = width;
    displayHeight = height;
    
    if (self.videoStatus == Rendering) {
        if (firstFrame) {
            needChangeViewFrame = YES;
            firstFrame = NO;
            scrollView.scrollEnabled = YES;
            [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
            NSLog(@"hideActivity");
            [self hideActivity];
        }
    }
    
    if (needChangeViewFrame) {
        [self setNeedsLayout];
        needChangeViewFrame = NO;
    }
}

- (void)reserveLastImageeBuf {
//    if (self.displayImage != nil && videoRes != nil) {
//        [SnapshotCache cacheImage:self.displayImage puid:[NSString stringWithFormat:@"%s", videoRes->puid.c_str()] index:self.videoRes->cIdx];
//    }
}

- (void)flush {
    [kxGlView flush];
    firstFrame = YES;
    scrollView.zoomScale = 1.0;
    scrollView.scrollEnabled = NO;
}

- (void)setVideoStatus:(IVideoStatus)videoStatus {
    _videoStatus = videoStatus;
}

- (void)handleTapGesture:(UITapGestureRecognizer *)tapGesture {
    [self.delegate videoViewBeginActive:self];
}

- (void)handleDoubleTapGesture:(UIGestureRecognizer *)gestureRecognizer {
    [self.delegate videoViewBeginActive:self];
    
    if (!self.fullScreen) {
        [self.delegate videoViewWillAnimateToFullScreen:self];
        self.fullScreen = YES;
    } else {
        [self.delegate videoViewWillAnimateToNomarl:self];
        self.fullScreen = NO;
    }
}

- (void)setFullScreen:(BOOL)fullScreen {
    _fullScreen = fullScreen;
}

- (void)setActive:(BOOL)active {
    _active = active;
    
//    self.layer.borderWidth = _active && _showActiveStatus ? 1 : 0;
//    self.layer.borderColor = [UIColor colorFromHex:0xc19948].CGColor;
}

- (void)setShowActiveStatus:(BOOL)showActiveStatus {
    _showActiveStatus = showActiveStatus;
    self.layer.borderWidth = _active && _showActiveStatus ? 1 : 0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([[touch view] isKindOfClass:[UIControl class]]) {
        return NO;
    }
    
    return YES;
}

- (void)showActivity {
    [self bringSubviewToFront:activityIndicatorView];
	[activityIndicatorView startAnimating];
    [loadingLabel sizeToFit];
    [self bringSubviewToFront:loadingLabel];
    [loadingLabel setHidden:NO];
}

- (void)hideActivity {
	[activityIndicatorView stopAnimating];
    [loadingLabel setHidden:YES];
}

- (void)showError:(NSString *)text {
    [self bringSubviewToFront:loadingLabel];
    [loadingLabel setHidden:NO];
    [activityIndicatorView stopAnimating];
    loadingLabel.text = text;
    [loadingLabel sizeToFit];
}

@end
