//
//  File.m
//  ImageOptim
//
//  Created by Kornel on 11/01/2017.
//
//

#import "File.h"
#import "TempFile.h"
#import "../log.h"
#import <assert.h>
#import <stdint.h>

static uint32_t ReadBE32(const unsigned char *data) {
    return ((uint32_t)data[0] << 24) |
           ((uint32_t)data[1] << 16) |
           ((uint32_t)data[2] << 8) |
           (uint32_t)data[3];
}

static uint64_t ReadBE64(const unsigned char *data) {
    return ((uint64_t)ReadBE32(data) << 32) | ReadBE32(data + 4);
}

static BOOL ParseFtypBox(const unsigned char *bytes, NSUInteger length,
                         NSUInteger *majorBrandOffset,
                         NSUInteger *compatibleBrandsOffset,
                         NSUInteger *compatibleBrandsLength) {
    const unsigned char ftypmagic[] = {'f','t','y','p'};
    if (!bytes || length < 16 || memcmp(bytes + 4, ftypmagic, sizeof(ftypmagic)) != 0) {
        return NO;
    }

    uint64_t boxSize = ReadBE32(bytes);
    NSUInteger headerSize = 8;

    if (boxSize == 1) {
        if (length < 24) {
            return NO;
        }
        boxSize = ReadBE64(bytes + 8);
        headerSize = 16;
    } else if (boxSize == 0) {
        boxSize = length;
    }

    if (boxSize < (uint64_t)headerSize + 8 || boxSize > length) {
        return NO;
    }

    NSUInteger compatLen = (NSUInteger)boxSize - (headerSize + 8);
    compatLen -= compatLen % 4; // Compatible brands are fourcc entries.

    *majorBrandOffset = headerSize;
    *compatibleBrandsOffset = headerSize + 8; // skip major brand + minor version
    *compatibleBrandsLength = compatLen;
    return YES;
}

@implementation File

- (nullable instancetype)initWithType:(enum IOFileType)type size:(NSUInteger)size fromPath:(NSURL *)aPath {
    if (!size) {
        return nil;
    }

    if ((self = [super init])) {
        _path = aPath;
        _byteSize = size;
        fileType = type;
    }
    return self;
}

-(instancetype)initWithData:(NSData *)fileData fromPath:(NSURL *)aPath {
    const unsigned char pngheader[] = {0x89,0x50,0x4e,0x47,0x0d,0x0a};
    const unsigned char jpegheader[] = {0xff,0xd8,0xff};
    const unsigned char gifheader[] = {0x47,0x49,0x46,0x38};
    const unsigned char svgheader[] = {'<','s','v','g'};
    const unsigned char jxlheader[] = {0xff,0x0a};
    const unsigned char jxlcontainer[] = {0x00,0x00,0x00,0x0c,'J','X','L',' '};
    const unsigned char riffheader[] = {'R','I','F','F'};
    const unsigned char webpmagic[] = {'W','E','B','P'};
    const unsigned char avifbrand[] = {'a','v','i','f'};
    const unsigned char avisbrand[] = {'a','v','i','s'};
    unsigned char fileHeaderBytes[24];
    const unsigned char *fileBytes = fileData.bytes;

    if (!fileData || fileData.length < 12) {
        return nil;
    }

    NSUInteger headerLen = MIN(fileData.length, sizeof(fileHeaderBytes));
    [fileData getBytes:fileHeaderBytes length:headerLen];

    enum IOFileType type = 0;
    BOOL animated = NO;

    if (0 == memcmp(fileHeaderBytes, pngheader, sizeof(pngheader))) {
        type = FILETYPE_PNG;
    } else if (0 == memcmp(fileHeaderBytes, jpegheader, sizeof(jpegheader))) {
        type = FILETYPE_JPEG;
    } else if (0 == memcmp(fileHeaderBytes, gifheader, sizeof(gifheader))) {
        type = FILETYPE_GIF;
    } else if (0 == memcmp(fileHeaderBytes, svgheader, sizeof(svgheader)) || [aPath.pathExtension isEqualToString:@"svg"]) {
        type = FILETYPE_SVG;
    } else if (0 == memcmp(fileHeaderBytes, jxlheader, sizeof(jxlheader)) || 0 == memcmp(fileHeaderBytes, jxlcontainer, sizeof(jxlcontainer))) {
        type = FILETYPE_JXL;
    } else if (0 == memcmp(fileHeaderBytes, riffheader, sizeof(riffheader)) && 0 == memcmp(fileHeaderBytes + 8, webpmagic, sizeof(webpmagic))) {
        type = FILETYPE_WEBP;
        // VP8X chunk at offset 12 has flags at offset 20; bit 1 = animation
        const unsigned char vp8x[] = {'V','P','8','X'};
        if (headerLen >= 21 && 0 == memcmp(fileHeaderBytes + 12, vp8x, sizeof(vp8x)) && (fileHeaderBytes[20] & 0x02)) {
            animated = YES;
        }
    } else {
        NSUInteger majorBrandOffset = 0;
        NSUInteger compatibleBrandsOffset = 0;
        NSUInteger compatibleBrandsLength = 0;
        BOOL hasAvifBrand = NO;
        BOOL hasAvisBrand = NO;

        if (ParseFtypBox(fileBytes, fileData.length, &majorBrandOffset, &compatibleBrandsOffset, &compatibleBrandsLength)) {
            if (0 == memcmp(fileBytes + majorBrandOffset, avifbrand, sizeof(avifbrand))) {
                hasAvifBrand = YES;
            } else if (0 == memcmp(fileBytes + majorBrandOffset, avisbrand, sizeof(avisbrand))) {
                hasAvisBrand = YES;
            }

            NSUInteger compatibleEnd = compatibleBrandsOffset + compatibleBrandsLength;
            for (NSUInteger offset = compatibleBrandsOffset; offset + 4 <= compatibleEnd; offset += 4) {
                if (0 == memcmp(fileBytes + offset, avifbrand, sizeof(avifbrand))) {
                    hasAvifBrand = YES;
                } else if (0 == memcmp(fileBytes + offset, avisbrand, sizeof(avisbrand))) {
                    hasAvisBrand = YES;
                }
            }
        }

        if (hasAvifBrand || hasAvisBrand) {
            type = FILETYPE_AVIF;
            animated = hasAvisBrand;
        }
    }

    File *result = [self initWithType:type size:fileData.length fromPath:aPath];
    if (result) {
        result->isAnimated = animated;
    }
    return result;
}

- (nullable File *)copyOfPath:(NSURL *)path {
    return [[File alloc] initWithType:fileType size:[File byteSize:path] fromPath:path];
}

- (nullable File *)copyOfPath:(NSURL *)path size:(NSUInteger)s {
    return [[File alloc] initWithType:fileType size:s fromPath:path];
}

- (nullable TempFile *)tempCopyOfPath:(NSURL *)path {
    return [[TempFile alloc] initWithType:fileType size:[File byteSize:path] fromPath:path];
}

- (nullable TempFile *)tempCopyOfPath:(NSURL *)path size:(NSUInteger)s {
    if (!s) {
        return nil;
    }

    if (s != [File byteSize:path]) {
        NSLog(@"Expected size %d, but file is actually %d", (int)s, (int)[File byteSize:path]);
        return nil;
    }
    return [[TempFile alloc] initWithType:fileType size:s fromPath:path];
}

- (BOOL)isLarge {
    if (fileType == FILETYPE_PNG) {
        return _byteSize > 250 * 1024;
    }
    return _byteSize > 1 * 1024 * 1024;
}

- (BOOL)isSmall {
    if (fileType == FILETYPE_PNG) {
        return _byteSize < 2048;
    }
    return _byteSize < 10 * 1024;
}

+ (NSInteger)byteSize:(NSURL *)afile {
    NSNumber *value = nil;
    NSError *err = nil;
    if ([afile getResourceValue:&value forKey:NSURLFileSizeKey error:&err] && value) {
        return [value integerValue];
    }
    IOWarn("Could not stat %@: %@", afile.path, err);
    return 0;
}

- (nullable NSString *)mimeType {
    switch (fileType) {
        case FILETYPE_PNG: return @"image/png";
        case FILETYPE_JPEG: return @"image/jpeg";
        case FILETYPE_GIF: return @"image/gif";
        case FILETYPE_SVG: return @"image/svg+xml";
        case FILETYPE_AVIF: return @"image/avif";
        case FILETYPE_WEBP: return @"image/webp";
        case FILETYPE_JXL: return @"image/jxl";
        default:
            return nil;
    }
}

@end
