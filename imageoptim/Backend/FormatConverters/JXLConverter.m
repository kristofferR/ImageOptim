//
//  JXLConverter.m
//  ImageOptim
//

#import "JXLConverter.h"
#import "../../log.h"

#ifdef HAVE_LIBJXL
#import <jxl/encode.h>
#import <jxl/thread_parallel_runner.h>
#endif

@implementation JXLConverter

+ (BOOL)isJXLSupported {
#ifdef HAVE_LIBJXL
    return YES;
#else
    return NO;
#endif
}

+ (nullable NSData *)convertImageData:(NSData *)imageData quality:(CGFloat)quality {
#ifdef HAVE_LIBJXL
    NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
    if (!imageRep) {
        IOWarn("Failed to create bitmap representation for JXL conversion");
        return nil;
    }

    return [self convertBitmapImageRep:imageRep quality:quality];
#else
    IOWarn("JPEG XL support not compiled in");
    return nil;
#endif
}

+ (nullable NSData *)convertBitmapImageRep:(NSBitmapImageRep *)imageRep quality:(CGFloat)quality {
#ifdef HAVE_LIBJXL
    if (!imageRep) {
        return nil;
    }

    NSInteger width = imageRep.pixelsWide;
    NSInteger height = imageRep.pixelsHigh;

    // Convert to sRGB if needed
    NSBitmapImageRep *rgbRep = imageRep;
    if (imageRep.colorSpaceName != NSCalibratedRGBColorSpace &&
        imageRep.colorSpaceName != NSDeviceRGBColorSpace) {
        rgbRep = [imageRep bitmapImageRepByConvertingToColorSpace:[NSColorSpace sRGBColorSpace]
                                                 renderingIntent:NSColorRenderingIntentRelativeColorimetric];
    }

    if (!rgbRep) {
        IOWarn("Failed to convert to RGB color space for JXL");
        return nil;
    }

    BOOL hasAlpha = rgbRep.hasAlpha;
    NSInteger numComponents = hasAlpha ? 4 : 3;

    // Create thread parallel runner
    void *runner = JxlThreadParallelRunnerCreate(NULL, JxlThreadParallelRunnerDefaultNumWorkerThreads());
    if (!runner) {
        IOWarn("Failed to create JXL thread runner");
        return nil;
    }

    // Create encoder
    JxlEncoder *encoder = JxlEncoderCreate(NULL);
    if (!encoder) {
        IOWarn("Failed to create JXL encoder");
        JxlThreadParallelRunnerDestroy(runner);
        return nil;
    }

    if (JxlEncoderSetParallelRunner(encoder, JxlThreadParallelRunner, runner) != JXL_ENC_SUCCESS) {
        IOWarn("Failed to set JXL parallel runner");
        JxlEncoderDestroy(encoder);
        JxlThreadParallelRunnerDestroy(runner);
        return nil;
    }

    // Set basic info
    JxlBasicInfo basicInfo;
    JxlEncoderInitBasicInfo(&basicInfo);
    basicInfo.xsize = (uint32_t)width;
    basicInfo.ysize = (uint32_t)height;
    basicInfo.bits_per_sample = 8;
    basicInfo.exponent_bits_per_sample = 0;
    basicInfo.num_color_channels = 3;
    basicInfo.num_extra_channels = hasAlpha ? 1 : 0;
    basicInfo.alpha_bits = hasAlpha ? 8 : 0;
    basicInfo.uses_original_profile = JXL_FALSE;

    if (JxlEncoderSetBasicInfo(encoder, &basicInfo) != JXL_ENC_SUCCESS) {
        IOWarn("Failed to set JXL basic info");
        JxlEncoderDestroy(encoder);
        JxlThreadParallelRunnerDestroy(runner);
        return nil;
    }

    // Set color encoding to sRGB
    JxlColorEncoding colorEncoding;
    JxlColorEncodingSetToSRGB(&colorEncoding, JXL_FALSE);
    if (JxlEncoderSetColorEncoding(encoder, &colorEncoding) != JXL_ENC_SUCCESS) {
        IOWarn("Failed to set JXL color encoding");
        JxlEncoderDestroy(encoder);
        JxlThreadParallelRunnerDestroy(runner);
        return nil;
    }

    // Set frame settings
    JxlEncoderFrameSettings *frameSettings = JxlEncoderFrameSettingsCreate(encoder, NULL);

    // Quality: 0.0 = worst, 1.0 = lossless
    // JXL distance: 0.0 = lossless, 15.0 = worst
    // Map quality (0-1) to distance (15-0)
    float distance;
    if (quality >= 1.0f) {
        distance = 0.0f; // lossless
    } else {
        distance = 15.0f * (1.0f - (float)quality);
        if (distance < 0.01f) distance = 0.01f;
    }

    JxlEncoderSetFrameDistance(frameSettings, distance);
    JxlEncoderFrameSettingsSetOption(frameSettings, JXL_ENC_FRAME_SETTING_EFFORT, 7);

    // Set pixel format
    JxlPixelFormat pixelFormat;
    pixelFormat.num_channels = (uint32_t)numComponents;
    pixelFormat.data_type = JXL_TYPE_UINT8;
    pixelFormat.endianness = JXL_NATIVE_ENDIAN;
    pixelFormat.align = 0;

    // Add image frame
    size_t pixelDataSize = (size_t)(width * height * numComponents);
    const uint8_t *pixelData = (const uint8_t *)rgbRep.bitmapData;

    if (JxlEncoderAddImageFrame(frameSettings, &pixelFormat, pixelData, pixelDataSize) != JXL_ENC_SUCCESS) {
        IOWarn("Failed to add JXL image frame");
        JxlEncoderDestroy(encoder);
        JxlThreadParallelRunnerDestroy(runner);
        return nil;
    }

    JxlEncoderCloseInput(encoder);

    // Process encoder output
    NSMutableData *outputData = [NSMutableData data];
    uint8_t buffer[65536];

    JxlEncoderStatus status;
    do {
        size_t availOut = sizeof(buffer);
        uint8_t *nextOut = buffer;
        status = JxlEncoderProcessOutput(encoder, &nextOut, &availOut);

        if (status == JXL_ENC_ERROR) {
            IOWarn("JXL encoding error");
            JxlEncoderDestroy(encoder);
            JxlThreadParallelRunnerDestroy(runner);
            return nil;
        }

        size_t bytesWritten = sizeof(buffer) - availOut;
        if (bytesWritten > 0) {
            [outputData appendBytes:buffer length:bytesWritten];
        }
    } while (status == JXL_ENC_NEED_MORE_OUTPUT);

    JxlEncoderDestroy(encoder);
    JxlThreadParallelRunnerDestroy(runner);

    if (outputData.length > 0) {
        IODebug("Successfully converted to JXL: %ld bytes", (long)outputData.length);
        return [outputData copy];
    }

    return nil;
#else
    IOWarn("JPEG XL support not compiled in");
    return nil;
#endif
}

@end
