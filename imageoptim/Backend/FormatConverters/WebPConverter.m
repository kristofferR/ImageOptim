//
//  WebPConverter.m
//  ImageOptim
//

#import "WebPConverter.h"
#import "../../log.h"

#ifdef HAVE_LIBWEBP
#import <webp/encode.h>
#import <webp/decode.h>
#endif

@implementation WebPConverter

+ (BOOL)isWebPSupported {
#ifdef HAVE_LIBWEBP
    return YES;
#else
    return NO;
#endif
}

+ (nullable NSData *)convertImageData:(NSData *)imageData quality:(CGFloat)quality {
#ifdef HAVE_LIBWEBP
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
    if (!imageRep) {
        IOWarn("Failed to create bitmap representation for WebP conversion");
        return nil;
    }
    
    return [self convertBitmapImageRep:imageRep quality:quality];
#else
    IOWarn("WebP support not compiled in");
    return nil;
#endif
}

+ (nullable NSData *)convertBitmapImageRep:(NSBitmapImageRep *)imageRep quality:(CGFloat)quality {
#ifdef HAVE_LIBWEBP
    if (!imageRep) {
        return nil;
    }
    
    NSInteger width = imageRep.pixelsWide;
    NSInteger height = imageRep.pixelsHigh;
    
    // Convert to RGB(A) format that libwebp expects
    NSBitmapImageRep *rgbRep = imageRep;
    if (imageRep.colorSpaceName != NSCalibratedRGBColorSpace && 
        imageRep.colorSpaceName != NSDeviceRGBColorSpace) {
        rgbRep = [imageRep bitmapImageRepByConvertingToColorSpace:[NSColorSpace sRGBColorSpace] 
                                                 renderingIntent:NSColorRenderingIntentRelativeColorimetric];
    }
    
    if (!rgbRep) {
        IOWarn("Failed to convert to RGB color space for WebP");
        return nil;
    }
    
    // Configure WebP encoding
    WebPConfig config;
    if (!WebPConfigInit(&config)) {
        IOWarn("Failed to initialize WebP config");
        return nil;
    }

    config.quality = quality * 100;
    config.method = 6;

    if (!WebPValidateConfig(&config)) {
        IOWarn("Invalid WebP configuration");
        return nil;
    }

    // Set up picture
    WebPPicture picture;
    if (!WebPPictureInit(&picture)) {
        IOWarn("Failed to initialize WebP picture");
        return nil;
    }

    picture.width = (int)width;
    picture.height = (int)height;
    picture.use_argb = 1;

    int importOk;
    if (rgbRep.hasAlpha) {
        importOk = WebPPictureImportRGBA(&picture,
                                         (uint8_t *)rgbRep.bitmapData,
                                         (int)rgbRep.bytesPerRow);
    } else {
        importOk = WebPPictureImportRGB(&picture,
                                        (uint8_t *)rgbRep.bitmapData,
                                        (int)rgbRep.bytesPerRow);
    }

    if (!importOk) {
        IOWarn("Failed to import pixel data for WebP");
        WebPPictureFree(&picture);
        return nil;
    }

    // Set up memory writer
    WebPMemoryWriter writer;
    WebPMemoryWriterInit(&writer);
    picture.writer = WebPMemoryWrite;
    picture.custom_ptr = &writer;

    int encodeOk = WebPEncode(&config, &picture);
    WebPPictureFree(&picture);

    NSData *webpData = nil;
    if (encodeOk && writer.size > 0) {
        webpData = [NSData dataWithBytes:writer.mem length:writer.size];
        IODebug("Successfully converted to WebP: %ld bytes", (long)writer.size);
    } else {
        IOWarn("Failed to encode WebP image");
    }

    WebPMemoryWriterClear(&writer);

    return webpData;
#else
    IOWarn("WebP support not compiled in");
    return nil;
#endif
}

@end