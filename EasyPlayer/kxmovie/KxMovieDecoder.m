//
//  KxMovieDecoder.m
//  kxmovie
//
//  Created by Kolyvan on 15.10.12.
//  Copyright (c) 2012 Konstantin Boukreev . All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt

#import "KxMovieDecoder.h"
#import <Accelerate/Accelerate.h>
#include "libavutil/pixdesc.h"

NSString * kxmovieErrorDomain = @"ru.kolyvan.kxmovie";

//static NSError * kxmovieError (NSInteger code, id info) {
//    NSDictionary *userInfo = nil;
//
//    if ([info isKindOfClass: [NSDictionary class]]) {
//        userInfo = info;
//    } else if ([info isKindOfClass: [NSString class]]) {
//        userInfo = @{ NSLocalizedDescriptionKey : info };
//    }
//
//    return [NSError errorWithDomain:kxmovieErrorDomain code:code userInfo:userInfo];
//}

//static NSString * errorMessage (kxMovieError errorCode) {
//    switch (errorCode) {
//        case kxMovieErrorNone:
//            return @"";
//        case kxMovieErrorOpenFile:
//            return NSLocalizedString(@"Unable to open file", nil);
//        case kxMovieErrorStreamInfoNotFound:
//            return NSLocalizedString(@"Unable to find stream information", nil);
//        case kxMovieErrorStreamNotFound:
//            return NSLocalizedString(@"Unable to find stream", nil);
//        case kxMovieErrorCodecNotFound:
//            return NSLocalizedString(@"Unable to find codec", nil);
//        case kxMovieErrorOpenCodec:
//            return NSLocalizedString(@"Unable to open codec", nil);
//        case kxMovieErrorAllocateFrame:
//            return NSLocalizedString(@"Unable to allocate frame", nil);
//        case kxMovieErroSetupScaler:
//            return NSLocalizedString(@"Unable to setup scaler", nil);
//        case kxMovieErroReSampler:
//            return NSLocalizedString(@"Unable to setup resampler", nil);
//        case kxMovieErroUnsupported:
//            return NSLocalizedString(@"The ability is not supported", nil);
//    }
//}

//static BOOL isNetworkPath (NSString *path) {
//    NSRange r = [path rangeOfString:@":"];
//    if (r.location == NSNotFound)
//        return NO;
//
//    NSString *scheme = [path substringToIndex:r.length];
//    if ([scheme isEqualToString:@"file"])
//        return NO;
//
//    return YES;
//}

//static int interrupt_callback(void *ctx);

////////////////////////////////////////////////////////////////////////////////

@interface KxMovieFrame()

@end

@implementation KxMovieFrame

@end

@interface KxAudioFrame()

@end

@implementation KxAudioFrame

- (KxMovieFrameType) type { return KxMovieFrameTypeAudio; }

@end

@interface KxVideoFrame()

@end

@implementation KxVideoFrame
- (KxMovieFrameType) type { return KxMovieFrameTypeVideo; }
@end

@interface KxVideoFrameRGB ()
@end

@implementation KxVideoFrameRGB

- (KxVideoFrameFormat) format {
    return KxVideoFrameFormatRGB;
}

- (UIImage *) asImage {
    UIImage *image = nil;
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)(_rgb));
    if (provider) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        if (colorSpace) {
            CGImageRef imageRef = CGImageCreate(self.width,
                                                self.height,
                                                8,
                                                24,
                                                self.linesize,
                                                colorSpace,
                                                kCGBitmapByteOrderDefault,
                                                provider,
                                                NULL,
                                                YES, // NO
                                                kCGRenderingIntentDefault);
            
            if (imageRef) {
                image = [UIImage imageWithCGImage:imageRef];
                CGImageRelease(imageRef);
            }
            CGColorSpaceRelease(colorSpace);
        }
        CGDataProviderRelease(provider);
    }
    
    return image;
}

@end

@interface KxVideoFrameYUV()

@end

@implementation KxVideoFrameYUV

- (KxVideoFrameFormat) format {
    return KxVideoFrameFormatYUV;
}

static NSData *KxCopyPlane(const uint8_t *src, int linesize, int rows) {
    if (src == NULL || linesize <= 0 || rows <= 0) {
        return nil;
    }
    return [NSData dataWithBytes:src length:(NSUInteger)linesize * (NSUInteger)rows];
}

// 渲染在 GL 队列上异步进行，而 AVFrame 的缓冲区归解码器所有：解下一帧时就会被复用，
// 停播 / 分辨率变化时 DecodeClose 直接 av_frame_free。只存 data 指针的话，
// GL 线程里 glTexImage2D 读到的是已被覆盖或已释放的内存 → EXC_BAD_ACCESS。
// 所以三个平面各拷贝一份（保留 linesize 布局，渲染代码不用改），由帧自己持有。
+ (instancetype) handleVideoFrame:(AVFrame *)videoFrame videoCodecCtx:(AVCodecContext *)videoCodecCtx {
    if (!videoFrame->data[0] || videoFrame->height <= 0)
        return nil;

    const int lumaRows = videoFrame->height;
    int chromaRows = (lumaRows + 1) / 2;
    const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get((enum AVPixelFormat)videoFrame->format);
    if (desc) {
        chromaRows = AV_CEIL_RSHIFT(lumaRows, desc->log2_chroma_h);
    }

    NSData *luma = KxCopyPlane(videoFrame->data[0], videoFrame->linesize[0], lumaRows);
    if (!luma)
        return nil;
    NSData *chromaB = KxCopyPlane(videoFrame->data[1], videoFrame->linesize[1], chromaRows);
    NSData *chromaR = KxCopyPlane(videoFrame->data[2], videoFrame->linesize[2], chromaRows);

    KxVideoFrameYUV * frame = [[KxVideoFrameYUV alloc] init];
    frame.luma = luma;
    frame.chromaB = chromaB;
    frame.chromaR = chromaR;

    frame.lumaData = (uint8_t *)luma.bytes;
    frame.lumaLinesize = videoFrame->linesize[0];
    frame.chromaBData = (uint8_t *)chromaB.bytes;
    frame.chromaBLinesize = videoFrame->linesize[1];
    frame.chromaRData = (uint8_t *)chromaR.bytes;
    frame.chromaRLinesize = videoFrame->linesize[2];

    return frame;
}

@end
