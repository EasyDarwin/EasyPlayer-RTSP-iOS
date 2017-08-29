#import "PlayViewController.h"
#import <VideoToolbox/VideoToolbox.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>
#import <EasyAudioDecode/EasyAudioDecode.h>
#import <CommonCrypto/CommonDigest.h>
#import "EasyRTSPClientAPI.h"
#import "ToolBar.h"

#define MIN_SIZE_PER_FRAME 100*1024
#define AUDIO_BUF_SIZE 3

PlayViewController* pvc = nil;
Easy_RTSP_Handle rtspHandle = NULL;
static NSObject *lockObj = nil;
static int nSizePerFrame = MIN_SIZE_PER_FRAME;
static AudioQueueRef audioQueue = NULL;
static AudioQueueBufferRef outQB[AUDIO_BUF_SIZE];
static AudioStreamBasicDescription audioDescription;
static EasyAudioHandle* hAudioDecode = NULL;
static unsigned char pcm_buffer[MIN_SIZE_PER_FRAME] = {0};

typedef struct Node {
    char *data;
    int len;
    int type;
    uint64_t stamp;
}MediaNode;

void audio_callback(void *input, AudioQueueRef outQ, AudioQueueBufferRef outQB)
{
    static char _last = 0;
    outQB->mAudioDataByteSize = nSizePerFrame;
    memset(outQB->mAudioData,_last,nSizePerFrame);
    [pvc.mediaCond lock];
    NSValue* node = [pvc.mediaArray lastObject];
    MediaNode mNode = {0};
    if(node){
        [node getValue:&mNode];
    }
    if(mNode.type == 1){
        outQB->mAudioDataByteSize = mNode.len;
        memcpy(outQB->mAudioData, mNode.data, outQB->mAudioDataByteSize);
        _last = *(mNode.data + mNode.len - 1);
        free(mNode.data);
        [pvc.mediaArray removeLastObject];
        [pvc.mediaCond signal];
    }
    [pvc.mediaCond unlock];
    AudioQueueEnqueueBuffer(audioQueue, outQB, 0, NULL);
}

BOOL initAudio(EASY_MEDIA_INFO_T* pMediaInfo)
{
    NSError *audioSessionError;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryAmbient error:&audioSessionError];
    if(audioSessionError){
        NSLog(@"AVAudioSession error setting category:%@",audioSessionError);
    }
    [audioSession setActive:YES error:&audioSessionError];
    if(audioSessionError){
        NSLog(@"AVAudioSession error activating: %@",audioSessionError);
    }
    
    hAudioDecode = EasyAudioDecodeCreate(pMediaInfo->u32AudioCodec,pMediaInfo->u32AudioSamplerate, pMediaInfo->u32AudioChannel, 16);
    if(!hAudioDecode){
        NSLog(@"EasyAudioDecodeCreate fail");
    }
    if(hAudioDecode->code == EASY_SDK_AUDIO_CODEC_G711A || hAudioDecode->code == EASY_SDK_AUDIO_CODEC_G711U){
        nSizePerFrame = 1024;
    }else{
        nSizePerFrame = 2048;
    }
    
    memset(&audioDescription,0,sizeof(AudioStreamBasicDescription));
    audioDescription.mSampleRate = pMediaInfo->u32AudioSamplerate;//8000;采样率
    audioDescription.mFormatID = kAudioFormatLinearPCM;
    audioDescription.mFramesPerPacket = 1;//每一个packet一侦数据
    audioDescription.mReserved = 0;
    
    audioDescription.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    audioDescription.mChannelsPerFrame = pMediaInfo->u32AudioChannel;//1;单声道
    audioDescription.mBitsPerChannel = 16;//每个采样点16bit量化
    audioDescription.mBytesPerFrame = audioDescription.mBitsPerChannel * audioDescription.mChannelsPerFrame /8;
    audioDescription.mBytesPerPacket = audioDescription.mBytesPerFrame * audioDescription.mFramesPerPacket;
    
    OSStatus err = AudioQueueNewOutput(&audioDescription, audio_callback, (__bridge void * _Nullable)(pvc), nil, kCFRunLoopCommonModes, 0, &audioQueue);//使用player的内部线程播
    if(err != noErr){
        NSLog(@"AudioQueueNewOutput 不成功, err = %d", (int)err);
        return NO;
    }
    
    for(int i=0;i<AUDIO_BUF_SIZE;i++){
        AudioQueueAllocateBuffer(audioQueue, nSizePerFrame, &outQB[i]);
        outQB[i]->mAudioDataByteSize = nSizePerFrame;
        memset(outQB[i]->mAudioData, 0, nSizePerFrame);
        AudioQueueEnqueueBuffer(audioQueue, outQB[i], 0, NULL);
    }
    AudioQueueStart(audioQueue, NULL);
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
    return YES;
}

void destroyAudio() {
    if(audioQueue){
        AudioQueueStop(audioQueue, YES);
        for(int i=0;i<AUDIO_BUF_SIZE;i++){
            AudioQueueFreeBuffer(audioQueue, outQB[i]);
        }
        AudioQueueDispose(audioQueue, YES);
        audioQueue = NULL;
    }
    if(hAudioDecode){
        EasyAudioDecodeClose(hAudioDecode);
        hAudioDecode = NULL;
    }
    
}

int RTSPClientCallBack(int _chid, int *_chPtr, int _frameType, char *_pBuf, RTSP_FRAME_INFO *_frameInfo)
{
    if (_frameType == EASY_SDK_AUDIO_FRAME_FLAG && _frameInfo != NULL && _pBuf != NULL){
        if(!audioQueue){
            NSLog(@"drop audio because audioQueue is NULL");
            return 0;
        }
        if(!hAudioDecode){
            NSLog(@"drop audio because hAudioDecode is NULL");
            return 0;
        }
        if(_frameInfo->length >= nSizePerFrame || _frameInfo->length <= 0){
            NSLog(@"drop audio because frameInfo->lenght is invalid");
            return 0;
        }
        
        int pcm_length = 0;
        int err = EasyAudioDecode(hAudioDecode, (unsigned char*)_pBuf, 0, _frameInfo->length, pcm_buffer, &pcm_length);
        if(err == 0){
            MediaNode mNode = {0};
            mNode.len = pcm_length;
            mNode.data = malloc(mNode.len);
            memcpy(mNode.data,pcm_buffer,mNode.len);
            mNode.type = 1;
            mNode.stamp = _frameInfo->timestamp_sec * 1000000 + _frameInfo->timestamp_usec;
            NSValue *node = [NSValue value:&mNode withObjCType:@encode(MediaNode)];
            [pvc.mediaCond lock];
            [pvc.mediaArray insertObject:node atIndex:0];
            [pvc.mediaArray sortUsingComparator:^NSComparisonResult(id _Nonnull obj1, id  _Nonnull obj2) {
                MediaNode node1, node2;
                [obj1 getValue:&node1];
                [obj2 getValue:&node2];
                if(node1.stamp > node2.stamp){
                    return NSOrderedAscending;
                }else if(node1.stamp < node2.stamp){
                    return NSOrderedDescending;
                }else {
                    return NSOrderedSame;
                }
            }];
            [pvc.mediaCond signal];
            [pvc.mediaCond unlock];
        }else{
            NSLog(@"EasyAudioDecode error, err = %d", err);
        }
    } else if (_frameType == EASY_SDK_VIDEO_FRAME_FLAG && _frameInfo != NULL && _pBuf != NULL && _frameInfo->codec == EASY_SDK_VIDEO_CODEC_H264) {
        MediaNode mNode = {0};
        mNode.len = _frameInfo->length;
        mNode.data = malloc(mNode.len);
        memcpy(mNode.data,_pBuf,mNode.len);
        mNode.type = 2;
        mNode.stamp = _frameInfo->timestamp_sec * 1000000 + _frameInfo->timestamp_usec;
        NSValue *node = [NSValue value:&mNode withObjCType:@encode(MediaNode)];
        [pvc.mediaCond lock];
        [pvc.mediaArray insertObject:node atIndex:0];
        [pvc.mediaArray sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
            MediaNode node1, node2;
            [obj1 getValue:&node1];
            [obj2 getValue:&node2];
            if(node1.stamp > node2.stamp){
                return NSOrderedAscending;
            }else if(node1.stamp < node2.stamp){
                return NSOrderedDescending;
            }else {
                return NSOrderedSame;
            }
        }];
        [pvc.mediaCond signal];
        [pvc.mediaCond unlock];
    } else if (_frameType == EASY_SDK_MEDIA_INFO_FLAG && _pBuf != NULL) {//回调出媒体信息
        EASY_MEDIA_INFO_T mediainfo;
        memcpy(&mediainfo, _pBuf, sizeof(EASY_MEDIA_INFO_T));
        NSLog(@"RTSP DESCRIBE Get Media Info: video:%u fps:%u audio:%u channel:%u sampleRate:%u \n",
              mediainfo.u32VideoCodec, mediainfo.u32VideoFps, mediainfo.u32AudioCodec, mediainfo.u32AudioChannel, mediainfo.u32AudioSamplerate);
        initAudio(&mediainfo);
        NSThread *videoThread = [[NSThread alloc] initWithTarget:pvc selector:@selector(procVideo) object:nil];
        [videoThread start];
    }
    return 0;
}




@interface PlayViewController()<UIAlertViewDelegate>
{
    UIAlertView* _authAlertView;
    NSTimer* _toolbarTimer;
    VTDecompressionSessionRef _decompressionSession;
    CMVideoFormatDescriptionRef _formatDesc;
    CVPixelBufferRef _pixelBuffer;
}
@property (nonatomic,strong)UIImageView *imageView;
@property (nonatomic,strong)ToolBar *topBar,*bottomBar;
@property (nonatomic,strong)UIBarButtonItem *backBtnItem, *spaceItem, *fullBtnItem;
@property (nonatomic,strong)UIButton *backBtn, *fullBtn;

@end




@implementation PlayViewController

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    dispatch_queue_t globalQueue=dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(globalQueue, ^{
        @synchronized (lockObj) {
            EasyRTSP_CloseStream(rtspHandle);
            EasyRTSP_Deinit(&rtspHandle);
            rtspHandle = NULL;
            [_mediaCond lock];
            for(id node in _mediaArray){
                MediaNode mNode = {0};
                [node getValue:&mNode];
                if(mNode.type != 0){
                    free(mNode.data);
                }
            }
            [_mediaArray removeAllObjects];
            [_mediaCond signal];
            [_mediaCond unlock];
            destroyAudio();
            
            if(_decompressionSession) {
                VTDecompressionSessionInvalidate(_decompressionSession);
                CFRelease(_decompressionSession);
                _decompressionSession = NULL;
            }
            
            if(_formatDesc) {
                CFRelease(_formatDesc);
                _formatDesc = NULL;
            }
            
        }
    });
    
}

- (void)dealloc
{
    if (spsData != NULL)
    {
        free(spsData);
        spsData = NULL;
    }
    
    if (ppsData != NULL)
    {
        free(ppsData);
        ppsData = NULL;
    }
    
    if (pInnerData != NULL)
    {
        free(pInnerData);
        pInnerData = NULL;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"视频播放";
    _imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
    [self.view addSubview:_imageView];
    [self.view bringSubviewToFront:_imageView];
    // create our AVSampleBufferDisplayLayer and add it to the view
    self.videoLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.videoLayer.frame = self.view.frame;
    self.videoLayer.bounds = self.view.bounds;
    self.videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    
    // set Timebase, you may need this if you need to display frames at specific times
    // I didn't need it so I haven't verified that the timebase is working
    CMTimebaseRef controlTimebase;
    CMTimebaseCreateWithMasterClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase);
    
    //videoLayer.controlTimebase = controlTimebase;
    CMTimebaseSetTime(self.videoLayer.controlTimebase, kCMTimeZero);
    CMTimebaseSetRate(self.videoLayer.controlTimebase, 1.0);
    [[self.view layer] addSublayer:self.videoLayer];
    
    self.spaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                   target:nil
                                                                   action:nil];
    self.topBar  = [[ToolBar alloc] initWithFrame:CGRectMake(0, 0, ScreenWidth, TOOLBAR_HEIGHT)];
    self.topBar.tintColor = [UIColor blackColor];
    self.bottomBar  = [[ToolBar alloc] initWithFrame:CGRectMake(0, ScreenHeight-TOOLBAR_HEIGHT, ScreenWidth, TOOLBAR_HEIGHT)];
    self.bottomBar.tintColor = [UIColor blackColor];
    self.topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.bottomBar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.topBar];
    [self.view addSubview:self.bottomBar];
    
    self.backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backBtn.frame = CGRectMake(0,0,TOOLBAR_HEIGHT,TOOLBAR_HEIGHT);
    self.backBtn.backgroundColor = [UIColor clearColor];
    self.backBtn.showsTouchWhenHighlighted = YES;
    [self.backBtn setBackgroundImage:[UIImage imageNamed:@"BackVideo"] forState:UIControlStateNormal];
    [self.backBtn addTarget:self action:@selector(backBtnDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    self.backBtnItem = [[UIBarButtonItem alloc] init];
    self.backBtnItem.customView = self.backBtn;
    [self.topBar setItems:@[self.backBtnItem, self.spaceItem] animated:NO];
    
    self.fullBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fullBtn.frame = CGRectMake(0, 0, TOOLBAR_HEIGHT, TOOLBAR_HEIGHT);
    self.fullBtn.backgroundColor = [UIColor clearColor];
    self.fullBtn.showsTouchWhenHighlighted = YES;
    [self.fullBtn setBackgroundImage:[UIImage imageNamed:@"LandspaceVideo"] forState:UIControlStateNormal];
    [self.fullBtn setBackgroundImage:[UIImage imageNamed:@"PortraitVideo"] forState:UIControlStateSelected];
    [self.fullBtn addTarget:self action:@selector(fullBtnDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    self.fullBtnItem = [[UIBarButtonItem alloc] init];
    self.fullBtnItem.customView = self.fullBtn;
    [self.bottomBar setItems:@[self.spaceItem, self.fullBtnItem] animated:NO];
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    tapGesture.numberOfTapsRequired = 1;
    [self.view addGestureRecognizer:tapGesture];
    [self restartToolbarTimer];
    
    spsData = NULL;
    ppsData = NULL;
    pvc = self;
    xps_found = NO;
    pInnerData = NULL;
    innerLen = 0;
    
    if(lockObj == nil){
        lockObj = [[NSObject alloc] init];
    }
    _mediaArray = [NSMutableArray array];
    _mediaCond = [[NSCondition alloc] init];
    int err = EasyRTSP_Activate("79393674362F2B32734B79415A6D565A70707159792F564659584E3555477868655756794B56634D5671442F532B424859585A7062695A4359574A76633246414D6A41784E6B566863336C4559584A33615735555A5746745A57467A65513D3D");
    if(err){
        _authAlertView = [[UIAlertView alloc] initWithTitle:@"授权失败" message:nil delegate:self
                                              cancelButtonTitle:@"关闭" otherButtonTitles:nil];
        [_authAlertView show];
    }
    dispatch_queue_t globalQueue=dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(globalQueue, ^{
        @synchronized (lockObj) {
            hAudioDecode = NULL;
            audioQueue = NULL;
            const  char *url =  [self.urlStr UTF8String];
            EasyRTSP_Init(&rtspHandle);
            EasyRTSP_SetCallback(rtspHandle, RTSPClientCallBack);
            EasyRTSP_OpenStream(rtspHandle, 1, (char *)url, EASY_RTP_OVER_TCP, EASY_SDK_VIDEO_FRAME_FLAG|EASY_SDK_AUDIO_FRAME_FLAG, 0,0, NULL, 1000, 0,0x01,3);
        }
    });
    }

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(alertView == _authAlertView){
        [self dismissViewControllerAnimated:YES completion:nil];
    }

}

NSString * const naluTypesStrings[] =
{
    @"0: Unspecified (non-VCL)",
    @"1: Coded slice of a non-IDR picture (VCL)",    // P frame
    @"2: Coded slice data partition A (VCL)",
    @"3: Coded slice data partition B (VCL)",
    @"4: Coded slice data partition C (VCL)",
    @"5: Coded slice of an IDR picture (VCL)",      // I frame
    @"6: Supplemental enhancement information (SEI) (non-VCL)",
    @"7: Sequence parameter set (non-VCL)",         // SPS parameter
    @"8: Picture parameter set (non-VCL)",          // PPS parameter
    @"9: Access unit delimiter (non-VCL)",
    @"10: End of sequence (non-VCL)",
    @"11: End of stream (non-VCL)",
    @"12: Filler data (non-VCL)",
    @"13: Sequence parameter set extension (non-VCL)",
    @"14: Prefix NAL unit (non-VCL)",
    @"15: Subset sequence parameter set (non-VCL)",
    @"16: Reserved (non-VCL)",
    @"17: Reserved (non-VCL)",
    @"18: Reserved (non-VCL)",
    @"19: Coded slice of an auxiliary coded picture without partitioning (non-VCL)",
    @"20: Coded slice extension (non-VCL)",
    @"21: Coded slice extension for depth view components (non-VCL)",
    @"22: Reserved (non-VCL)",
    @"23: Reserved (non-VCL)",
    @"24: STAP-A Single-time aggregation packet (non-VCL)",
    @"25: STAP-B Single-time aggregation packet (non-VCL)",
    @"26: MTAP16 Multi-time aggregation packet (non-VCL)",
    @"27: MTAP24 Multi-time aggregation packet (non-VCL)",
    @"28: FU-A Fragmentation unit (non-VCL)",
    @"29: FU-B Fragmentation unit (non-VCL)",
    @"30: Unspecified (non-VCL)",
    @"31: Unspecified (non-VCL)",
};

-(void) receivedRawVideoFrame:(uint8_t *)frame withSize:(uint32_t)frameSize
{
    OSStatus status = noErr;
    uint8_t *pData = frame;
    int len = frameSize;
    if (_formatDesc == NULL)
    {
        int spsIndex = 0;
        int ppsIndex = 0;
        int spsLength = 0;
        int ppsLength = 0;
        getXps2(pData, 0, len, 7, &spsIndex, &spsLength);
        getXps2(pData, 0, len, 8, &ppsIndex, &ppsLength);
        
        if (spsLength == 0 || ppsLength == 0)
        {
            return;
        }
        
        if (spsData != NULL)
        {
            free(spsData);
            spsData = NULL;
        }
        
        if (ppsData != NULL)
        {
            free(ppsData);
            ppsData = NULL;
        }
        
        spsData = (unsigned char *)malloc(spsLength);
        memcpy(spsData, pData + spsIndex, spsLength);
        
        ppsData = (unsigned char *)malloc(ppsLength);
        memcpy(ppsData, pData + ppsIndex, ppsLength);
        
        const uint8_t* const parameterSetPointers[2] = { spsData, ppsData };
        const size_t parameterSetSizes[2] = { (size_t)spsLength, (size_t)ppsLength };
        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL,
                                                                              2,
                                                                              parameterSetPointers,
                                                                              parameterSetSizes,
                                                                              4,
                                                                              &_formatDesc);
        NSLog(@"Found all data for CMVideoFormatDescription. Creation: %@.", (status == noErr) ? @"successfully." : @"failed.");
        if (status != noErr)
        {
            return;
        }
        
        VTDecompressionOutputCallbackRecord callback;
        callback.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
        callback.decompressionOutputRefCon = (__bridge void *)self;
        NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                                          [NSNumber numberWithBool:YES],(id)kCVPixelBufferOpenGLESCompatibilityKey,
                                                          [NSNumber numberWithInt:kCVPixelFormatType_32BGRA],(id)kCVPixelBufferPixelFormatTypeKey,
                                                          nil
                                                          ];
        //kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
        status = VTDecompressionSessionCreate(kCFAllocatorDefault, _formatDesc, NULL, (__bridge CFDictionaryRef)destinationImageBufferAttributes, &callback, &_decompressionSession);
        NSLog(@"Creating Video Decompression Session: %@.", (status == noErr) ? @"successfully." : @"failed.");
    }
    
    int nDiff = 0;
    int nalPackLen = len;
    unsigned char *pTemp = pData;
    for (int i=0; i<len; i++)
    {
        if (*(pTemp) == 0 && *(pTemp+1) == 0)
        {
            if (*(pTemp+2) == 1)
            {
                int nalu_type = ((uint8_t)*(pTemp+3) & 0x1F);
                if (nalu_type == 1 || nalu_type == 5)
                {
                    nDiff = 3;
                    break;
                }
            }
            else if (*(pTemp+2) == 0 && *(pTemp+3) == 1)
            {
                int nalu_type = ((uint8_t)*(pTemp+4) & 0x1F);
                
                if (nalu_type == 1 || nalu_type == 5)
                {
                    nDiff = 4;
                    break;
                }
            }
        }
        
        pTemp++;
        nalPackLen--;
    }
    
    if (nDiff == 0)
    {
        return;
    }
    
    int nalu_type = ((uint8_t)*(pTemp + nDiff) & 0x1F);
    
    if (nalu_type == 1 || nalu_type == 5)
    {
        if (nDiff == 3)
        {
            // 只有2个0 前面补位0
            if (innerLen <= nalPackLen)
            {
                innerLen = nalPackLen + 1;
                pInnerData = (unsigned char *)realloc(pInnerData, innerLen);
            }
            
            memcpy(pInnerData + 1, pTemp, nalPackLen);
            pTemp = pInnerData;
            nalPackLen++;
        }
        
        CMBlockBufferRef videoBlock = NULL;
        OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL, pTemp, nalPackLen, kCFAllocatorNull, NULL, 0, nalPackLen, 0, &videoBlock);
        
        int reomveHeaderSize = nalPackLen - 4;
        const uint8_t sourceBytes[] = {(uint8_t)(reomveHeaderSize >> 24), (uint8_t)(reomveHeaderSize >> 16), (uint8_t)(reomveHeaderSize >> 8), (uint8_t)reomveHeaderSize};
        status = CMBlockBufferReplaceDataBytes(sourceBytes, videoBlock, 0, 4);
        
        CMSampleBufferRef sampleBuffer = NULL;
        CMSampleTimingInfo sampleTiming = { 1/25, 12012/30000, 10010/30000 };
        const size_t sampleSize = len;
        status = CMSampleBufferCreate(kCFAllocatorDefault,
                                      videoBlock, true, NULL, NULL,
                                      _formatDesc, 1, 1, &sampleTiming, 1,
                                      &sampleSize, &sampleBuffer);
        
        if(status == noErr) {
            CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
            CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
            [self.videoLayer enqueueSampleBuffer:sampleBuffer];
            //        if(![[NSFileManager defaultManager] fileExistsAtPath:_imagePath]){
            VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
            VTDecodeInfoFlags flagOut;
            CVPixelBufferRef outputPixelBuffer = NULL;
            status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags, &outputPixelBuffer, &flagOut);
            
            if(status == kVTInvalidSessionErr) {
                NSLog(@"IOS8VT: Invalid session, reset decoder session");
            } else if(status == kVTVideoDecoderBadDataErr) {
                NSLog(@"IOS8VT: decode failed status=%d(Bad data)", (int)status);
            } else if(status != noErr) {
                NSLog(@"IOS8VT: decode failed status=%d", (int)status);
            }
            //        }
            
            CFRelease(sampleBuffer);
        }

    }
}

int getXps2(unsigned char *data, int offset, int length, int type, int *outPos, int *xpsLen)
{
    int i;
    int pos0;
    int pos1;
    pos0 = -1;
    
    for (i = offset; i < length - 4; i++)
    {
        if ((0 == data[i]) && (0 == data[i + 1]) && (1 == data[i + 2]) && (type == (0x0F & data[i + 3])))
        {
            pos0 = i;
            break;
        }
    }
    
    if (-1 == pos0)
    {
        return -1;
    }
    
    pos1 = -1;
    for (i = pos0 + 4; i < length - 4; i++)
    {
        if ((0 == data[i]) && (0 == data[i + 1]) && (1 == data[i + 2]))
        {
            pos1 = i;
            
            if (data[i - 1] == 0)
            {
                // 00 00 00 01
                pos1--;
            }
            break;
        }
    }
    
    if (-1 == pos1)
    {
        return -2;
    }
    
    *outPos = pos0 + 3;
    *xpsLen = pos1 - pos0 - 3;
    printf("type = %d xpsLen= %d ; outPos = %d pos1 = %d\r\n", type, *xpsLen, *outPos, pos1);
    return 0;
}

void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
                                             void *sourceFrameRefCon,
                                             OSStatus status,
                                             VTDecodeInfoFlags infoFlags,
                                             CVImageBufferRef imageBuffer,
                                             CMTime presentationTimeStamp,
                                             CMTime presentationDuration)
{
    if (status != noErr){
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"Decompressed error: %@", error);
    }else{
//        static int frame1 = 0;
//        //        CMTime lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
//        
//        if( frame1 == 0 && pvc.videoWriter.status != AVAssetWriterStatusWriting &&  pvc.videoWriter.status != AVAssetWriterStatusFailed)
//            
//        {
//            BOOL success = [pvc.videoWriter startWriting];
//            
//            //            [_videoWriter startSessionAtSourceTime:CMTimeMake(1, 25)];
//            [pvc.videoWriter startSessionAtSourceTime:CMTimeMake(1, 25)];
//            
//        } if( pvc.videoWriter.status > AVAssetWriterStatusWriting )
//            
//        {
//            
//            NSLog(@"Warning: writer status is %zd", pvc.videoWriter.status);
//            if( pvc.videoWriter.status == AVAssetWriterStatusFailed )
//                
//                NSLog(@"Error: %@",pvc.videoWriter.error);
//            
//            return;
//            
//        }
//        if (pvc.videoWriter.status == AVAssetWriterStatusWriting) {
//            if ([pvc.videoWriterInput isReadyForMoreMediaData])
//            {
////                                NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],kCVPixelBufferCGImageCompatibilityKey, nil];
////                                int cvRet = CVPixelBufferCreate(kCFAllocatorDefault,480, 320,kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)(options),&outputPixelBuffer);
////                OSStatus result = CMSampleBufferMakeDataReady(sampleBuffer);
//                CIImage *ciImage = [CIImage imageWithCVPixelBuffer:CVPixelBufferRetain(imageBuffer)];
//                UIImage *image = [UIImage imageWithCIImage:ciImage];
//                pvc.imageView.image = image;
//                if( ![pvc.adaptor appendPixelBuffer:imageBuffer withPresentationTime:CMTimeMake(1*frame1, 25)])
//                {
//                    NSLog(@"Unable to write to video input");
//                }
//                else
//                {
//                    NSLog(@"already write vidio");
//                }
//                CFRelease(imageBuffer);
//            }
//            frame1++;
//            
//        }
//       
//        if(![[NSFileManager defaultManager] fileExistsAtPath:pvc.imagePath]){
//            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:CVPixelBufferRetain(imageBuffer)];
//            UIImageView* imgView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, ScreenWidth, ScreenHeight)];
//            imgView.image = [UIImage imageWithCIImage:ciImage];
//            
//            UIGraphicsBeginImageContext(imgView.bounds.size);
//            [imgView.layer renderInContext:UIGraphicsGetCurrentContext()];
//            UIImage *temp = UIGraphicsGetImageFromCurrentImageContext();
//            UIGraphicsEndImageContext();
//            [pvc writeImage:temp toFileAtPath:pvc.imagePath];
//        }
    }
}

- (CVPixelBufferRef)pixelBufferFaster:(UIImage *)image{
    
    NSDictionary *options =[NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithBool:YES],kCVPixelBufferCGImageCompatibilityKey,
                            [NSNumber numberWithBool:YES],kCVPixelBufferCGBitmapContextCompatibilityKey,nil];
    
    CVPixelBufferRef pxbuffer =NULL;
    CVReturn status =CVPixelBufferCreate(kCFAllocatorDefault,640,960,kCVPixelFormatType_32BGRA,(__bridge CFDictionaryRef) options,&pxbuffer);
    
    NSParameterAssert(status ==kCVReturnSuccess && pxbuffer !=NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer,0);
    void *pxdata =CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata !=NULL);
    
    CGColorSpaceRef rgbColorSpace=CGColorSpaceCreateDeviceRGB();
    CGContextRef context =CGBitmapContextCreate(pxdata,640,480,8,4*640,rgbColorSpace,kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    NSParameterAssert(context);
    
    
    CGContextDrawImage(context,CGRectMake(0,0,CGImageGetWidth(image.CGImage),CGImageGetHeight(image.CGImage)),image.CGImage);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer,0);
    
    
    return pxbuffer;}

- (void)createDecompSession
{
    // make sure to destroy the old VTD session
    _decompressionSession = NULL;
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
    
    // this is necessary if you need to make calls to Objective C "self" from within in the callback method.
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
    // you can set some desired attributes for the destination pixel buffer.  I didn't use this but you may
    // if you need to set some attributes, be sure to uncomment the dictionary in VTDecompressionSessionCreate
    NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                                      [NSNumber numberWithBool:YES],
                                                      (id)kCVPixelBufferOpenGLESCompatibilityKey,
                                                      nil];
    
    OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDesc, NULL,
                                                    NULL, // (__bridge CFDictionaryRef)(destinationImageBufferAttributes)
                                                    &callBackRecord, &_decompressionSession);
    if(status != noErr) {
        NSLog(@"VTDecompressionSessionCreate ERROR type: %d", (int)status);
    }
}

-(void)procVideo
{
    @autoreleasepool {
        while(rtspHandle){
                [_mediaCond lock];
                MediaNode mNode = {0};
                NSValue *node = [_mediaArray lastObject];
                if(node){
                    [node getValue:&mNode];
                }
                if(mNode.type != 2){
                    [_mediaCond wait];
                }else{
                    [self receivedRawVideoFrame:(uint8_t*)mNode.data withSize:mNode.len];
                    free(mNode.data);
                    [_mediaArray removeLastObject];
                    [_mediaCond signal];
                }
                [_mediaCond unlock];
        }
    }
}

- (void)handleTap
{
    CGFloat _alpha = 1 - self.topBar.alpha;
    [UIView animateWithDuration:0.1
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                     animations:^{
                         self.topBar.alpha = _alpha;
                         self.bottomBar.alpha = _alpha;
                     }
                     completion:nil];
    
    
    if(_alpha > 0){
        [self restartToolbarTimer];
    }else {
        [self stopToolbarTimer];
    }
}

- (void)restartToolbarTimer
{
    if(!_toolbarTimer){
        _toolbarTimer = [NSTimer scheduledTimerWithTimeInterval:4.
                                                         target:self
                                                       selector:@selector(handleTap)
                                                       userInfo:nil
                                                        repeats:NO];
    }
    [_toolbarTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:4.]];
}

- (void)stopToolbarTimer
{
    if(_toolbarTimer){
        [_toolbarTimer invalidate];
        _toolbarTimer = nil;
    }
}

- (void)backBtnDidTouch:(id)sender
{
    __weak typeof(self) weakSelf = self;
    
//    if (_videoWriter.status != AVAssetWriterStatusUnknown) {
//        [_videoWriterInput markAsFinished];
//        [_videoWriter finishWritingWithCompletionHandler:^{
//            [weakSelf dismissViewControllerAnimated:YES completion:nil];
//        }];
//    }
//    else
    {
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    }
   
    
}

- (void)fullBtnDidTouch:(id)sender
{
    if (!self.fullBtn.selected) {
        [UIView animateWithDuration:0.5 animations:^{
            self.view.transform =CGAffineTransformMakeRotation(M_PI_2);
            self.view.bounds = CGRectMake(0, 0,ScreenHeight,ScreenWidth);
            self.videoLayer.frame = CGRectMake(0, 0,ScreenHeight,ScreenWidth);
            self.topBar.frame = CGRectMake(self.topBar.frame.origin.x,self.topBar.frame.origin.y,ScreenHeight,TOOLBAR_HEIGHT);
            self.bottomBar.frame = CGRectMake(0,ScreenWidth-TOOLBAR_HEIGHT,ScreenHeight,TOOLBAR_HEIGHT);
            
            self.fullBtn.selected = YES;
        }];
    }else {
        [UIView animateWithDuration:0.5 animations:^{
            self.view.transform = CGAffineTransformIdentity;
            self.view.bounds = CGRectMake(0, 0, ScreenWidth, ScreenHeight);
            self.videoLayer.frame = CGRectMake(0, 0,ScreenWidth,ScreenHeight);
            self.topBar.frame = CGRectMake(self.topBar.frame.origin.x,self.topBar.frame.origin.y,self.topBar.frame.size.width,TOOLBAR_HEIGHT);
            self.fullBtn.selected = NO;
        }];
    }
    [self restartToolbarTimer];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (NSString *)touchDir:(NSString*)dir
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* docDir = [paths objectAtIndex:0];
    NSString* _dir = [docDir stringByAppendingPathComponent:dir];
    if(![[NSFileManager defaultManager] fileExistsAtPath:_dir]){
        [[NSFileManager defaultManager] createDirectoryAtPath:_dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return _dir;
}

- (BOOL)writeImage:(UIImage*)image toFileAtPath:(NSString*)aPath
{
    if ((image == nil) || (aPath == nil) || ([aPath isEqualToString:@""]))
        return NO;
    @try{
        NSData *imageData = nil;
        NSString *ext = [aPath pathExtension];
        if ([ext isEqualToString:@"png"]){
            imageData = UIImagePNGRepresentation(image);
        }else{
            imageData = UIImageJPEGRepresentation(image,1);
        }
        if ((imageData == nil) || ([imageData length] <= 0)){
            NSLog(@"image data is empty");
            return NO;
        }
        
        [imageData writeToFile:aPath atomically:YES];
        return YES;
    }@catch (NSException *e){
        NSLog(@"create thumbnail exception.");
    }
    return NO;
}

- (NSString *)md5:(NSString *)str
{
    const char *cStr = [str UTF8String];
    unsigned char result[16];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), result);
    return [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}


@end


