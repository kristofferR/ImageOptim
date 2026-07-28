//
//  FormatDetectionTests.m
//  BackendTests
//
//  Covers File's sniffing of the formats added alongside AVIF and JPEG XL.
//  Everything here is synthesised in memory: the point is the parser, not the
//  encoders, so these run without the vendored tools being built.
//

@import Cocoa;
#import <XCTest/XCTest.h>
#import "File.h"

@interface FormatDetectionTests : XCTestCase
@end

@implementation FormatDetectionTests

static NSURL *DummyPath(void) {
    return [NSURL fileURLWithPath:@"/tmp/imageoptim-format-detection-test"];
}

static File *Detect(NSData *data) {
    return [[File alloc] initWithData:data fromPath:DummyPath()];
}

static void AppendBE32(NSMutableData *data, uint32_t value) {
    unsigned char bytes[4] = {
        (unsigned char)(value >> 24), (unsigned char)(value >> 16),
        (unsigned char)(value >> 8), (unsigned char)value};
    [data appendBytes:bytes length:sizeof(bytes)];
}

/* Builds an ISO-BMFF ftyp box. boxSize is written verbatim so the 0 (extends to
   EOF) and 1 (64-bit size follows) escapes can be exercised. */
static NSData *FtypBox(uint32_t boxSize, NSString *majorBrand, NSArray<NSString *> *compatibleBrands, BOOL use64BitSize) {
    NSMutableData *data = [NSMutableData data];
    AppendBE32(data, use64BitSize ? 1 : boxSize);
    [data appendData:[@"ftyp" dataUsingEncoding:NSASCIIStringEncoding]];
    if (use64BitSize) {
        AppendBE32(data, 0);
        AppendBE32(data, boxSize);
    }
    [data appendData:[majorBrand dataUsingEncoding:NSASCIIStringEncoding]];
    AppendBE32(data, 0); // minor version
    for (NSString *brand in compatibleBrands) {
        [data appendData:[brand dataUsingEncoding:NSASCIIStringEncoding]];
    }
    return data;
}

static NSData *AvifFile(NSString *majorBrand, NSArray<NSString *> *compatibleBrands) {
    NSUInteger size = 16 + 4 * compatibleBrands.count;
    return FtypBox((uint32_t)size, majorBrand, compatibleBrands, NO);
}

#pragma mark - The formats that already worked

- (void)testDetectsPngJpegGifSvg {
    const unsigned char png[] = {0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a};
    const unsigned char jpeg[] = {0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10};
    const unsigned char gif[] = {'G', 'I', 'F', '8', '9', 'a'};

    XCTAssertEqual(Detect([NSData dataWithBytes:png length:sizeof(png)])->fileType, FILETYPE_PNG);
    XCTAssertEqual(Detect([NSData dataWithBytes:jpeg length:sizeof(jpeg)])->fileType, FILETYPE_JPEG);
    XCTAssertEqual(Detect([NSData dataWithBytes:gif length:sizeof(gif)])->fileType, FILETYPE_GIF);
    XCTAssertEqual(Detect([@"<svg xmlns=\"...\">" dataUsingEncoding:NSUTF8StringEncoding])->fileType, FILETYPE_SVG);
}

- (void)testRejectsTruncatedInput {
    const unsigned char tooShort[] = {0x89, 'P', 'N', 'G', 0x0d};
    XCTAssertNil(Detect([NSData dataWithBytes:tooShort length:sizeof(tooShort)]));
    XCTAssertNil(Detect([NSData data]));
    XCTAssertNil(Detect(nil));
}

#pragma mark - AVIF

- (void)testDetectsAvifByMajorBrand {
    File *file = Detect(AvifFile(@"avif", @[@"mif1", @"miaf"]));
    XCTAssertEqual(file->fileType, FILETYPE_AVIF);
    XCTAssertFalse(file->isAnimated);
}

/* Plenty of AVIF files in the wild carry some other major brand and only list
   avif as compatible, which is why the compatible-brands list is scanned. */
- (void)testDetectsAvifListedOnlyAsCompatibleBrand {
    File *file = Detect(AvifFile(@"mif1", @[@"miaf", @"avif"]));
    XCTAssertEqual(file->fileType, FILETYPE_AVIF);
    XCTAssertFalse(file->isAnimated);
}

- (void)testDetectsAnimatedAvifSequence {
    File *byMajorBrand = Detect(AvifFile(@"avis", @[@"msf1"]));
    XCTAssertEqual(byMajorBrand->fileType, FILETYPE_AVIF);
    XCTAssertTrue(byMajorBrand->isAnimated, @"avis must be flagged: avifenc cannot re-encode a sequence");

    File *byCompatibleBrand = Detect(AvifFile(@"mif1", @[@"avis"]));
    XCTAssertEqual(byCompatibleBrand->fileType, FILETYPE_AVIF);
    XCTAssertTrue(byCompatibleBrand->isAnimated);
}

- (void)testDetectsAvifWith64BitBoxSize {
    NSData *data = FtypBox(24, @"avif", @[@"mif1"], YES);
    XCTAssertEqual(Detect(data)->fileType, FILETYPE_AVIF);
}

/* size == 0 means the box runs to end of file. */
- (void)testDetectsAvifWithBoxExtendingToEndOfFile {
    NSData *data = FtypBox(0, @"avif", @[@"mif1"], NO);
    XCTAssertEqual(Detect(data)->fileType, FILETYPE_AVIF);
}

- (void)testIgnoresNonAvifIsoBmff {
    XCTAssertEqual(Detect(AvifFile(@"mp42", @[@"isom", @"mp42"]))->fileType, 0);
    XCTAssertEqual(Detect(AvifFile(@"heic", @[@"mif1", @"heic"]))->fileType, 0);
}

/* A brand list that stops mid-brand must not be read past its end. The declared
   size covers the two stray bytes — 16 header + "miaf" + 2 — so they are inside
   the box and the parser has to stop at the last whole brand on its own. */
- (void)testIgnoresTruncatedCompatibleBrandList {
    NSMutableData *data = [FtypBox(22, @"mif1", @[@"miaf"], NO) mutableCopy];
    [data appendBytes:"av" length:2];
    XCTAssertEqual(Detect(data)->fileType, 0);
}

/* A box claiming to be larger than the file is clamped to what is there. */
- (void)testClampsOversizedBoxToAvailableBytes {
    NSData *data = FtypBox(4096, @"avif", @[@"mif1"], NO);
    XCTAssertEqual(Detect(data)->fileType, FILETYPE_AVIF);
}

#pragma mark - JPEG XL

- (void)testDetectsBareJxlCodestream {
    const unsigned char codestream[] = {0xff, 0x0a, 0x00, 0x11, 0x22, 0x33};
    File *file = Detect([NSData dataWithBytes:codestream length:sizeof(codestream)]);
    XCTAssertEqual(file->fileType, FILETYPE_JXL);
}

- (void)testDetectsJxlContainer {
    const unsigned char container[] = {0x00, 0x00, 0x00, 0x0c, 'J', 'X', 'L', ' ',
                                       0x0d, 0x0a, 0x87, 0x0a, 0x00, 0x00, 0x00, 0x14};
    File *file = Detect([NSData dataWithBytes:container length:sizeof(container)]);
    XCTAssertEqual(file->fileType, FILETYPE_JXL);
}

- (void)testIgnoresJxlLookalikeSignatureBox {
    // Right length and name, wrong signature bytes.
    const unsigned char notJxl[] = {0x00, 0x00, 0x00, 0x0c, 'J', 'X', 'L', ' ',
                                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    XCTAssertEqual(Detect([NSData dataWithBytes:notJxl length:sizeof(notJxl)])->fileType, 0);
}

#pragma mark - MIME types

- (void)testReportsMimeTypesForNewFormats {
    XCTAssertEqualObjects(Detect(AvifFile(@"avif", @[@"mif1"])).mimeType, @"image/avif");

    const unsigned char codestream[] = {0xff, 0x0a, 0x00, 0x11, 0x22, 0x33};
    XCTAssertEqualObjects(Detect([NSData dataWithBytes:codestream length:sizeof(codestream)]).mimeType, @"image/jxl");
}

@end
