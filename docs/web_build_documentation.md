# Odin + Raylib WebAssembly Build Documentation

## Philosophy: Post-Processing Over Build Modifications

This project uses a **post-processing approach** to create single-file HTML builds rather than modifying the Emscripten build process itself. This design decision ensures:

1. **Robustness**: Working builds remain untouched and stable
2. **Maintainability**: Updates to Odin, Emscripten, or Raylib don't break our single-file system
3. **Debuggability**: Original multi-file builds remain available for development and debugging
4. **Flexibility**: Can easily switch between multi-file and single-file outputs

## Build Architecture Overview

### Standard Multi-File Web Build (`build\web\`)

The standard web build produces 5 critical files that work together:

1. **`index.html`** - HTML entry point and WebAssembly orchestration
2. **`index.js`** - Emscripten JavaScript runtime
3. **`odin.js`** - Odin WebAssembly runtime and imports
4. **`index.wasm`** - Compiled Odin + Raylib WebAssembly binary
5. **`index.data`** - Virtual file system data (assets)

### Single-File Build (`build\web_single\game_standalone.html`)

The single-file build embeds all 5 files into one self-contained HTML document:
- **Dependencies**: None (completely self-contained)
- **Distribution**: Single file that works offline
- **Compatibility**: Modern browsers with WebAssembly support

---

## Technical Deep Dive

### Standard Build File Analysis

#### 1. `index.html` - WebAssembly Orchestration Hub

**Purpose**: Coordinates the entire WebAssembly loading and initialization process.

**Critical Components**:
```html
<canvas class="game_canvas" id="canvas" oncontextmenu="event.preventDefault()"
        tabindex="-1" onmousedown="event.target.focus()" onkeydown="event.preventDefault()"></canvas>
```
- Main rendering surface for the game
- Event handlers prevent browser context menus and focus management

**Odin Runtime Setup**:
```javascript
var odinMemoryInterface = new odin.WasmMemoryInterface();
odinMemoryInterface.setIntSize(4);
var odinImports = odin.setupDefaultImports(odinMemoryInterface);
```
- Creates interface for Odin WebAssembly memory management
- Sets integer size to 4 bytes (js_wasm32 target)
- Generates all required Odin runtime imports

**WebAssembly Loading Strategy**:
```javascript
instantiateWasm: (imports, successCallback) => {
    const newImports = {
        ...odinImports,    // Odin imports first (critical)
        ...imports         // Emscripten imports second
    }
    return WebAssembly.instantiateStreaming(fetch("index.wasm"), newImports)
        .then(function(output) {
            var e = output.instance.exports;
            odinMemoryInterface.setExports(e);
            odinMemoryInterface.setMemory(e.memory);
            return successCallback(output.instance);
        });
}
```

**Critical Factor**: Import order matters! `...odinImports` must come before `...imports` or the build will fail.

#### 2. `index.js` - Emscripten JavaScript Runtime

**Purpose**: Emscripten-generated runtime that handles WebAssembly instantiation, memory management, virtual file system, and browser APIs.

**Key Responsibilities**:
- **WASM Instantiation**: Detects and calls custom `Module.instantiateWasm` function
- **Memory Management**: Handles heap allocation, garbage collection, and memory mapping
- **File System**: Virtual file system for accessing `index.data` assets
- **Browser Integration**: Canvas management, input handling, and API polyfills
- **Error Handling**: Comprehensive error reporting and fallback mechanisms

**Loading Flow**:
1. Emscripten runtime initializes
2. Detects custom `Module.instantiateWasm` in `index.html`
3. Calls custom function with collected imports
4. Custom function merges Odin + Emscripten imports
5. Uses streaming WASM instantiation for optimal performance
6. Runtime completes initialization and calls `onRuntimeInitialized`

#### 3. `odin.js` - Odin WebAssembly Runtime

**Purpose**: Provides essential runtime imports that Odin-compiled WebAssembly requires.

**Core Classes**:
- **`WasmMemoryInterface`**: Memory read/write, string conversion, type handling
- **`WebGLInterface`**: Complete WebGL 1.0/2.0 API implementation for graphics
- **DOM utilities**: Document manipulation, event handling, element access

**Export Structure**:
```javascript
setupDefaultImports(wasmMemoryInterface) returns {
    env: {},                    // Standard environment
    odin_env: { /* ... */ },    // Core Odin runtime (MUST be import #0)
    odin_dom: { /* ... */ },    // DOM manipulation functions
    webgl: { /* ... */ },       // WebGL 1.0 graphics API
    webgl2: { /* ... */ }       // WebGL 2.0 extended API
}
```

**Critical Requirement**: `odin_env` must be the first import (import #0) or WASM instantiation fails.

#### 4. `index.wasm` - Compiled WebAssembly Binary

**Purpose**: Contains the compiled Odin + Raylib game code as WebAssembly.

**Import Dependencies** (in exact order):
1. `odin_env` (Import #0) - Core Odin runtime functions
2. `env` - Standard Emscripten environment imports
3. `odin_dom` - DOM manipulation functions
4. `webgl` - WebGL 1.0 graphics functions
5. `webgl2` - WebGL 2.0 graphics functions

**Export Responsibilities**:
- Memory management functions
- Game initialization and main loop
- Raylib graphics integration
- Asset loading and management

#### 5. `index.data` - Virtual File System Assets

**Purpose**: Contains packed asset files (images, sounds, etc.) in Emscripten's virtual file system format.

**Usage**: Emscripten runtime automatically loads this data and makes assets available to the WASM through standard file I/O operations.

---

## Single-File Post-Processing Strategy

### Why Not Emscripten's `-sSINGLE_FILE`?

**The Problem**: Emscripten's built-in single-file option breaks the fragile WebAssembly loading orchestration:

1. **No Streaming**: Embeds WASM as base64, preventing `WebAssembly.instantiateStreaming()`
2. **Import Timing**: Different instantiation path may not preserve import order
3. **Custom Logic Lost**: Bypasses our custom `instantiateWasm` function
4. **Odin Integration**: May not properly handle Odin-specific runtime requirements

**The Solution**: Post-process the working multi-file build instead of modifying the build process.

### Post-Processing Algorithm

The `build_web_single.ps1` PowerShell script implements this strategy:

#### 1. **Preserve Working Architecture**
```powershell
# the original build\web files are preserved
$indexHtml = Read-TextFileContent (Join-Path $WEB_BUILD_DIR "index.html")
$indexJs = Read-TextFileContent (Join-Path $WEB_BUILD_DIR "index.js")
$odinJs = Read-TextFileContent (Join-Path $WEB_BUILD_DIR "odin.js")
$wasmBase64 = Convert-FileToBase64 (Join-Path $WEB_BUILD_DIR "index.wasm")
$dataBase64 = Convert-FileToBase64 (Join-Path $WEB_BUILD_DIR "index.data")
```

#### 2. **String Replacements**
```powershell
# replace external script tags with inline scripts
$odinScriptTag = '<script type="text/javascript" src="odin.js"></script>'
$inlineOdinScript = "<script>$odinJs</script>"
$singleFileHtml = $singleFileHtml.Replace($odinScriptTag, $inlineOdinScript)

$indexScriptTag = '<script async type="text/javascript" src="index.js"></script>'
$inlineIndexScript = "<script>$indexJs</script>"
$singleFileHtml = $singleFileHtml.Replace($indexScriptTag, $inlineIndexScript)
```

#### 3. **Embed Binary Assets**
```powershell
# convert WASM fetch to data URL
$wasmFetchCall = 'fetch("index.wasm")'
$wasmDataUrl = "data:application/wasm;base64,$wasmBase64"
$wasmFetchReplacement = "fetch(`"$wasmDataUrl`")"
$singleFileHtml = $singleFileHtml.Replace($wasmFetchCall, $wasmFetchReplacement)

# replace all index.data references
$dataDataUrl = "data:application/octet-stream;base64,$dataBase64"
$singleFileHtml = $singleFileHtml.Replace('build/web/index.data', $dataDataUrl)
$singleFileHtml = $singleFileHtml.Replace('"index.data"', "`"$dataDataUrl`"")
```

#### 4. **Add Responsive Canvas Handling**
```powershell
$resizeScript = @"
<script>
  function resizeCanvas() {
    const canvas = document.getElementById('canvas');
    if (canvas) {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
      canvas.style.width = window.innerWidth + 'px';
      canvas.style.height = window.innerHeight + 'px';
    }
  }
  window.addEventListener('load', resizeCanvas);
  window.addEventListener('resize', resizeCanvas);
  resizeCanvas();
</script>
"@
```

### Key Advantages of Post-Processing

1. **Build System Independence**: Should work (?) with any Emscripten/Odin version
2. **Low Risk**: Original working build remains untouched
3. **Exact Preservation**: Maintains working load order and timing
4. **Easy Debugging**: Can compare single-file vs multi-file builds
5. **Future Proof**: Probably adapts to changes in underlying tools automatically

---

## Usage and Maintenance

### Building Single-File HTML

```powershell
# Build the standard multi-file web build first
.\build_web.ps1

# Post-process into single-file
.\build_web_single.ps1
```

Output: `build\web_single\game_standalone.html` (completely self-contained)

### Distribution

The single-file HTML can be:
- Opened directly in any modern browser (no web server required)
- Shared via email, USB drives, or any file transfer method
- Hosted on static file servers, CDNs, or GitHub Pages
- Embedded in other web pages or applications

### Troubleshooting

**If single-file build fails**:
1. Ensure `build\web\` contains a working multi-file build first
2. Check that all 5 files exist in `build\web\`
3. Verify the standard web build works in browser
4. Check PowerShell execution policy allows script execution

**If browser compatibility issues occur**:
- Ensure WebAssembly support (available in all modern browsers)
- Check browser console for specific error messages
- Test with the original `build\web\index.html` first to isolate issues

**Future Maintenance**:
- When Odin updates: Rebuild and test the standard web build first
- When Emscripten updates: Post-processing may need adjustment for new output format
- When Raylib updates: No changes needed to post-processing logic

---

## Notes

### String Replacement Precision

The post-processing uses exact string matching rather than regex to avoid corrupting embedded JavaScript:

```powershell
# good: Exact string matching
$singleFileHtml.Replace('<script type="text/javascript" src="odin.js"></script>', $replacement)

# bad: Regex could match inside embedded JavaScript
$singleFileHtml -replace 'odin\.js', $replacement  # would corrupt embedded JS
```

### Import Order Preservation

The working build depends on this exact import merge order:
```javascript
const newImports = {
    ...odinImports,    // MUST be first
    ...imports         // Emscripten imports second
}
```

This order ensures `odin_env` becomes import #0, which the WASM binary expects.

### File Encoding

All text files are read as UTF-8, binary files are base64 encoded:
```powershell
function Convert-FileToBase64($filePath) {
  $bytes = [System.IO.File]::ReadAllBytes($filePath)
  return [System.Convert]::ToBase64String($bytes)
}
```

### Canvas Responsiveness

The added resize handling ensures the game canvas adapts to window size changes:
- Sets both rendering resolution (`canvas.width/height`) and display size (`canvas.style.width/height`)
- Responds to both initial load and window resize events
- Uses `window.innerWidth/innerHeight` for full viewport coverage

This documentation should remain accurate regardless of future updates to Odin, Emscripten, or Raylib, as long as the post-processing approach is maintained.
