#!/bin/bash
# Runs a corpus of real-world images through every codec ImageOptim ships and
# asserts the invariants that hold regardless of which encoder is underneath:
#
#   1. the file ImageOptim would keep is never larger than the input
#   2. output still decodes, at the original dimensions
#   3. a lossless pass decodes to exactly the pixels it started from
#   4. a file the worker declines is left byte-identical
#   5. nothing crashes, even on deliberately corrupt input
#
# The corpus is downloaded from upstream test suites rather than generated
# here, so the awkward cases are the ones those projects actually curate —
# interlaced and 16-bit PNGs, corrupt PNGs, monochrome and odd-sized AVIFs,
# animated AVIF sequences, and JPEG XL written by libjxl itself.
#
#   PngSuite            Willem van Schaik's PNG conformance suite
#   avif-sample-images  link-u's AVIF sample set, including .avifs animations
#   libjxl/testdata     libjxl's own test corpus
#   libjpeg-turbo       its reference JPEG
#   W3C SVG test suite  and one real-world icon
#
# Coverage spans every codec the format stack changed: Jpegli, mainline
# gifsicle, the PNG tools left after Zopfli's removal, SVGO v4, libavif and
# libjxl.
#
# Usage: tests/codec-corpus.sh [--refresh]
# Downloads are cached in tests/corpus-cache/; --refresh re-fetches them.
# Build the ImageOptim scheme first so the tools exist.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$SCRIPT_DIR/corpus-cache"
# mktemp, not a predictable name: on a shared /tmp anyone can pre-create a
# predictable directory and read or redirect every fixture written into it.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/imageoptim-corpus.XXXXXX")" || exit 1

[ "${1:-}" = "--refresh" ] && rm -rf "$CACHE_DIR"

PASS=0; FAIL=0; SKIP=0

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s — %s\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  skip  %s (%s)\n' "$1" "$2"; }

# --- tools -------------------------------------------------------------------

find_tools() {
    # Every checkout shares one DerivedData directory, so ask Xcode where this
    # project's products go and use that answer alone — a stale bundle from
    # another checkout, whether in DerivedData or left behind in the tree, would
    # let the corpus pass having exercised codecs this checkout never built. The
    # in-tree paths are only for when xcodebuild cannot answer at all: falling
    # back to them once it has answered would pick up such a bundle whenever the
    # products directory it named is simply not built yet.
    local candidates=()
    local built
    built="$(xcodebuild -project "$ROOT_DIR/imageoptim/ImageOptim.xcodeproj" \
        -target ImageOptim -configuration Release -showBuildSettings 2>/dev/null |
        /usr/bin/awk '/^ *BUILT_PRODUCTS_DIR = /{sub(/^ *BUILT_PRODUCTS_DIR = /, ""); print; exit}')"
    if [ -n "$built" ]; then
        candidates+=("$built/ImageOptim.app/Contents/Frameworks/ImageOptimGPL.framework/Versions/A/Resources")
    else
        candidates+=(
            "$ROOT_DIR/imageoptim/build/Release/ImageOptim.app/Contents/Frameworks/ImageOptimGPL.framework/Versions/A/Resources"
            "$ROOT_DIR/build/Release/ImageOptim.app/Contents/Frameworks/ImageOptimGPL.framework/Versions/A/Resources"
        )
    fi

    local dir
    for dir in "${candidates[@]}"; do
        if [ -x "$dir/jpegtran" ]; then TOOLS="$dir"; return 0; fi
    done
    return 1
}

if ! find_tools; then
    echo "error: could not find the bundled tools; build the ImageOptim scheme first" >&2
    exit 1
fi
echo "tools: $TOOLS"

# --- corpus ------------------------------------------------------------------

# Pinned to commits, not branch heads: a corpus that followed master would let
# the same ImageOptim commit test different bytes on a machine whose cache is
# cold, and an upstream rewrite or deletion would quietly drop one of the
# characteristics this harness claims to cover. The W3C URLs below are already a
# dated snapshot, and PngSuite is pinned by archive digest.
AVIF_BASE="https://raw.githubusercontent.com/link-u/avif-sample-images/c666a368b73006246694919b5dbcc078317af6cc"
JXL_BASE="https://raw.githubusercontent.com/libjxl/testdata/73695d303670c90e4d506ea89d9901b081385089"

# "<destination name>|<url>"
CORPUS=(
    # AVIF: bit depths, monochrome, odd dimensions, alpha, and animations
    "avif-8bpc-yuv420.avif|$AVIF_BASE/fox.profile0.8bpc.yuv420.avif"
    "avif-10bpc-yuv420.avif|$AVIF_BASE/fox.profile0.10bpc.yuv420.avif"
    "avif-8bpc-monochrome.avif|$AVIF_BASE/fox.profile0.8bpc.yuv420.monochrome.avif"
    "avif-8bpc-odd-size.avif|$AVIF_BASE/fox.profile0.8bpc.yuv420.odd-width.odd-height.avif"
    "avif-animated-8bpc.avifs|$AVIF_BASE/star-8bpc.avifs"
    "avif-animated-alpha.avifs|$AVIF_BASE/star-8bpc-with-alpha.avifs"

    # JPEG XL, written by libjxl
    "jxl-pq-gradient.jxl|$JXL_BASE/jxl/pq_gradient.jxl"
    "jxl-splines.jxl|$JXL_BASE/jxl/splines.jxl"

    # A real animated GIF
    "gif-animation-patches.gif|$JXL_BASE/jxl/animation_patches.gif"

    # libjpeg-turbo's reference JPEG
    "jpeg-testorig.jpg|https://raw.githubusercontent.com/libjpeg-turbo/libjpeg-turbo/52da6095c9986f485e29d9f51bd9042f7911681a/testimages/testorig.jpg"

    # SVG: two W3C conformance cases and a real-world icon. The gradient case is
    # the one that carries url(#…) references, which is what the audit below
    # needs to have anything to say about cleanupIds.
    "svg-w3c-struct-image.svg|https://www.w3.org/Graphics/SVG/Test/20110816/svg/struct-image-01-t.svg"
    "svg-w3c-gradients.svg|https://www.w3.org/Graphics/SVG/Test/20110816/svg/pservers-grad-01-b.svg"
    "svg-bootstrap-gear.svg|https://raw.githubusercontent.com/twbs/icons/e3ba0e23490599192547000a7f78652342339e28/icons/gear.svg"
)

# PngSuite carries the awkward PNGs: interlaced, 16-bit, palette+tRNS, and a
# set of deliberately corrupt files.
PNGSUITE_URL="http://www.schaik.com/pngsuite/PngSuite-2017jul19.tgz"
# schaik.com serves no HTTPS, so the archive is authenticated by digest before
# anything is unpacked from it.
PNGSUITE_SHA256="0294b244c95a8342c01b00010cf34abdcabc7c6a34fd0fe1bd963917537bfdc8"
PNGSUITE_WANTED=(
    basn0g01.png  # 1-bit grayscale
    basn0g16.png  # 16-bit grayscale
    basn2c08.png  # 8-bit RGB
    basn2c16.png  # 16-bit RGB
    basn3p08.png  # 256-colour palette
    basn4a08.png  # grayscale + alpha
    basn6a08.png  # RGBA
    basi2c08.png  # interlaced RGB
    basi6a08.png  # interlaced RGBA
    tbbn3p08.png  # palette with tRNS
    s01i3p01.png  # 1x1 interlaced
    s40i3p04.png  # 40x40 interlaced palette
    xdtn0g01.png  # corrupt: missing IDAT chunk
    xcrn0g04.png  # corrupt: stray CR bytes injected
)

# Names of the inputs that could not be fetched or unpacked; each one is
# reported as a failure below, so a codec is never left unexercised without
# saying so.
MISSING=()

# The wanted PngSuite entries that are not in the cache, one per line. Looking
# at a single file would let an interrupted extraction — or cases deleted from
# the cache afterwards — leave most PNG variants untested.
pngsuite_missing() {
    local want
    for want in "${PNGSUITE_WANTED[@]}"; do
        [ -n "$(find "$CACHE_DIR/pngsuite" -name "$want" -type f 2>/dev/null | head -1)" ] || echo "$want"
    done
}

fetch_corpus() {
    local entry name url want
    mkdir -p "$CACHE_DIR"
    for entry in "${CORPUS[@]}"; do
        name="${entry%%|*}"; url="${entry#*|}"
        [ -s "$CACHE_DIR/$name" ] && continue
        if ! curl -sL --fail --max-time 60 -o "$CACHE_DIR/$name.part" "$url"; then
            rm -f "$CACHE_DIR/$name.part"
            echo "  could not fetch $name" >&2
            MISSING+=("$name")
            continue
        fi
        mv "$CACHE_DIR/$name.part" "$CACHE_DIR/$name"
    done

    if [ -n "$(pngsuite_missing)" ]; then
        mkdir -p "$CACHE_DIR/pngsuite"
        if ! curl -sL --fail --max-time 120 -o "$WORK_DIR/pngsuite.tgz" "$PNGSUITE_URL"; then
            echo "  could not fetch PngSuite" >&2
            MISSING+=("PngSuite")
        elif [ "$(/usr/bin/shasum -a 256 "$WORK_DIR/pngsuite.tgz" | cut -d' ' -f1)" != "$PNGSUITE_SHA256" ]; then
            echo "  PngSuite archive does not match its pinned checksum; not extracting" >&2
            MISSING+=("PngSuite")
        elif ! tar xzf "$WORK_DIR/pngsuite.tgz" -C "$CACHE_DIR/pngsuite" 2>/dev/null; then
            # Without this the PNG cases below would all report as skips and the
            # harness could pass having exercised neither PNG codec.
            echo "  could not unpack PngSuite" >&2
            MISSING+=("PngSuite")
        else
            # A case the archive turned out not to hold is a failure too: it is
            # a PNG variant nothing else in the corpus covers.
            for want in $(pngsuite_missing); do
                echo "  $want is not in the PngSuite archive" >&2
                MISSING+=("pngsuite/$want")
            done
        fi
    fi
}

echo
echo "fetching corpus into $CACHE_DIR"
fetch_corpus
if [ "${#MISSING[@]}" -gt 0 ]; then
    for name in "${MISSING[@]}"; do
        bad "fetch $name" "unavailable, so its codec goes unexercised"
    done
fi
fetched=$(find "$CACHE_DIR" -type f \( -name '*.png' -o -name '*.avif' -o -name '*.avifs' -o -name '*.jxl' -o -name '*.gif' -o -name '*.jpg' -o -name '*.svg' \) 2>/dev/null | wc -l | tr -d ' ')
echo "corpus files available: $fetched"
if [ "$fetched" -eq 0 ]; then
    echo "error: no corpus could be fetched (offline?); nothing to check" >&2
    exit 1
fi

# Work on copies so the cache stays pristine.
copy_in() { # <src> -> echoes work path
    local src=$1 dst="$WORK_DIR/$(basename "$1")"
    cp "$src" "$dst" && echo "$dst"
}

size_of() { /usr/bin/stat -f%z "$1"; }
dimensions_of() {
    /usr/bin/sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null |
        /usr/bin/awk '/pixel(Width|Height)/ {printf "%s ", $2}'
}

# sips has no AVIF or JPEG XL decoder on older macOS, but the bundled decoders
# do on every host. Decode every format to PNG before reading its dimensions:
# asking sips for dimensions directly can succeed from an intact header even
# when the compressed payload is truncated.
decoded_dimensions_of() {
    local src=$1
    local png
    png="$WORK_DIR/probe-$(basename "$src").png"
    rm -f "$png"
    case "$src" in
        *.avif|*.avifs) "$TOOLS/avifdec" "$src" "$png" >/dev/null 2>&1 ;;
        *.jxl)          "$TOOLS/djxl" "$src" "$png" >/dev/null 2>&1 ;;
        *)              /usr/bin/sips -s format png "$src" --out "$png" >/dev/null 2>&1 ;;
    esac
    [ -s "$png" ] && dimensions_of "$png"
}

# A digest of what a file decodes to, blind to how those pixels were encoded;
# empty when nothing here reads the format. Every lossless pass below is free to
# re-represent the same image — reorder a palette, narrow the bit depth,
# de-interlace, drop chunks, or rewrite the RGB underneath fully transparent
# pixels, which pngcrush's -blacken and oxipng's -a do by design — so the
# comparison has to happen after a decode, and after oxipng has normalised what
# survives it. libjxl does the PNG and JPEG decoding rather than sips because
# ImageIO decodes a progressive JPEG slightly differently from the baseline file
# it was made from, which is no fault of jpegtran's; -j 0 keeps cjxl out of its
# JPEG transcoding mode, so it decodes the pixels instead of repacking them.
pixels_of() {
    local src=$1 base png canon
    base="pixels-$(basename "$src")"
    png="$WORK_DIR/$base.png"
    canon="$WORK_DIR/$base.canon.png"
    rm -f "$png" "$canon"
    case "$src" in
        *.avif|*.avifs) "$TOOLS/avifdec" "$src" "$png" >/dev/null 2>&1 ;;
        *.jxl)          "$TOOLS/djxl" "$src" "$png" >/dev/null 2>&1 ;;
        *)              "$TOOLS/cjxl" -q 100 -j 0 -e 1 "$src" "$WORK_DIR/$base.jxl" >/dev/null 2>&1 &&
                            "$TOOLS/djxl" "$WORK_DIR/$base.jxl" "$png" >/dev/null 2>&1 ;;
    esac
    [ -s "$png" ] || return 0
    "$TOOLS/oxipng" --strip=all -i0 -o2 -a --out "$canon" -- "$png" >/dev/null 2>&1 || return 0
    /usr/bin/shasum -a 256 "$canon" | cut -d' ' -f1
}

# What a lossless pass must not do: change the image. Size and dimensions alone
# would let a codec regression that shifted colours or alpha through the whole
# corpus. The input digest is taken once per file by the caller.
assert_same_pixels() {
    local name=$1 before=$2 after=$3 after_pixels
    if [ -z "$before" ]; then
        skip "$name pixels" "no decoder here reads this format"
        return
    fi
    after_pixels=$(pixels_of "$after")
    if [ -z "$after_pixels" ]; then
        bad "$name pixels" "output does not decode, though the input did"
    elif [ "$before" != "$after_pixels" ]; then
        bad "$name pixels" "a lossless pass changed the decoded image"
    else
        ok "$name kept every pixel it decoded from"
    fi
}

# Gifsicle's unoptimized frames are the complete images a viewer renders, not
# the rectangular patches an optimized animation stores. Hash each one after
# decoding so palette reordering is harmless but any visible pixel change is
# caught.
gif_rendered_frames_of() {
    local src=$1 frame_dir frame_copy frame frame_pixels
    local found=0 digests=
    frame_dir="$WORK_DIR/gif-frames-$(basename "$src")"
    frame_copy="$frame_dir/input.gif"
    rm -rf "$frame_dir"
    mkdir -p "$frame_dir"
    cp "$src" "$frame_copy" || return 1
    "$TOOLS/gifsicle" --explode --unoptimize "$frame_copy" >/dev/null 2>&1 || return 1
    for frame in "$frame_copy".[0-9][0-9][0-9]; do
        [ -f "$frame" ] || continue
        frame_pixels=$(pixels_of "$frame")
        [ -n "$frame_pixels" ] || return 1
        digests="${digests}${frame_pixels}"$'\n'
        found=1
    done
    [ "$found" -eq 1 ] || return 1
    printf '%s' "$digests"
}

# SVGO's output has to preserve the rendered image, not merely remain XML.
# Render both documents through the host SVG decoder at a fixed size. The lite
# mode is byte-exact; the lossy mode allows tiny antialiasing/rounding changes
# but rejects a shifted colour or a missing graphical element.
svg_rasterize() {
    local src=$1 out=$2
    rm -f "$out"
    /usr/bin/sips -s format bmp -z 256 256 "$src" --out "$out" >/dev/null 2>&1 &&
        [ -s "$out" ]
}

svg_visual_difference() {
    local before=$1 after=$2
    /usr/bin/paste \
        <(/usr/bin/hexdump -v -e '1/1 "%u\n"' "$before") \
        <(/usr/bin/hexdump -v -e '1/1 "%u\n"' "$after") |
        /usr/bin/awk '{
            difference = $1 - $2
            if (difference < 0) difference = -difference
            total += difference
            if (difference > 8) large++
            bytes++
        }
        END {
            mean = bytes ? total / bytes : 999
            fraction = bytes ? large / bytes : 1
            printf "mean byte error %.3f; %.3f%% differ by more than 8", mean, fraction * 100
            exit !(bytes && mean <= 1 && fraction <= 0.001)
        }'
}

# The worker contract: it replaces the file only when the result is smaller, so
# a pass that grows a file is discarded, not wrong. What must never happen is
# corrupt output or changed dimensions.
assert_pass() {
    local name=$1 before=$2 after=$3
    if [ ! -s "$after" ]; then bad "$name" "produced no output"; return; fi
    local sb sa db da
    sb=$(size_of "$before"); sa=$(size_of "$after")
    db=$(decoded_dimensions_of "$before"); da=$(decoded_dimensions_of "$after")
    if [ -z "$db" ]; then
        # Nothing here can read the input, so nothing can judge the output
        # either. Say so rather than let the invariant pass unchecked.
        skip "$name decodes" "no decoder here reads this format"
    elif [ -z "$da" ]; then
        bad "$name" "output does not decode, though the input did"
        return
    elif [ "$db" != "$da" ]; then
        bad "$name" "dimensions changed: [$db] -> [$da]"
        return
    fi
    if [ "$sa" -gt "$sb" ]; then
        ok "$name (${sb} -> ${sa} bytes; larger, so the worker discards it)"
    else
        ok "$name (${sb} -> ${sa} bytes)"
    fi
}

# Corrupt input must be refused cleanly: a non-zero exit is fine and makes the
# worker discard its temporary copy, a signal is not, and a tool that claims
# success has to leave behind something that still decodes.
assert_corrupt() {
    local name=$1 rc=$2 before=$3 after=$4
    if [ "$rc" -ge 128 ]; then
        bad "$name" "died with a signal (exit $rc)"
    elif [ "$rc" -ne 0 ]; then
        ok "$name (corrupt input refused; temporary output discarded)"
    elif cmp -s "$before" "$after"; then
        ok "$name (corrupt input accepted, file untouched)"
    elif [ ! -s "$after" ]; then
        bad "$name" "exited 0 but left no output"
    elif [ -z "$(decoded_dimensions_of "$after")" ]; then
        bad "$name" "exited 0 but the rewritten file does not decode"
    else
        ok "$name (corrupt input accepted and rewritten to a decodable file)"
    fi
}

# The same contract for a tool that writes to a separate path, as OxiPngWorker
# and PngCrushWorker do: there is no input file to leave untouched, so a clean
# refusal is one that leaves behind nothing the worker would keep. The optional
# fourth argument is the size at or below which the worker discards the output —
# 70 bytes for pngcrush, whose failure mode is a header-only PNG.
assert_corrupt_out() {
    local name=$1 rc=$2 out=$3 discard_at_or_below=${4:-0}
    if [ "$rc" -ge 128 ]; then
        bad "$name" "died with a signal (exit $rc)"
    elif [ "$rc" -ne 0 ]; then
        ok "$name (corrupt input refused)"
    elif [ ! -s "$out" ] || [ "$(size_of "$out")" -le "$discard_at_or_below" ]; then
        ok "$name (corrupt input accepted, but nothing the worker would keep)"
    elif [ -z "$(decoded_dimensions_of "$out")" ]; then
        bad "$name" "exited 0 but the output does not decode"
    else
        ok "$name (corrupt input accepted and rewritten to a decodable file)"
    fi
}

# --- JPEG: Jpegli, through jpegtran and jpegoptim ----------------------------

echo
echo "JPEG — jpegtran and jpegoptim linked against Jpegli"
JPEG_LOSSY_RETAINED=0
for src in "$CACHE_DIR"/jpeg-*.jpg; do
    [ -f "$src" ] || continue
    n=$(basename "$src")
    f=$(copy_in "$src")
    # Taken once: everything jpegtran does here, and jpegoptim's lossless set,
    # only rewrites the entropy coding, so every one of those outputs has to
    # decode to exactly these pixels.
    pixels=$(pixels_of "$f")
    if "$TOOLS/jpegtran" -copy none -optimize -outfile "$WORK_DIR/jt-$n" "$f" 2>/dev/null; then
        assert_pass "jpegtran $n" "$f" "$WORK_DIR/jt-$n"
        assert_same_pixels "jpegtran $n" "$pixels" "$WORK_DIR/jt-$n"
    else
        bad "jpegtran $n" "exited non-zero"
    fi
    if "$TOOLS/jpegtran" -copy none -progressive -outfile "$WORK_DIR/jp-$n" "$f" 2>/dev/null; then
        assert_pass "jpegtran -progressive $n" "$f" "$WORK_DIR/jp-$n"
        assert_same_pixels "jpegtran -progressive $n" "$pixels" "$WORK_DIR/jp-$n"
    else
        bad "jpegtran -progressive $n" "exited non-zero"
    fi
    # JpegoptimWorker's own argument sets, verbose output and all, merged the way
    # the worker merges it: the lossless default, and the -m<quality> progressive
    # set it switches to once LossyEnabled is on, at the shipped max quality.
    for jomode in "lossless:--strip-all --all-normal" "lossy:-m80 --strip-all --all-progressive"; do
        jotag="${jomode%%:*}"; joargs="${jomode#*:}"
        out="$WORK_DIR/jo-$jotag-$n"
        cp "$f" "$out"
        if jo_out=$("$TOOLS/jpegoptim" $joargs -v -- "$out" 2>&1); then
            assert_pass "jpegoptim $jotag $n" "$f" "$out"
            # Only the lossless set promises the pixels back; -m80 re-quantizes.
            if [ "$jotag" = lossless ]; then
                assert_same_pixels "jpegoptim $jotag $n" "$pixels" "$out"
            elif [ "$(( $(size_of "$out") * 100 ))" -lt "$(( $(size_of "$f") * 95 ))" ]; then
                JPEG_LOSSY_RETAINED=$((JPEG_LOSSY_RETAINED+1))
            fi
            # The worker takes the optimized size from the number after " --> " and
            # keeps the temp file only once that parse succeeded, so losing this
            # line would make ImageOptim discard every jpegoptim result.
            if grep -Eq ' --> +[0-9]+' <<< "$jo_out"; then
                ok "jpegoptim -v still prints the size line JpegoptimWorker parses for $jotag $n"
            else
                bad "jpegoptim size probe $jotag $n" "no ' --> <size>' line, so fileSizeOptimized would stay zero"
            fi
        else
            bad "jpegoptim $jotag $n" "exited non-zero"
        fi
    done
done
if [ "$JPEG_LOSSY_RETAINED" -gt 0 ]; then
    ok "jpegoptim lossy produced $JPEG_LOSSY_RETAINED result(s) JpegoptimWorker would retain"
else
    bad "jpegoptim lossy retention" "no result cleared JpegoptimWorker's 5% minimum-savings gate"
fi

# --- PNG: the tools left after Zopfli's removal ------------------------------

echo
echo "PNG — PngSuite through OxiPNG, PNGCrush, PNGOUT and AdvPNG"

# PngCrushWorker's own argument set. It turns -rem alla and -brute on
# independently — the first from its strip setting, the second from the level or
# from the input being small — so at the shipped level 4 a stripped PNG of 2 KiB
# or more runs without -brute, while a higher level can brute-force with
# stripping off. Each combination the worker can produce gets its own run, so a
# regression confined to one of them cannot pass here.
PNGCRUSH_MODES=("plain:" "strip:-rem alla" "brute:-brute" "strip-brute:-rem alla -brute")
# A run that declines one variant is tolerable, but if a mode declines every
# valid PNG the loop below records nothing but skips, and the summary ignores
# skips — so the harness would pass having never seen the tool produce a result,
# while the worker would decline every PNG in production.
PNG_VALID=0
PNGCRUSH_SUCCEEDED=""

# PNGOUT and AdvPNG are what the shipped defaults actually enable for PNG —
# PngCrush2Enabled is false there — so a broken or missing bundle copy of either
# degrades every normal PNG run while the two tools above still pass.
PNGOUT_AVAILABLE=1
[ -x "$TOOLS/pngout" ] || { bad "pngout" "not in the bundle, though the shipped defaults enable PngoutWorker"; PNGOUT_AVAILABLE=0; }
ADVPNG_AVAILABLE=1
[ -x "$TOOLS/advpng" ] || { bad "advpng" "not in the bundle, though the shipped defaults enable AdvCompWorker"; ADVPNG_AVAILABLE=0; }

# PngoutWorker's own argument set. -r and -v are on every run; -k1 appears only
# when PngOutRemoveChunks is off, and -s1 only for a PNG the app calls large, so
# each combination the worker can build gets its own run.
PNGOUT_MODES=("plain:-r" "keep:-k1 -r" "large:-s1 -r" "keep-large:-s1 -k1 -r")
PNGOUT_SUCCEEDED=""

for want in "${PNGSUITE_WANTED[@]}"; do
    src=$(find "$CACHE_DIR/pngsuite" -name "$want" -type f 2>/dev/null | head -1)
    # An absent case is already counted as a failure by fetch_corpus, so this
    # only says which codecs went unexercised because of it.
    if [ -z "$src" ]; then skip "pngsuite $want" "not in the corpus; reported as a fetch failure"; continue; fi
    corrupt=0
    case "$want" in x*) corrupt=1 ;; esac
    [ "$corrupt" -eq 0 ] && PNG_VALID=$((PNG_VALID+1))
    f=$(copy_in "$src")
    # Every PNG tool here is a lossless pass, so each output is compared against
    # the pixels of this file. A corrupt input has none worth preserving.
    pixels=
    [ "$corrupt" -eq 0 ] && pixels=$(pixels_of "$f")

    # OxiPngWorker's own argument set: the shipped level with metadata stripping,
    # written to a separate path rather than in place, as the worker does.
    out="$WORK_DIR/ox-$want"
    rm -f "$out"
    "$TOOLS/oxipng" --strip=safe -o4 -i0 -a --out "$out" -- "$f" >/dev/null 2>&1
    rc=$?
    if [ "$corrupt" -eq 1 ]; then
        assert_corrupt_out "oxipng $want (corrupt)" "$rc" "$out"
    elif [ "$rc" -eq 0 ]; then
        # oxipng copies the input across when it cannot improve on it, so an
        # already-optimal PNG still leaves a file the worker would compare.
        assert_pass "oxipng $want" "$f" "$out"
        assert_same_pixels "oxipng $want" "$pixels" "$out"
    else
        bad "oxipng $want" "exited $rc on a valid PNG"
    fi

    # pngcrush, written to a separate path as the worker does.
    for pcmode in "${PNGCRUSH_MODES[@]}"; do
        pctag="${pcmode%%:*}"; pcextra="${pcmode#*:}"
        out="$WORK_DIR/pc-$pctag-$want"
        rm -f "$out"
        "$TOOLS/pngcrush" $pcextra -nofilecheck -bail -blacken -reduce -cc -- "$f" "$out" >/dev/null 2>&1
        rc=$?
        label="pngcrush $pctag $want"
        if [ "$corrupt" -eq 1 ]; then
            # PngCrushWorker keeps the output only above 70 bytes, because
            # pngcrush's failure mode is a header-only PNG of exactly that size.
            assert_corrupt_out "$label (corrupt)" "$rc" "$out" 70
        elif [ "$rc" -ge 128 ]; then
            bad "$label" "died with a signal (exit $rc)"
        elif [ "$rc" -eq 0 ]; then
            if [ -s "$out" ]; then
                assert_pass "$label" "$f" "$out"
                assert_same_pixels "$label" "$pixels" "$out"
                case " $PNGCRUSH_SUCCEEDED " in
                    *" $pctag "*) ;;
                    *) PNGCRUSH_SUCCEEDED="$PNGCRUSH_SUCCEEDED $pctag" ;;
                esac
            else
                bad "$label" "exited 0 without writing an output file"
            fi
        elif [ -s "$out" ]; then
            # Only a clean refusal that writes nothing is tolerable here; a
            # crash, or a failure that still wrote a file, is a real failure.
            bad "$label" "exited $rc on a valid PNG and still wrote an output file"
        else
            skip "$label" "declined this variant, nothing written"
        fi
    done

    # pngout, writing the PNG to stdout as the worker does — that is what forces
    # the progress output onto stderr, which is where the worker reads the size
    # it needs before it keeps anything.
    for pomode in "${PNGOUT_MODES[@]}"; do
        [ "$PNGOUT_AVAILABLE" -eq 1 ] || continue
        potag="${pomode%%:*}"; poargs="${pomode#*:}"
        out="$WORK_DIR/po-$potag-$want"
        rm -f "$out"
        po_out=$("$TOOLS/pngout" $poargs -v "$f" - 2>&1 >"$out")
        rc=$?
        label="pngout $potag $want"
        # PngoutWorker takes the optimized size from the "Out:" line and keeps the
        # temp file only once that parse succeeded, so losing the line would make
        # ImageOptim discard every pngout result. It splits on CR as well as LF,
        # since pngout writes its progress with CR.
        po_size_line=0
        tr '\r' '\n' <<< "$po_out" | grep -Eq '^Out: *[0-9]+' && po_size_line=1
        if [ "$corrupt" -eq 1 ]; then
            # Status 2 is pngout's accepted early exit: with an Out: size,
            # PngoutWorker keeps the file just as it does for status 0. Validate
            # that output instead of counting every non-zero status as refusal.
            if { [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; } && [ "$po_size_line" -eq 1 ]; then
                assert_corrupt_out "$label (corrupt)" 0 "$out"
            elif [ "$rc" -ge 128 ]; then
                bad "$label (corrupt)" "died with a signal (exit $rc)"
            else
                ok "$label (corrupt input refused; nothing PngoutWorker would keep)"
            fi
        elif [ "$rc" -ge 128 ]; then
            bad "$label" "died with a signal (exit $rc)"
        # The worker discards every status but 0 and pngout's early-exit 2, and
        # even those only with a size to hand on, so a file written alongside any
        # other status is not a result this harness may count.
        elif { [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; } && [ -s "$out" ] && [ "$po_size_line" -eq 1 ]; then
            assert_pass "$label" "$f" "$out"
            assert_same_pixels "$label" "$pixels" "$out"
            ok "pngout -v still prints the size line PngoutWorker parses for $potag $want"
            case " $PNGOUT_SUCCEEDED " in
                *" $potag "*) ;;
                *) PNGOUT_SUCCEEDED="$PNGOUT_SUCCEEDED $potag" ;;
            esac
        elif [ "$rc" -eq 0 ]; then
            # Exit 0 is a run ImageOptim would keep, so anything missing from it
            # is a failure rather than pngout declining the variant.
            if [ ! -s "$out" ]; then
                bad "$label" "exited 0 without writing anything to stdout"
            else
                bad "pngout size probe $potag $want" "no 'Out: <size>' line, so fileSizeOptimized would stay zero"
            fi
        else
            # pngout exits non-zero when it cannot improve on the input, and the
            # worker keeps nothing in that case either.
            skip "$label" "declined this variant (exit $rc), nothing the worker would keep"
        fi
    done

    # AdvCompWorker's own run: the shipped level, in place on a temp copy. It is
    # scheduled only when PngOutRemoveChunks is on, which the shipped defaults
    # have it be, and the level is the only thing that varies.
    if [ "$ADVPNG_AVAILABLE" -eq 1 ]; then
        out="$WORK_DIR/ad-$want"
        cp "$f" "$out"
        ad_out=$("$TOOLS/advpng" -4 -z -- "$out" 2>&1)
        rc=$?
        label="advpng $want"
        if [ "$corrupt" -eq 1 ]; then
            assert_corrupt "$label (corrupt)" "$rc" "$f" "$out"
        elif [ "$rc" -ne 0 ]; then
            bad "$label" "exited $rc on a valid PNG"
        else
            assert_pass "$label" "$f" "$out"
            assert_same_pixels "$label" "$pixels" "$out"
            # The worker reads the optimized size from the second number of the
            # first line that holds a pair, exactly as NSScanner does, and hands
            # it to tempCopyOfPath:size:, which drops the result unless it matches
            # the file advpng actually wrote. A pair that no longer is that size
            # therefore loses every advpng result, so compare the value itself.
            ad_reported=$(/usr/bin/awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print $2; exit }' <<< "$ad_out")
            if [ -z "$ad_reported" ]; then
                bad "advpng size probe $want" "no '<original> <optimized>' line, so AdvCompWorker would keep nothing"
            elif [ "$ad_reported" != "$(size_of "$out")" ]; then
                bad "advpng size probe $want" "reports $ad_reported bytes for a file of $(size_of "$out"), so tempCopyOfPath:size: would drop it"
            else
                ok "advpng still reports the optimized size AdvCompWorker parses for $want"
            fi
        fi
    fi
done

# Declining every valid PNG is not a variant the tool dislikes, it is a mode that
# no longer works — one of the worker's mandatory flags gone, say.
if [ "$PNG_VALID" -gt 0 ]; then
    for pcmode in "${PNGCRUSH_MODES[@]}"; do
        pctag="${pcmode%%:*}"
        case " $PNGCRUSH_SUCCEEDED " in
            *" $pctag "*) ok "pngcrush $pctag produced a result for at least one of the $PNG_VALID valid PNGs" ;;
            *) bad "pngcrush $pctag" "declined all $PNG_VALID valid PNGs, so PngCrushWorker would never keep an output" ;;
        esac
    done
    if [ "$PNGOUT_AVAILABLE" -eq 1 ]; then
        for pomode in "${PNGOUT_MODES[@]}"; do
            potag="${pomode%%:*}"
            case " $PNGOUT_SUCCEEDED " in
                *" $potag "*) ok "pngout $potag produced a result for at least one of the $PNG_VALID valid PNGs" ;;
                *) bad "pngout $potag" "declined all $PNG_VALID valid PNGs, so PngoutWorker would never keep an output" ;;
            esac
        done
    fi
fi

# --- GIF: mainline gifsicle --------------------------------------------------

echo
echo "GIF — mainline gifsicle, including the --lossy path from giflossy"

# Everything GifsicleWorker passes on every run. --careful in particular works
# around a Safari/Preview decoding bug, so a build that rejected it would make
# ImageOptim fail every GIF while a bare -O3 run still succeeded.
GIF_WORKER_OPTS="-O3 --careful --no-comments --no-names --same-delay --same-loopcount --no-warnings"

# GifsicleWorker derives --lossy from the configured quality and the input size
# rather than passing a fixed value, so the corpus derives it the same way. A
# hard-coded number would leave the argument ImageOptim actually runs — 6, 22 or
# 43 at the shipped quality of 80, depending on the size — unexercised.
GIF_QUALITY=80
GIF_LOSSY_RETAINED=0
gif_lossy_for() { # <file> -> the --lossy value GifsicleWorker would pass for it
    /usr/bin/awk -v q="$GIF_QUALITY" -v size="$(size_of "$1")" 'BEGIN {
        loss = int((100 - q) ^ 1.8 / 5.0)
        if (size < 10 * 1024)         loss = 1 + int(loss / 8)   # isSmall: spare GIF icons
        else if (size <= 1024 * 1024) loss = 1 + int(loss / 2)   # !isLarge: spare GIF images
        print loss
    }'
}

# The frame delays and loop count gifsicle reports, which --same-delay and
# --same-loopcount are there to preserve.
timing_of() {
    "$TOOLS/gifsicle" --info "$1" 2>/dev/null |
        grep -Eo 'delay [0-9.]+s|loop( count [0-9]+| forever)'
}

for src in "$CACHE_DIR"/gif-*.gif; do
    [ -f "$src" ] || continue
    n=$(basename "$src")
    f=$(copy_in "$src")
    rendered_frames=$(gif_rendered_frames_of "$f")
    if [ -z "$rendered_frames" ]; then
        bad "gifsicle input frames $n" "could not decode every rendered frame"
    fi
    lossy=$(gif_lossy_for "$f")
    for mode in "plain:--no-interlace" "interlaced:--interlace" "lossy:--no-interlace --lossy=$lossy"; do
        tag="${mode%%:*}"; opts="${mode#*:}"
        label="gifsicle $tag $n"
        outfile="$WORK_DIR/gs-$tag-$n"
        if "$TOOLS/gifsicle" $opts $GIF_WORKER_OPTS -o "$outfile" -- "$f" 2>/dev/null && [ -s "$outfile" ]; then
            if "$TOOLS/gifsicle" --info "$outfile" >/dev/null 2>&1; then
                assert_pass "$label" "$f" "$outfile"
            else
                bad "$label" "output is not a readable GIF"
            fi
            if [ "$tag" != lossy ] && [ -n "$rendered_frames" ]; then
                output_frames=$(gif_rendered_frames_of "$outfile")
                if [ -z "$output_frames" ]; then
                    bad "$label frames" "could not decode every rendered output frame"
                elif [ "$rendered_frames" != "$output_frames" ]; then
                    bad "$label frames" "a lossless pass changed rendered frame pixels"
                else
                    ok "$label kept every rendered frame pixel"
                fi
            elif [ "$tag" = lossy ] &&
                [ "$(( $(size_of "$outfile") * (105 + (100 - GIF_QUALITY) / 2) / 100 ))" -lt "$(size_of "$f")" ]; then
                GIF_LOSSY_RETAINED=$((GIF_LOSSY_RETAINED+1))
            fi
        else
            bad "$label" "gifsicle failed (are --lossy and the worker's options present?)"
        fi
    done
    # Every output must keep every frame, and play it the same way — --lossy is
    # the path that changed, and a dropped delay or loop count is a regression
    # the frame count alone would not notice.
    fin=$("$TOOLS/gifsicle" --info "$f" 2>/dev/null | grep -c 'image #')
    if [ "$fin" -gt 1 ]; then
        tin=$(timing_of "$f")
        for tag in plain interlaced lossy; do
            fout=$("$TOOLS/gifsicle" --info "$WORK_DIR/gs-$tag-$n" 2>/dev/null | grep -c 'image #')
            if [ "$fin" = "$fout" ]; then
                ok "gifsicle $tag preserved all $fin frames of $n"
            else
                bad "gifsicle frames $tag $n" "frame count changed: $fin -> $fout"
            fi
            if [ "$tin" = "$(timing_of "$WORK_DIR/gs-$tag-$n")" ]; then
                ok "gifsicle $tag preserved the delays and loop count of $n"
            else
                bad "gifsicle timing $tag $n" "frame delays or loop count changed"
            fi
        done
    fi
done
if [ "$GIF_LOSSY_RETAINED" -gt 0 ]; then
    ok "gifsicle lossy produced $GIF_LOSSY_RETAINED result(s) GifsicleWorker would retain"
else
    bad "gifsicle lossy retention" "no result cleared GifsicleWorker's quality-$GIF_QUALITY minimum-savings gate"
fi

# --- SVG: SVGO v4 ------------------------------------------------------------

echo
echo "SVG — SVGO v4"
SVGO_JS="$TOOLS/svgo.js"
XMLLINT=/usr/bin/xmllint

# SvgoWorker accepts node at these two paths and nowhere else, so resolving it
# through PATH would run SVGO here on a host where the app declines every SVG.
NODE=
for candidate in /usr/local/bin/node /opt/homebrew/bin/node; do
    if [ -x "$candidate" ]; then NODE=$candidate; break; fi
done

# The ids a document references through url(#…), one per line.
refs_in() { grep -o 'url(#[^)]*)' "$1" | sed 's/url(#//;s/)//' | sort -u; }

if [ ! -f "$SVGO_JS" ]; then
    # find_tools already proved the bundle is there, so svgo.js missing from it
    # is a packaging error that makes SvgoWorker decline every SVG.
    bad "svgo" "svgo.js is not in the bundle, so no SVG would ever be optimized"
elif [ -z "$NODE" ]; then
    skip "svgo" "node is not at either path SvgoWorker accepts"
else
    for src in "$CACHE_DIR"/svg-*.svg; do
        [ -f "$src" ] || continue
        n=$(basename "$src")
        f=$(copy_in "$src")
        rendered_input="$WORK_DIR/sv-render-input-$n.bmp"
        input_rendered=0
        if svg_rasterize "$f" "$rendered_input"; then
            input_rendered=1
        else
            bad "svgo input render $n" "the input could not be rasterized"
        fi
        # The argument SvgoWorker passes: 0 for the default plugin list, 1 once
        # LossyEnabled turns on cleanupIds and the rest of the lossy plugins.
        for svmode in "lite:0" "lossy:1"; do
            svtag="${svmode%%:*}"; svarg="${svmode#*:}"
            out="$WORK_DIR/sv-$svtag-$n"
            rm -f "$out"
            if "$NODE" "$SVGO_JS" "$svarg" "$f" "$out" 2>/dev/null && [ -s "$out" ]; then
                sb=$(size_of "$f"); sa=$(size_of "$out")
                # The raster paths run the output through a decoder; this is the
                # equivalent for SVG, since truncated XML can still contain "<svg".
                if [ ! -x "$XMLLINT" ]; then
                    skip "svgo $svtag $n parses" "xmllint is not available here"
                elif ! "$XMLLINT" --noout "$out" 2>/dev/null; then
                    bad "svgo $svtag $n" "output is not well-formed XML"
                elif ! grep -q '<svg' "$out"; then
                    bad "svgo $svtag $n" "output parses but has no <svg> element"
                else
                    ok "svgo $svtag $n parses as XML"
                fi
                if [ "$input_rendered" -eq 1 ]; then
                    rendered_output="$WORK_DIR/sv-render-$svtag-$n.bmp"
                    if ! svg_rasterize "$out" "$rendered_output"; then
                        bad "svgo $svtag $n render" "output could not be rasterized"
                    elif [ "$svtag" = lite ]; then
                        if cmp -s "$rendered_input" "$rendered_output"; then
                            ok "svgo $svtag $n preserved the exact rendered image"
                        else
                            bad "svgo $svtag $n render" "the rendered image changed"
                        fi
                    elif visual_difference=$(svg_visual_difference "$rendered_input" "$rendered_output"); then
                        ok "svgo $svtag $n preserved the rendered image ($visual_difference)"
                    else
                        bad "svgo $svtag $n render" "visual difference is too large ($visual_difference)"
                    fi
                fi
                if [ "$sa" -gt "$sb" ]; then
                    ok "svgo $svtag $n (${sb} -> ${sa} bytes; larger, so the worker discards it)"
                else
                    ok "svgo $svtag $n (${sb} -> ${sa} bytes)"
                fi
                # Every url(#id) reference must still resolve, and none may have
                # vanished: dropping a reference along with its target is the
                # rendering regression this is here to catch. cleanupIds, which
                # only the lossy run enables, renames ids, so the input and
                # output sets are compared by count, not by name.
                dangling=0
                for ref in $(refs_in "$out"); do
                    grep -q "id=\"$ref\"" "$out" || dangling=1
                done
                rin=$(refs_in "$f" | wc -l | tr -d ' ')
                rout=$(refs_in "$out" | wc -l | tr -d ' ')
                if [ "$dangling" -ne 0 ]; then
                    bad "svgo $svtag $n" "an id referenced by url(#…) was removed"
                elif [ "$rout" -lt "$rin" ]; then
                    bad "svgo $svtag $n" "url(#…) references disappeared: $rin -> $rout"
                else
                    ok "svgo $svtag $n kept all $rin url(#…) references resolvable"
                fi
            else
                bad "svgo $svtag $n" "produced no output"
            fi
        done
    done
fi

# --- AVIF --------------------------------------------------------------------

echo
echo "AVIF — libavif, round-tripped through PNG as AVIFWorker does"

# The bit depth AVIFWorker reads out of avifdec --info, empty if that line is
# not there in the form the worker parses.
avif_depth_of() {
    "$TOOLS/avifdec" --info "$1" 2>/dev/null |
        /usr/bin/sed -n 's/^ \* Bit Depth      : \([0-9][0-9]*\).*/\1/p' | head -1
}

# Both literals AVIFWorker requires before it will touch a file at all.
avif_worker_accepts() {
    local info
    info="$("$TOOLS/avifdec" --info "$1" 2>/dev/null)"
    grep -q ' \* Gain map       : Absent' <<< "$info" &&
        grep -q ' \* Transformations: None' <<< "$info"
}

# Every fox.* sample carries a pasp box, so AVIFWorker declines all of them, and
# a round trip run only on those would stay green even if ImageOptim refused
# every AVIF it ever met. avifenc writes none of the transformation boxes, so its
# own output is the transformation-free file the worker would accept; it joins
# the corpus below and is what the string probe reads afterwards.
PLAIN_AVIF=
avif_seed=$(find "$CACHE_DIR" -name 'avif-8bpc-yuv420.avif' | head -1)
# Kept out of $WORK_DIR itself, which is where copy_in puts the working copies.
mkdir -p "$WORK_DIR/fixtures"
if [ -n "$avif_seed" ] &&
    "$TOOLS/avifdec" "$avif_seed" "$WORK_DIR/avif-plain.png" >/dev/null 2>&1 &&
    "$TOOLS/avifenc" --lossless -s 4 "$WORK_DIR/avif-plain.png" "$WORK_DIR/fixtures/avif-plain.avif" >/dev/null 2>&1; then
    PLAIN_AVIF="$WORK_DIR/fixtures/avif-plain.avif"
else
    bad "avif transformation-free fixture" "could not write one, so nothing here is an AVIF the worker would take on"
fi

# How many of the files below AVIFWorker would actually hand to avifenc.
AVIF_ELIGIBLE=0
AVIF_LOSSY_RETAINED=0

for src in "$CACHE_DIR"/avif-*.avif ${PLAIN_AVIF:+"$PLAIN_AVIF"}; do
    [ -f "$src" ] || continue
    n=$(basename "$src")
    f=$(copy_in "$src")
    avif_eligible=0
    if avif_worker_accepts "$f"; then
        avif_eligible=1
        AVIF_ELIGIBLE=$((AVIF_ELIGIBLE+1))
    fi
    depth=$(avif_depth_of "$f")
    if [ -z "$depth" ]; then
        bad "avif bit-depth probe $n" "avifdec --info no longer prints the depth AVIFWorker re-encodes with"
    fi
    # avifdec writes >8-bit images as 16-bit PNG, from which avifenc would infer
    # 12 bits, so the worker passes the original depth back. Without doing the
    # same here the round trip silently changes it.
    depthargs=
    case "$depth" in
        10|12) depthargs="-d $depth" ;;
    esac
    if "$TOOLS/avifdec" "$f" "$WORK_DIR/dec-$n.png" >/dev/null 2>&1 && [ -s "$WORK_DIR/dec-$n.png" ]; then
        # AVIFWorker's own encoder arguments: --lossless with the shipped
        # LossyEnabled=false default, -q <AvifQuality> once it is on, and speed 4
        # either way.
        for avmode in "lossless:--lossless" "lossy:-q 85"; do
            avtag="${avmode%%:*}"; avq="${avmode#*:}"
            out="$WORK_DIR/re-$avtag-$n"
            if "$TOOLS/avifenc" $avq $depthargs -s 4 "$WORK_DIR/dec-$n.png" "$out" >/dev/null 2>&1; then
                assert_pass "avif $avtag round-trip $n" "$f" "$out"
                # Only --lossless owes the pixels back; -q 85 is the lossy path.
                # Even --lossless is bit-exact only when the depth survives the
                # PNG hop: avifenc warns as much for a >8-bit image, whose 16-bit
                # PNG it has to narrow to the original depth again.
                if [ "$avtag" = lossless ] && [ -n "$depthargs" ]; then
                    skip "avif lossless round-trip $n pixels" "avifenc warns that re-encoding ${depth}-bit from a 16-bit PNG may not be lossless"
                elif [ "$avtag" = lossless ]; then
                    assert_same_pixels "avif lossless round-trip $n" "$(pixels_of "$f")" "$out"
                elif [ "$avif_eligible" -eq 1 ] &&
                    [ "$(( $(size_of "$out") * 100 ))" -le "$(( $(size_of "$f") * 95 ))" ]; then
                    AVIF_LOSSY_RETAINED=$((AVIF_LOSSY_RETAINED+1))
                fi
                if [ -n "$depth" ]; then
                    redepth=$(avif_depth_of "$out")
                    if [ "$depth" = "$redepth" ]; then
                        ok "avif $avtag round-trip $n kept its ${depth}-bit depth"
                    else
                        bad "avif depth $avtag $n" "bit depth changed: $depth -> ${redepth:-unreadable}"
                    fi
                fi
            else
                bad "avif $avtag round-trip $n" "avifenc failed on the decoded PNG"
            fi
        done
    else
        bad "avif decode $n" "avifdec failed"
    fi
done

# A round trip run only on files the worker's info guards reject says nothing
# about what ImageOptim does with an AVIF.
if [ "$AVIF_ELIGIBLE" -gt 0 ]; then
    ok "avif round-tripped $AVIF_ELIGIBLE file(s) AVIFWorker would hand to avifenc"
else
    bad "avif worker eligibility" "no AVIF here passes AVIFWorker's info guards, so the round trips above prove nothing about the app"
fi
if [ "$AVIF_LOSSY_RETAINED" -gt 0 ]; then
    ok "avif lossy produced $AVIF_LOSSY_RETAINED result(s) AVIFWorker would retain"
else
    bad "avif lossy retention" "no eligible result cleared AVIFWorker's 5% minimum-savings gate"
fi

# Animated AVIF must be recognisable as such: AVIFWorker keys on the avis brand
# in the ftyp box and declines the file, because avifenc cannot re-encode a
# sequence. Confirm real-world .avifs files actually carry that brand.
for src in "$CACHE_DIR"/*.avifs; do
    [ -f "$src" ] || continue
    n=$(basename "$src")
    if head -c 64 "$src" | grep -q 'avis'; then
        ok "$n carries the avis brand, so AVIFWorker declines it"
    else
        bad "$n" "no avis brand in the ftyp box — AVIFWorker would try to re-encode an animation"
    fi
done

# AVIFWorker requires two literal strings in avifdec --info, and the worker
# pipes only stdout, so stderr is discarded here too: output that moved to
# stderr, or either line changing shape, would make the worker decline every
# file. The transformations line only reads "None" for a file carrying no
# clap/irot/imir/pasp box, and every fox.* sample carries a pasp, so that
# literal is probed on the transformation-free AVIF written above instead.
if [ -n "$avif_seed" ]; then
    if "$TOOLS/avifdec" --info "$avif_seed" 2>/dev/null | grep -q ' \* Gain map       : Absent'; then
        ok "avifdec --info still prints the exact gain-map line AVIFWorker matches"
    else
        bad "avif gain-map probe" "that line changed — AVIFWorker would skip every file"
    fi
fi
if [ -n "$PLAIN_AVIF" ]; then
    if "$TOOLS/avifdec" --info "$PLAIN_AVIF" 2>/dev/null | grep -q ' \* Transformations: None'; then
        ok "avifdec --info still prints the exact transformations line AVIFWorker matches"
    else
        bad "avif transformations probe" "that line changed — AVIFWorker would skip every file"
    fi
fi

# --- JPEG XL -----------------------------------------------------------------

echo
echo "JPEG XL — libjxl round-trips and the jxlinfo probe"

# The bit depths the worker's regex finds in a jxlinfo -v listing, one per line.
jxl_depths_of() { grep -Eo ', [0-9]+-bit|bits per sample: [0-9]+' <<< "$1" | grep -Eo '[0-9]+'; }

# The box checks HasUnsupportedBoxes makes on that same listing: a box type the
# round trip cannot rebuild, an ftyp holding more than the twelve bytes cjxl
# writes back, or compressed metadata that is neither Exif nor XMP. Each of them
# makes JXLWorker decline the file, so a listing that only has the right shape
# still says nothing about whether the app would touch it.
jxl_boxes_supported() { # <jxlinfo -v output>
    /usr/bin/awk '
        BEGIN { split("JXL |ftyp|jxlc|jxlp|jxll|Exif|xml |brob", t, "|"); for (i in t) supported[t[i]] = 1 }
        function metadata_ok(t) { return t == "Exif" || t == "xml " }
        /^  type: "..../                    { type = substr($0, 10, 4); if (!(type in supported)) bad = 1; next }
        /^  contents size: [0-9]+$/         { if (type == "ftyp" && $3 > 12) bad = 1; next }
        /^Uncompressed .... metadata:/      { if (!metadata_ok(substr($0, 14, 4))) bad = 1; next }
        /^Brotli-compressed .... metadata:/ { if (!metadata_ok(substr($0, 19, 4))) bad = 1; next }
        END { exit bad ? 1 : 0 }' <<< "$1"
}

# Everything canRoundTripThroughPngAtPath: requires before JXLWorker decodes a
# file at all. The probes below check that jxlinfo still prints those lines in
# the shape the worker parses; this decides whether the worker would take the
# file on, which is what makes a round trip say anything about the app.
jxl_worker_accepts() { # <jxlinfo -v output>
    local info=$1 depths
    grep -qF 'JPEG bitstream reconstruction data' <<< "$info" && return 1
    grep -qF 'alpha premultiplied: 1' <<< "$info" && return 1
    grep -Eq 'float \(|float, with exponent_bits_per_sample:' <<< "$info" && return 1
    grep -qF 'Have animation: 0' <<< "$info" || return 1
    grep -qF 'Have preview: 0' <<< "$info" || return 1
    depths=$(jxl_depths_of "$info")
    [ -n "$depths" ] || return 1
    /usr/bin/awk '$1 > 16 { over = 1 } END { exit over ? 0 : 1 }' <<< "$depths" && return 1
    jxl_boxes_supported "$info"
}

# How many of the files below JXLWorker would actually re-encode: the ones its
# info guards accept and that djxl decodes to the single image PNG can hold.
JXL_ELIGIBLE=0
JXL_LOSSY_RETAINED=0

for src in "$CACHE_DIR"/jxl-*.jxl; do
    [ -f "$src" ] || continue
    n=$(basename "$src")
    f=$(copy_in "$src")

    # canRoundTripThroughPngAtPath: refuses the file unless jxlinfo -v matches
    # every one of the things checked below, on the stdout the worker pipes:
    # output that moved to stderr, or a line that changed shape, would otherwise
    # leave ImageOptim declining every JXL while the round trip still succeeds.
    info="$("$TOOLS/jxlinfo" -v "$f" 2>/dev/null)"
    info_rc=$?
    accepts=0
    if [ "$info_rc" -ne 0 ]; then
        bad "jxlinfo $n" "exited $info_rc, so JXLWorker would decline the file"
    elif jxl_worker_accepts "$info"; then
        accepts=1
    fi

    # JXLWorker's own decode. --output_frames makes djxl write the frame as
    # <name>-0.png instead of <name>.png for some files, which is why the worker
    # looks for both; decoding into a directory of its own keeps the two apart.
    decdir="$WORK_DIR/jxl-dec-$n"
    rm -rf "$decdir"; mkdir -p "$decdir"
    if "$TOOLS/djxl" "$f" "$decdir/dec.png" --output_frames --output_extra_channels >/dev/null 2>&1; then
        # HasAdditionalDecodedFiles counts what djxl left in the directory the
        # same way and refuses anything past the first, because re-encoding one
        # image would drop the other frames or the extra channels. Round-tripping
        # it here would report a success for a file the app never processes.
        decoded=$(find "$decdir" -type f \( -name 'dec.png' -o -name 'dec-*.png' \) | wc -l | tr -d ' ')
        frame="$decdir/dec.png"
        [ -s "$frame" ] || frame="$decdir/dec-0.png"
        if [ "$decoded" -gt 1 ]; then
            skip "jxl round-trip $n" "djxl wrote $decoded images, so HasAdditionalDecodedFiles declines the file"
        elif [ ! -s "$frame" ]; then
            bad "jxl decode $n" "djxl wrote neither dec.png nor dec-0.png, so DecodedFramePath would find nothing"
        else
            # Only now is this a file ImageOptim would re-encode: its info
            # passed the worker's guards and djxl left one image behind.
            [ "$accepts" -eq 1 ] && JXL_ELIGIBLE=$((JXL_ELIGIBLE+1))
            # -q 100 -e 9 is what Job builds by default, since it creates a
            # quality-100 worker unless lossy optimization is on; -q <JxlQuality>
            # is the lossy case, at the same effort.
            for jxmode in "lossless:100" "lossy:90"; do
                jxtag="${jxmode%%:*}"; jxq="${jxmode#*:}"
                out="$WORK_DIR/re-$jxtag-$n"
                if "$TOOLS/cjxl" -q "$jxq" -e 9 "$frame" "$out" >/dev/null 2>&1; then
                    assert_pass "jxl $jxtag round-trip $n" "$f" "$out"
                    # -q 100 is cjxl's lossless mode, so the frame it was handed
                    # has to come back out of the re-encode unchanged; -q 90 is
                    # the lossy path and owes nothing.
                    if [ "$jxtag" = lossless ]; then
                        assert_same_pixels "jxl lossless round-trip $n" "$(pixels_of "$frame")" "$out"
                    elif [ "$accepts" -eq 1 ] &&
                        [ "$(( $(size_of "$out") * 100 ))" -le "$(( $(size_of "$f") * 95 ))" ]; then
                        JXL_LOSSY_RETAINED=$((JXL_LOSSY_RETAINED+1))
                    fi
                else
                    bad "jxl $jxtag round-trip $n" "cjxl failed on the decoded PNG"
                fi
            done
        fi
    else
        bad "jxl decode $n" "djxl failed"
    fi

    # The bit-depth regex, which also declines anything float or above 16 bits.
    # A bare "10-bit" without the comma the worker requires fails here too. The
    # float and depth limits are checked as well, because the round trip above
    # invokes djxl and cjxl directly: on a file the worker refuses it would keep
    # passing while ImageOptim never encodes such a JXL at all.
    depths=$(jxl_depths_of "$info")
    if [ -z "$depths" ]; then
        bad "jxl bit-depth probe $n" "jxlinfo output no longer matches the worker's regex"
    elif grep -Eq 'float \(|float, with exponent_bits_per_sample:' <<< "$info"; then
        bad "jxl bit-depth probe $n" "jxlinfo reports float samples, which JXLWorker refuses, so the round trip above tests a file ImageOptim would never encode"
    elif /usr/bin/awk '$1 > 16 { over = 1 } END { exit over ? 0 : 1 }' <<< "$depths"; then
        bad "jxl bit-depth probe $n" "jxlinfo reports a depth above 16 bits, which JXLWorker refuses, so the round trip above tests a file ImageOptim would never encode"
    else
        ok "jxlinfo -v reports bit depth for $n in the form JXLWorker parses"
    fi

    # The animation and preview flags, which the worker requires literally.
    for want_line in "Have animation: 0" "Have preview: 0"; do
        if grep -qF "$want_line" <<< "$info"; then
            ok "jxlinfo -v still prints \"$want_line\" for $n"
        else
            bad "jxl probe $n" "\"$want_line\" is missing, so JXLWorker would decline this still image"
        fi
    done

    # Container boxes, which the worker matches with a regex spanning three
    # consecutive lines; anything it cannot match reads as a box the round trip
    # would drop. A bare codestream carries none, and there is nothing to check.
    boxes=$(grep -c '^  type: "' <<< "$info")
    if [ "$boxes" -eq 0 ]; then
        skip "jxl box probe $n" "this file is a bare codestream"
    # A record cut short — the next type: arriving early, or the listing ending —
    # is a box the worker's three-line regex would not match either, so an
    # outstanding expectation counts as broken rather than being dropped.
    elif ! /usr/bin/awk '
            /^  type: "..../ { if (expect) broken = 1; expect = 2; next }
            expect == 2 { if ($0 !~ /^  size: [0-9]+$/) broken = 1; expect = 1; next }
            expect == 1 { if ($0 !~ /^  contents size: [0-9]+$/) broken = 1; expect = 0; next }
            END { exit (broken || expect) ? 1 : 0 }' <<< "$info"; then
        bad "jxl box probe $n" "the box listing no longer matches the worker's regex, so every box would read as unsupported"
    # A record the worker can read is still one it can refuse: HasUnsupportedBoxes
    # also turns down unknown box types, an oversized ftyp and compressed metadata
    # that is neither Exif nor XMP.
    elif jxl_boxes_supported "$info"; then
        ok "jxlinfo -v lists the $boxes boxes of $n the way JXLWorker reads them, and every one of them round-trips"
    else
        bad "jxl box probe $n" "a box here is one HasUnsupportedBoxes refuses, so JXLWorker declines the file and the round trip above tests something ImageOptim never encodes"
    fi
done

# Round trips run only on files the worker refuses — for a box it cannot rebuild,
# a sample PNG cannot hold, or an extra channel the decode would drop — say
# nothing about what ImageOptim does with a JXL.
if [ "$JXL_ELIGIBLE" -gt 0 ]; then
    ok "jxl round-tripped $JXL_ELIGIBLE file(s) JXLWorker would re-encode"
else
    bad "jxl worker eligibility" "no JXL here is one JXLWorker would re-encode, so the round trips above prove nothing about the app"
fi
if [ "$JXL_LOSSY_RETAINED" -gt 0 ]; then
    ok "jxl lossy produced $JXL_LOSSY_RETAINED result(s) JXLWorker would retain"
else
    bad "jxl lossy retention" "no eligible result cleared JXLWorker's 5% minimum-savings gate"
fi

# --- summary -----------------------------------------------------------------

echo
echo "----------------------------------------"
printf 'passed %d   failed %d   skipped %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
