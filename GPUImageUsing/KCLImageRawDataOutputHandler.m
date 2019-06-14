//
//  KCLImageRawDataOutputHandler.m
//  GPUImageUsing
//
//  Created by Chentao on 2019/6/3.
//  Copyright © 2019 Chentao. All rights reserved.
//

#import "KCLImageRawDataOutputHandler.h"
#import <libyuv.h>
#import "KCLH264Encoder.h"


#define aw_stride(wid) ((wid % 16 != 0) ? ((wid) + 16 - (wid) % 16): (wid))

@interface KCLImageRawDataOutputHandler ()<KCLH264EncoderDelegate>

@property (nonatomic, strong) KCLH264Encoder *h264Encoder;

@end

@implementation KCLImageRawDataOutputHandler

-(id)initWithImageSize:(CGSize)newImageSize resultsInBGRAFormat:(BOOL)resultsInBGRAFormat{
    self = [super initWithImageSize:newImageSize resultsInBGRAFormat:resultsInBGRAFormat];
    if (self) {
        self.h264Encoder = [[KCLH264Encoder alloc]init];
        self.h264Encoder.delegate = self;
        self.h264Encoder.frameRate = 15;
        self.h264Encoder.maxKeyFrameInterval = 1;
    }
    return self;
}

-(void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex{
    [super newFrameReadyAtTime:frameTime atIndex:textureIndex];

    //将bgra转为yuv
    //图像宽度
    int width = aw_stride((int)imageSize.width);
    //图像高度
    int height = imageSize.height;
    //宽*高
    int w_x_h = width * height;
    //yuv数据长度 = (宽 * 高) * 3 / 2
    int yuv_len = w_x_h * 3 / 2;
    
    //yuv数据
    uint8_t *yuv_bytes = malloc(yuv_len);
    
    //ARGBToNV12这个函数是libyuv这个第三方库提供的一个将bgra图片转为yuv420格式的一个函数。
    //libyuv是google提供的高性能的图片转码操作。支持大量关于图片的各种高效操作，是视频推流不可缺少的重要组件，你值得拥有。
    [self lockFramebufferForReading];
    ARGBToNV12(self.rawBytesForImage, width * 4, yuv_bytes, width, yuv_bytes + w_x_h, width, width, height);
    [self unlockFramebufferAfterReading];
    
    NSData *yuvData = [NSData dataWithBytesNoCopy:yuv_bytes length:yuv_len];

    NSLog(@"yuvData.length:%d width:%d height:%d",yuvData.length,width,height);
    
    
    
//    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
//    NSString *documentsDirectory = [paths objectAtIndex:0];
//    NSString *filepath= [documentsDirectory stringByAppendingPathComponent:@"test.yuv"];
//    [yuvData writeToFile:filepath atomically:YES];
    
    /////////////////
    
//    int sYLineSize = packet.yLineSize;
//    int sULineSize = packet.uLineSize;
//    int sVLineSize = packet.vLineSize;
    //////////////////////////////////////
    CVPixelBufferRef pxbuffer;
    CVReturn rc;

    rc = CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pxbuffer);
    if (rc != 0) {
        NSLog(@"CVPixelBufferCreate failed %d", rc);
        if (pxbuffer) { CFRelease(pxbuffer); }
        return;
    }

    rc = CVPixelBufferLockBaseAddress(pxbuffer, 0);

    if (rc != 0) {
        NSLog(@"CVPixelBufferLockBaseAddress falied %d", rc);
        if (pxbuffer) { CFRelease(pxbuffer); }
        return;
    } else {
        uint8_t *y_copyBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 0);
        uint8_t *uv_copyBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 1);


        //NSLog(@"%@%@%@",y_copyBaseAddress,u_copyBaseAddress,v_copyBaseAddress);
        
        
//        int dYLineSize = (int)CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 0);
//        int dULineSize = (int)CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 1);
//        int dVLineSize = (int)CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 2);

        memcpy(y_copyBaseAddress, yuvData.bytes,              w_x_h);
        memcpy(uv_copyBaseAddress, yuvData.bytes + w_x_h, w_x_h*0.5);


        rc = CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
        if (rc != 0) {
            NSLog(@"CVPixelBufferUnlockBaseAddress falied %d", rc);
        }
    }

    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pxbuffer, &videoInfo);

    CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeInvalid, kCMTimeInvalid};
    CMSampleBufferRef dstSampleBuffer = NULL;
    rc = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pxbuffer, YES, NULL, NULL, videoInfo, &timing, &dstSampleBuffer);

    if (rc) {
        NSLog(@"CMSampleBufferCreateForImageBuffer error: %d", rc);
    } else {
        if (!self.h264Encoder.initialize) {
            [self.h264Encoder configurationEncoderWithWidth:width height:height];
        }
        [self.h264Encoder encode:dstSampleBuffer];
    }

    if (pxbuffer) { CFRelease(pxbuffer); }
    if (videoInfo) { CFRelease(videoInfo); }
    if (dstSampleBuffer) { CFRelease(dstSampleBuffer); }
}


#pragma mark - KCLH264EncoderDelegate
-(void)h264Encoder:(KCLH264Encoder *)encoder encodeOutputData:(NSData *)data{
    NSLog(@"encoder data length:%d %@",data.length,[NSThread currentThread]);
    [self.delegate dataOutputHandler:self h264Data:data];
}

////YUV数据转CVPixelBuffer（不是必须）
//- (void)didReceivedYUV420pPacket:(APYUV420pPacket)packet {
//    int sYLineSize = packet.yLineSize;
//    int sULineSize = packet.uLineSize;
//    int sVLineSize = packet.vLineSize;
//    int sYSize = sYLineSize * packet.height;
//    int sUSize = sULineSize * packet.height/2;
//    int sVSize = sVLineSize * packet.height/2;
//
//    int dWidth = packet.width;
//    int dHeight = packet.height;
//
//    CVPixelBufferRef pxbuffer;
//    CVReturn rc;
//
//    rc = CVPixelBufferCreate(NULL, dWidth, dHeight, kCVPixelFormatType_420YpCbCr8PlanarFullRange, NULL, &pxbuffer);
//    if (rc != 0) {
//        NSLog(@"CVPixelBufferCreate failed %d", rc);
//        if (pxbuffer) { CFRelease(pxbuffer); }
//        return;
//    }
//
//    rc = CVPixelBufferLockBaseAddress(pxbuffer, 0);
//
//    if (rc != 0) {
//        NSLog(@"CVPixelBufferLockBaseAddress falied %d", rc);
//        if (pxbuffer) { CFRelease(pxbuffer); }
//        return;
//    } else {
//        uint8_t *y_copyBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 0);
//        uint8_t *u_copyBaseAddress= (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 1);
//        uint8_t *v_copyBaseAddress= (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 2);
//
//        int dYLineSize = (int)CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 0);
//        int dULineSize = (int)CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 1);
//        int dVLineSize = (int)CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 2);
//
//        memcpy(y_copyBaseAddress, packet.dataBuffer,                    sYSize);
//        memcpy(u_copyBaseAddress, packet.dataBuffer + sYSize,           sUSize);
//        memcpy(v_copyBaseAddress, packet.dataBuffer + sYSize + sUSize,  sVSize);
//
//
//        rc = CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
//        if (rc != 0) {
//            NSLog(@"CVPixelBufferUnlockBaseAddress falied %d", rc);
//        }
//    }
//
//    CMVideoFormatDescriptionRef videoInfo = NULL;
//    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pxbuffer, &videoInfo);
//
//    CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeInvalid, kCMTimeInvalid};
//    CMSampleBufferRef dstSampleBuffer = NULL;
//    rc = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pxbuffer, YES, NULL, NULL, videoInfo, &timing, &dstSampleBuffer);
//
//    if (rc) {
//        NSLog(@"CMSampleBufferCreateForImageBuffer error: %d", rc);
//    } else {
//        [self.txLivePublisher sendVideoSampleBuffer:dstSampleBuffer];
//    }
//
//    if (pxbuffer) { CFRelease(pxbuffer); }
//    if (videoInfo) { CFRelease(videoInfo); }
//    if (dstSampleBuffer) { CFRelease(dstSampleBuffer); }
//}


@end