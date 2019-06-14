//
//  KCLSafeMutableArray.m
//  KCLiveSDK
//
//  Created by Chentao on 2017/12/14.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import "KCLSafeMutableArray.h"

@interface KCLSafeMutableArray () {
    NSMutableArray *_array;
    NSRecursiveLock *_safeLock;
}

@end

@implementation KCLSafeMutableArray

- (instancetype)init {
    self = [super init];
    if (self) {
        _safeLock = [[NSRecursiveLock alloc] init];
        _array = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSUInteger)count {
    [_safeLock lock];
    NSUInteger result = _array.count;
    [_safeLock unlock];
    return result;
}

- (id)objectAtIndex:(NSUInteger)index {
    [_safeLock lock];
    id result = [_array objectAtIndex:index];
    [_safeLock unlock];
    return result;
}

- (NSUInteger)indexOfObject:(id)anObject {
    if (!anObject) {
        return NSNotFound;
    }
    [_safeLock lock];
    NSUInteger result = [_array indexOfObject:anObject];
    [_safeLock unlock];
    return result;
}

- (id)firstObject {
    [_safeLock lock];
    id result = [_array firstObject];
    [_safeLock unlock];
    return result;
}

- (id)lastObject {
    [_safeLock lock];
    id result = [_array lastObject];
    [_safeLock unlock];
    return result;
}

- (void)addObject:(id)anObject {
    [_safeLock lock];
    [_array addObject:anObject];
    [_safeLock unlock];
}

- (void)insertObject:(id)anObject atIndex:(NSUInteger)index {
    [_safeLock lock];
    [_array insertObject:anObject atIndex:index];
    [_safeLock unlock];
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
    [_safeLock lock];
    [_array replaceObjectAtIndex:index withObject:anObject];
    [_safeLock unlock];
}

- (void)removeLastObject {
    [_safeLock lock];
    [_array removeLastObject];
    [_safeLock unlock];
}

- (void)removeObjectAtIndex:(NSUInteger)index {
    [_safeLock lock];
    [_array removeObjectAtIndex:index];
    [_safeLock unlock];
}

- (void)removeObject:(id)anObject {
    [_safeLock lock];
    [_array removeObject:anObject];
    [_safeLock unlock];
}

- (void)removeObjectsInRange:(NSRange)range {
    [_safeLock lock];
    [_array removeObjectsInRange:range];
    [_safeLock unlock];
}

- (void)removeAllObjects {
    [_safeLock lock];
    [_array removeAllObjects];
    [_safeLock unlock];
}

#pragma mark NSLocking

- (void)lock {
    [_safeLock lock];
}

- (void)unlock {
    [_safeLock unlock];
}

@end
