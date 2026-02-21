//
//  AVIFConverter.h
//  ImageOptim
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVIFConverter : NSObject

+ (nullable NSData *)convertImageData:(NSData *)imageData 
                              quality:(CGFloat)quality;

+ (nullable NSData *)convertBitmapImageRep:(NSBitmapImageRep *)imageRep 
                                   quality:(CGFloat)quality;

+ (BOOL)isAVIFSupported;

@end

NS_ASSUME_NONNULL_END
