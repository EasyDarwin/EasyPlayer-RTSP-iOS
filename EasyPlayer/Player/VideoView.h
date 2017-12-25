//
#import <UIKit/UIKit.h>
#import "RtspDataReader.h"

typedef enum {
    Stopped,
    Suspend,
    Connecting,
    Rendering,
}IVideoStatus;

@protocol VideoViewDelegate;

@interface VideoView : UIView <UIGestureRecognizerDelegate>

@property (nonatomic, weak)UIView *container;
@property (nonatomic, strong) UIButton *addButton;

@property (nonatomic, copy)NSString *url;

@property (nonatomic, weak) id<VideoViewDelegate> delegate;

@property (nonatomic) BOOL active;
@property (nonatomic, strong)RtspDataReader *reader;
@property (nonatomic, assign)IVideoStatus videoStatus;

@property (nonatomic)BOOL showAllRegon;
@property(nonatomic) BOOL fullScreen;
@property (nonatomic, assign)BOOL showActiveStatus;
@property (nonatomic, readonly)BOOL audioPlaying;

// 是否启用硬解
@property (nonatomic)BOOL useHWDecoder;

- (void)beginTransform;
- (void)endTransform;

- (void)reserveLastImageeBuf;

// ----------------- 视频 -----------------
- (void)startPlay;
- (void)stopPlay;


- (void)flush;
//- (void)puaseReplay;
//- (void)resumeReplay;
//- (void)snapshot:(id)sender;

// ----------------- 音频 -----------------
- (void)startRecord;
- (void)stopRecord;

- (void)stopAudio;

@end


@protocol VideoViewDelegate <NSObject>

@optional
- (void)videoViewDidiUpdateStream:(VideoView *)view;
- (void)videoViewBeginActive:(VideoView *)view;

- (void)videoViewWillAnimateToFullScreen:(VideoView *)view;
- (void)videoViewWillAnimateToNomarl:(VideoView *)view;

- (void)videoViewWillTryToConnect:(VideoView *)view;

@end
