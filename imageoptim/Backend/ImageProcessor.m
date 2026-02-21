//
//  ImageProcessor.m
//  ImageOptim
//
//  Created by Enhanced ImageOptim on 2025.
//
//

#import "ImageProcessor.h"
#import "FormatConverters/FormatConverterFactory.h"
#import "../log.h"

@implementation ImageProcessor

+ (nullable NSData *)resizeImageData:(NSData *)imageData
                            toWidth:(NSInteger)targetWidth
                           toHeight:(NSInteger)targetHeight
                         resizeMode:(ImageResizeMode)resizeMode {
    if (!imageData || resizeMode == ImageResizeModeNone) {
        return imageData;
    }
    
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
    if (!imageRep) {
        IOWarn("Failed to create image representation for resizing");
        return imageData;
    }
    
    NSInteger originalWidth = imageRep.pixelsWide;
    NSInteger originalHeight = imageRep.pixelsHigh;
    
    NSInteger newWidth = originalWidth;
    NSInteger newHeight = originalHeight;
    
    switch (resizeMode) {
        case ImageResizeModeWidth:
            if (targetWidth > 0 && targetWidth < originalWidth) {
                newWidth = targetWidth;
                newHeight = (originalHeight * targetWidth) / originalWidth;
            }
            break;
            
        case ImageResizeModeHeight:
            if (targetHeight > 0 && targetHeight < originalHeight) {
                newHeight = targetHeight;
                newWidth = (originalWidth * targetHeight) / originalHeight;
            }
            break;
            
        case ImageResizeModeFit:
            if (targetWidth > 0 && targetHeight > 0) {
                CGFloat widthRatio = (CGFloat)targetWidth / originalWidth;
                CGFloat heightRatio = (CGFloat)targetHeight / originalHeight;
                CGFloat ratio = MIN(widthRatio, heightRatio);
                
                if (ratio < 1.0) {
                    newWidth = originalWidth * ratio;
                    newHeight = originalHeight * ratio;
                }
            }
            break;
            
        default:
            return imageData;
    }
    
    if (newWidth == originalWidth && newHeight == originalHeight) {
        return imageData;
    }
    
    NSImage *originalImage = [[NSImage alloc] initWithData:imageData];
    if (!originalImage) {
        IOWarn("Failed to create NSImage for resizing");
        return imageData;
    }
    
    NSBitmapImageRep *resizedRep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:newWidth
                      pixelsHigh:newHeight
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];
    if (!resizedRep) {
        IOWarn("Failed to create resized image representation");
        return imageData;
    }
    resizedRep.size = NSMakeSize(newWidth, newHeight);

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:resizedRep]];
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;

    [originalImage drawInRect:NSMakeRect(0, 0, newWidth, newHeight)
                     fromRect:NSZeroRect
                    operation:NSCompositingOperationCopy
                     fraction:1.0];

    [NSGraphicsContext restoreGraphicsState];
    
    // Return PNG data for further processing
    NSData *resizedData = [resizedRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    
    IODebug("Resized image from %ldx%ld to %ldx%ld", originalWidth, originalHeight, newWidth, newHeight);
    
    return resizedData ?: imageData;
}

+ (nullable NSData *)convertImageData:(NSData *)imageData
                             toFormat:(ImageOutputFormat)format
                              quality:(CGFloat)quality {
    return [FormatConverterFactory convertImageData:imageData toFormat:format quality:quality] ?: imageData;
}

+ (NSString *)fileExtensionForFormat:(ImageOutputFormat)format {
    switch (format) {
        case ImageOutputFormatJPEG:
            return @"jpg";
        case ImageOutputFormatPNG:
            return @"png";
        case ImageOutputFormatAVIF:
            return @"avif";
        case ImageOutputFormatWebP:
            return @"webp";
        case ImageOutputFormatJXL:
            return @"jxl";
        default:
            return @"";
    }
}

+ (NSString *)mimeTypeForFormat:(ImageOutputFormat)format {
    switch (format) {
        case ImageOutputFormatJPEG:
            return @"image/jpeg";
        case ImageOutputFormatPNG:
            return @"image/png";
        case ImageOutputFormatAVIF:
            return @"image/avif";
        case ImageOutputFormatWebP:
            return @"image/webp";
        case ImageOutputFormatJXL:
            return @"image/jxl";
        default:
            return @"application/octet-stream";
    }
}

@end