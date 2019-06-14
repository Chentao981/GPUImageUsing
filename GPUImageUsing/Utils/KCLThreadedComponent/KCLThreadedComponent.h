//
//  KCLThreadedComponent.h
//  OpusAudioPlayer
//
//  Created by Chentao on 2017/4/6.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface KCLThreadedComponent : NSObject

@property(nonatomic,readonly)NSThread *thread;

@property(nonatomic,copy)NSString *threadName;


- (void)start;

- (void)stop;


@end
