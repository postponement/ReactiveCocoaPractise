//
//  AppDelegate.m
//  ReactiveCocoaPractise
//
//  Created by liuyanchi on 2017/5/26.
//  Copyright © 2017年 yidaoyongche. All rights reserved.


#import "ViewController.h"
#import <ReactiveCocoa.h>
#import <Masonry.h>

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIView *grid;
@property (weak, nonatomic) IBOutlet UIButton *autoRunBtn;
@property (weak, nonatomic) IBOutlet UIButton *oneStepBtn;

@end

static int GridXBlocks = 13;
static int GridYBlocks = 7;

typedef NS_ENUM(NSUInteger, SpiritState) {
    SpiritStateAppear,
    SpiritStateRunning,
    SpiritStateDisappear,
};

typedef NS_ENUM(NSUInteger, ControlState) {
    ControlStateStop,
    ControlStateAuto,
    ControlStateOneStep,
};

NSNumber *(^addFunction)(NSNumber *a, NSNumber *b) = ^NSNumber *(NSNumber *a, NSNumber *b) {
    return @(a.integerValue + b.integerValue);
};

typedef BOOL(^filterType)(id );

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIImage *img1 = [UIImage imageNamed:@"pet1"];
    UIImage *img2 = [UIImage imageNamed:@"pet2"];
    UIImage *img3 = [UIImage imageNamed:@"pet3"];
    
    NSArray *steps = @[RACTuplePack(@1, @0), RACTuplePack(@1, @0),
                       RACTuplePack(@1, @0), RACTuplePack(@0, @1),
                       RACTuplePack(@0, @1), RACTuplePack(@0, @1),
                       RACTuplePack(@1, @0), RACTuplePack(@1, @0),
                       RACTuplePack(@1, @0), RACTuplePack(@1, @0),
                       RACTuplePack(@0, @-1), RACTuplePack(@0, @-1),
                       RACTuplePack(@1, @0), RACTuplePack(@1, @0),
                       RACTuplePack(@1, @0)
                       ];
    
    RACTuple *startBlock = RACTuplePack(@1, @2);
    
    NSInteger spiritCount = steps.count + 1; // 步数 + 1个起始位置
    
    void (^updateXYConstraints)(UIView *view, RACTuple *location) = ^(UIView *view, RACTuple *location) {
        CGFloat width = self.grid.frame.size.width / GridXBlocks;
        CGFloat height = self.grid.frame.size.height / GridYBlocks;
        RACTupleUnpack(NSNumber *locationX, NSNumber *locationY) = location;
        CGFloat x = [locationX floatValue] * width;
        CGFloat y = [locationY floatValue] * height;
        view.frame = CGRectMake(x, y, width, height);
    };
    
    for (int i = 0; i < spiritCount; ++i) {
        UIImageView *spiritView = [[UIImageView alloc] init];
        
        spiritView.tag = i;
        spiritView.animationImages = @[img1, img2, img3];
        spiritView.animationDuration = 1.0;
        spiritView.alpha = 0.0f;
        [self.grid addSubview:spiritView];
        
        updateXYConstraints(spiritView, startBlock);
    }
    
    RACSequence *stepsSequence = steps.rac_sequence;
    
    stepsSequence = [stepsSequence scanWithStart:startBlock reduce:^id(RACTuple *running, RACTuple *next) {
        RACTupleUnpack(NSNumber *x1, NSNumber *y1) = running;
        RACTupleUnpack(NSNumber *x2, NSNumber *y2) = next;
        return RACTuplePack(addFunction(x1, x2), addFunction(y1, y2));
    }];
    
    RACSignal *stepsSignal = stepsSequence.signal;
    stepsSignal = [[stepsSignal map:^id(id value) {
        return [[RACSignal return:value] delay:1];
    }] concat];
    
    RACSignal *(^newSpiritSignal)(NSNumber *idx) = ^RACSignal *(NSNumber *idx) {
        RACSignal *head = [RACSignal return:RACTuplePack(idx,
                                                         @(SpiritStateAppear),
                                                         startBlock)];
        
        RACSignal *running = [stepsSignal map:^id(RACTuple *xy) {
            return RACTuplePack(idx, @(SpiritStateRunning), xy);
        }];
        
        RACSignal *end = [RACSignal return:RACTuplePack(idx,
                                                        @(SpiritStateDisappear),
                                                        nil)];
        
        return [[head concat:running] concat:end];
    };
    
    RACSignal *timerSignal = [[RACSignal interval:1.5 onScheduler:[RACScheduler mainThreadScheduler]] startWith:nil];
    
    RACSignal *autoBtnClickSignal = [[self.autoRunBtn rac_signalForControlEvents:UIControlEventTouchUpInside] mapReplace:@(ControlStateAuto)];
    RACSignal *oneStepBtnClickSignal = [[self.oneStepBtn rac_signalForControlEvents:UIControlEventTouchUpInside] mapReplace:@(ControlStateOneStep)];
    
    RACSignal *clickSignal = [RACSignal merge:@[autoBtnClickSignal, oneStepBtnClickSignal]];
    
    clickSignal = [clickSignal scanWithStart:@(ControlStateStop) reduce:^id(NSNumber *running, NSNumber *next) {
        if ([running isEqual:next] && [running isEqual:@(ControlStateAuto)]) {
            // 如果上一次和这一次都是auto状态，就转换为stop状态
            return @(ControlStateStop);
        }
        return next;
    }];
    RACSignal *stepSignal = [RACSignal switch:clickSignal
                             cases:@{@(ControlStateAuto): timerSignal,
                                     @(ControlStateOneStep): [RACSignal return:nil]
                                     }
                             default:[RACSignal empty]];
    
    
    RACSignal *runSignal = [stepSignal scanWithStart:@-1 reduce:^id(NSNumber *running, id _) {
        NSInteger idx = running.integerValue;
        ++idx;
        if (idx == spiritCount) { idx = 0 ;}
        return @(idx);
    }];
    
    RACSignal *spiritRunSignal = [runSignal flattenMap:newSpiritSignal];
    
    // **拆分:1.单个精灵的出发信号 2.单个精灵的运动信号 3.单个精灵的消失信号

    // 总的信号主    replay -- 信号(冷信号)转换为热信号
    RACSignal *mainSignal = [[spiritRunSignal deliverOnMainThread] replay];
    // 高阶函数
    filterType(^filterWithState)(NSNumber *state) = ^filterType(NSNumber *state){
        return ^BOOL(RACTuple *info){
            return [info.second isEqual:state];
        };
    };
    // tuple 变换
    RACTuple *(^mapTuple)(RACTuple *tuple) = ^RACTuple *(RACTuple *tuple){
        RACTupleUnpack(NSNumber *idx,NSNumber *state,RACTuple *xy) = tuple;
        return RACTuplePack(idx,xy);
    };
    
    // 精灵与坐标
    typedef void (^SpiritAction)(UIImageView *spirit,RACTuple *xy);
    typedef void (^Aciton)(RACTuple *);
    
    // 标准高阶函数(返回值和入参都是函数)
    Aciton (^makeAction)(SpiritAction spiritAction) = ^Aciton(SpiritAction spiritAction){
        return ^(RACTuple *tuple){
            RACTupleUnpack(NSNumber *idx,RACTuple *xy) = tuple;
            UIImageView *spirit = [self.grid viewWithTag:idx.integerValue];
            spiritAction(spirit,xy);
        };
    };

    [[[mainSignal filter:filterWithState(@(SpiritStateAppear))] map:mapTuple] subscribeNext:makeAction(^(UIImageView *spirit,RACTuple *xy){
        updateXYConstraints(spirit, xy);
        [UIView animateWithDuration:1 animations:^{
            spirit.alpha = 1.0f;
        }];
        [spirit startAnimating];
    })] ;
    
    [[[mainSignal filter:filterWithState(@(SpiritStateRunning))] map:mapTuple] subscribeNext:makeAction(^(UIImageView *spirit,RACTuple *xy){
        [UIView animateWithDuration:1 animations:^{
            updateXYConstraints(spirit, xy);
        }];
    })];
    [[[mainSignal filter:filterWithState(@(SpiritStateDisappear))] map:mapTuple] subscribeNext:makeAction(^(UIImageView *spirit,RACTuple *xy){
        [UIView animateWithDuration:1 animations:^{
            spirit.alpha = 0.0f;
        } completion:^(BOOL finished) {
            [spirit stopAnimating];
        }];
    })];
}
 
@end
