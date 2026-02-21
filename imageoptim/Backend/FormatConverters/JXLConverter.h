//
//  JXLConverter.h
//  ImageOptim
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface JXLConverter : NSObject

+ (nullable NSData *)convertImageData:(NSData *)imageData
                              quality:(CGFloat)quality;

+ (nullable NSData *)convertBitmapImageRep:(NSBitmapImageRep *)imageRep
                                   quality:(CGFloat)quality;

+ (BOOL)isJXLSupported;

@end

NS_ASSUME_NONNULL_END
