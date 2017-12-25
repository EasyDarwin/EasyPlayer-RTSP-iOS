
#import <UIKit/UIKit.h>
#import "VideoContainerView.h"

typedef NS_OPTIONS(NSInteger, IVideoLayout){
    IVL_One = 1,
    IVL_Four = 4,
    IVL_Nine = 9,
};

@protocol VideoPanelDelegate;

@interface VideoPanel : UIView

@property (nonatomic, weak) id<VideoPanelDelegate> delegate;
@property (nonatomic) IVideoLayout layout;
@property (nonatomic, strong) VideoView *activeView;

- (VideoContainerView *) nextAvailableContainer;

- (BOOL) hasVideoPlaying;
- (VideoView *) viewInRecording;
- (BOOL) isVideoPlaying:(NSString *)url;

- (void) stopRecord;
- (void) stopAll;
- (void) restore;
- (void) unregistObserver;

@end

@protocol VideoPanelDelegate <NSObject>

@optional
- (void) activeViewDidiUpdateStream:(VideoView *)view;
- (void) didSelectVideoView:(VideoView *)view;
- (void) activeVideoViewRendStatusChanged:(VideoView *)view;

- (void) videoViewWillAnimateToFullScreen:(VideoView *)view;
- (void) videoViewWillAnimateToNomarl:(VideoView *)view;

- (void) videoViewWillAddNewRes:(VideoView *)view;

@end
