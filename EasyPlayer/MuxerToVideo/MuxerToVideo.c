//
//  MuxerToVideo.c
//  EasyPlayer
//
//  Created by liyy on 2017/12/22.
//  Copyright © 2017年 cs. All rights reserved.
//

#include "MuxerToVideo.h"

#pragma mark - FFMPEG

AVFormatContext *ofmt_ctx = NULL;   // Output AVFormatContext
AVOutputFormat *ofmt = NULL;
int ret = 0;

AVCodec *videoCodec;
AVCodecContext *videoCodecCtx;

AVCodec *audioCodec;
AVCodecContext *audioCodecCtx;

#pragma mark - 关闭输出文件

/**
 关闭文件

 @return 0:成功
 */
int closeOutPut() {
    if (ofmt_ctx) {
        // av_write_trailer()：写入文件尾 Write file trailer
        av_write_trailer(ofmt_ctx);
        
        // close output
        if (ofmt_ctx && !(ofmt->flags & AVFMT_NOFILE)) {
            avio_close(ofmt_ctx->pb);
        }
        
        avformat_free_context(ofmt_ctx);
        ofmt_ctx = NULL;
    }
    
    return 0;
}

#pragma mark - 打开输出文件

/**
 打开输入文件

 @param out_filename 路径
 @return 2:已经打开；1:打开成功;0:打开失败
 */
int openOutPut(const char *out_filename) {
    if (ofmt_ctx) {
        return 2;
    } else {
        if (audioCodec != NULL && videoCodec != NULL) {
//            av_register_all();
            
            // 初始化输出文件 Output
            avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, out_filename);
            if (!ofmt_ctx) {
                printf("Could not create output context\n");
                ret = AVERROR_UNKNOWN;
                
                return closeOutPut();
            }
            ofmt = ofmt_ctx->oformat;
            
            AVStream *video_out_stream = avformat_new_stream(ofmt_ctx, videoCodec);
            // 赋值AVCodecContext的参数 Copy the settings of AVCodecContext
            if (avcodec_copy_context(video_out_stream->codec, videoCodecCtx) < 0) {
                printf( "Failed to copy context from input to output stream codec context\n");
                return closeOutPut();
            }
            if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER) {
                video_out_stream->codec->flags |= CODEC_FLAG_GLOBAL_HEADER;
                videoCodecCtx->flags |= CODEC_FLAG_GLOBAL_HEADER;
            }
            
            
            
            AVStream *audio_out_stream = avformat_new_stream(ofmt_ctx, audioCodec);
            if (avcodec_copy_context(audio_out_stream->codec, audioCodecCtx) < 0) {
                printf( "Failed to copy context from input to output stream codec context\n");
                return closeOutPut();
            }
            if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER) {
                audioCodecCtx->flags |= CODEC_FLAG_GLOBAL_HEADER;
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
            
            return 1;
        } else {
            return 0;
        }
    }
}

#pragma mark - avpacket写入文件

int writeData(const char *out_filename, AVPacket pkt) {
    if (out_filename == NULL) {
        return closeOutPut();
    } else {
        if (openOutPut(out_filename) == 2) {
            
            // av_compare_ts()：比较时间戳，决定写入视频还是写入音频 Get an AVPacket
            
            printf("Write 1 Packet. size:%5d\tpts:%lld\n", pkt.size, pkt.pts);
            
            // av_interleaved_write_frame()：写入一个AVPacket到输出文件
            if (av_interleaved_write_frame(ofmt_ctx, &pkt) < 0) {
                printf( "Error muxing packet\n");
            }
            
            av_free_packet(&pkt);
            
            return 1;
        } else {
            return 0;
        }
    }
}

#pragma mark - 将h264流转换为AVPacket

int convertVideoToAVPacket(const char *out_filename, void *recordHandle, DEC_DECODE_PARAM *pDecodeParam) {
    DEC_COMPONENT *pComponent = (DEC_COMPONENT *)recordHandle;
    if (pComponent == NULL || pComponent->pCodecCtx == NULL || pComponent->pFrame == NULL) {
        return 0;
    }
    
    videoCodec = pComponent->avCodec;
    videoCodecCtx = pComponent->pCodecCtx;
    
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
    
    writeData(out_filename, packet);
    
    return 0;
}

#pragma mark - 将aac流转换为AVPacket

int convertAudioToAVPacket(const char *out_filename, void *audioDecHandle, unsigned char *pData, int nLen) {
    EasyAudioHandle *pComponent = (EasyAudioHandle *)audioDecHandle;
    
    AACDFFmpeg *aacDFFmpeg = (AACDFFmpeg *)pComponent->pContext;
    audioCodec = aacDFFmpeg->avCodec;
    audioCodecCtx = aacDFFmpeg->pCodecCtx;
    
    AVPacket packet;
    av_init_packet(&packet);
    
    packet.size = nLen;
    packet.data = pData;
    
    writeData(out_filename, packet);
    
    return 0;
}
