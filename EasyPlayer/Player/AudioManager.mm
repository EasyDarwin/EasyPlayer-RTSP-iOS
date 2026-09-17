//
//  AudioUnitPlayback.m
//  iMyCamera
//
//  Created by cs on 15/10/16.
//  Copyright © 2015年 MacBook. All rights reserved.
//

#import "AudioManager.h"
#import <Accelerate/Accelerate.h>
#import <os/lock.h>
#include <vector>

@interface AudioManager() {
    AudioUnit remoteIOUnit;
    SInt16 * _outData;
    BOOL _activated;   // AVAudioSession 是否已激活，只在音频队列上读写
    os_unfair_lock _outputBlockLock;   // outputBlock 由主线程写、音频渲染线程读，必须加锁
}

@property (nonatomic, readwrite)BOOL playing;

- (void)fillBuf:(AudioBufferList *)ioData num:(UInt32)inNumberFrames;

@end

static BOOL checkError(OSStatus error, const char *operation) {
    if (error == noErr)
        return NO;
    
    char str[20] = {0};
    // see if it appears to be a 4-char-code
    *(UInt32 *)(str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else {
        // no, format it as an integer
        sprintf(str, "%d", (int)error);
    }
    
    NSLog(@"Error: %s (%s)\n", operation, str);
    
    return YES;
}

@implementation AudioManager

@synthesize outputBlock = _outputBlock;

static const void * const kAudioQueueKey = &kAudioQueueKey;

static dispatch_queue_t AudioSessionQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.easydarwin.easyplayer.audio", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue, kAudioQueueKey, (void *)kAudioQueueKey, NULL);
    });
    return queue;
}

// 主线程绝不能同步等这条队列：AVAudioSession setActive: / AudioUnitUninitialize 都可能耗时几百毫秒，
// 在 viewWillAppear / becomeActive 这种时机同步等待会把主线程卡死，最终被 watchdog 杀掉
static void RunOnAudioQueue(dispatch_block_t block) {
    if (dispatch_get_specific(kAudioQueueKey)) {
        block();
    } else {
        dispatch_async(AudioSessionQueue(), block);
    }
}

+ (AudioManager *) sharedInstance {
    static AudioManager *audioManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioManager = [[AudioManager alloc] init];
    });
    
    return audioManager;
}

- (id)init {
    if (self = [super init]) {
        _outData = (SInt16 *)calloc(4096 * 2, sizeof(SInt16));
        _outputBlockLock = OS_UNFAIR_LOCK_INIT;
    }
    
    return self;
}

#pragma mark - outputBlock 的跨线程读写

// 主线程把 outputBlock 置 nil 时，音频渲染线程可能正在执行它。
// 默认的 nonatomic 访问器在这里会 use-after-free，所以改成自己加锁。
- (void)setOutputBlock:(AudioManagerOutputBlock)outputBlock {
    AudioManagerOutputBlock copied = [outputBlock copy];
    
    os_unfair_lock_lock(&_outputBlockLock);
    _outputBlock = copied;
    os_unfair_lock_unlock(&_outputBlockLock);
}

- (AudioManagerOutputBlock)outputBlock {
    os_unfair_lock_lock(&_outputBlockLock);
    AudioManagerOutputBlock block = _outputBlock;
    os_unfair_lock_unlock(&_outputBlockLock);
    
    return block;
}

// 下面几个公开方法都只是把请求投递到音频队列，不会阻塞调用方（通常是主线程），
// 返回值只表示“请求已提交”，真正的结果通过 playing 属性观察
- (BOOL) activateAudioSession {
    RunOnAudioQueue(^{
        [self activateSessionOnQueue];
    });
    
    return YES;
}

- (void) deactivateAudioSession {
    RunOnAudioQueue(^{
        [self stopOnQueue];
        
        if (self->_activated) {
            [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
            self->_activated = NO;
        }
    });
}

- (void)stop {
    RunOnAudioQueue(^{
        [self stopOnQueue];
    });
}

- (BOOL)play {
    RunOnAudioQueue(^{
        if (self.playing) {
            return;
        }
        
        if ([self activateSessionOnQueue] && [self setupAudio]) {
            self.playing = !checkError(AudioOutputUnitStart(self->remoteIOUnit),
                                       "Couldn't start the output unit");
        }
    });
    
    return YES;
}

- (void)pause {
    RunOnAudioQueue(^{
        [self pauseOnQueue];
    });
}

#pragma mark - 以下方法只允许在音频队列上执行

- (BOOL)activateSessionOnQueue {
    if (_activated) {
        return YES;
    }
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback error:nil]) {
        return NO;
    }
    
    if (![session setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil]) {
        return NO;
    }
    
    _activated = YES;
    
    return YES;
}

- (void)pauseOnQueue {
    if (_playing && remoteIOUnit != NULL) {
        checkError(AudioOutputUnitStop(remoteIOUnit),
                   "Couldn't stop the output unit");
    }
    
    _playing = NO;
}

- (void)stopOnQueue {
    [self pauseOnQueue];
    
    if (remoteIOUnit != NULL) {
        checkError(AudioUnitUninitialize(remoteIOUnit),
                   "Couldn't uninitialize the audio unit");
        // 只 Uninitialize 不 Dispose 会泄漏 AudioComponentInstance，下次 setupAudio 又会新建一个
        checkError(AudioComponentInstanceDispose(remoteIOUnit),
                   "Couldn't dispose the output audio unit");
        remoteIOUnit = NULL;
    }
}

- (void)dealloc {
    [self stopOnQueue];
    
    // _outData 是 calloc 出来的，必须用 free 释放；delete[] 会破坏堆
    free(_outData);
    _outData = NULL;
}

static OSStatus outputRenderCallback(void                        *inRefCon,
                                     AudioUnitRenderActionFlags  *ioActionFlags,
                                     const AudioTimeStamp        *inTimeStamp,
                                     UInt32                      inBusNumber,
                                     UInt32                      inNumberFrames,
                                     AudioBufferList             *ioData){
    AudioManager *output = (__bridge AudioManager*)inRefCon;
    
    [output fillBuf:ioData num:inNumberFrames];
    return noErr;
}

-(BOOL)setupAudio {
    if (remoteIOUnit != NULL) {
        return YES;
    }
    
    AudioComponentDescription inputcd = {0};
    inputcd.componentType = kAudioUnitType_Output;
    inputcd.componentSubType = kAudioUnitSubType_RemoteIO;
    inputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent component = AudioComponentFindNext(NULL, &inputcd);
    if (checkError(AudioComponentInstanceNew(component, &remoteIOUnit),
                 "Couldn't create the output audio unit")) {
        return NO;
    }
    
    AudioStreamBasicDescription streamFormat;
    UInt32 size = sizeof(AudioStreamBasicDescription);
    AudioUnitGetProperty(remoteIOUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &streamFormat,
                         &size);
    
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    streamFormat.mSampleRate = self.sampleRate;
    streamFormat.mChannelsPerFrame = self.channel;
    streamFormat.mBitsPerChannel = 16;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerFrame = self.channel * 2;
    streamFormat.mBytesPerPacket = self.channel * 2;
    
    if (checkError(AudioUnitSetProperty(remoteIOUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0,
                                      &streamFormat,
                                      sizeof(streamFormat)),
                 "kAudioUnitProperty_StreamFormat of bus 0 failed")) {
        return NO;
    }
    
    AURenderCallbackStruct input;
    input.inputProc = outputRenderCallback;
    input.inputProcRefCon = (__bridge void *)self;
    if (checkError(AudioUnitSetProperty(remoteIOUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input,
                                      0,//input mic
                                      &input,
                                      sizeof(input)),
                 "kAudioUnitProperty_SetRenderCallback failed")) {
        return NO;
    }
    
    if (checkError(AudioUnitInitialize(remoteIOUnit),
               "Couldn't initialize the audio unit")) {
        return NO;
    }
    
    return YES;
}

- (void)fillBuf:(AudioBufferList *)ioData num:(UInt32)inNumberFrames {
    for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
        memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
    }
    
    // 先在锁里把 block 抓到栈上（强引用），出锁之后即使主线程把属性置 nil 也不会被释放；
    // 这里不能用 self.outputBlock，getter 返回的是 autorelease 对象，渲染线程上没有自动释放池
    AudioManagerOutputBlock outputBlock = nil;
    os_unfair_lock_lock(&_outputBlockLock);
    outputBlock = _outputBlock;
    os_unfair_lock_unlock(&_outputBlockLock);
    
    if (_playing && outputBlock != nil) {
        outputBlock(_outData, inNumberFrames, self.channel);
        
        for (int iBuffer = 0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
            int thisNumChannels = ioData->mBuffers[iBuffer].mNumberChannels;
            
            if (thisNumChannels <= 0 || thisNumChannels > 2) {
                thisNumChannels = 1;
            }
            
            SInt16 *frameBuffer = (SInt16 *)ioData->mBuffers[iBuffer].mData;
            memcpy(frameBuffer, _outData, inNumberFrames * thisNumChannels * sizeof(SInt16));
        }
    }
}

@end
