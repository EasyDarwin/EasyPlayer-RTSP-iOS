#import <UIKit/UIKit.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

@interface PlayViewController : UIViewController
{
    BOOL xps_found;
    uint8_t *spsData;
    uint8_t *ppsData;
    
    unsigned char *pInnerData;
    unsigned int innerLen;
}
@property(nonatomic,strong)NSString *urlStr;
@property(nonatomic,strong)NSString *imagePath;

@property(nonatomic,strong)NSMutableArray *mediaArray;
@property(nonatomic,strong)NSCondition *mediaCond;
@property(nonatomic, retain)AVSampleBufferDisplayLayer *videoLayer;

//+ (NSString *)docDir;
//
//+ (NSString *)docPath:(NSString*)filename;
//
//+ (NSString *)touchDir:(NSString*)dir;
//
//+ (BOOL)writeImage:(UIImage*)image toFileAtPath:(NSString*)aPath;
//
//+ (NSString *)md5:(NSString *)str;

@end

