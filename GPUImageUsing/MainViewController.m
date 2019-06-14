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
//#import "GPUImageBeautifyFilter.h"
#import "GPUImageBeautyFilter.h"
#import "KCLImageRawDataOutputHandler.h"
#import "KCLH264Decoder.h"
#import "KCLOpenGLImageView.h"



@interface MainViewController ()<KCLH264DecoderDelegate,KCLImageRawDataOutputHandlerDelegate>

@property(nonatomic,strong)GPUImageVideoCamera *videoCamera;
@property(nonatomic,strong)GPUImageView *videoView;

@property(nonatomic,strong)GPUImageFilterGroup *filterGroup;



@property(nonatomic,strong)GPUImageBeautyFilter *beautifyFilter;

//@property(nonatomic,strong)GPUImageBeautifyFilter *beautifyFilter;
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
    
//    self.beautifyFilter = [[GPUImageBeautifyFilter alloc]initWithDegree:0.7];
    self.beautifyFilter = [[GPUImageBeautyFilter alloc]init];
//    self.beautifyFilter.toneLevel = 0.9;
//    self.beautifyFilter.beautyLevel = 0.4;
//    self.beautifyFilter.brightLevel = 0.25;
    
    
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
    
    self.videoView = [[GPUImageView alloc]initWithFrame:CGRectMake(videoViewX, videoViewY, videoViewW, videoViewH)];
    self.videoView.backgroundColor = [UIColor blackColor];
    [self.videoView setInputRotation:kGPUImageFlipHorizonal atIndex:0];
    self.videoView.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
    [self.view addSubview:self.videoView];

//    [self.filterGroup addTarget:self.videoView];
    
    [self.transformFilter addTarget:self.videoView];
    
    //////////////////////////
    
    self.imageRawDataOutputHandler = [[KCLImageRawDataOutputHandler alloc]initWithImageSize:CGSizeMake(videoViewW, videoViewH) resultsInBGRAFormat:YES];
    self.imageRawDataOutputHandler.delegate = self;
    [self.filterGroup addTarget:self.imageRawDataOutputHandler];
    
    ///////////////////////////
    self.playLayer = [[KCLOpenGLImageView alloc] initWithFrame:CGRectMake(CGRectGetMaxX(self.videoView.frame)+10 , videoViewY, videoViewW, videoViewH)];
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

#pragma mark - H264解码回调
-(void)h264DecoderReceiveFrameData:(KCLH264Decoder *)decoder{
    KCLVideoFrameData *frameData = [decoder.frameDatas firstObject];
    if (frameData) {
        //[self.playLayer inputPixelBuffer:frameData.pixelBuffer];
        [self.playLayer renderImageBuffer:frameData.pixelBuffer];
        [decoder.frameDatas removeObjectAtIndex:0];
    }
}

@end
