# ImageOptim

ImageOptim is an enhanced image compression app based on [ImageOptim](https://imageoptim.com). It's a GUI for image optimization tools with added features for resizing and format conversion: PNGOUT, [OxiPNG](https://lib.rs/crates/oxipng), AdvPNG, [JPEGOptim](https://github.com/tjko/jpegoptim), [Jpegli](https://github.com/libjxl/libjxl/tree/main/lib/jpegli), [Gifsicle](https://kornel.ski/lossygif), and [SVGO](https://github.com/svg/svgo).

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
git clone --recursive <repo-url> ImageOptim
cd ImageOptim
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
```
