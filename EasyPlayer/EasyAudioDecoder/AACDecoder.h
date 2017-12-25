#ifndef _AACDecoder_h
#define _AACDecoder_h

#ifdef __cplusplus
extern "C" {
#endif
    
#include "libavformat/avformat.h"
#include "libswresample/swresample.h"
#include "libavcodec/avcodec.h"

    void *aac_decoder_create(enum AVCodecID codecid, int sample_rate, int channels, int bit_rate);
    int aac_decode_frame(void *pParam, unsigned char *pData, int nLen, unsigned char *pPCM, unsigned int *outLen);
    void aac_decode_close(void *pParam);

    
#ifdef __cplusplus
}
#endif

#endif



