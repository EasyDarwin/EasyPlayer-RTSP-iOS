
#import "VideoPanel.h"
#import "PureLayout.h"
#import "VideoContainerView.h"
#import "AudioManager.h"

static NSString* const RenerStatisObservationContext = @"RenerStatisObservationContext";

#define kContentInset 1

@interface VideoPanel() <VideoViewDelegate> {
    NSMutableArray *resuedViews;
    VideoView *_activeView;
    
    VideoView *primaryView;
    CGRect curPrimaryRect;
    BOOL startAnimate;
    BOOL willAnimateToPrimary;
}

@end

@implementation VideoPanel

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        resuedViews = [[NSMutableArray alloc] init];
        self.layout = IVL_One;
    }
    
    return self;
}

- (void)setActiveView:(VideoView *)activeView {
    if (_activeView != activeView) {
        _activeView.active = NO;
        _activeView = activeView;
        _activeView.active = YES;
    }
}

- (BOOL)hasVideoPlaying {
    BOOL playing = NO;
    for (int i=0; i<[resuedViews count]; i++) {
        VideoContainerView *view = [resuedViews objectAtIndex:i];
        if (view.videoView.videoStatus == Rendering) {
            playing = YES;
            break;
        }
    }
    
    return playing;
}

- (VideoView *)viewInRecording {
    VideoView *target = nil;
    for (int i=0; i<[resuedViews count]; i++) {
//        VideoContainerView *container = [resuedViews objectAtIndex:i];
//        AVCommand *avCom = container.videoView.avCom;
//        if (avCom.recording) {
//            target = container.videoView;
//            break;
//        }
    }
    
    return target;
}

- (BOOL)isVideoPlaying:(NSString *)url {
    BOOL resPlaying = NO;
    for (int i = 0; i < [resuedViews count]; i++) {
//        VideoContainerView *container = [resuedViews objectAtIndex:i];
//        AVCommand *avCom = container.videoView.avCom;
//        if (container.videoView.videoRes == pRes && container.videoView.videoStatus != Stopped) {
//            resPlaying = YES;
//            break;
//        }
    }
    
    return resPlaying;
}

- (void)stopRecord {
    for (int i = 0; i < [resuedViews count]; i++) {
//        VideoContainerView *container = [resuedViews objectAtIndex:i];
//        AVCommand *avCom = container.videoView.avCom;
//        if (avCom.recording)
//        {
//            [container.videoView stopRecord];
//        }
    }
}

- (void)stopAll {
    for (int i = 0; i < [resuedViews count]; i++) {
        VideoContainerView *view = [resuedViews objectAtIndex:i];
        view.videoView.isRecord = NO;
//        [view.videoView stopPlay];
    }
}

- (void)restore {
    for (int i = 0; i < [resuedViews count]; i++) {
        VideoContainerView *view = [resuedViews objectAtIndex:i];
        if (view.videoView.videoStatus == Stopped) {
//            NSInteger mode = view.videoView.avCom.playMode;
            [view.videoView startPlay];
        }
    }
}

- (VideoContainerView *)nextAvailableContainer {
    int nIndex = -1;

    for (int i=0; i<[resuedViews count]; i++) {
        VideoContainerView *view = [resuedViews objectAtIndex:i];
        if (view.videoView.videoStatus == Stopped && view.videoView.active) {
            nIndex = i;
            break;
        }
    }
    
    VideoContainerView *view = nil;
    if (nIndex >= 0) {
        view = [resuedViews objectAtIndex:nIndex];
    } else {
        view = [resuedViews firstObject];
    }
    
    if (view.videoView.videoStatus == Rendering) {
        
    }

    return view;
}

- (void)unregistObserver {
    for (int i = 0; i < [resuedViews count]; i++) {
        VideoContainerView *view = [resuedViews objectAtIndex:i];
        [view.videoView removeObserver:self forKeyPath:@"audioPlaying"];
        [view.videoView removeObserver:self forKeyPath:@"videoStatus"];
    }
}

- (void)setLayout:(IVideoLayout)layout {
    if (_layout == layout) {
        return;
    }
    
    _layout = layout;
    NSInteger diff = _layout - [resuedViews count];
    for (int i = 0; i < diff; i++) {
        VideoContainerView *view = [VideoContainerView newAutoLayoutView];
        view.videoView.delegate = self;
        [resuedViews addObject:view];
        [view.videoView.addButton addTarget:self action:@selector(addCameraRes:) forControlEvents:UIControlEventTouchUpInside];
        
        [view.videoView addObserver:self forKeyPath:@"audioPlaying" options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:(__bridge void *)(RenerStatisObservationContext)];
        [view.videoView addObserver:self forKeyPath:@"videoStatus" options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:(__bridge void *)(RenerStatisObservationContext)];
    }

    for (int i = (int)layout; i<[resuedViews count]; i++) {
        VideoContainerView *view = [resuedViews objectAtIndex:i];
        if (view.videoView.videoStatus >= Connecting) {
            [view.videoView stopPlay];
            view.videoView.url = nil;
        }
    }
    
    for (int i = 0; i < [resuedViews count]; i++) {
        VideoContainerView *view = [resuedViews objectAtIndex:i];
        if (view.superview != nil) {
            [view removeFromSuperview];
        }
    }
    
    BOOL hasActiveView = NO;
    NSInteger rowCnt = [self rowCount];
//    NSMutableArray *viewsOneCol = [[NSMutableArray alloc] init];
    VideoContainerView *topView = nil;
    NSInteger colCount = _layout / rowCnt;
    for (int i = 0; i < rowCnt; i++) {
        VideoContainerView *leftView = nil;
        NSMutableArray *viewsOneRow = [[NSMutableArray alloc] init];
        for (int j = 0; j < colCount; j++) {
            VideoContainerView *view = [resuedViews objectAtIndex:(i * colCount + j)];
            [self addSubview:view];
            [viewsOneRow addObject:view];
            
            if (view.videoView.active) {
                hasActiveView = YES;
            }
            
            if (leftView == nil) {
                [view autoPinEdgeToSuperviewEdge:ALEdgeLeading];
                
                if (topView == nil) {
                    [view autoPinEdgeToSuperviewEdge:ALEdgeTop];
                } else {
                    [UIView autoSetPriority:UILayoutPriorityRequired - 1 forConstraints:^{
                        [view autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:topView withOffset:kContentInset];
                    }];
                    
                    [view autoMatchDimension:ALDimensionHeight toDimension:ALDimensionHeight ofView:topView];
                }
                
                if (i == rowCnt -1) {
                    [view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
                }
                
                topView = view;
            } else {
                [view autoAlignAxis:ALAxisHorizontal toSameAxisOfView:leftView];
                [UIView autoSetPriority:UILayoutPriorityRequired - 1 forConstraints:^{
                    [view autoPinEdge:ALEdgeLeading toEdge:ALEdgeTrailing ofView:leftView withOffset:kContentInset];
                }];
                
                [view autoMatchDimension:ALDimensionWidth toDimension:ALDimensionWidth ofView:leftView];
                [view autoMatchDimension:ALDimensionHeight toDimension:ALDimensionHeight ofView:leftView];
            }
            
            if (j == colCount - 1) {
                [view autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
            }
            
            leftView = view;
        }
        
        leftView = nil;
    }
    
    if (!hasActiveView) {
        for (VideoContainerView *view in resuedViews) {
            view.videoView.active = NO;
        }
        
        VideoContainerView *view = [resuedViews firstObject];
        [self videoViewBeginActive:view.videoView];
    }
}

- (IBAction)addCameraRes:(id)sender {
    UIButton *button = (UIButton *)sender;
    VideoView *view = (VideoView *)button.superview;
    [self videoViewBeginActive:view];
    [self.delegate videoViewWillAddNewRes:view];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    if (startAnimate) {
        if (willAnimateToPrimary) {
            primaryView.frame = self.bounds;
        } else {
            primaryView.frame = primaryView.container.frame;
        }
        
        startAnimate = NO;
    }
}

- (NSInteger)rowCount {
    NSInteger count = 1;
    switch (self.layout) {
        case IVL_Four:
            count = 2;
            break;
        case IVL_Nine:
            count = 3;
            break;
        default:
            break;
    }
    
    return count;
}

- (CGFloat)cellWidth {
    CGSize size = [UIScreen mainScreen].bounds.size;
    return (size.width - kContentInset * [self insertCount]) / ([self insertCount] + 1);
}

- (CGFloat)cellHeight {
    return (self.frame.size.height - kContentInset * [self insertCount]) / ([self insertCount] + 1);
}

- (NSInteger)insertCount {
    NSInteger insetCount = 0;
    switch (self.layout) {
        case IVL_Four:
            insetCount = 1;
            break;
        case IVL_Nine:
            insetCount = 2;
            break;
        default:
            break;
    }
    
    return insetCount;
}

- (void)videoViewBeginActive:(VideoView *)view {
    [self setActiveView:view];
    [self.delegate didSelectVideoView:view];
}

- (void)videoViewWillAnimateToFullScreen:(VideoView *)view {
    [self.delegate videoViewWillAnimateToFullScreen:view];
}

- (void)videoViewWillAnimateToNomarl:(VideoView *)view {
    [self.delegate videoViewWillAnimateToNomarl:view];
}

//- (void)videoViewWillAnimateToPrimary:(VideoView *)view complete:(dispatch_block_t)block {
//    primaryView = view;
//    [view removeFromSuperview];
//    [self addSubview:view];
//    view.frame = view.container.frame;
//    willAnimateToPrimary = YES;
//    startAnimate = YES;
//    
//    [UIView animateWithDuration:0.25
//                     animations:^{
//                         
//                         [self setNeedsLayout];
//                         [self layoutIfNeeded];
//              
//                     }completion:^(BOOL finish){
//                     
//                         block();
//                     }];
//}
//
//- (void)videoViewWillAnimateToNormal:(VideoView *)view complete:(dispatch_block_t)block {
//    primaryView = view;
//    willAnimateToPrimary = NO;
//    startAnimate = YES;
//    [UIView animateWithDuration:0.25
//                     animations:^{
//                         
//                         [self setNeedsLayout];
//                         [self layoutIfNeeded];
//                         
//                     }completion:^(BOOL finish){
//                         
//                         [view removeFromSuperview];
//                         [view.container addSubview:view];
//                         view.frame = view.container.bounds;
//
//                         primaryView = nil;
//                         block();
//                     }];
//}

- (void)videoView:(VideoView *)view response:(int)error {
    if (view == _activeView) {
        [self.delegate activeVideoViewRendStatusChanged:view];
    }
}

- (void)videoView:(VideoView *)view connectionBreak:(int)error {
    if (view == _activeView) {
        [self.delegate activeVideoViewRendStatusChanged:_activeView];
    }
}

- (void)videoViewWillTryToConnect:(VideoView *)view {
    if (view == _activeView) {
        [self.delegate activeVideoViewRendStatusChanged:_activeView];
    }
}

- (void)videoViewDidiUpdateStream:(VideoView *)view {
    if (view == _activeView) {
        [self.delegate activeViewDidiUpdateStream:_activeView];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == (__bridge void * )(RenerStatisObservationContext)) {
        VideoView *view = (VideoView *)object;
        if ([keyPath isEqualToString:@"audioPlaying"]) {
            if (view.audioPlaying) {
                for (int i = 0; i < [resuedViews count]; i++) {
                    VideoContainerView *container = [resuedViews objectAtIndex:i];
                    if (container.videoView != view) {
                        [container.videoView stopAudio];
                    }
                }
            }
        }
        
        [self.delegate activeVideoViewRendStatusChanged:view];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)dealloc {
    [self unregistObserver];
}

@end
