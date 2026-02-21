//
//  PostProcessWorker.m
//  ImageOptim
//
//  Created by Enhanced ImageOptim on 2025.
//
//

#import "PostProcessWorker.h"
#import "../Job.h"
#import "../File.h"
#import "../TempFile.h"
#import "../ImageProcessor.h"
#import "../../log.h"

@implementation PostProcessWorker

- (instancetype)initWithJob:(Job *)aJob {
    if (self = [super initWithFile:aJob]) {
        // Initialization
    }
    return self;
}

- (NSInteger)settingsIdentifier {
    return job.outputFormat * 1000 + (NSInteger)(job.outputQuality * 100);
}

- (BOOL)makesNonOptimizingModifications {
    return job.outputFormat != 0; // Not ImageOutputFormatOriginal
}

- (void)run {
    File *inputFile = job.wipInput;
    if (!inputFile || job.outputFormat == 0) { // ImageOutputFormatOriginal
        return;
    }
    
    NSData *inputData = [NSData dataWithContentsOfURL:inputFile.path];
    if (!inputData) {
        IOWarn("Failed to read input file for post-processing");
        return;
    }
    
    NSData *convertedData = [ImageProcessor convertImageData:inputData
                                                    toFormat:(ImageOutputFormat)job.outputFormat
                                                     quality:job.outputQuality];
    
    if (convertedData && convertedData != inputData) {
        // Create temporary file with converted data
        NSURL *tempPath = [self tempPath];
        if ([convertedData writeToURL:tempPath atomically:YES]) {
            TempFile *convertedFile = [inputFile tempCopyOfPath:tempPath size:convertedData.length];
            if (convertedFile) {
                NSString *formatName = [ImageProcessor fileExtensionForFormat:(ImageOutputFormat)job.outputFormat].uppercaseString;
                [job setFileOptimized:convertedFile toolName:[NSString stringWithFormat:@"Convert to %@", formatName]];
                IODebug("Post-processing completed for %@", inputFile.path.lastPathComponent);
            }
        } else {
            IOWarn("Failed to write post-processed file to %@", tempPath.path);
        }
    }
}

- (NSURL *)tempPath {
    static int uid = 0;
    if (uid == 0) uid = getpid() << 12;
    NSString *filename = [NSString stringWithFormat:@"ImageOptim.PostProcess.%x.%x.temp", (unsigned int)([Job hash] ^ [self hash]), uid++];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
}

@end