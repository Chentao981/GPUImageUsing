//
//  KCLAssetsUtil.h
//  KCLiveSDK
//
//  Created by Chentao on 2017/12/11.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface KCLAssetsUtil : NSObject

extern NSString *const KCLAssetsBundlePath;

+ (UIImage *)imageWithName:(NSString *)imageName;

+ (NSURL *)urlForResource:(NSString *)name withExtension:(NSString *)ext;

@end
