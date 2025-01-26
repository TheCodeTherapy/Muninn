#!/bin/bash -eu

OUT_DIR="build/web"
EMSCRIPTEN_SDK_DIR="$HOME/.emsdk"

mkdir -p $OUT_DIR

export EMSDK_QUIET=1
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

odin \
  build source/main_web \
  -target:freestanding_wasm32 \
  -build-mode:obj \
  -define:RAYLIB_WASM_LIB=env.o \
  -vet -strict-style \
  -o:speed \
  -out:$OUT_DIR/game

ODIN_PATH=$(odin root)

files="source/main_web/main_web.c $OUT_DIR/game.wasm.o ${ODIN_PATH}/vendor/raylib/wasm/libraylib.a"
flags="-sUSE_GLFW=3 -sASSERTIONS -sSINGLE_FILE -sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2 --shell-file source/main_web/index_template.html --embed-file assets"

emcc -o $OUT_DIR/index.html $files $flags && rm $OUT_DIR/game.wasm.o
echo "Web build created in ${OUT_DIR}"
