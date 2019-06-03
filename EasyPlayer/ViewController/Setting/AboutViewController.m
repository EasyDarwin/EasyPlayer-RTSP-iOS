//
//  AboutViewController.m
//  EasyPlayer
//
//  Created by liyy on 2017/12/30.
//  Copyright © 2017年 cs. All rights reserved.
//

#import "AboutViewController.h"
#import "NSUserDefaultsUnit.h"
#import "WebViewController.h"

@interface AboutViewController ()

@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UILabel *descLabel;

@end

@implementation AboutViewController

- (instancetype) initWithStoryboard {
    return [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateViewControllerWithIdentifier:@"AboutViewController"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.title = @"版本信息";
    
    NSString *name = @"EasyPlayer RTSP iOS 播放器";
    NSString *content;
    UIColor *color;
    
    int activeDays = [NSUserDefaultsUnit activeDay];
    if (activeDays >= 9999) {
        content = @"激活码永久有效";
        color = UIColorFromRGB(0x2cff1c);
    } else if (activeDays > 0) {
        content = [NSString stringWithFormat:@"激活码还剩%ld天可用", (long)activeDays];
        color = UIColorFromRGB(0xeee604);
    } else {
        content = [NSString stringWithFormat:@"激活码已过期%ld天", (long)activeDays];
        color = UIColorFromRGB(0xf64a4a);
    }
    
    NSString *str = [NSString stringWithFormat:@"%@(%@)", name, content];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:str];
    
    NSRange range = [str rangeOfString:content];
    NSDictionary *dict = @{ NSForegroundColorAttributeName:color };
    
    [attr setAttributes:dict range:range];
    
    self.nameLabel.attributedText = attr;
    self.nameLabel.numberOfLines = 0;
    
    NSString *html = @"EasyPlayer-RTSP iOS版 播放器是由 TSINGSEE青犀开放平台 开发和维护的一个完善的RTSP流媒体播放器项目，视频编码支持H.264，H.265，MPEG4，MJPEG，音频支持G711A，G711U，G726，AAC，支持RTSP over TCP/UDP协议，支持硬解码，是一套极佳的安防流媒体平台播放组件！EasyPlayer-RTSP iOS版本经过了多个项目的检验和迭代，已经非常稳定、完整，功能包括：直播、录像、抓图，支持指令集包括armv7a、armv8a、x86，应该说是目前市面上功能性、稳定性和完整性最强的一款RTSP播放器！";
    NSData *data = [html dataUsingEncoding:NSUnicodeStringEncoding];
    
    NSDictionary *options = @{ NSDocumentTypeDocumentAttribute : NSHTMLTextDocumentType,
                               NSCharacterEncodingDocumentAttribute : @(NSUTF8StringEncoding) };
    
    // 设置富文本
    NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithData:data options:options documentAttributes:nil error:nil];
    
    // 设置段落格式
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 7;
    para.paragraphSpacing = 10;
    [attrStr addAttribute:NSParagraphStyleAttributeName value:para range:NSMakeRange(0, attrStr.length)];
    
    [attrStr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16] range:NSMakeRange(0, attrStr.length)];
    [attrStr addAttribute:NSForegroundColorAttributeName value:UIColorFromRGB(0x4c4c4c) range:NSMakeRange(0, attrStr.length)];
    
    self.descLabel.attributedText = attrStr;
}

- (IBAction)easyDarwin:(id)sender {
    UIButton *btn = (UIButton *)sender;
    
    WebViewController *controller = [[WebViewController alloc] init];
    controller.title = @"EasyPlayer播放器系列";
    controller.url = btn.titleLabel.text;
    [self.navigationController pushViewController:controller animated:YES];
}

@end
