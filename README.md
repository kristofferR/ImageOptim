# ImageOptim

ImageOptim is an enhanced image compression app based on [ImageOptim](https://imageoptim.com). It's a GUI for image optimization tools: PNGOUT, [OxiPNG](https://lib.rs/crates/oxipng), AdvPNG, [JPEGOptim](https://github.com/tjko/jpegoptim), [Jpegli](https://github.com/libjxl/libjxl/tree/main/lib/jpegli), [Gifsicle](https://kornel.ski/lossygif), [SVGO](https://github.com/svg/svgo), plus AVIF, WebP, and JPEG XL optimizers.

## Building

Requires:

* Xcode
* [Rust](https://rust-lang.org/) installed via [rustup](https://www.rustup.rs/) (not Homebrew).
* [Homebrew](https://brew.sh/) for dependency management

```sh
git clone --recursive <repo-url> ImageOptim
cd ImageOptim
```

To get started, open `imageoptim/ImageOptim.xcodeproj`. It will automatically download and build all subprojects when run in Xcode.

In case of build errors, these sometimes help:

```sh
git submodule update --init
```

```sh
cd gifsicle # or pngquant
make clean
make
```
