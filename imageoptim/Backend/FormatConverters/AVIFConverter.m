//
//  AVIFConverter.m
//  ImageOptim
//

#import "AVIFConverter.h"
#import "../../log.h"

#ifdef HAVE_LIBAVIF
#import <avif/avif.h>
#endif

@implementation AVIFConverter

+ (BOOL)isAVIFSupported {
#ifdef HAVE_LIBAVIF
    return YES;
#else
    return NO;
#endif
}

+ (nullable NSData *)convertImageData:(NSData *)imageData quality:(CGFloat)quality {
#ifdef HAVE_LIBAVIF
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
    if (!imageRep) {
        IOWarn("Failed to create bitmap representation for AVIF conversion");
        return nil;
    }
    
    return [self convertBitmapImageRep:imageRep quality:quality];
#else
    IOWarn("AVIF support not compiled in");
    return nil;
#endif
}

+ (nullable NSData *)convertBitmapImageRep:(NSBitmapImageRep *)imageRep quality:(CGFloat)quality {
#ifdef HAVE_LIBAVIF
    if (!imageRep) {
        return nil;
    }
    
    NSInteger width = imageRep.pixelsWide;
    NSInteger height = imageRep.pixelsHigh;
    NSInteger bytesPerPixel = imageRep.hasAlpha ? 4 : 3;
    
    // Convert to RGB(A) format that libavif expects
    NSBitmapImageRep *rgbRep = imageRep;
    if (imageRep.colorSpaceName != NSCalibratedRGBColorSpace && 
        imageRep.colorSpaceName != NSDeviceRGBColorSpace) {
        rgbRep = [imageRep bitmapImageRepByConvertingToColorSpace:[NSColorSpace sRGBColorSpace] 
                                                 renderingIntent:NSColorRenderingIntentRelativeColorimetric];
    }
    
    if (!rgbRep) {
        IOWarn("Failed to convert to RGB color space for AVIF");
        return nil;
    }
    
    // Create AVIF image
    avifImage *image = avifImageCreate(width, height, 8, AVIF_PIXEL_FORMAT_YUV420);
    if (!image) {
        IOWarn("Failed to create AVIF image structure");
        return nil;
    }
    
    // Allocate planes
    avifImageAllocatePlanes(image, AVIF_PLANES_ALL);
    
    // Convert RGB to YUV
    avifRGBImage rgb;
    avifRGBImageSetDefaults(&rgb, image);
    rgb.format = imageRep.hasAlpha ? AVIF_RGB_FORMAT_RGBA : AVIF_RGB_FORMAT_RGB;
    rgb.pixels = (uint8_t *)rgbRep.bitmapData;
    rgb.rowBytes = rgbRep.bytesPerRow;
    
    avifResult result = avifImageRGBToYUV(image, &rgb);
    if (result != AVIF_RESULT_OK) {
        IOWarn("Failed to convert RGB to YUV for AVIF: %s", avifResultToString(result));
        avifImageDestroy(image);
        return nil;
    }
    
    // Create encoder
    avifEncoder *encoder = avifEncoderCreate();
    if (!encoder) {
        IOWarn("Failed to create AVIF encoder");
        avifImageDestroy(image);
        return nil;
    }
    
    // Set quality (0-100 scale, where 100 is lossless)
    encoder->quality = (int)(quality * 100);
    encoder->qualityAlpha = encoder->quality;
    
    // Encode
    avifRWData output = AVIF_DATA_EMPTY;
    result = avifEncoderWrite(encoder, image, &output);
    
    NSData *avifData = nil;
    if (result == AVIF_RESULT_OK && output.size > 0) {
        avifData = [NSData dataWithBytes:output.data length:output.size];
        IODebug("Successfully converted to AVIF: %ld bytes", (long)output.size);
    } else {
        IOWarn("Failed to encode AVIF: %s", avifResultToString(result));
    }
    
    // Cleanup
    avifRWDataFree(&output);
    avifEncoderDestroy(encoder);
    avifImageDestroy(image);
    
    return avifData;
#else
    IOWarn("AVIF support not compiled in");
    return nil;
#endif
}

@end
