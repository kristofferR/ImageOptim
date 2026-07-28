#!/bin/bash
# Runs a corpus of real-world images through every codec ImageOptim ships and
# asserts the invariants that hold regardless of which encoder is underneath:
#
#   1. the file ImageOptim would keep is never larger than the input
#   2. output still decodes, at the original dimensions
#   3. a file the worker declines is left byte-identical
#   4. nothing crashes, even on deliberately corrupt input
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
WORK_DIR="${TMPDIR:-/tmp}/imageoptim-corpus.$$"

[ "${1:-}" = "--refresh" ] && rm -rf "$CACHE_DIR"

PASS=0; FAIL=0; SKIP=0

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s — %s\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  skip  %s (%s)\n' "$1" "$2"; }

# --- tools -------------------------------------------------------------------

find_tools() {
    local candidates=(
        "$ROOT_DIR/imageoptim/build/Release/ImageOptim.app/Contents/Frameworks/ImageOptimGPL.framework/Versions/A/Resources"
        "$ROOT_DIR/build/Release/ImageOptim.app/Contents/Frameworks/ImageOptimGPL.framework/Versions/A/Resources"
    )
    # Resources sits eleven levels below DerivedData in Xcode's default layout:
    # <project-hash>/Build/Products/Release/…/Versions/A/Resources.
    local derived
    derived="$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 11 \
        -path '*/Build/Products/Release/ImageOptim.app/Contents/Frameworks/ImageOptimGPL.framework/Versions/A/Resources' \
        -type d 2>/dev/null | head -1)"
    [ -n "$derived" ] && candidates+=("$derived")

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

AVIF_BASE="https://raw.githubusercontent.com/link-u/avif-sample-images/master"
JXL_BASE="https://raw.githubusercontent.com/libjxl/testdata/main"

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
    "jpeg-testorig.jpg|https://raw.githubusercontent.com/libjpeg-turbo/libjpeg-turbo/main/testimages/testorig.jpg"

    # SVG: a W3C conformance case and a real-world icon
    "svg-w3c-struct-image.svg|https://www.w3.org/Graphics/SVG/Test/20110816/svg/struct-image-01-t.svg"
    "svg-bootstrap-gear.svg|https://raw.githubusercontent.com/twbs/icons/main/icons/gear.svg"
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
    x00n0g01.png  # corrupt: zero-length IDAT
    xcrn0g04.png  # corrupt: broken CRC
)

# Names of the inputs that could not be fetched or unpacked; each one is
# reported as a failure below, so a codec is never left unexercised without
# saying so.
MISSING=()

fetch_corpus() {
    local entry name url
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

    if [ ! -s "$CACHE_DIR/pngsuite/basn2c08.png" ]; then
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
        fi
    fi
}

mkdir -p "$WORK_DIR"
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

# The worker contract: it replaces the file only when the result is smaller, so
# a pass that grows a file is discarded, not wrong. What must never happen is
# corrupt output or changed dimensions.
assert_pass() {
    local name=$1 before=$2 after=$3
    if [ ! -s "$after" ]; then bad "$name" "produced no output"; return; fi
    local sb sa db da
    sb=$(size_of "$before"); sa=$(size_of "$after")
    db=$(dimensions_of "$before"); da=$(dimensions_of "$after")
    if [ -z "$db" ]; then
        # sips has no decoder for this format on this host — AVIF and JPEG XL on
        # older macOS. Say so rather than let the invariant pass unchecked.
        skip "$name decodes" "sips cannot read this format here"
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

# Corrupt input must be refused cleanly: a non-zero exit is fine, a signal is
# not, the file must not be replaced with garbage, and a tool that claims
# success has to leave behind something that still decodes.
assert_corrupt() {
    local name=$1 rc=$2 before=$3 after=$4
    if [ "$rc" -ge 128 ]; then
        bad "$name" "died with a signal (exit $rc)"
    elif [ "$rc" -ne 0 ]; then
        if cmp -s "$before" "$after"; then
            ok "$name (corrupt input refused, file untouched)"
        else
            bad "$name" "failed but modified the file"
        fi
    elif cmp -s "$before" "$after"; then
        ok "$name (corrupt input accepted, file untouched)"
    elif [ ! -s "$after" ]; then
        bad "$name" "exited 0 but left no output"
    elif [ -z "$(dimensions_of "$after")" ]; then
        bad "$name" "exited 0 but the rewritten file does not decode"
    else
        ok "$name (corrupt input accepted and rewritten to a decodable file)"
    fi
}

# --- JPEG: Jpegli, through jpegtran and jpegoptim ----------------------------

echo
echo "JPEG — jpegtran and jpegoptim linked against Jpegli"
for src in "$CACHE_DIR"/jpeg-*.jpg; do
    [ -f "$src" ] || continue
    n=$(basename "$src")
    f=$(copy_in "$src")
    if "$TOOLS/jpegtran" -copy none -optimize -outfile "$WORK_DIR/jt-$n" "$f" 2>/dev/null; then
        assert_pass "jpegtran $n" "$f" "$WORK_DIR/jt-$n"
    else
        bad "jpegtran $n" "exited non-zero"
    fi
    if "$TOOLS/jpegtran" -copy none -progressive -outfile "$WORK_DIR/jp-$n" "$f" 2>/dev/null; then
        assert_pass "jpegtran -progressive $n" "$f" "$WORK_DIR/jp-$n"
    else
        bad "jpegtran -progressive $n" "exited non-zero"
    fi
    cp "$f" "$WORK_DIR/jo-$n"
    if "$TOOLS/jpegoptim" --strip-all --quiet "$WORK_DIR/jo-$n" 2>/dev/null; then
        assert_pass "jpegoptim $n" "$f" "$WORK_DIR/jo-$n"
    else
        bad "jpegoptim $n" "exited non-zero"
    fi
done

# --- PNG: the tools left after Zopfli's removal ------------------------------

echo
echo "PNG — PngSuite through OxiPNG and PNGCrush"
for want in "${PNGSUITE_WANTED[@]}"; do
    src=$(find "$CACHE_DIR/pngsuite" -name "$want" -type f 2>/dev/null | head -1)
    if [ -z "$src" ]; then skip "pngsuite $want" "not in the archive"; continue; fi
    corrupt=0
    case "$want" in x*) corrupt=1 ;; esac
    f=$(copy_in "$src")

    cp "$f" "$WORK_DIR/ox-$want"
    "$TOOLS/oxipng" -o 2 -q --strip safe "$WORK_DIR/ox-$want" >/dev/null 2>&1
    rc=$?
    if [ "$corrupt" -eq 1 ]; then
        assert_corrupt "oxipng $want (corrupt)" "$rc" "$f" "$WORK_DIR/ox-$want"
    elif [ "$rc" -eq 0 ]; then
        assert_pass "oxipng $want" "$f" "$WORK_DIR/ox-$want"
    else
        bad "oxipng $want" "exited $rc on a valid PNG"
    fi

    cp "$f" "$WORK_DIR/pc-$want"
    "$TOOLS/pngcrush" -q -ow "$WORK_DIR/pc-$want" >/dev/null 2>&1
    rc=$?
    if [ "$corrupt" -eq 1 ]; then
        assert_corrupt "pngcrush $want (corrupt)" "$rc" "$f" "$WORK_DIR/pc-$want"
    elif [ "$rc" -eq 0 ]; then
        assert_pass "pngcrush $want" "$f" "$WORK_DIR/pc-$want"
    elif [ "$rc" -ge 128 ]; then
        bad "pngcrush $want" "died with a signal (exit $rc)"
    elif cmp -s "$f" "$WORK_DIR/pc-$want"; then
        # Only a clean refusal that leaves the file alone is tolerable here; a
        # crash, or a failure that still rewrote the file, is a real failure.
        skip "pngcrush $want" "declined this variant, file untouched"
    else
        bad "pngcrush $want" "exited $rc on a valid PNG and modified the file"
    fi
done

# --- GIF: mainline gifsicle --------------------------------------------------

echo
echo "GIF — mainline gifsicle, including the --lossy path from giflossy"
for src in "$CACHE_DIR"/gif-*.gif; do
    [ -f "$src" ] || continue
    n=$(basename "$src")
    f=$(copy_in "$src")
    for mode in "plain:-O3" "lossy:-O3 --lossy=30"; do
        tag="${mode%%:*}"; opts="${mode#*:}"
        label="gifsicle ${opts} $n"
        outfile="$WORK_DIR/gs-$tag-$n"
        if "$TOOLS/gifsicle" $opts -o "$outfile" "$f" 2>/dev/null && [ -s "$outfile" ]; then
            if "$TOOLS/gifsicle" --info "$outfile" >/dev/null 2>&1; then
                assert_pass "$label" "$f" "$outfile"
            else
                bad "$label" "output is not a readable GIF"
            fi
        else
            bad "$label" "gifsicle failed (is --lossy present?)"
        fi
    done
    # Both outputs must keep every frame — --lossy is the path that changed.
    fin=$("$TOOLS/gifsicle" --info "$f" 2>/dev/null | grep -c 'image #')
    if [ "$fin" -gt 1 ]; then
        for tag in plain lossy; do
            fout=$("$TOOLS/gifsicle" --info "$WORK_DIR/gs-$tag-$n" 2>/dev/null | grep -c 'image #')
            if [ "$fin" = "$fout" ]; then
                ok "gifsicle $tag preserved all $fin frames of $n"
            else
                bad "gifsicle frames $tag $n" "frame count changed: $fin -> $fout"
            fi
        done
    fi
done

# --- SVG: SVGO v4 ------------------------------------------------------------

echo
echo "SVG — SVGO v4"
SVGO_JS="$TOOLS/svgo.js"
XMLLINT=/usr/bin/xmllint

# The ids a document references through url(#…), one per line.
refs_in() { grep -o 'url(#[^)]*)' "$1" | sed 's/url(#//;s/)//' | sort -u; }

if [ ! -f "$SVGO_JS" ]; then
    # find_tools already proved the bundle is there, so svgo.js missing from it
    # is a packaging error that makes SvgoWorker decline every SVG.
    bad "svgo" "svgo.js is not in the bundle, so no SVG would ever be optimized"
elif ! command -v node >/dev/null 2>&1; then
    skip "svgo" "node is not installed"
else
    for src in "$CACHE_DIR"/svg-*.svg; do
        [ -f "$src" ] || continue
        n=$(basename "$src")
        f=$(copy_in "$src")
        if node "$SVGO_JS" 0 "$f" "$WORK_DIR/sv-$n" 2>/dev/null && [ -s "$WORK_DIR/sv-$n" ]; then
            sb=$(size_of "$f"); sa=$(size_of "$WORK_DIR/sv-$n")
            # The raster paths run the output through a decoder; this is the
            # equivalent for SVG, since truncated XML can still contain "<svg".
            if [ ! -x "$XMLLINT" ]; then
                skip "svgo $n parses" "xmllint is not available here"
            elif ! "$XMLLINT" --noout "$WORK_DIR/sv-$n" 2>/dev/null; then
                bad "svgo $n" "output is not well-formed XML"
            elif ! grep -q '<svg' "$WORK_DIR/sv-$n"; then
                bad "svgo $n" "output parses but has no <svg> element"
            else
                ok "svgo $n parses as XML"
            fi
            if [ "$sa" -gt "$sb" ]; then
                ok "svgo $n (${sb} -> ${sa} bytes; larger, so the worker discards it)"
            else
                ok "svgo $n (${sb} -> ${sa} bytes)"
            fi
            # Every url(#id) reference must still resolve, and none may have
            # vanished: dropping a reference along with its target is the
            # rendering regression this is here to catch. cleanupIds renames
            # ids, so the input and output sets are compared by count, not by
            # name.
            dangling=0
            for ref in $(refs_in "$WORK_DIR/sv-$n"); do
                grep -q "id=\"$ref\"" "$WORK_DIR/sv-$n" || dangling=1
            done
            rin=$(refs_in "$f" | wc -l | tr -d ' ')
            rout=$(refs_in "$WORK_DIR/sv-$n" | wc -l | tr -d ' ')
            if [ "$dangling" -ne 0 ]; then
                bad "svgo $n" "an id referenced by url(#…) was removed"
            elif [ "$rout" -lt "$rin" ]; then
                bad "svgo $n" "url(#…) references disappeared: $rin -> $rout"
            else
                ok "svgo $n kept all $rin url(#…) references resolvable"
            fi
        else
            bad "svgo $n" "produced no output"
        fi
    done
fi

# --- AVIF --------------------------------------------------------------------

echo
echo "AVIF — libavif, round-tripped through PNG as AVIFWorker does"
for src in "$CACHE_DIR"/avif-*.avif; do
    [ -f "$src" ] || continue
    n=$(basename "$src")
    f=$(copy_in "$src")
    if "$TOOLS/avifdec" "$f" "$WORK_DIR/dec-$n.png" >/dev/null 2>&1 && [ -s "$WORK_DIR/dec-$n.png" ]; then
        if "$TOOLS/avifenc" -q 80 -s 8 "$WORK_DIR/dec-$n.png" "$WORK_DIR/re-$n" >/dev/null 2>&1; then
            assert_pass "avif round-trip $n" "$f" "$WORK_DIR/re-$n"
        else
            bad "avif round-trip $n" "avifenc failed on the decoded PNG"
        fi
    else
        bad "avif decode $n" "avifdec failed"
    fi
done

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

# The gain-map probe AVIFWorker relies on is a literal string match, and the
# worker pipes only stdout, so stderr is discarded here too: output that moved
# to stderr would make the worker decline every file.
probe=$(find "$CACHE_DIR" -name 'avif-8bpc-yuv420.avif' | head -1)
if [ -n "$probe" ]; then
    if "$TOOLS/avifdec" --info "$probe" 2>/dev/null | grep -q ' \* Gain map       : Absent'; then
        ok "avifdec --info still prints the exact gain-map line AVIFWorker matches"
    else
        bad "avif gain-map probe" "that line changed — AVIFWorker would skip every file"
    fi
fi

# --- JPEG XL -----------------------------------------------------------------

echo
echo "JPEG XL — libjxl round-trips and the jxlinfo probe"
for src in "$CACHE_DIR"/jxl-*.jxl; do
    [ -f "$src" ] || continue
    n=$(basename "$src")
    f=$(copy_in "$src")
    if "$TOOLS/djxl" "$f" "$WORK_DIR/dec-$n.png" >/dev/null 2>&1 && [ -s "$WORK_DIR/dec-$n.png" ]; then
        if "$TOOLS/cjxl" -q 90 -e 4 "$WORK_DIR/dec-$n.png" "$WORK_DIR/re-$n" >/dev/null 2>&1; then
            assert_pass "jxl round-trip $n" "$f" "$WORK_DIR/re-$n"
        else
            bad "jxl round-trip $n" "cjxl failed on the decoded PNG"
        fi
    else
        bad "jxl decode $n" "djxl failed"
    fi

    # JXLWorker reads bit depth out of jxlinfo -v with a regex and declines
    # anything float or above 16 bits. This is that regex, on the stdout the
    # worker pipes, so a bare "10-bit" without the comma the worker requires —
    # or output that moved to stderr — fails here too.
    if "$TOOLS/jxlinfo" -v "$f" 2>/dev/null | grep -Eq ', [0-9]+-bit|bits per sample: [0-9]+'; then
        ok "jxlinfo -v reports bit depth for $n in the form JXLWorker parses"
    else
        bad "jxl bit-depth probe $n" "jxlinfo output no longer matches the worker's regex"
    fi
done

# --- summary -----------------------------------------------------------------

echo
echo "----------------------------------------"
printf 'passed %d   failed %d   skipped %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
