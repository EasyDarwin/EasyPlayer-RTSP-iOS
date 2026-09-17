//
//  URLUnit.m
//  EasyPlayerRTSP
//
//  Created by leo on 2019/4/27.
//  Copyright © 2019年 cs. All rights reserved.
//

#import "URLUnit.h"
#import <YYKit/YYKit.h>

static NSString *URLUnitName = @"URLUnitName";
static NSString *URLUnitKey = @"URLUnitKey";

@implementation URLUnit

+ (YYCache *)sharedCache {
    static YYCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [YYCache cacheWithName:URLUnitName];
    });
    return cache;
}

// 所有的读改写都在这把锁里完成，避免两个线程同时 读-改-写 丢数据
+ (NSRecursiveLock *)lock {
    static NSRecursiveLock *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [[NSRecursiveLock alloc] init];
    });
    return lock;
}

#pragma mark - 播放url的存储

// 缓存里存的对象会被 YYCache 在后台线程归档（NSKeyedArchiver），
// 所以对外只给深拷贝，谁都不能再去改缓存里那份；否则归档线程遍历数组／读属性时
// 会撞上正在被修改（甚至已释放）的对象，崩在 valueForKey: / CFBasicHashFindBucket
+ (NSMutableArray *) urlModels {
    NSRecursiveLock *lock = [self lock];
    
    [lock lock];
    NSArray *cached = (NSArray *)[[self sharedCache] objectForKey:URLUnitKey];
    NSMutableArray *result = cached.count > 0 ? [[NSMutableArray alloc] initWithArray:cached copyItems:YES] : [NSMutableArray array];
    [lock unlock];
    
    return result;
}

// 存进去的一定是一份不可变的深拷贝快照，后台归档期间不会再有人改它
+ (void) saveURLModels:(NSArray<URLModel *> *)models {
    NSArray *snapshot = [[NSArray alloc] initWithArray:models copyItems:YES];
    
    NSRecursiveLock *lock = [self lock];
    [lock lock];
    [[self sharedCache] setObject:snapshot forKey:URLUnitKey];
    [lock unlock];
}

// 添加rl
+ (void) addURLModel:(URLModel *)model {
    if (model.url.length == 0) {
        return;
    }
    
    NSRecursiveLock *lock = [self lock];
    [lock lock];
    
    NSMutableArray *arr = [self urlModels];
    
    BOOL isRepeat = NO;
    for (NSUInteger i = 0; i < arr.count; i++) {
        URLModel *m = arr[i];
        
        if ([m.url isEqualToString:model.url]) {
            isRepeat = YES;
            [arr replaceObjectAtIndex:i withObject:model];
            break;
        }
    }
    
    if (!isRepeat) {
        [arr insertObject:model atIndex:0];
    }
    
    [self saveURLModels:arr];
    [lock unlock];
}

+ (void) updateURLModel:(URLModel *)model oldModel:(URLModel *)m {
    if (model.url.length == 0) {
        return;
    }
    
    NSRecursiveLock *lock = [self lock];
    [lock lock];
    
    NSMutableArray *arr = [self urlModels];
    
    BOOL found = NO;
    for (NSUInteger i = 0; i < arr.count; i++) {
        URLModel *temp = arr[i];
        
        if ([temp.url isEqualToString:m.url]) {
            found = YES;
            [arr replaceObjectAtIndex:i withObject:model];
            break;
        }
    }
    
    if (!found) {
        [arr insertObject:model atIndex:0];
    }
    
    [self saveURLModels:arr];
    [lock unlock];
}

// 删除url
+ (void) removeURLModel:(URLModel *)model {
    NSRecursiveLock *lock = [self lock];
    [lock lock];
    
    NSMutableArray *arr = [self urlModels];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:arr.count];
    for (URLModel *temp in arr) {
        // 取出来的是副本，不能再用指针／isEqual 比较对象本身，按 url 匹配
        if (![temp.url isEqualToString:model.url]) {
            [result addObject:temp];
        }
    }
    
    [self saveURLModels:result];
    [lock unlock];
}

@end
