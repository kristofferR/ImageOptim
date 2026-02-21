//
//  FormatConverterFactory.h
//  ImageOptim
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "../ImageProcessor.h"

NS_ASSUME_NONNULL_BEGIN

@interface FormatConverterFactory : NSObject

+ (nullable NSData *)convertImageData:(NSData *)imageData 
                             toFormat:(ImageOutputFormat)format 
                              quality:(CGFloat)quality;

+ (nullable NSData *)convertBitmapImageRep:(NSBitmapImageRep *)imageRep 
                                  toFormat:(ImageOutputFormat)format 
                                   quality:(CGFloat)quality;

+ (BOOL)isFormatSupported:(ImageOutputFormat)format;
+ (NSArray<NSNumber *> *)supportedFormats;

@end

NS_ASSUME_NONNULL_END
