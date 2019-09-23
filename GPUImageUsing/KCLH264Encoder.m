//
//  KCLH264Encoder.m
//  CameraVideoCapture
//
//  Created by Chentao on 2019/5/16.
//  Copyright © 2019 Chentao. All rights reserved.
//

#import "KCLH264Encoder.h"
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "KCLLogger.h"

@implementation KCLH264Encoder{
    VTCompressionSessionRef encodingSession;
}

- (instancetype)init{
    self = [super init];
    if (self) {
        encodingSession = NULL;
        _initialize = NO;
    }
    return self;
}


-(void)configurationEncoderWithWidth:(int)width height:(int)height{
    [self destroyEncodingSession];
    
    OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, encodeOutputDataCallback, (__bridge void * _Nullable)(self), &encodingSession);
    if (0 == status) {
        
        _initialize = YES;
        
        // 设置码率 512kbps
        OSStatus status = VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(1024 * 1024));
        // 设置ProfileLevel为BP3.1
        status = VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_3_1);
        // 设置实时编码输出（避免延迟）
        status = VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        // 配置是否产生B帧
        status = VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
        // 配置最大I帧间隔  15帧 x 240秒 = 3600帧，也就是每隔3600帧编一个I帧
        status = VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(self.frameRate * self.maxKeyFrameInterval));
        // 配置I帧持续时间，240秒编一个I帧
        status = VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (__bridge CFTypeRef)@(self.maxKeyFrameInterval));
        // 编码器准备编码
        status = VTCompressionSessionPrepareToEncodeFrames(encodingSession);
    }
}

-(void)encode:(CMSampleBufferRef)sampleBuffer{
    //    /////////
    //    // 获取CVImageBufferRef
    //    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    //    // 设置是否为I帧
    //    NSDictionary *frameProperties = @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @(forceKeyFrame)};;
    //    // 输入待编码数据
    //    OSStatus status = VTCompressionSessionEncodeFrame(encodingSession, imageBuffer, kCMTimeInvalid, kCMTimeInvalid, (__bridge CFDictionaryRef)frameProperties, NULL, NULL);
    //    /////////
    
    
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    
    // Create properties
    //    CMTime presentationTimeStamp = CMTimeMake(frameCount, 1000);
    //CMTime duration = CMTimeMake(1, DURATION);
    VTEncodeInfoFlags flags;
    
    // Pass it to the encoder
    OSStatus statusCode = VTCompressionSessionEncodeFrame(encodingSession,
                                                          imageBuffer,
                                                          kCMTimeInvalid,
                                                          kCMTimeInvalid,
                                                          NULL,
                                                          NULL,
                                                          &flags);
    
    if (noErr != statusCode) {
        KCLLogError(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        [self destroyEncodingSession];
    }
}


-(void)destroyEncodingSession{
    if (encodingSession) {
        VTCompressionSessionCompleteFrames(encodingSession, kCMTimeInvalid);
        VTCompressionSessionInvalidate(encodingSession);
        CFRelease(encodingSession);
        encodingSession = NULL;
        _initialize = NO;
    }
}

void encodeOutputDataCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,  CMSampleBufferRef sampleBuffer){
    
    KCLH264Encoder *encoder = (__bridge KCLH264Encoder *)outputCallbackRefCon;
    // 开始码
    const char header[] = "\x00\x00\x00\x01";
    size_t headerLen = (sizeof header) - 1;
    NSData *headerData = [NSData dataWithBytes:header length:headerLen];
    
    // 判断是否是关键帧
    bool isKeyFrame = !CFDictionaryContainsKey((CFDictionaryRef)CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0), (const void *)kCMSampleAttachmentKey_NotSync);
    
    if (isKeyFrame){
        KCLLogDebug(@"VEVideoEncoder::编码了一个关键帧");
        CMFormatDescriptionRef formatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        // 关键帧需要加上SPS、PPS信息
        size_t sParameterSetSize, sParameterSetCount;
        const uint8_t *sParameterSet;
        OSStatus spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescriptionRef, 0, &sParameterSet, &sParameterSetSize, &sParameterSetCount, 0);
        
        size_t pParameterSetSize, pParameterSetCount;
        const uint8_t *pParameterSet;
        OSStatus ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescriptionRef, 1, &pParameterSet, &pParameterSetSize, &pParameterSetCount, 0);
        
        if (noErr == spsStatus && noErr == ppsStatus){
            // sps数据加上开始码组成NALU
            NSData *sps = [NSData dataWithBytes:sParameterSet length:sParameterSetSize];
            NSMutableData *spsData = [NSMutableData data];
            [spsData appendData:headerData];
            [spsData appendData:sps];
            //            // 通过代理回调给上层
            if ([encoder.delegate respondsToSelector:@selector(h264Encoder:encodeOutputData:)]) {
                [encoder.delegate h264Encoder:encoder encodeOutputData:spsData];
            }
            
            // pps数据加上开始码组成NALU
            NSData *pps = [NSData dataWithBytes:pParameterSet length:pParameterSetSize];
            NSMutableData *ppsData = [NSMutableData data];
            [ppsData appendData:headerData];
            [ppsData appendData:pps];
            
            if ([encoder.delegate respondsToSelector:@selector(h264Encoder:encodeOutputData:)]) {
                [encoder.delegate h264Encoder:encoder encodeOutputData:ppsData];
            }
            
        }
    }
    // 获取帧数据
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    status = CMBlockBufferGetDataPointer(blockBuffer, 0, &length, &totalLength, &dataPointer);
    if (noErr != status)
    {
        KCLLogError(@"VEVideoEncoder::CMBlockBufferGetDataPointer Error : %d!", (int)status);
        return;
    }
    
    size_t bufferOffset = 0;
    static const int avcHeaderLength = 4;
    while (bufferOffset < totalLength - avcHeaderLength){
        // 读取 NAL 单元长度
        uint32_t nalUnitLength = 0;
        memcpy(&nalUnitLength, dataPointer + bufferOffset, avcHeaderLength);
        
        // 大端转小端
        nalUnitLength = CFSwapInt32BigToHost(nalUnitLength);
        
        NSData *frameData = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + avcHeaderLength) length:nalUnitLength];
        
        NSMutableData *outputFrameData = [NSMutableData data];
        [outputFrameData appendData:headerData];
        [outputFrameData appendData:frameData];
        
        bufferOffset += avcHeaderLength + nalUnitLength;
        
        if ([encoder.delegate respondsToSelector:@selector(h264Encoder:encodeOutputData:)]) {
            [encoder.delegate h264Encoder:encoder encodeOutputData:outputFrameData];
        }
        
    }
}



@end
