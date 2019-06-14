
//
//  KCLSafeMutableArray.h
//  KCLiveSDK
//
//  Created by Chentao on 2017/12/14.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface KCLSafeMutableArray : NSObject <NSLocking>

- (NSUInteger)count;

- (id)objectAtIndex:(NSUInteger)index;
- (NSUInteger)indexOfObject:(id)anObject;

- (id)firstObject;
- (id)lastObject;

- (void)addObject:(id)anObject;
- (void)insertObject:(id)anObject atIndex:(NSUInteger)index;

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject;

- (void)removeLastObject;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeObject:(id)anObject;
- (void)removeObjectsInRange:(NSRange)range;
- (void)removeAllObjects;



@end
