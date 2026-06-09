#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${WHISPER_SOURCE_DIR:-$ROOT_DIR/.e2e-runs/source-whisper.cpp}"
BUILD_DIR="$SOURCE_DIR/build-majordomo"
HELPERS_DIR="$ROOT_DIR/Helpers"
DICTATE_SOURCE="$ROOT_DIR/tools/whisper-dictate.cpp"
WHISPER_TAG="${WHISPER_TAG:-v1.8.6}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-15.0}"

if ! command -v cmake >/dev/null 2>&1; then
	echo "cmake is required to build the app-owned Whisper helper" >&2
	exit 1
fi

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
	git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp "$SOURCE_DIR"
else
	git -C "$SOURCE_DIR" fetch --depth 1 origin "refs/tags/$WHISPER_TAG:refs/tags/$WHISPER_TAG"
	git -C "$SOURCE_DIR" checkout --force "$WHISPER_TAG"
	git -C "$SOURCE_DIR" clean -fd
fi

git -C "$SOURCE_DIR" checkout --force "$WHISPER_TAG"

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
	-DBUILD_SHARED_LIBS=OFF \
	-DGGML_BACKEND_DL=OFF \
	-DGGML_METAL=ON \
	-DGGML_METAL_EMBED_LIBRARY=ON \
	-DWHISPER_BUILD_TESTS=OFF \
	-DWHISPER_BUILD_SERVER=OFF \
	-DWHISPER_BUILD_EXAMPLES=ON

cmake --build "$BUILD_DIR" --config Release -j "$(sysctl -n hw.ncpu)"

mkdir -p "$HELPERS_DIR"
cp "$BUILD_DIR/bin/whisper-cli" "$HELPERS_DIR/whisper-cli"
chmod +x "$HELPERS_DIR/whisper-cli"

clang++ \
	-std=c++17 \
	-O3 \
	-mmacosx-version-min="$MACOS_DEPLOYMENT_TARGET" \
	-DMAJORDOMO_BUILD_WHISPER_DICTATE \
	-I"$SOURCE_DIR/include" \
	-I"$SOURCE_DIR/ggml/include" \
	"$DICTATE_SOURCE" \
	"$BUILD_DIR/src/libwhisper.a" \
	"$BUILD_DIR/ggml/src/libggml.a" \
	"$BUILD_DIR/ggml/src/libggml-base.a" \
	"$BUILD_DIR/ggml/src/libggml-cpu.a" \
	"$BUILD_DIR/ggml/src/ggml-blas/libggml-blas.a" \
	"$BUILD_DIR/ggml/src/ggml-metal/libggml-metal.a" \
	-framework Accelerate \
	-framework Foundation \
	-framework CoreFoundation \
	-framework Metal \
	-framework MetalKit \
	-o "$HELPERS_DIR/whisper-dictate"
chmod +x "$HELPERS_DIR/whisper-dictate"

codesign --force --sign - "$HELPERS_DIR/whisper-cli" >/dev/null
codesign --force --sign - "$HELPERS_DIR/whisper-dictate" >/dev/null

for helper in "$HELPERS_DIR/whisper-cli" "$HELPERS_DIR/whisper-dictate"; do
	if otool -L "$helper" | grep -q /opt/homebrew; then
		echo "packaged $(basename "$helper") still links to /opt/homebrew" >&2
		exit 1
	fi
	if ! file "$helper" | grep -q "arm64"; then
		echo "packaged $(basename "$helper") is not arm64" >&2
		exit 1
	fi
	if ! xcrun vtool -show-build "$helper" 2>/dev/null | grep -q "minos $MACOS_DEPLOYMENT_TARGET"; then
		echo "packaged $(basename "$helper") has unexpected minimum macOS version" >&2
		xcrun vtool -show-build "$helper" >&2 || true
		exit 1
	fi
done

cat <<EOF
Packaged app-owned static Whisper helpers:
  $HELPERS_DIR/whisper-cli
  $HELPERS_DIR/whisper-dictate
EOF
