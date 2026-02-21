# ImageOptim - Enhanced Image Compression

ImageOptim is an enhanced image compression app based on ImageOptim that adds the following features:

## New Features

### Pre-Compression Image Resizing
- **Resize by Width**: Resize images to a target width while maintaining aspect ratio
- **Resize by Height**: Resize images to a target height while maintaining aspect ratio  
- **Fit to Dimensions**: Resize images to fit within specified width and height bounds
- **No Resize**: Keep original dimensions (default)

### Post-Compression Format Conversion
- **Keep Original**: Maintain the original file format (default)
- **JPEG**: Convert to JPEG with adjustable quality (10-100%)
- **PNG**: Convert to PNG format
- **AVIF**: Convert to AVIF format (planned)
- **WebP**: Convert to WebP format (planned)

## How It Works

ImageOptim adds two new processing stages to the ImageOptim pipeline:

1. **Pre-Processing**: Applied before optimization
   - Image resizing based on user settings
   - Maintains aspect ratio and image quality

2. **Post-Processing**: Applied after optimization
   - Format conversion to target file type
   - Quality adjustment for lossy formats

## Usage

1. Open the ImageOptim Preferences
2. Navigate to the "Processing" tab
3. Configure your resize and format conversion settings:
   - Set target dimensions for resizing
   - Choose resize mode (width, height, or fit)
   - Select output format
   - Adjust quality for JPEG output
4. Process images as usual by dragging them into the main window

## Technical Implementation

### New Classes
- `ImageProcessor`: Core image processing utilities for resizing and format conversion
- `PreProcessWorker`: Handles pre-compression resizing
- `PostProcessWorker`: Handles post-compression format conversion
- `EnhancedPrefsController`: Extended preferences interface

### Modified Classes
- `Job`: Extended with processing settings (target dimensions, resize mode, output format, quality)
- `FilesController`: Applies user settings to new jobs
- `ImageOptimController`: Uses enhanced preferences controller

### Processing Pipeline
```
Original Image → Pre-Process (Resize) → Optimize → Post-Process (Convert) → Final Output
```

## Building

ImageOptim maintains compatibility with the original ImageOptim build system. Simply build the project using Xcode as before.

## Future Enhancements

- Native AVIF and WebP support using dedicated libraries
- Batch processing with different settings per file type
- Advanced resize options (smart cropping, upscaling)
- Watermarking capabilities
- Metadata preservation options during format conversion