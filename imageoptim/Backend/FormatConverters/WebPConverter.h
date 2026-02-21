//
//  WebPConverter.h
//  ImageOptim
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WebPConverter : NSObject

+ (nullable NSData *)convertImageData:(NSData *)imageData 
                              quality:(CGFloat)quality;

+ (nullable NSData *)convertBitmapImageRep:(NSBitmapImageRep *)imageRep 
                                   quality:(CGFloat)quality;

+ (BOOL)isWebPSupported;

@end

NS_ASSUME_NONNULL_END
