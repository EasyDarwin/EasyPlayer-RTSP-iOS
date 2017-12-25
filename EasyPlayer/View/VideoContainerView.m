

#import "VideoContainerView.h"
#import "PureLayout.h"

@interface VideoContainerView() <UIGestureRecognizerDelegate>

@end

@implementation VideoContainerView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        
        _videoView = [[VideoView alloc] initWithFrame:self.bounds];
        [self addSubview:_videoView];
        _videoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _videoView.container = self;
    }
    
    return self;
}

@end
