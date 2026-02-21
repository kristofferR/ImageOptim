//
//  ImageProcessor.h
//  ImageOptim
//
//  Created by Enhanced ImageOptim on 2025.
//
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, ImageOutputFormat) {
    ImageOutputFormatOriginal = 0,
    ImageOutputFormatJPEG,
    ImageOutputFormatPNG,
    ImageOutputFormatAVIF,
    ImageOutputFormatWebP,
    ImageOutputFormatJXL
};

typedef NS_ENUM(NSInteger, ImageResizeMode) {
    ImageResizeModeNone = 0,
    ImageResizeModeWidth,
    ImageResizeModeHeight,
    ImageResizeModeFit
};

NS_ASSUME_NONNULL_BEGIN

@interface ImageProcessor : NSObject

+ (nullable NSData *)resizeImageData:(NSData *)imageData
                            toWidth:(NSInteger)targetWidth
                           toHeight:(NSInteger)targetHeight
                         resizeMode:(ImageResizeMode)resizeMode;

+ (nullable NSData *)convertImageData:(NSData *)imageData
                             toFormat:(ImageOutputFormat)format
                              quality:(CGFloat)quality;

+ (NSString *)fileExtensionForFormat:(ImageOutputFormat)format;
+ (NSString *)mimeTypeForFormat:(ImageOutputFormat)format;

@end

NS_ASSUME_NONNULL_END