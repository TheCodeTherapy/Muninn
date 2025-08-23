# Muninn

## The Odin + Raylib Boilerplate with hot-reloading and WebAssembly builds.

**Muninn** is a minimal boilerplate for making games with Odin and Raylib, targeting both native and WebAssembly.
It focuses on **fast iteration, simple builds, and frictionless distribution**, making it perfect for teaching gamedev or rapid prototyping.

## Try it Live!

- [https://thecodetherapy.github.io/Muninn/](https://thecodetherapy.github.io/Muninn/)

## Features

- [x] Using Odin itself as our build system (because Odin is fucking awesome);
- [x] Frictionless hot-reload so we can just save the code and see the changes immediately;
- [x] Basic game example;
- [x] Independent post-processing effects;
- [x] A multi-pass shader manager to facilitate starting projects with multi-pass shaders;
- [x] A shader-chunk system so you can conveniently inject/re-use shader chunks with `#include`;
- [x] WebAssembly builds so we can run the games in browsers too;
- [x] Single-File WebAssembly build philosophy (more on that below);
- [x] Cool-looking WASM-compatible Debug UI using MicroUI;
- [ ] Gamepad support (soon™️);
- [ ] Mobile touch controls and virtual joysticks (soon™️);
- [ ] Sound system with procedurally generated, parameterizable sound effects (soon™️).

> #### 🔥 Hot-reload on save
> Instead of having to manually run the hot-reload build scripts (or triggering build commands through key bindings) after saving changes to your code, I've chosen to implement a minimal logic that monitors the source files and triggers the hot-reload build automatically once any changes are detected to any of the source files.
>
> #### 📦 Single-File WebAssembly build philosophy
> For the WebAssembly single-file builds, I've chosen to allow for some overhead in terms of bundle size to obtain the advantage of generating a single self-contained HTML file with everything that is necessary to run the game (including the compiled WASM file and all the assets as base64 strings in the script tag, which is inlined to the single HTML file).
>
> That, IMHO, offers the convenience of running the game just by opening the HTML file locally in a web browser (just by double-clicking the file on your file manager), without the need to serve the files through a web server to comply with browser policies that would prevent loading the needed files directly from the disk.
>
> That also offers a great distribution value, as sharing your game with friends only involves sending them a single HTML file, and they'll be able to play your game.

## Usage

### 🥾 Bootstrap the Build System

First, compile the build system itself:

```bash
odin build build.odin -file
```

This creates a `build.exe` executable that contains all build functionality.

### Available Build Commands

#### 🔥 Hot-Reload Development
```bash
./build.exe hot-reload
```
Builds the game with hot-reload support and automatically watches source files for changes. When you save any source file, the game will rebuild automatically and reload the updated code without restarting.

**Flags:**
- `--watch` - Watch files and rebuild on changes (default behavior)
- `--run` - Run the game after building (default behavior)
- `--build-only` - Build once and exit without watching or running

#### 🐛 Debug Build
```bash
./build.exe debug
```
Creates a debug build with debug symbols at `build/debug/game_debug.exe`. Perfect for development and debugging with full symbol information.

#### 🚀 Release Build
```bash
./build.exe release
```
Creates an optimized release build at `build/release/game_release.exe` with maximum performance optimizations and no bounds checking.

#### 🌐 WebAssembly Build
```bash
./build.exe web [--debug]
```
Builds a WebAssembly version of your game at `build/web/index.html`. Automatically manages EMSDK installation and setup. The resulting build can be served with any web server.

**Flags:**
- `--debug` - Enable debug UI and logging in the WebAssembly build

To test the web build locally:
```bash
cd build/web
python -m http.server 8000
# Then open http://localhost:8000 in your browser
```

#### 📦 WebAssembly Single-File Build
```bash
./build.exe web-single [--debug]
```
Creates a single self-contained HTML file at `build/web_single/index.html` that includes everything needed to run the game (WebAssembly, assets, and runtime) embedded as base64. This file can be opened directly in a browser without a web server, making it perfect for easy distribution.

**Flags:**
- `--debug` - Enable debug UI and logging in the single-file WebAssembly build

**Note:** Requires an existing web build first (run `./build.exe web` before using this command).

#### ❓ Help
```bash
./build.exe help
```
Shows detailed usage information and all available commands.

> #### Without Bootstrap
>
> _If for any weird reason you do not want to bootstrap the build system into the `build.exe` binary, you may also run it directly, with the following syntax:_
>
> ```bash
> odin run build.odin -file -- hot-reload [--watch] [--run] [--build-only]
> ```
> ```bash
> odin run build.odin -file -- debug
> ```
> ```bash
> odin run build.odin -file -- release
> ```
> ```bash
> odin run build.odin -file -- web [--debug] [--webgl2]
> ```
> ```bash
> odin run build.odin -file -- web-single [--debug] [--webgl2]
> ```
> ```bash
> odin run build.odin -file -- help
> ```

### Example Workflow

1. **Start Development:** `./build.exe hot-reload` - Begin coding with automatic rebuilds
2. **Test WebAssembly Version:** `./build.exe web --debug` - Create web build with debug UI for browser testing
3. **Create Distribution:** `./build.exe release` - Build the optimized executable
4. **WebAssembly Distribution:** `./build.exe web-single` - Create the single-file WebAssembly release

## Current Known Quirks and Compromises

#### WebGL2:

- WebGL2 **KINDA** works, but with some quirks, so I'm currently using the `USE_WEBGL2` feature flag to `false` for my WASM build to use `WebGL1`. That kinda sucks because all of the limitations of `#version 100` shaders (no layouts, old and ugly varyings, no full bitwise ops, no unsigned ints, no texelFetch, no textureGrad, etc... it's kind of a nightmare). When the WASM build targets `WebGL2` everything works, but we end up with `WebGL: INVALID_VALUE: vertexAttribPointer: index out of range` and `WebGL: INVALID_VALUE: enableVertexAttribArray: index out of range` warnings all over the place. This MAY be related to Raylib's closed [issue #4330](https://github.com/raysan5/raylib/issues/4330), but I couldn't find the time to investigate this yet. It works, but it's a no-no to me. I won't sleep well with warnings on my console. We're flawed, but not savages.

#### Texture Format:

- Raylib (or at least its implementation vendored by Odin) does not expose a `LoadRenderTexture` method that allows to pick a specific `PixelFormat`. Because of that, I wrote my own implementation of [`LoadRenderTextureWithFormat`](https://github.com/TheCodeTherapy/Muninn/blob/master/src/gamelogic/render_texture_utils.odin#L8) and [`LoadRT_WithFallback`](https://github.com/TheCodeTherapy/Muninn/blob/master/src/gamelogic/render_texture_utils.odin#L79). The former just tries to create the `RenderTexture2D` with the chosen `PixelFormat` and the latter uses the former with a fall-through logic in case the wanted `PixelFormat` is not available (which is quite common in the WASM build). Weirdly, the WASM build works fine with `UNCOMPRESSED_R32G32B32A32` (FloatType) when the build targets `WebGL1` and `#version 100` shaders, but it falls through into `UNCOMPRESSED_R8G8B8A8` when the build targets `WebGL2` and `#version 300 es` shaders. I couldn't find the time to start investigating that yet.

#### Why are you maintaining v100 and v300es shaders? Can't we just replace some keywords?

- No, we can't. It's not as simple as finding `round(float x)` and replacing it with `floor(x + 0.5)` or equally simple stuff. Even the capacity to use non-constant loop bounds/conditions/steps in simple `for`/`while`/`do-while` loops, changes everything about the way you write shaders. The fastest and simplest solution to this issue will be to offer a PR to solve the two items above upstream, as soon as I can find the time to.

## Thanks and Credits:

This project was inspired by one of [Karl Zylinski](https://github.com/karl-zylinski)'s projects, which you may find [here](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template). My version fits my personal development workflow and choices better, but you should definitely check out his work.

Karl is a prolific author and game developer who specializes in Odin and Raylib. Reading his book (which you can find [here](https://odinbook.com/)) was invaluable for my incredibly easy transition from C++ to Odin to develop my Raylib projects. If you're interested in Odin, please consider supporting Karl by [buying his book](https://odinbook.com/) or checking out [his game](https://store.steampowered.com/app/2781210/CAT__ONION/) built with Odin + Raylib on Steam.

The inspiration to create the build system with the same language that aims to be self-sufficient (soon™️) came from the recreational programming streamer [Tsoding](https://x.com/tsoding) and his project [nob.h](https://github.com/tsoding/nob.h)

Special thanks to [Ginger Bill](https://x.com/thegingerbill) (Creator of the [Odin Programming Language](https://odin-lang.org/), and an awesome guy), and [Ray](https://x.com/raysan5) (Creator of [Raylib](https://www.raylib.com/)). If you like their tech, please support their work in any way you can.
