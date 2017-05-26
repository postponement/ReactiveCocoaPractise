//
//  AppDelegate.m
//  ReactiveCocoaPractise
//
//  Created by liuyanchi on 2017/5/26.
//  Copyright © 2017年 yidaoyongche. All rights reserved.
//

#import "RACPlayground.h"
#import <ReactiveCocoa.h>

void rac_playground()
{
    RACSignal *signal = [RACSignal return:@1];
    [signal subscribeNext:^(id x) {
        NSLog(@"%@", x);
    }];
}
