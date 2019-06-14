//
//  KCLAssetsUtil.m
//  KCLiveSDK
//
//  Created by Chentao on 2017/12/11.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import "KCLAssetsUtil.h"

NSString *const KCLAssetsBundlePath = @"KCLiveSDK.bundle";

@implementation KCLAssetsUtil

+ (UIImage *)imageWithName:(NSString *)imageName {
    NSString *imagePath = [KCLAssetsBundlePath stringByAppendingPathComponent:imageName];
    UIImage *image = [UIImage imageNamed:imagePath];
    return image;
}

+ (NSURL *)urlForResource:(NSString *)name withExtension:(NSString *)ext {
    NSURL *resourceURL = [[NSBundle mainBundle] URLForResource:name withExtension:ext];
    return resourceURL;
}

@end
