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
//#define aw_stride(wid) ((wid % 4 != 0) ? ((wid) + 4 - (wid) % 4): (wid))


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

//static int i = 0;

-(void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex{
    [super newFrameReadyAtTime:frameTime atIndex:textureIndex];
    
    //将bgra转为yuv
    //图像宽度
    int width = aw_stride((int)imageSize.width);
    //图像高度
    int height = imageSize.height;
    
    NSLog(@"width:%d,height:%d",width,height);
    
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
    
    
    //    NSData *yuvData = [NSData dataWithBytesNoCopy:yuv_bytes length:yuv_len];
    //    NSLog(@"yuvData.length:%d width:%d height:%d",yuvData.length,width,height);
    
    //    i++;
    //    /////////////
    //    if (i==40) {
    //        NSData *desData = [NSData dataWithBytes:yuv_bytes length:yuv_len];
    //        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    //        NSString *documentsDirectory = [paths objectAtIndex:0];
    //
    //        NSString *clipFilePath = [documentsDirectory stringByAppendingPathComponent:@"test.yuv"];
    //
    //        [[NSFileManager defaultManager] createFileAtPath:clipFilePath contents:nil attributes:nil];
    //
    //        NSFileHandle *fileHandler = [NSFileHandle fileHandleForWritingAtPath:clipFilePath];
    //
    //        [fileHandler writeData:desData];
    //
    //        [fileHandler closeFile];
    //    }
    
    
    
    
    
    
    //////////////////////////////////////
    CVPixelBufferRef pxbuffer;
    CVReturn rc;
    
//    NSDictionary *pixelBufferAttributes = [[NSDictionary alloc]initWithObjectsAndKeys:[NSNumber numberWithInt:width/2],kCVPixelBufferBytesPerRowAlignmentKey,
//                                           nil];
//
//    rc = CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, (__bridge CFDictionaryRef)pixelBufferAttributes, &pxbuffer);
    
    rc = CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pxbuffer);
    
    if (rc != 0) {
        NSLog(@"CVPixelBufferCreate failed %d", rc);
        if (pxbuffer) { CFRelease(pxbuffer); }
        free(yuv_bytes);
        return;
    }
    
    rc = CVPixelBufferLockBaseAddress(pxbuffer, 0);
    
    if (rc != 0) {
        NSLog(@"CVPixelBufferLockBaseAddress falied %d", rc);
        if (pxbuffer) { CFRelease(pxbuffer); }
        free(yuv_bytes);
        return;
    } else {
        //////////////////////
//        size_t yWidth = CVPixelBufferGetWidthOfPlane(pxbuffer, 0);
        size_t yHeight = CVPixelBufferGetHeightOfPlane(pxbuffer, 0);
        
//        size_t uvWidth = CVPixelBufferGetWidthOfPlane(pxbuffer, 1);
        size_t uvHeight = CVPixelBufferGetHeightOfPlane(pxbuffer, 1);
        
        size_t bytesPerRowY = CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 0);
        size_t bytesPerRowUV = CVPixelBufferGetBytesPerRowOfPlane(pxbuffer, 1);
        
        
        //NSLog(@"yWidth:%d yHeight:%d uvWidth:%d uvHeight:%d bytesPerRowY:%d bytesPerRowUV:%d",yWidth,yHeight,uvWidth,uvHeight,bytesPerRowY,bytesPerRowUV);

        uint8_t *y_copyBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 0);
        memset(y_copyBaseAddress, 0x80, yHeight * bytesPerRowY);
        uint8_t *y_bytes = yuv_bytes;
        for (int row = 0; row < yHeight; row++) {
            memcpy(y_copyBaseAddress + row * bytesPerRowY, y_bytes + row * width, width);
        }
        
        uint8_t *uv_copyBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 1);
        memset(uv_copyBaseAddress, 0x80, uvHeight * bytesPerRowUV);
        uint8_t *uv_bytes = yuv_bytes + w_x_h;
        for (int row = 0; row < uvHeight; row++) {
            memcpy(uv_copyBaseAddress + row * bytesPerRowUV, uv_bytes + row * width, width);
        }
        //////////////////////
        
//        ////////////////////////
//        uint8_t *y_copyBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 0);
//        uint8_t *uv_copyBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 1);
//
//        memcpy(y_copyBaseAddress, yuv_bytes,              w_x_h);
//        memcpy(uv_copyBaseAddress, yuv_bytes + w_x_h, w_x_h/2);
//        ////////////////////////
        
        rc = CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
        if (rc != 0) {
            NSLog(@"CVPixelBufferUnlockBaseAddress falied %d", rc);
        }
    }
    
//    ////////////////////////
//    
//            size_t frameWidth = CVPixelBufferGetWidth(pxbuffer);
//            size_t frameHeight = CVPixelBufferGetHeight(pxbuffer);
//    
//            int yuvDataLength = frameWidth*frameHeight*3/2;
//            char *yuvData = malloc(yuvDataLength);
//            pixelBufferNV21ToYUV(pxbuffer,yuvData);
//    
//            i++;
//            /////////////
//            if (i==40) {
//                NSData *desData = [NSData dataWithBytes:yuvData length:yuvDataLength];
//                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
//                NSString *documentsDirectory = [paths objectAtIndex:0];
//    
//                NSString *clipFilePath = [documentsDirectory stringByAppendingPathComponent:@"test.yuv"];
//    
//                [[NSFileManager defaultManager] createFileAtPath:clipFilePath contents:nil attributes:nil];
//    
//                NSFileHandle *fileHandler = [NSFileHandle fileHandleForWritingAtPath:clipFilePath];
//    
//                [fileHandler writeData:desData];
//    
//                [fileHandler closeFile];
//            }
//    ////////////////////////
    
    
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
    
    free(yuv_bytes);
    
    if (pxbuffer) { CFRelease(pxbuffer); }
    if (videoInfo) { CFRelease(videoInfo); }
    if (dstSampleBuffer) { CFRelease(dstSampleBuffer); }
}


#pragma mark - KCLH264EncoderDelegate
-(void)h264Encoder:(KCLH264Encoder *)encoder encodeOutputData:(NSData *)data{
    NSLog(@"encoder data length:%d %@",data.length,[NSThread currentThread]);
    [self.delegate dataOutputHandler:self h264Data:data];
}


int pixelBufferNV21ToYUV(CVPixelBufferRef pixelBuffer,char *yuvData){
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    if (CVPixelBufferIsPlanar(pixelBuffer)) {
        size_t w = CVPixelBufferGetWidth(pixelBuffer);
        size_t h = CVPixelBufferGetHeight(pixelBuffer);
        
        size_t d = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        char* src = (char*) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        char* dst = yuvData;
        
        for (unsigned int rIdx = 0; rIdx < h; ++rIdx, dst += w, src += d) {
            memcpy(dst, src, w);
        }
        
        d = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        src = (char *) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
        
        h = h >> 1;
        for (unsigned int rIdx = 0; rIdx < h; ++rIdx, dst += w, src += d) {
            memcpy(dst, src, w);
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return 0;
}

@end
