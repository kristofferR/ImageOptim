//
//  EnhancedPrefsController.m
//  ImageOptim
//
//  Created by Enhanced ImageOptim on 2025.
//
//

#import "EnhancedPrefsController.h"
#import "Backend/FormatConverters/FormatConverterFactory.h"

@implementation EnhancedPrefsController

- (instancetype)init {
    if ((self = [super init])) {
        // Additional initialization if needed
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    
    // Setup resize mode popup
    [self.resizeModePopup removeAllItems];
    [self.resizeModePopup addItemWithTitle:@"No Resize"];
    [self.resizeModePopup addItemWithTitle:@"Resize by Width"];
    [self.resizeModePopup addItemWithTitle:@"Resize by Height"];
    [self.resizeModePopup addItemWithTitle:@"Fit to Dimensions"];
    
    // Setup output format popup
    [self.outputFormatPopup removeAllItems];
    
    NSArray *formatTitles = @[@"Keep Original", @"JPEG", @"PNG", @"AVIF", @"WebP", @"JPEG XL"];
    NSArray<NSNumber *> *supportedFormats = [FormatConverterFactory supportedFormats];
    
    for (NSInteger i = 0; i < formatTitles.count; i++) {
        NSNumber *formatNumber = @(i);
        if ([supportedFormats containsObject:formatNumber]) {
            NSString *title = formatTitles[i];
            if (i == ImageOutputFormatAVIF && ![FormatConverterFactory isFormatSupported:ImageOutputFormatAVIF]) {
                title = [title stringByAppendingString:@" (Not Available)"];
            }
            if (i == ImageOutputFormatWebP && ![FormatConverterFactory isFormatSupported:ImageOutputFormatWebP]) {
                title = [title stringByAppendingString:@" (Not Available)"];
            }
            if (i == ImageOutputFormatJXL && ![FormatConverterFactory isFormatSupported:ImageOutputFormatJXL]) {
                title = [title stringByAppendingString:@" (Not Available)"];
            }
            [self.outputFormatPopup addItemWithTitle:title];
        }
    }
    
    // Bind controls to user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    [self.targetWidthField bind:@"value" 
                       toObject:defaults 
                    withKeyPath:@"TargetWidth" 
                        options:@{NSNullPlaceholderBindingOption: @""}];
    
    [self.targetHeightField bind:@"value" 
                        toObject:defaults 
                     withKeyPath:@"TargetHeight" 
                         options:@{NSNullPlaceholderBindingOption: @""}];
    
    [self.resizeModePopup bind:@"selectedIndex" 
                      toObject:defaults 
                   withKeyPath:@"ResizeMode" 
                       options:nil];
    
    [self.outputFormatPopup bind:@"selectedIndex" 
                        toObject:defaults 
                     withKeyPath:@"OutputFormat" 
                           options:nil];
    
    [self.outputQualitySlider bind:@"value" 
                          toObject:defaults 
                       withKeyPath:@"OutputQuality" 
                           options:nil];
    
    [self updateQualityLabel];
    [self updateControlStates];
}

- (IBAction)resizeModeChanged:(id)sender {
    [self updateControlStates];
}

- (IBAction)outputFormatChanged:(id)sender {
    [self updateControlStates];
}

- (IBAction)outputQualityChanged:(id)sender {
    [self updateQualityLabel];
}

- (void)updateControlStates {
    NSInteger resizeMode = self.resizeModePopup.indexOfSelectedItem;
    NSInteger outputFormat = self.outputFormatPopup.indexOfSelectedItem;
    
    // Enable/disable resize fields based on mode
    BOOL enableWidth = (resizeMode == 1 || resizeMode == 3); // Width or Fit
    BOOL enableHeight = (resizeMode == 2 || resizeMode == 3); // Height or Fit
    
    self.targetWidthField.enabled = enableWidth;
    self.targetHeightField.enabled = enableHeight;
    
    // Enable/disable quality slider based on format
    BOOL enableQuality = (outputFormat == 1); // JPEG
    self.outputQualitySlider.enabled = enableQuality;
    self.outputQualityLabel.enabled = enableQuality;
}

- (void)updateQualityLabel {
    NSInteger qualityPercent = (NSInteger)(self.outputQualitySlider.doubleValue * 100);
    self.outputQualityLabel.stringValue = [NSString stringWithFormat:@"%ld%%", qualityPercent];
}

@end