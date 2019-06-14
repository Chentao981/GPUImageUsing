

//
//  KCLH264Decoder.m
//  H264Decoder
//
//  Created by Chentao on 2017/11/28.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import "KCLH264Decoder.h"
#import "KCLH264NaluParser.h"
#import <VideoToolbox/VideoToolbox.h>
#import "KCLLogger.h"
#import "KCLThreadedComponent.h"
#import "KCLUtilityMacro.h"

static const int KCL_NALU_HEADER_LENGTH = 4;

static NSString *const kKCLH264DecoderSynlock = @"h264DecoderSynlock"; //解码同步控制

@interface KCLH264DecoderData : NSObject

@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) uint32_t timeLine;

@end

@implementation KCLH264DecoderData
@end

@interface KCLH264Decoder () <KCLH264NaluParserDelegate>

@end

@implementation KCLH264Decoder {
    NSData *spsData;
    BOOL receiveSPS;

    NSData *ppsData;
    BOOL receivePPS;

    VTDecompressionSessionRef deocderSession;
    BOOL deocderSessionInitialize;

    CMVideoFormatDescriptionRef decoderFormatDescription;

    BOOL isInvalidate;

    uint32_t currentTimeLine;

    KCLThreadedComponent *_decoderThreadComponent;
    BOOL _decoderThreadStop;
    BOOL _decoding;

    KCLH264NaluParser *_naluParser;
    KCLSafeMutableArray *_decoderDatas;
}

- (instancetype)init {
    self = [super init];
    if (self) {

        _naluParser = [[KCLH264NaluParser alloc] init];
        _naluParser.delegate = self;

        _maxFrameDataCount = 2 * KCL_DEFAULT_VIDEO_FPS; // 2秒  ;

        _decoderDatas = [[KCLSafeMutableArray alloc] init];
        self.frameDatas = [[KCLSafeMutableArray alloc] init];

        _decoderThreadComponent = [[KCLThreadedComponent alloc] init];
        _decoderThreadComponent.threadName = @"h264DecoderThread";
        [_decoderThreadComponent start];
    }
    return self;
}

- (void)pushData:(NSData *)data timeLine:(uint32_t)timeLine {

    if (!_decoderThreadStop) {
        KCLH264DecoderData *decoderData = [[KCLH264DecoderData alloc] init];
        decoderData.data = data;
        decoderData.timeLine = timeLine;
        [_decoderDatas addObject:decoderData];

        if (!_decoding) {
            __weak NSThread *decoderThread = _decoderThreadComponent.thread;
            [self performSelector:@selector(startDecoderHandler) onThread:decoderThread withObject:nil waitUntilDone:NO];
        }
    }
}

- (void)startDecoderHandler {
    _decoding = YES;
    while ([_decoderDatas count] > 0 && !_decoderThreadStop && [self.frameDatas count] < _maxFrameDataCount) {
        KCLH264DecoderData *decoderData = [_decoderDatas firstObject];
        NSData *decoderSourceData = decoderData.data;
        NSUInteger dataLength = decoderSourceData.length;

        currentTimeLine = decoderData.timeLine;

        if (dataLength > 0) {
            uint8_t *_pointer = (uint8_t *)decoderSourceData.bytes;
            size_t typeLength = sizeof(uint8_t);
            size_t _poz = 0;

            while (_poz <= (dataLength - 1)) {
                uint8_t *ptr = _pointer + _poz;
                _poz += typeLength;
                [_naluParser pushData:ptr size:1];
            }
        }

        [_decoderDatas removeObjectAtIndex:0];
    }
    _decoding = NO;
}

- (void)reset {
    __weak NSThread *decoderThread = _decoderThreadComponent.thread;
    [self performSelector:@selector(resetHandler) onThread:decoderThread withObject:nil waitUntilDone:YES];
}

- (void)resetHandler {
    [_decoderDatas removeAllObjects];
    [self.frameDatas removeAllObjects];

    [_naluParser clear];
    receiveSPS = NO;
    receivePPS = NO;
}

- (void)destroy {
    __weak NSThread *decoderThread = _decoderThreadComponent.thread;
    [self performSelector:@selector(destroyHandler) onThread:decoderThread withObject:nil waitUntilDone:YES];

    _decoderThreadStop = YES;
    [_decoderThreadComponent stop];
}

- (void)destroyHandler {
    if (NULL != deocderSession) {
        VTDecompressionSessionInvalidate(deocderSession);
        CFRelease(deocderSession);
        deocderSession = NULL;
    }
    if (NULL != decoderFormatDescription) {
        CFRelease(decoderFormatDescription);
        decoderFormatDescription = NULL;
    }
}

- (void)initializeDecoder {
    //    if (receiveSPS && receivePPS) {

    NSLog(@"initializeDecoder");

    const uint8_t *const parameterSetPointers[2] = { spsData.bytes, ppsData.bytes };
    const size_t parameterSetSizes[2] = { spsData.length, ppsData.length };

    if (NULL != decoderFormatDescription) {
        CFRelease(decoderFormatDescription);
        decoderFormatDescription = NULL;
    }

    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, KCL_NALU_HEADER_LENGTH, &decoderFormatDescription);
    if (noErr == status) {
        CGSize videoSize = CMVideoFormatDescriptionGetPresentationDimensions(decoderFormatDescription, NO, NO);
        NSDictionary *destinationPixelBufferAttributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
            (id)kCVPixelBufferWidthKey: [NSNumber numberWithInt:videoSize.width],
            (id)kCVPixelBufferHeightKey: [NSNumber numberWithInt:videoSize.height],
            (id)kCVPixelBufferOpenGLCompatibilityKey: [NSNumber numberWithBool:YES]
        };

        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;

        if (NULL != deocderSession) {
            VTDecompressionSessionInvalidate(deocderSession);
            CFRelease(deocderSession);
            deocderSession = NULL;
        }

        status = VTDecompressionSessionCreate(kCFAllocatorDefault, decoderFormatDescription, NULL, (__bridge CFDictionaryRef)destinationPixelBufferAttributes, &callBackRecord, &deocderSession);
        if (noErr == status) {

            VTSessionSetProperty(deocderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
            VTSessionSetProperty(deocderSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);

            deocderSessionInitialize = YES;
            receiveSPS = NO;
            receivePPS = NO;
        } else {
            deocderSessionInitialize = NO;
            KCLLogError(@"H264 Decoder: create decompression session  failed status=%d", (int)status);
        }
    } else {
        deocderSessionInitialize = NO;
        KCLLogError(@"H264 Decoder: create video format description  failed status=%d", (int)status);
    }
    //    }
}

//- (CVPixelBufferRef)decodeH264Data:(NSData *)data naluType:(int)naluType {
- (CVPixelBufferRef)decodeH264Nalu:(KCLH264Nalu *)nalu {
    // NSLog(@"%s naluType=%d", __FUNCTION__, nalu.naluType);

    CMBlockBufferRef blockBuffer = NULL;

    //    NSLog(@"%lu", data.length);
    CVPixelBufferRef outputPixelBuffer = NULL;

    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL, nalu.naluData.bytes, nalu.naluData.length, kCFAllocatorNull, NULL, 0, nalu.naluData.length, FALSE, &blockBuffer);
    if (kCMBlockBufferNoErr == status) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = { nalu.naluData.length };
        status = CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, decoderFormatDescription, 1, 0, NULL, 1, sampleSizeArray, &sampleBuffer);
        if (kCMBlockBufferNoErr == status && sampleBuffer) {

            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(deocderSession, sampleBuffer, flags, &outputPixelBuffer, &flagOut);
            CFRelease(sampleBuffer);

            if (noErr != decodeStatus) {
                KCLLogError(@"H264 Decoder: decoder failed:%d naluType:%ld", (int)decodeStatus, nalu.naluType);
                if (kVTInvalidSessionErr == decodeStatus) {
                    [self resetDecoder];
                }
            }

        } else {
            KCLLogError(@"H264 Decoder: init sampleBuffer failed:%d naluType:%ld", (int)status, nalu.naluType);
        }
        CFRelease(blockBuffer);
    } else {
        KCLLogError(@"H264 Decoder: init blockBuffer failed:%d naluType:%ld", (int)status, nalu.naluType);
    }

    return outputPixelBuffer;
}

//解码回调函数
static void didDecompress(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration) {
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
}

#pragma mark - KCLH264NaluParserDelegate

- (void)h264NaluParser:(KCLH264NaluParser *)parser receiveNalu:(KCLH264Nalu *)nalu {
    // NSLog(@"packetDataLength:%lu nalutype:%d", nalu.naluData.length, nalu.naluType);
    switch (nalu.naluType) {
        case 7: {
            receiveSPS = YES;
            spsData = [NSData dataWithData:[nalu.naluData subdataWithRange:NSMakeRange(KCL_NALU_HEADER_LENGTH, nalu.naluData.length - KCL_NALU_HEADER_LENGTH)]];
            // KCLLogDebug(@"spsData:%@", spsData);
            break;
        }
        case 8: {
            receivePPS = YES;
            ppsData = [NSData dataWithData:[nalu.naluData subdataWithRange:NSMakeRange(KCL_NALU_HEADER_LENGTH, nalu.naluData.length - KCL_NALU_HEADER_LENGTH)]];
            // KCLLogDebug(@"ppsData:%@",ppsData);
            break;
        }
        default: {
            if (receiveSPS && receivePPS) {
                [self initializeDecoder];
            }

            if (deocderSessionInitialize) {
                //                if (KCLH264NALUTypeIDR == nalu.naluType) {
                //                    [_naluSequence removeAllObjects];
                //                }
                //                [_naluSequence addObject:nalu];

                // NSLog(@"_naluSequence:%ld", _naluSequence.count);

                CVPixelBufferRef outputPixelBuffer = [self decodeH264Nalu:nalu];

                if (outputPixelBuffer) {
                    CVPixelBufferLockBaseAddress(outputPixelBuffer, 0);

                    KCLVideoFrameData *frameData = [[KCLVideoFrameData alloc] init];
                    frameData.decoderId = self.decoderId;
                    frameData.pixelBuffer = outputPixelBuffer;
                    frameData.timeLine = currentTimeLine;
                    [self.frameDatas addObject:frameData];

                    [self performSelectorOnMainThread:@selector(receiveFrameDataHandler) withObject:nil waitUntilDone:NO];

                    CVPixelBufferUnlockBaseAddress(outputPixelBuffer, 0);
                    CVPixelBufferRelease(outputPixelBuffer);
                }
            }
            break;
        }
    }
}

- (void)receiveFrameDataHandler {
    if (self.delegate && [self.delegate respondsToSelector:@selector(h264DecoderReceiveFrameData:)]) {
        [self.delegate h264DecoderReceiveFrameData:self];
    }
}

#pragma mark -

- (void)resetDecoder {
    //    if (spsData && ppsData) {
    //        [self initializeDecoder];
    //        if (_naluSequence.count > 0) {
    //            for (KCLH264Nalu *nalu in _naluSequence) {
    //                [self decodeH264Nalu:nalu];
    //            }
    //        }
    //    }
}

- (void)dealloc {
    KCLLogDebug(@"%s", __FUNCTION__);
}

@end

