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

#ifdef __cplusplus
extern "C" {
#endif
    
// 算法类型
typedef enum {
    RECORD_CODER_MPEG4,
    RECORD_CODER_H264
}RECORD_Coder;

typedef enum {
    RECORD_IDM_SW = 0,
    RECORD_IDM_GLSL,
}RECORD_IDECODE_METHODE;

// 创建参数
typedef struct _RECORD_CREATE_PARAM {
    int nMaxImgWidth;
    int nMaxImgHeight;
    RECORD_Coder coderID;
    RECORD_IDECODE_METHODE method;
    
}RECORD_CREATE_PARAM;

// h264流参数
typedef struct _MUXER_VIDEO_PARAM {
    int need_sps_head;
    unsigned char *pStream;
    int nLen;
}MUXER_VIDEO_PARAM;

void *recordVideoCreate(RECORD_CREATE_PARAM *pCreateParam);

// 将h264流转换为AVPacket
int convertVideoToAVPacket(AVCodec *avCodec, AVCodecContext *pCodecCtx, const char *out_filename, void *recordHandle, MUXER_VIDEO_PARAM *pDecodeParam);

// 将aac流转换为AVPacket
int convertAudioToAVPacket(AVCodec *avCodec, AVCodecContext *pCodecCtx, const char *out_filename, unsigned char *pData, int nLen);

#ifdef __cplusplus
}
#endif

#endif /* MuxerToVideo_h */
