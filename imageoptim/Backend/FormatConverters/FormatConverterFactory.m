//
//  FormatConverterFactory.m
//  ImageOptim
//

#import "FormatConverterFactory.h"
#import "AVIFConverter.h"
#import "WebPConverter.h"
#import "JXLConverter.h"
#import "../../log.h"

@implementation FormatConverterFactory

+ (nullable NSData *)convertImageData:(NSData *)imageData 
                             toFormat:(ImageOutputFormat)format 
                              quality:(CGFloat)quality {
    if (!imageData) {
        return nil;
    }
    
    switch (format) {
        case ImageOutputFormatOriginal:
            return imageData;
            
        case ImageOutputFormatJPEG:
        case ImageOutputFormatPNG: {
            // Use native NSBitmapImageRep for JPEG and PNG
            NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
            if (!imageRep) {
                IOWarn("Failed to create bitmap representation for native format conversion");
                return nil;
            }
            return [self convertBitmapImageRep:imageRep toFormat:format quality:quality];
        }
            
        case ImageOutputFormatAVIF:
            return [AVIFConverter convertImageData:imageData quality:quality];
            
        case ImageOutputFormatWebP:
            return [WebPConverter convertImageData:imageData quality:quality];

        case ImageOutputFormatJXL:
            return [JXLConverter convertImageData:imageData quality:quality];

        default:
            IOWarn("Unsupported output format: %ld", (long)format);
            return nil;
    }
}

+ (nullable NSData *)convertBitmapImageRep:(NSBitmapImageRep *)imageRep 
                                  toFormat:(ImageOutputFormat)format 
                                   quality:(CGFloat)quality {
    if (!imageRep) {
        return nil;
    }
    
    switch (format) {
        case ImageOutputFormatOriginal:
            return [imageRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            
        case ImageOutputFormatJPEG: {
            NSDictionary *properties = @{NSImageCompressionFactor: @(quality)};
            return [imageRep representationUsingType:NSBitmapImageFileTypeJPEG properties:properties];
        }
            
        case ImageOutputFormatPNG:
            return [imageRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            
        case ImageOutputFormatAVIF:
            return [AVIFConverter convertBitmapImageRep:imageRep quality:quality];
            
        case ImageOutputFormatWebP:
            return [WebPConverter convertBitmapImageRep:imageRep quality:quality];

        case ImageOutputFormatJXL:
            return [JXLConverter convertBitmapImageRep:imageRep quality:quality];

        default:
            IOWarn("Unsupported output format: %ld", (long)format);
            return nil;
    }
}

+ (BOOL)isFormatSupported:(ImageOutputFormat)format {
    switch (format) {
        case ImageOutputFormatOriginal:
        case ImageOutputFormatJPEG:
        case ImageOutputFormatPNG:
            return YES;
            
        case ImageOutputFormatAVIF:
            return [AVIFConverter isAVIFSupported];
            
        case ImageOutputFormatWebP:
            return [WebPConverter isWebPSupported];

        case ImageOutputFormatJXL:
            return [JXLConverter isJXLSupported];

        default:
            return NO;
    }
}

+ (NSArray<NSNumber *> *)supportedFormats {
    NSMutableArray *formats = [NSMutableArray array];

    for (NSInteger format = ImageOutputFormatOriginal; format <= ImageOutputFormatJXL; format++) {
        if ([self isFormatSupported:(ImageOutputFormat)format]) {
            [formats addObject:@(format)];
        }
    }
    
    return [formats copy];
}

@end
