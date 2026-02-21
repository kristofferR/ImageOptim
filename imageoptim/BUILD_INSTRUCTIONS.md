# Building ImageOptim with AVIF and WebP Support

This guide explains how to build ImageOptim with full AVIF and WebP support.

## Prerequisites

1. **Xcode** (latest version recommended)
2. **Homebrew** (for dependency management)
3. **CocoaPods** (for WebP integration)

## Setup Instructions

### 1. Install System Dependencies

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install cmake nasm git
```

### 2. Install CocoaPods

```bash
sudo gem install cocoapods
```

### 3. Setup Project Dependencies

Run the setup script from the project root:

```bash
cd /path/to/your/ImageOptim
chmod +x Scripts/setup-dependencies.sh
./Scripts/setup-dependencies.sh
```

This script will:
- Install WebP via CocoaPods
- Build libavif from source
- Configure the necessary build settings

### 4. Configure Xcode Project

#### Add libavif to Your Project

1. Open `ImageOptim.xcworkspace` (not .xcodeproj) in Xcode
2. Right-click on your project and select "Add Files to ImageOptim"
3. Navigate to `Dependencies/libavif/build/` and add `libavif.a`
4. Add the libavif headers:
   - Go to Build Settings → Header Search Paths
   - Add `$(SRCROOT)/Dependencies/libavif/include`

#### Configure Preprocessor Definitions

1. Go to Build Settings → Preprocessor Macros
2. Add these definitions:
   - `HAVE_LIBAVIF=1`
   - `HAVE_LIBWEBP=1`

#### Link Required Frameworks

Add these frameworks to your target:
- `VideoToolbox.framework` (for AVIF hardware acceleration)
- `CoreMedia.framework` (for AVIF)
- `CoreVideo.framework` (for AVIF)

### 5. Build Configuration

#### For Debug Builds
```bash
xcodebuild -workspace ImageOptim.xcworkspace -scheme ImageOptim -configuration Debug
```

#### For Release Builds
```bash
xcodebuild -workspace ImageOptim.xcworkspace -scheme ImageOptim -configuration Release
```

## Manual Library Installation (Alternative)

If the automated setup doesn't work, you can install libraries manually:

### Manual libavif Installation

```bash
# Clone and build libavif
git clone https://github.com/AOMediaCodec/libavif.git
cd libavif
mkdir build && cd build

# Install codec dependencies
brew install dav1d aom

# Configure and build
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DBUILD_SHARED_LIBS=OFF \
         -DAVIF_CODEC_DAV1D=ON \
         -DAVIF_CODEC_AOM=ON \
         -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"
make -j$(sysctl -n hw.ncpu)
```

### Manual WebP Installation

```bash
# Install via Homebrew
brew install webp

# Or build from source
git clone https://chromium.googlesource.com/webm/libwebp
cd libwebp
./autogen.sh
./configure --enable-static --disable-shared
make -j$(sysctl -n hw.ncpu)
```

## Troubleshooting

### Common Issues

1. **"libavif.h not found"**
   - Ensure header search paths include the libavif include directory
   - Verify libavif was built successfully

2. **"Undefined symbols for libwebp"**
   - Make sure CocoaPods installed correctly
   - Check that libwebp pod is linked to your target

3. **"AVIF/WebP not supported" at runtime**
   - Verify preprocessor definitions are set correctly
   - Check that libraries are properly linked

### Verification

To verify everything is working:

1. Build the project successfully
2. Run the app and open preferences
3. Check that AVIF and WebP appear in the output format dropdown
4. Test converting an image to each format

## Performance Notes

- **AVIF**: Slower encoding but excellent compression
- **WebP**: Good balance of speed and compression
- **Hardware Acceleration**: AVIF can use VideoToolbox on supported Macs

## Distribution

When distributing your app:

1. Include all required dynamic libraries
2. Test on different macOS versions (10.15+)
3. Consider code signing requirements for the bundled libraries
4. Update your app's Info.plist to support new file types

## File Type Support

The enhanced version will automatically register support for:
- `.avif` files (if libavif is available)
- `.webp` files (if libwebp is available)
- All original ImageOptim formats (PNG, JPEG, GIF, SVG)