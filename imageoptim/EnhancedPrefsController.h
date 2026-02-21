//
//  EnhancedPrefsController.h
//  ImageOptim
//

#import <Cocoa/Cocoa.h>
#import "PrefsController.h"

@interface EnhancedPrefsController : PrefsController

@property (weak) IBOutlet NSTabView *enhancedTabs;
@property (weak) IBOutlet NSTextField *targetWidthField;
@property (weak) IBOutlet NSTextField *targetHeightField;
@property (weak) IBOutlet NSPopUpButton *resizeModePopup;
@property (weak) IBOutlet NSPopUpButton *outputFormatPopup;
@property (weak) IBOutlet NSSlider *outputQualitySlider;
@property (weak) IBOutlet NSTextField *outputQualityLabel;

- (IBAction)resizeModeChanged:(id)sender;
- (IBAction)outputFormatChanged:(id)sender;
- (IBAction)outputQualityChanged:(id)sender;

@end
