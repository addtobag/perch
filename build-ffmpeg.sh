#!/bin/bash
# Builds a small, LGPL-only ffmpeg for Perch from the official source, for Apple silicon and Intel,
# and puts it in Resources/ffmpeg/. Only needs Apple's Command Line Tools. Takes a few minutes.
#
#   bash build-ffmpeg.sh
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
VERSION="7.1"
TARBALL="ffmpeg-$VERSION.tar.xz"
WORK="$ROOT/build/ffmpeg-src"
OUT="$ROOT/Resources/ffmpeg"
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$WORK" "$OUT"
cd "$WORK"
if [ ! -f "$TARBALL" ]; then
  echo "Downloading FFmpeg $VERSION source…"
  curl -fL --progress-bar -o "$TARBALL" "https://ffmpeg.org/releases/$TARBALL"
fi

# Only what Perch uses: RTSP in, H.264/H.265 decode (hardware via VideoToolbox), MJPEG frames out.
COMMON=(
  --disable-everything --disable-autodetect --disable-doc --disable-debug
  --disable-ffplay --disable-ffprobe --enable-ffmpeg
  --enable-network --enable-videotoolbox
  --enable-protocol=file,pipe,tcp,udp,rtp
  --enable-demuxer=rtsp,rtp,sdp
  --enable-decoder=h264,hevc
  --enable-parser=h264,hevc
  --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox
  --enable-encoder=mjpeg
  --enable-muxer=image2pipe,mjpeg
  --enable-filter=buffer,buffersink,format,fps,null,scale,copy
  --enable-swscale
)

for ARCH in arm64 x86_64; do
  echo ""
  echo "Building ffmpeg for ${ARCH}..."
  rm -rf "$WORK/$ARCH"
  mkdir -p "$WORK/$ARCH"
  tar -xf "$TARBALL" -C "$WORK/$ARCH" --strip-components 1
  cd "$WORK/$ARCH"
  EXTRA=()
  if [ "$ARCH" = "x86_64" ]; then
    EXTRA=(--enable-cross-compile --target-os=darwin --arch=x86_64 --disable-x86asm)
  else
    EXTRA=(--arch=arm64)
  fi
  ./configure "${COMMON[@]}" "${EXTRA[@]}" \
    --cc="clang -arch $ARCH" \
    --extra-cflags="-arch $ARCH -mmacosx-version-min=13.0" \
    --extra-ldflags="-arch $ARCH -mmacosx-version-min=13.0" > "$WORK/configure-$ARCH.log"
  make -j"$JOBS" ffmpeg > "$WORK/make-$ARCH.log" 2>&1 || { echo "Build failed for $ARCH. Last lines of the log:"; tail -20 "$WORK/make-$ARCH.log"; exit 1; }
  cd "$WORK"
done

lipo -create -output "$OUT/ffmpeg" "$WORK/arm64/ffmpeg" "$WORK/x86_64/ffmpeg"
chmod +x "$OUT/ffmpeg"
cp "$WORK/arm64/COPYING.LGPLv2.1" "$OUT/COPYING.LGPLv2.1"
echo "$VERSION" > "$OUT/VERSION"
echo ""
echo "Built $(du -h "$OUT/ffmpeg" | cut -f1) universal ffmpeg $VERSION → Resources/ffmpeg/ffmpeg"
