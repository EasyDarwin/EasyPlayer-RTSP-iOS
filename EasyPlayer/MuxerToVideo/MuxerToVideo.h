//
//  MuxerToVideo.h
//  EasyPlayer
//
//  Created by liyy on 2017/12/22.
//  Copyright © 2017年 cs. All rights reserved.
//

#ifndef MuxerToVideo_h
#define MuxerToVideo_h

#include <stdio.h>
#include "libavformat/avformat.h"
#include "VideoDecode.h"
#include "EasyAudioDecoder.h"

#ifdef __cplusplus
extern "C" {
#endif

    // 将h264流转换为AVPacket
    int convertVideoToAVPacket(const char *out_filename, void *recordHandle, DEC_DECODE_PARAM *pDecodeParam);
    
    // 将aac流转换为AVPacket
    int convertAudioToAVPacket(const char *out_filename, void *audioDecHandle, unsigned char *pData, int nLen);

#ifdef __cplusplus
}
#endif

#endif /* MuxerToVideo_h */
