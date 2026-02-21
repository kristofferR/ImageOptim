# ImageOptim

ImageOptim is an enhanced image compression app based on [ImageOptim](https://imageoptim.com). It's a GUI for image optimization tools with added features for resizing and format conversion: Zopfli, PNGOUT, [OxiPNG](https://lib.rs/crates/oxipng), AdvPNG, PNGCrush, [JPEGOptim](https://github.com/tjko/jpegoptim), Jpegtran, [Guetzli](https://github.com/google/guetzli), [Gifsicle](https://kornel.ski/lossygif), [SVGO](https://github.com/svg/svgo), [svgcleaner](https://github.com/RazrFalcon/svgcleaner) and [MozJPEG](https://github.com/mozilla/mozjpeg).

## Enhanced Features

ImageOptim adds these capabilities to the original ImageOptim:

- **Pre-compression resizing**: Resize images by width, height, or fit to dimensions
- **Post-compression format conversion**: Convert to JPEG, PNG, AVIF, or WebP
- **Quality control**: Adjustable quality settings for lossy formats
- **Modern format support**: AVIF and WebP with hardware acceleration

## Building

Requires:

* Xcode
* [Rust](https://rust-lang.org/) installed via [rustup](https://www.rustup.rs/) (not Homebrew).
* [Homebrew](https://brew.sh/) for dependency management
* [CocoaPods](https://cocoapods.org/) for WebP integration

```sh
git clone --recursive https://github.com/yourusername/ImageOptim.git ImageOptim
cd ImageOptim
chmod +x Scripts/setup-dependencies.sh
./Scripts/setup-dependencies.sh
```

To get started, open `imageoptim/ImageOptim.xcworkspace`. It will automatically download and build all subprojects when run in Xcode.

In case of build errors, these sometimes help:

```sh
git submodule update --init
```

```sh
cd gifsicle # or pngquant
make clean
make
