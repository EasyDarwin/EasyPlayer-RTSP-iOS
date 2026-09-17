//
//  AudioUnitPlayback.h
//  iMyCamera
//
//  Created by cs on 15/10/16.
//  Copyright © 2015年 MacBook. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>

typedef void (^AudioManagerOutputBlock)(SInt16 *outData, UInt32 numFrames, UInt32 numChannels);

/**
 音频播放Audio Unit
 */
@interface AudioManager : NSObject

+ (AudioManager *) sharedInstance;

@property (nonatomic, copy) AudioManagerOutputBlock outputBlock;

@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, weak) id source;
@property (nonatomic) float sampleRate;
@property (nonatomic) int channel;

/**
 以下方法都是异步的：只把请求投递到内部的音频串行队列，不会阻塞调用线程。
 AVAudioSession / AudioUnit 的调用可能耗时较长，主线程同步等待会造成卡死。
 activateAudioSession、play 的返回值只代表“请求已提交”。
 */
- (BOOL) activateAudioSession;
- (void) deactivateAudioSession;

- (void)pause;
- (BOOL)play;
- (void)stop;

@end
