
#import "RootViewController.h"
#import "AboutViewController.h"
#import "VideoPlayerController.h"
#import "EditURLViewController.h"
#import "SplitScreenViewController.h"
#import "SettingViewController.h"
#import "VideoCell.h"
#import "PathUnit.h"
#import "NSUserDefaultsUnit.h"
#import "URLUnit.h"
#import <CommonCrypto/CommonDigest.h>

@interface RootViewController()<UICollectionViewDelegate, UICollectionViewDataSource>
@end

@implementation RootViewController

- (instancetype) initWithStoryboard {
    return [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateViewControllerWithIdentifier:@"RootViewController"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self navigationSetting];
    self.navigationItem.title = @"EasyPlayer RTSP";
    self.view.backgroundColor = [UIColor whiteColor];
    
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc]init];
    //定义每个UICollectionView 横向的间距
    layout.minimumLineSpacing = 10;
    //定义每个UICollectionView 纵向的间距
    layout.minimumInteritemSpacing = 10;
    //定义每个UICollectionView 的边距距
    layout.sectionInset = UIEdgeInsetsMake(10, 10, 10, 10);//上左下右
    
    [self.collectionView setCollectionViewLayout:layout];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.showsHorizontalScrollIndicator = NO;
    self.collectionView.showsVerticalScrollIndicator = NO;
    self.collectionView.backgroundColor = [UIColor whiteColor];
    [self.collectionView registerClass:[VideoCell class] forCellWithReuseIdentifier:@"VideoCell"];
    [self.view addSubview:self.collectionView];
    
    [self setUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.dataArray = [URLUnit urlModels];
    [self.collectionView reloadData];
}

// 导航栏设置
- (void)navigationSetting {
    UIButton *btn = [[UIButton alloc] init];
    [btn addTarget:self action:@selector(info) forControlEvents:UIControlEventTouchUpInside];
    
    int days = [NSUserDefaultsUnit activeDay];
    if (days >= 9999) {
        [btn setImage:[UIImage imageNamed:@"version1"] forState:UIControlStateNormal];
    } else if (days > 0) {
        [btn setImage:[UIImage imageNamed:@"version2"] forState:UIControlStateNormal];
    } else {
        [btn setImage:[UIImage imageNamed:@"version3"] forState:UIControlStateNormal];
    }
    
    if (self.previewMore) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelVc)];
        
        self.bottomView.hidden = YES;
        self.bottomViewHeight.constant = 0;
    } else {
        UIBarButtonItem *infoBtn = [[UIBarButtonItem alloc] initWithCustomView:btn];
        self.navigationItem.rightBarButtonItem = infoBtn;
    }
}

#pragma mark - UI

- (void)setUI {
    [self.settingBtn setImage:[UIImage imageNamed:@"set"] forState:UIControlStateNormal];
    [self.settingBtn setImage:[UIImage imageNamed:@"set_click"] forState:UIControlStateHighlighted];
    [self.settingBtn setTitleColor:UIColorFromRGB(DefaultBtnColor) forState:UIControlStateNormal];
    [self.settingBtn setTitleColor:UIColorFromRGB(SelectBtnColor) forState:UIControlStateHighlighted];
    
    [self.pushBtn setImage:[UIImage imageNamed:@"address"] forState:UIControlStateNormal];
    [self.pushBtn setImage:[UIImage imageNamed:@"address_click"] forState:UIControlStateHighlighted];
    [self.pushBtn setTitleColor:UIColorFromRGB(DefaultBtnColor) forState:UIControlStateNormal];
    [self.pushBtn setTitleColor:UIColorFromRGB(SelectBtnColor) forState:UIControlStateHighlighted];
    
    [self.recordBtn setImage:[UIImage imageNamed:@"split"] forState:UIControlStateNormal];
    [self.recordBtn setImage:[UIImage imageNamed:@"split_click"] forState:UIControlStateHighlighted];
    [self.recordBtn setTitleColor:UIColorFromRGB(DefaultBtnColor) forState:UIControlStateNormal];
    [self.recordBtn setTitleColor:UIColorFromRGB(SelectBtnColor) forState:UIControlStateHighlighted];
    
    for (UIButton *btn in @[ self.pushBtn, self.recordBtn, self.settingBtn ]) {
        [self layoutImageAboveTitle:btn spacing:4];
    }

    // 按钮栏顶部分割线，让按钮栏和上方内容区分开
    UIView *topLine = [[UIView alloc] init];
    topLine.backgroundColor = UIColorFromRGB(0xdddddd);
    topLine.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bottomView addSubview:topLine];
    [NSLayoutConstraint activateConstraints:@[
        [topLine.topAnchor constraintEqualToAnchor:self.bottomView.topAnchor],
        [topLine.leadingAnchor constraintEqualToAnchor:self.bottomView.leadingAnchor],
        [topLine.trailingAnchor constraintEqualToAnchor:self.bottomView.trailingAnchor],
        [topLine.heightAnchor constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale],
    ]];

    // 底部按钮栏贴着安全区底部（按钮不被 Home 指示条挡住），全面屏机型下方会露出一条白边：
    // 把按钮栏的背景色延伸到屏幕最底部。加在 bottomView 里，分屏选源时 bottomView 隐藏，它也跟着隐藏
    UIView *bottomFill = [[UIView alloc] init];
    bottomFill.backgroundColor = self.bottomView.backgroundColor;
    bottomFill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bottomView addSubview:bottomFill];
    [NSLayoutConstraint activateConstraints:@[
        [bottomFill.topAnchor constraintEqualToAnchor:self.bottomView.bottomAnchor],
        [bottomFill.leadingAnchor constraintEqualToAnchor:self.bottomView.leadingAnchor],
        [bottomFill.trailingAnchor constraintEqualToAnchor:self.bottomView.trailingAnchor],
        [bottomFill.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

// 按钮图标在上、文字在下，整体在按钮内水平、垂直居中（按图标和文字的实际尺寸计算，不写死偏移量）
- (void)layoutImageAboveTitle:(UIButton *)btn spacing:(CGFloat)spacing {
    CGSize imageSize = btn.currentImage.size;
    CGSize titleSize = [btn.currentTitle sizeWithAttributes:@{ NSFontAttributeName: btn.titleLabel.font }];
    CGFloat totalHeight = imageSize.height + spacing + titleSize.height;

    btn.imageEdgeInsets = UIEdgeInsetsMake(-(totalHeight - imageSize.height), 0, 0, -titleSize.width);
    btn.titleEdgeInsets = UIEdgeInsetsMake(0, -imageSize.width, -(totalHeight - titleSize.height), 0);
}

#pragma mark - click event

/**
 分屏时选择视频源，取消事件
 */
- (void)cancelVc {
    [self dismissViewControllerAnimated:YES completion:nil];
}

/**
 关于我们
 */
- (void) info {
    AboutViewController *controller = [[AboutViewController alloc] initWithStoryboard];
    [self.navigationController pushViewController:controller animated:YES];
}

/**
 添加流地址
 */
- (IBAction)addUrlAddress:(id)sender {
    [self editAlert:-1];
}

/**
 分屏
 */
- (IBAction)splitScreen:(id)sender {
    SplitScreenViewController *controller = [[SplitScreenViewController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

/**
 设置
 */
- (IBAction)setting:(id)sender {
    SettingViewController *controller = [[SettingViewController alloc] initWithStoryboard];
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - UICollectionViewDataSource

-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _dataArray.count;
}

-(CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    int w = EasyScreenWidth - 20;
    int h = w * 9 / 16;
    return CGSizeMake(w, h + VIDEO_TITLE_HEIGHT);// 30 is the bottom title height
}

-(UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    VideoCell * cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"VideoCell" forIndexPath:indexPath];
    URLModel *model = _dataArray[indexPath.row];
    
    NSString *path = [PathUnit snapshotWithURL:model.url];
    if([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        cell.imageView.image = [UIImage imageWithContentsOfFile:path];
    } else {
        cell.imageView.image = [UIImage imageNamed:@"ImagePlaceholder"];
    }
    
    [cell.titleLabel setText:[NSString stringWithFormat:@"%@", model.url]];
    
    UILongPressGestureRecognizer* longgs=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(longpress:)];
    [cell addGestureRecognizer:longgs];
    longgs.minimumPressDuration=0.3;
    longgs.view.tag=indexPath.row;
    
    return cell;
}

-(void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.previewMore != nil) {
        [self cancelVc];
        self.previewMore(_dataArray[indexPath.row]);
    } else {
        VideoPlayerController* pvc = [[VideoPlayerController alloc] init];
        pvc.model = _dataArray[indexPath.row];
        [self.navigationController pushViewController:pvc animated:YES];
    }
}

#pragma mark - GestureRecognizer

-(void)longpress:(UILongPressGestureRecognizer *)ges {
    CGPoint pointTouch = [ges locationInView:self.collectionView];
    if(ges.state == UIGestureRecognizerStateBegan) {
        NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:pointTouch];
        [self showActionSheet:(int)indexPath.row];
    }
}

#pragma mark - 对话框

- (void)showActionSheet:(int)index {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"请选择" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:cancelAction];
    
    UIAlertAction *OKAction = [UIAlertAction actionWithTitle:@"修改" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self editAlert:index];
    }];
    [alertController addAction:OKAction];
    
    UIAlertAction *moreAction = [UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self delelteAlert:index];
    }];
    [alertController addAction:moreAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)delelteAlert:(int)index {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"确认要删除该地址吗？" message:@"同时会删除录像和截图" preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleDefault handler:nil];
    [alertController addAction:cancelAction];
    
    // 添加确定到UIAlertController中
    UIAlertAction *OKAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        URLModel *model = self.dataArray[index];
        [PathUnit deleteBaseRecordPathWithURL:model.url];
        [PathUnit deleteBaseShotPathWithURL:model.url];
        
        [URLUnit removeURLModel:model];
        
        [self.dataArray removeObjectAtIndex:index];
        [self.collectionView reloadData];
    }];
    [alertController addAction:OKAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)editAlert:(int)index {
    EditURLViewController *vc = [[EditURLViewController alloc] initWithStoryboard];
    [vc.subject subscribeNext:^(id x) {
        self.dataArray = [URLUnit urlModels];
        [self.collectionView reloadData];
    }];
    
    if (index >= 0) {
        vc.urlModel = self.dataArray[index];
    }
    
    vc.modalPresentationStyle = UIModalPresentationOverCurrentContext;//关键语句，必须有 ios8 later
    [self presentViewController:vc animated:YES completion:nil];
}

@end
