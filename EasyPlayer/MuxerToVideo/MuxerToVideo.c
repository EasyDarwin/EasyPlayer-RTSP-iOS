//
//  MuxerToVideo.c
//  EasyPlayer
//
//  Created by liyy on 2017/12/22.
//  Copyright © 2017年 cs. All rights reserved.
//

#include "MuxerToVideo.h"

unsigned char RECORD_H264_SPS_PPS_NEW[] = {
    48,   0,   0,   0,
    9,   0,   0,   0, 103,  88,   0,  21, 150,  86,  11,   4, 162,   9,   0,   0,   0,
    103,  88,   0,  21,  69, 149, 133, 137, 136,  10,   0,   0,   0, 103,  88,   0,  21,
    101, 149, 129,  96,  36, 136,   9,   0,   0,   0, 103,  88,   0,  21,  33, 101,  97,
    71, 136,  10,   0,   0,   0, 103,  88,   0,  21,  41, 101,  96, 176, 248, 128,  10,
    0,   0,   0, 103,  88,   0,  21,  49, 101,  96, 160, 248, 128,  10,   0,   0,   0,
    103,  88,   0,  21,  57, 101,  96,  80,  30, 136,  10,   0,   0,   0, 103,  88,   0,
    21,  16,  89,  88,  20,  15, 136,  10,   0,   0,   0, 103,  88,   0,  21,  18,  89,
    88,  20,   4, 162,  10,   0,   0,   0, 103,  88,   0,  21,  20,  89,  88,  22,   7,
    162,  10,   0,   0,   0, 103,  88,   0,  21,  22,  89,  88,  22,  15, 136,  10,   0,
    0,   0, 103,  88,   0,  21,  24,  89,  88,  22,   4, 162,  11,   0,   0,   0, 103,
    88,   0,  21,  26,  89,  88,  22, 130,  72, 128,  10,   0,   0,   0, 103,  88,   0,
    21,  28,  89,  88,  22, 135, 162,  10,   0,   0,   0, 103,  88,   0,  21,  30,  89,
    88,  22, 143, 136,  11,   0,   0,   0, 103,  88,   0,  21,   8,  22,  86,   5, 161,
    40, 128,   4,   0,   0,   0, 104, 206,  56, 128,   4,   0,   0,   0, 104,  83, 143,
    32,   4,   0,   0,   0, 104, 104, 227, 136,   4,   0,   0,   0, 104,  34,  56, 242,
    4,   0,   0,   0, 104,  43,  56, 226,   4,   0,   0,   0, 104,  51,  56, 242,   5,
    0,   0,   0, 104,  57,  14,  56, 128,   5,   0,   0,   0, 104,  16,  67, 143,  32,
    5,   0,   0,   0, 104,  18,  83, 142,  32,   5,   0,   0,   0, 104,  20,  83, 143,
    32,   5,   0,   0,   0, 104,  22,  99, 142,  32,   5,   0,   0,   0, 104,  24,  99,
    143,  32,   5,   0,   0,   0, 104,  26, 115, 142,  32,   5,   0,   0,   0, 104,  28,
    115, 143,  32,   5,   0,   0,   0, 104,  30,  32, 227, 136,   5,   0,   0,   0, 104,
    8,   8,  56, 242,   5,   0,   0,   0, 104,   8, 137,  56, 226,   5,   0,   0,   0,
    104,   9,   9,  56, 242,   5,   0,   0,   0, 104,   9, 138,  56, 226,   5,   0,   0,
    0, 104,  10,  10,  56, 242,   5,   0,   0,   0, 104,  10, 139,  56, 226,   5,   0,
    0,   0, 104,  11,  11,  56, 242,   5,   0,   0,   0, 104,  11, 140,  56, 226,   5,
    0,   0,   0, 104,  12,  12,  56, 242,   5,   0,   0,   0, 104,  12, 141,  56, 226,
    5,   0,   0,   0, 104,  13,  13,  56, 242,   5,   0,   0,   0, 104,  13, 142,  56,
    226,   5,   0,   0,   0, 104,  14,  14,  56, 242,   5,   0,   0,   0, 104,  14, 143,
    56, 226,   5,   0,   0,   0, 104,  15,  15,  56, 242,   6,   0,   0,   0, 104,  15,
    132,  14,  56, 128,   6,   0,   0,   0, 104,   4,   1,   3, 143,  32
};

// h264流组件
typedef struct _MUXER_VIDEO_COMPONENT {
    AVCodecContext *pCodecCtx;
    AVFrame *pFrame;
    unsigned char * pNewStream;
    int newStreamLen;
}MUXER_VIDEO_COMPONENT;

void *recordVideoCreate(RECORD_CREATE_PARAM *pCreateParam) {
    MUXER_VIDEO_COMPONENT *pComponent = (MUXER_VIDEO_COMPONENT *)malloc(sizeof(MUXER_VIDEO_COMPONENT));
    pComponent->pCodecCtx = NULL;
    pComponent->pFrame = NULL;
//    s_uiDecodeMethod = pCreateParam->method;
    
    AVCodec *pCodec = avcodec_find_decoder(CODEC_ID_H264);
    if (pCodec == NULL) {
        printf("avcodec_find_decoder codec error\r\n");
        return 0;
    }
    
    // 创建显示contedxt
    pComponent->pCodecCtx = avcodec_alloc_context3(pCodec);
    pComponent->pCodecCtx->width = pCreateParam->nMaxImgWidth;
    pComponent->pCodecCtx->height = pCreateParam->nMaxImgHeight;
    pComponent->pCodecCtx->pix_fmt = PIX_FMT_YUV420P;
    AVDictionary *options = NULL;
    if(avcodec_open2(pComponent->pCodecCtx, pCodec, &options) < 0) {
        printf("open codec error\r\n");
        return 0;
    }
    
    pComponent->pFrame = av_frame_alloc();
    if (pComponent->pFrame == NULL) {
        return 0;
    }
    
    pComponent->pNewStream = (unsigned char *)malloc(1024*1024);
    memset(pComponent->pNewStream , 0, 1024*1024);
    
    // add sps pps head
    unsigned char * p1,*ps;
    int * ptmplen;
    int k,m,n;
    int spsppslen = 0;
    p1 = RECORD_H264_SPS_PPS_NEW;
    ptmplen = (int*)p1;
    m = *ptmplen;
    ps = pComponent->pNewStream;
    
    p1 += 4;
    for (k=0; k<m; k++) {
        memcpy(&n, p1, 4);
        
        ps[0] =0;
        ps[1] = 0;
        ps[2] = 1;
        memcpy(ps+3,p1+4,n);
        ps += 3+n;
        spsppslen += (3+n);
        
        p1 += 4+n;
    }
    pComponent->newStreamLen = spsppslen;
    
//    pComponent->uiOriginLen = pComponent->newStreamLen;
//    pComponent->bScaleCreated = 0;
    return (void *)pComponent;
}

#pragma mark - FFMPEG

int openOutputFile = 0;

AVFormatContext *ofmt_ctx = NULL;   // Output AVFormatContext
AVOutputFormat *ofmt = NULL;
int ret = 0;

#pragma mark - 关闭输出文件

int closeOutPut() {
    if (openOutputFile == 0) {
        return 0;
    }
    
    openOutputFile = 0;
    
    // av_write_trailer()：写入文件尾 Write file trailer
    av_write_trailer(ofmt_ctx);
    
    // close output
    if (ofmt_ctx && !(ofmt->flags & AVFMT_NOFILE)) {
        avio_close(ofmt_ctx->pb);
    }
    
    avformat_free_context(ofmt_ctx);
    
    if (ret < 0 && ret != AVERROR_EOF) {
        printf( "Error occurred.\n");
        return -1;
    }
    
    return 0;
}

#pragma mark - 打开输出文件

int openOutPut(AVCodec *avCodec, AVCodecContext *pCodecCtx, const char *out_filename) {
    if (out_filename == NULL) {
        return closeOutPut();
    }
    
    if (openOutputFile == 0) {
        openOutputFile = 1;
        
        av_register_all();
        
        // 初始化输出文件 Output
        avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, out_filename);
        if (!ofmt_ctx) {
            printf("Could not create output context\n");
            ret = AVERROR_UNKNOWN;
            
            return closeOutPut();
        }
        ofmt = ofmt_ctx->oformat;
        
        // 设置编码器
        avformat_new_stream(ofmt_ctx, avCodec);
        if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER) {
            pCodecCtx->flags |= CODEC_FLAG_GLOBAL_HEADER;
        }
        
        printf("==========Output Information==========\n");
        av_dump_format(ofmt_ctx, 0, out_filename, 1);
        printf("======================================\n");
        
        // avio_open 打开输出文件
        if (!(ofmt->flags & AVFMT_NOFILE)) {
            if (avio_open(&ofmt_ctx->pb, out_filename, AVIO_FLAG_WRITE) < 0) {
                printf("Could not open output file '%s'", out_filename);
                
                return closeOutPut();
            }
        }
        
        // 写入文件头 Write file header
        if (avformat_write_header(ofmt_ctx, NULL) < 0) {
            printf("Error occurred when opening output file\n");
            
            return closeOutPut();
        }
    }
    
    return 0;
}

#pragma mark - avpacket写入文件

int writeData(AVCodec *avCodec, AVCodecContext *pCodecCtx, const char *out_filename, AVPacket pkt) {
    if (out_filename == NULL) {
        return closeOutPut();
    } else {
        openOutPut(avCodec, pCodecCtx, out_filename);
    }
    
    printf("Write 1 Packet. size:%5d\tpts:%lld\n", pkt.size, pkt.pts);
    
    // av_interleaved_write_frame()：写入一个AVPacket到输出文件
    if (av_interleaved_write_frame(ofmt_ctx, &pkt) < 0) {
        printf( "Error muxing packet\n");
    }
    
    av_free_packet(&pkt);
    
    return 0;
}

#pragma mark - 将h264流转换为AVPacket

int convertVideoToAVPacket(AVCodec *avCodec, AVCodecContext *pCodecCtx, const char *out_filename, void *recordHandle, MUXER_VIDEO_PARAM *pDecodeParam) {
    MUXER_VIDEO_COMPONENT *pComponent = (MUXER_VIDEO_COMPONENT *)recordHandle;
    if (pComponent == NULL || pComponent->pCodecCtx == NULL || pComponent->pFrame == NULL) {
        return 0;
    }
    
    AVPacket packet;
    av_init_packet(&packet);
    if (pDecodeParam->need_sps_head) {
        memset(pComponent->pNewStream+pComponent->newStreamLen, 0, 1024*1024-pComponent->newStreamLen);
        pComponent->pNewStream[pComponent->newStreamLen+0] = 0;
        pComponent->pNewStream[pComponent->newStreamLen+1] = 0;
        pComponent->pNewStream[pComponent->newStreamLen+2] = 1;
        memcpy(pComponent->pNewStream+3+pComponent->newStreamLen, pDecodeParam->pStream, pDecodeParam->nLen);
        pComponent->newStreamLen += pDecodeParam->nLen +3;
        packet.size = pComponent->newStreamLen;
        packet.data = pComponent->pNewStream;
    } else {
        packet.size = pDecodeParam->nLen;
        packet.data = pDecodeParam->pStream;
    }
    
    writeData(avCodec, pCodecCtx, out_filename, packet);
    
    return 0;
}

#pragma mark - 将aac流转换为AVPacket

int convertAudioToAVPacket(AVCodec *avCodec, AVCodecContext *pCodecCtx, const char *out_filename, unsigned char *pData, int nLen) {
    
    AVPacket packet;
    av_init_packet(&packet);
    
    packet.size = nLen;
    packet.data = pData;
    
    writeData(avCodec, pCodecCtx, out_filename, packet);
    
    return 0;
}
