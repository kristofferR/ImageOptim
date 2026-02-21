//
//  PreProcessWorker.m
//  ImageOptim
//
//  Created by Enhanced ImageOptim on 2025.
//
//

#import "PreProcessWorker.h"
#import "../Job.h"
#import "../File.h"
#import "../TempFile.h"
#import "../ImageProcessor.h"
#import "../../log.h"

@implementation PreProcessWorker

- (instancetype)initWithJob:(Job *)aJob {
    if (self = [super initWithFile:aJob]) {
        // Initialization
    }
    return self;
}

- (NSInteger)settingsIdentifier {
    return job.targetWidth * 10000 + job.targetHeight * 100 + job.resizeMode * 10 + job.outputFormat;
}

- (BOOL)makesNonOptimizingModifications {
    return job.resizeMode != 0 || job.outputFormat != 0; // Not ImageResizeModeNone or ImageOutputFormatOriginal
}

- (void)run {
    File *inputFile = job.wipInput;
    if (!inputFile) {
        return;
    }
    
    // Only process if we have resize or format conversion settings
    if (job.resizeMode == 0 && job.outputFormat == 0) {
        return;
    }
    
    NSData *inputData = [NSData dataWithContentsOfURL:inputFile.path];
    if (!inputData) {
        IOWarn("Failed to read input file for preprocessing");
        return;
    }
    
    NSData *processedData = inputData;
    
    // Apply resizing if configured
    if (job.resizeMode != 0 && (job.targetWidth > 0 || job.targetHeight > 0)) {
        processedData = [ImageProcessor resizeImageData:processedData
                                               toWidth:job.targetWidth
                                              toHeight:job.targetHeight
                                            resizeMode:(ImageResizeMode)job.resizeMode];
    }
    
    if (processedData && processedData != inputData) {
        // Create temporary file with processed data
        NSURL *tempPath = [self tempPath];
        if ([processedData writeToURL:tempPath atomically:YES]) {
            TempFile *processedFile = [inputFile tempCopyOfPath:tempPath size:processedData.length];
            if (processedFile) {
                [job setFileOptimized:processedFile toolName:@"Resize"];
                IODebug("Pre-processing completed for %@", inputFile.path.lastPathComponent);
            }
        } else {
            IOWarn("Failed to write preprocessed file to %@", tempPath.path);
        }
    }
}

- (NSURL *)tempPath {
    static int uid = 0;
    if (uid == 0) uid = getpid() << 12;
    NSString *filename = [NSString stringWithFormat:@"ImageOptim.PreProcess.%x.%x.temp", (unsigned int)([Job hash] ^ [self hash]), uid++];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
}

@end