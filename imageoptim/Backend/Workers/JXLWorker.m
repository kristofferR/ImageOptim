#import "JXLWorker.h"
#import "../Job.h"
#import "../TempFile.h"
#import "../../log.h"

@implementation JXLWorker

- (NSInteger)settingsIdentifier {
    return quality * 2 + lossy;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults file:(Job *)aFile {
    if (self = [super initWithFile:aFile]) {
        lossy = [defaults boolForKey:@"LossyEnabled"];
        quality = lossy ? [defaults integerForKey:@"JxlQuality"] : 100;
        if (quality <= 0) quality = 85;
    }
    return self;
}

- (BOOL)makesNonOptimizingModifications {
    return lossy && quality < 100;
}

- (BOOL)optimizeFile:(File *)file toTempPath:(NSURL *)temp {
    if (file->isAnimated) {
        return NO; // Animated JXL cannot be safely re-encoded via PNG
    }

    NSString *djxlPath = [self pathForExecutableName:@"djxl"];
    NSString *cjxlPath = [self pathForExecutableName:@"cjxl"];

    if (!djxlPath || !cjxlPath) {
        IOWarn("cjxl/djxl not found in bundle");
        [job setError:@"JPEG XL tools not found"];
        return NO;
    }

    // Decode JXL to temp PNG
    NSURL *pngTemp = [[temp URLByDeletingPathExtension] URLByAppendingPathExtension:@"png"];

    NSTask *decodeTask = [NSTask new];
    [decodeTask setLaunchPath:djxlPath];
    [decodeTask setArguments:@[file.path.path, pngTemp.path]];
    @try {
        [decodeTask launch];
        [decodeTask waitUntilExit];
    } @catch (NSException *e) {
        IOWarn("djxl failed: %@", e);
        return NO;
    }

    if ([decodeTask terminationStatus] != 0) {
        [[NSFileManager defaultManager] removeItemAtURL:pngTemp error:nil];
        return NO;
    }

    // Re-encode to JXL
    NSMutableArray *args = [NSMutableArray array];
    if (lossy && quality < 100) {
        [args addObjectsFromArray:@[@"-q", [NSString stringWithFormat:@"%ld", (long)quality]]];
    } else {
        [args addObjectsFromArray:@[@"-q", @"100"]];
    }
    [args addObjectsFromArray:@[@"-e", @"9", pngTemp.path, temp.path]];

    [self taskWithPath:cjxlPath arguments:args];
    [self launchTask];
    BOOL success = [self waitUntilTaskExit];

    [[NSFileManager defaultManager] removeItemAtURL:pngTemp error:nil];

    if (!success) {
        return NO;
    }

    NSString *toolName = (lossy && quality < 100)
        ? [NSString stringWithFormat:@"JPEG XL %ld%%", (long)quality]
        : @"JPEG XL";
    return [job setFileOptimized:[file tempCopyOfPath:temp] toolName:toolName];
}

@end
