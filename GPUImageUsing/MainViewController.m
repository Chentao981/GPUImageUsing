//
//  MainViewController.m
//  GPUImageUsing
//
//  Created by Chentao on 2019/5/30.
//  Copyright © 2019 Chentao. All rights reserved.
//

#import "MainViewController.h"
#import <GPUImage/GPUImage.h>
#import "DSoftLightBlendFilter.h"
#import "GPUImageBeautyFilter.h"
#import "KCLImageRawDataOutputHandler.h"
#import "KCLH264Decoder.h"
#import "KCLOpenGLImageView.h"



@interface MainViewController ()<KCLH264DecoderDelegate,KCLImageRawDataOutputHandlerDelegate>

@property(nonatomic,strong)GPUImageVideoCamera *videoCamera;
@property(nonatomic,strong)GPUImageView *videoView;

@property(nonatomic,strong)GPUImageFilterGroup *filterGroup;

@property(nonatomic,strong)GPUImageBeautyFilter *beautifyFilter;
@property(nonatomic,strong)DSoftLightBlendFilter *blendFilter;
@property(nonatomic,strong)GPUImageTransformFilter *transformFilter;

@property(nonatomic,strong)KCLImageRawDataOutputHandler *imageRawDataOutputHandler;

/** 视频流播放器 */
@property (nonatomic, strong) KCLOpenGLImageView *playLayer;

/** H264解码器 */
@property (nonatomic, strong) KCLH264Decoder *h264Decoder;

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    //CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    //CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    
    // 初始化视频解码
    self.h264Decoder = [[KCLH264Decoder alloc]init];
    self.h264Decoder.delegate = self;
    
    
    //////////////////////////
    self.videoCamera = [[GPUImageVideoCamera alloc]initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionFront];
    self.videoCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
    self.videoCamera.horizontallyMirrorFrontFacingCamera = YES;
    self.videoCamera.horizontallyMirrorRearFacingCamera = NO;
    self.videoCamera.frameRate = 15;
    //////////////////////////
    
    self.filterGroup = [[GPUImageFilterGroup alloc]init];
    
    self.beautifyFilter = [[GPUImageBeautyFilter alloc]init];
    [self.filterGroup addFilter:self.beautifyFilter];
    
    self.blendFilter = [[DSoftLightBlendFilter alloc]init];
    [self.filterGroup addFilter:self.blendFilter];
    
    self.transformFilter =[[GPUImageTransformFilter alloc]init];
    CATransform3D transform = CATransform3DIdentity;
    transform = CATransform3DRotate(transform,M_PI, 0.0, 1.0, 0.0);
    self.transformFilter.transform3D =transform;
    [self.filterGroup addFilter:self.transformFilter];

    [self.beautifyFilter addTarget:self.blendFilter];
    [self.blendFilter addTarget:self.transformFilter];
    
    [self.filterGroup setInitialFilters:[NSArray arrayWithObject:self.beautifyFilter]];
    [self.filterGroup setTerminalFilter:self.blendFilter];
    
    [self.videoCamera addTarget:self.filterGroup];
    
    //////////////////////////
    
    CGFloat videoViewW = 144;
    CGFloat videoViewH = 192;
    CGFloat videoViewX = 5;
    CGFloat videoViewY = 50;
    
    self.videoView = [[GPUImageView alloc]initWithFrame:CGRectMake(videoViewX, videoViewY, 2*videoViewW, 2*videoViewH)];
    self.videoView.backgroundColor = [UIColor blackColor];
    [self.videoView setInputRotation:kGPUImageFlipHorizonal atIndex:0];
    self.videoView.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
    [self.view addSubview:self.videoView];
    
    [self.transformFilter addTarget:self.videoView];
    
    //////////////////////////
    
    self.imageRawDataOutputHandler = [[KCLImageRawDataOutputHandler alloc]initWithImageSize:CGSizeMake(2*videoViewW, 2*videoViewH) resultsInBGRAFormat:YES];
    self.imageRawDataOutputHandler.delegate = self;
    [self.filterGroup addTarget:self.imageRawDataOutputHandler];
    
    ///////////////////////////
    self.playLayer = [[KCLOpenGLImageView alloc] initWithFrame:CGRectMake(CGRectGetMaxX(self.videoView.frame)+10 , videoViewY, videoViewW, videoViewH)];
//    self.playLayer = [[KCLOpenGLImageView alloc] initWithFrame:CGRectMake(CGRectGetMaxX(self.videoView.frame)+10 , videoViewY, 100, 100)];
    self.playLayer.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.playLayer];
    //////////////////////////
    
    CGFloat startButtonW = 70;
    CGFloat startButtonH = 35;
    CGFloat startButtonX = 30;
    CGFloat startButtonY = CGRectGetMaxY(self.videoView.frame) + 20;
    
    UIButton *startButton = [[UIButton alloc]initWithFrame:CGRectMake(startButtonX, startButtonY, startButtonW, startButtonH)];
    startButton.backgroundColor = [UIColor grayColor];
    [startButton addTarget:self action:@selector(startButtonTouchHandler:) forControlEvents:UIControlEventTouchUpInside];
    [startButton setTitle:@"start" forState:UIControlStateNormal];
    [self.view addSubview:startButton];
    ///////////
    
    CGFloat rotateButtonW = 70;
    CGFloat rotateButtonH = 35;
    CGFloat rotateButtonX = CGRectGetMaxX(startButton.frame) + 30;
    CGFloat rotateButtonY = CGRectGetMaxY(self.videoView.frame) + 20;
    
    UIButton *rotateButton = [[UIButton alloc]initWithFrame:CGRectMake(rotateButtonX, rotateButtonY, rotateButtonW, rotateButtonH)];
    rotateButton.backgroundColor = [UIColor grayColor];
    [rotateButton addTarget:self action:@selector(rotateButtonTouchHandler:) forControlEvents:UIControlEventTouchUpInside];
    [rotateButton setTitle:@"back" forState:UIControlStateNormal];
    [rotateButton setTitle:@"front" forState:UIControlStateSelected];
    [self.view addSubview:rotateButton];
    
    ///////////
    CGFloat stopButtonW = 70;
    CGFloat stopButtonH = 35;
    CGFloat stopButtonX = CGRectGetMaxX(rotateButton.frame) + 30;
    CGFloat stopButtonY = CGRectGetMaxY(self.videoView.frame) + 20;
    
    UIButton *stopButton = [[UIButton alloc]initWithFrame:CGRectMake(stopButtonX, stopButtonY, stopButtonW, stopButtonH)];
    stopButton.backgroundColor = [UIColor grayColor];
    [stopButton addTarget:self action:@selector(stopButtonTouchHandler:) forControlEvents:UIControlEventTouchUpInside];
    [stopButton setTitle:@"stop" forState:UIControlStateNormal];
    [self.view addSubview:stopButton];
    
    ///////////
    CGFloat beautifyButtonW = 70;
    CGFloat beautifyButtonH = 35;
    CGFloat beautifyButtonX = CGRectGetMinX(startButton.frame);
    CGFloat beautifyButtonY = CGRectGetMaxY(startButton.frame) + 20;
    
    UIButton *beautifyButton = [[UIButton alloc]initWithFrame:CGRectMake(beautifyButtonX, beautifyButtonY, beautifyButtonW, beautifyButtonH)];
    beautifyButton.backgroundColor = [UIColor grayColor];
    [beautifyButton addTarget:self action:@selector(beautifyButtonTouchHandler:) forControlEvents:UIControlEventTouchUpInside];
    [beautifyButton setTitle:@"去美颜" forState:UIControlStateNormal];
    [beautifyButton setTitle:@"美颜" forState:UIControlStateSelected];
    [self.view addSubview:beautifyButton];
    
    //////////////////////////
    
    
    
}


-(void)startButtonTouchHandler:(UIButton *) button{
    [self.videoCamera startCameraCapture];
}

-(void)rotateButtonTouchHandler:(UIButton *) button{
    [self.videoCamera rotateCamera];
    button.selected = !button.selected;
}

-(void)stopButtonTouchHandler:(UIButton *) button{
    [self.videoCamera stopCameraCapture];
}

-(void)beautifyButtonTouchHandler:(UIButton *) button{
    
    if (button.selected) {
        [self.filterGroup addFilter:self.beautifyFilter];
        [self.beautifyFilter addTarget:self.blendFilter];
        [self.filterGroup setInitialFilters:[NSArray arrayWithObject:self.beautifyFilter]];
        [self.filterGroup setTerminalFilter:self.blendFilter];
    }else{
        [self.beautifyFilter removeTarget:self.blendFilter];
        [self.filterGroup removeTarget:self.beautifyFilter];
        [self.filterGroup setInitialFilters:[NSArray arrayWithObject:self.blendFilter]];
        [self.filterGroup setTerminalFilter:self.blendFilter];
    }
    button.selected = !button.selected;
}


#pragma mark - KCLImageRawDataOutputHandlerDelegate
-(void)dataOutputHandler:(KCLImageRawDataOutputHandler *)handler h264Data:(NSData *)data{
    [self.h264Decoder pushData:data timeLine:0];
}

static int i = 0;

#pragma mark - H264解码回调
-(void)h264DecoderReceiveFrameData:(KCLH264Decoder *)decoder{
    KCLVideoFrameData *frameData = [decoder.frameDatas firstObject];
    if (frameData) {
        //[self.playLayer renderImageBuffer:frameData.pixelBuffer];
        
        size_t frameWidth = CVPixelBufferGetWidth(frameData.pixelBuffer);
        size_t frameHeight = CVPixelBufferGetHeight(frameData.pixelBuffer);
        
        int yuvDataLength = frameWidth*frameHeight*3/2;
        char *yuvData = malloc(yuvDataLength);
        pixelBufferNV21ToYUV(frameData.pixelBuffer,yuvData);
        
//        i++;
//        /////////////
//        if (i==40) {
//            NSData *desData = [NSData dataWithBytes:yuvData length:yuvDataLength];
//            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
//            NSString *documentsDirectory = [paths objectAtIndex:0];
//
//            NSString *clipFilePath = [documentsDirectory stringByAppendingPathComponent:@"test.yuv"];
//
//            [[NSFileManager defaultManager] createFileAtPath:clipFilePath contents:nil attributes:nil];
//
//            NSFileHandle *fileHandler = [NSFileHandle fileHandleForWritingAtPath:clipFilePath];
//
//            [fileHandler writeData:desData];
//
//            [fileHandler closeFile];
//        }
//
//        /////////////
        
        
        int corpX = 4;
        int corpY = 4;
        int corpWidth = 144;
        int corpHeight = 144;

        int corpYUVDataLength = corpWidth*corpHeight*3/2;
        char *corpYUVData = malloc(corpYUVDataLength);
        corpNv21YUV(yuvData, frameWidth, frameHeight, corpYUVData, corpX, corpY, corpWidth, corpHeight);

//                i++;
//                /////////////
//                if (i==40) {
//                    NSData *desData = [NSData dataWithBytes:corpYUVData length:corpYUVDataLength];
//                    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
//                    NSString *documentsDirectory = [paths objectAtIndex:0];
//
//                    NSString *clipFilePath = [documentsDirectory stringByAppendingPathComponent:@"test.yuv"];
//
//                    [[NSFileManager defaultManager] createFileAtPath:clipFilePath contents:nil attributes:nil];
//
//                    NSFileHandle *fileHandler = [NSFileHandle fileHandleForWritingAtPath:clipFilePath];
//
//                    [fileHandler writeData:desData];
//
//                    [fileHandler closeFile];
//                }
//
//                /////////////
        
        
        //////////////////
        int w_x_h = corpWidth*corpHeight;

        CVPixelBufferRef pxbuffer;
        CVReturn rc;
        rc = CVPixelBufferCreate(NULL, corpWidth, corpHeight, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NULL, &pxbuffer);
        if (rc != 0) {
            NSLog(@"CVPixelBufferCreate failed %d", rc);
            if (pxbuffer) { CFRelease(pxbuffer); }
        }
        rc = CVPixelBufferLockBaseAddress(pxbuffer, 0);
        if (rc != 0) {
            NSLog(@"CVPixelBufferLockBaseAddress falied %d", rc);
            if (pxbuffer) {
                CFRelease(pxbuffer);
            }
        } else {
            uint8_t *y_copyBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 0);
            uint8_t *uv_copyBaseAddress = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pxbuffer, 1);

            memcpy(y_copyBaseAddress, corpYUVData,              w_x_h);
            memcpy(uv_copyBaseAddress, corpYUVData + w_x_h, w_x_h*0.5);

            rc = CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
            if (rc != 0) {
                NSLog(@"CVPixelBufferUnlockBaseAddress falied %d", rc);
            }
        }

        [self.playLayer renderImageBuffer:pxbuffer];

        CFRelease(pxbuffer);

        //////////////////

        free(corpYUVData);
        free(yuvData);
        
        [decoder.frameDatas removeObjectAtIndex:0];
    }
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


int corpNv21YUV(const char* sourceYUV,const int sourceWidth,const int sourceHeight,char* destYUV,const int destX,const int destY,const int destWidth,const int destHeight){

    const char* pNv21Source0 = sourceYUV;
    int i = 0;

    //关键二之一。
    //取整。估计不同平台要求取整范围有差异。
    //这样计算的结果，有可能差一个像素。宽高最好对应调整。
    int clipLeft = (int)(destX+1)  / 2 * 2;
    int clipTop  = (int)(destY +1)  / 2 * 2;

    //移动到指定位置
    pNv21Source0 += clipTop * sourceWidth + clipLeft;

    //复制Y
    for (i=0; i<destHeight; i++){
        memcpy(destYUV, pNv21Source0, destWidth);
        pNv21Source0 += sourceWidth;
        destYUV    += destWidth;
    }

    //复制U/V
    pNv21Source0  = sourceYUV + sourceWidth*sourceHeight;
    pNv21Source0 += (clipTop * sourceWidth/2 + clipLeft);
    //关键二之二：
    for (i=0; i<destHeight/2; i++){
        memcpy(destYUV, pNv21Source0, destWidth);
        pNv21Source0 += sourceWidth;
        destYUV    += destWidth;
    }
    return 0;
}

@end
