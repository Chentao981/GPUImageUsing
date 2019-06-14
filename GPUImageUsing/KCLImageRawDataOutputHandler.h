//
//  KCLImageRawDataOutputHandler.h
//  GPUImageUsing
//
//  Created by Chentao on 2019/6/3.
//  Copyright © 2019 Chentao. All rights reserved.
//

#import "GPUImageRawDataOutput.h"

NS_ASSUME_NONNULL_BEGIN

@class KCLImageRawDataOutputHandler;
@protocol KCLImageRawDataOutputHandlerDelegate <NSObject>

-(void)dataOutputHandler:(KCLImageRawDataOutputHandler *)handler h264Data:(NSData *)data;

@end

@interface KCLImageRawDataOutputHandler : GPUImageRawDataOutput

@property(nonatomic,weak)id <KCLImageRawDataOutputHandlerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
