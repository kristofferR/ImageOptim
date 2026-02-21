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
    const unsigned char ftypmagic[] = {'f','t','y','p'};
    unsigned char fileHeaderBytes[12];

    if (!fileData || fileData.length < sizeof(fileHeaderBytes)) {
        return nil;
    }

    [fileData getBytes:fileHeaderBytes length:sizeof(fileHeaderBytes)];

    enum IOFileType type = 0;

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
    } else if (0 == memcmp(fileHeaderBytes + 4, ftypmagic, sizeof(ftypmagic))) {
        type = FILETYPE_AVIF;
    }

    return [self initWithType:type size:fileData.length fromPath:aPath];
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
        case FILETYPE_SVG: return @"image/svg";
        case FILETYPE_AVIF: return @"image/avif";
        case FILETYPE_WEBP: return @"image/webp";
        case FILETYPE_JXL: return @"image/jxl";
        default:
            return nil;
    }
}

@end
