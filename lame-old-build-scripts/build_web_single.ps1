param(
  [switch]$Run,
  [switch]$BuildOnly,
  [switch]$ForceUpdate
)

# If no parameters are provided, default to BuildOnly mode
if (-not $Run -and -not $BuildOnly -and -not $ForceUpdate) {
  $BuildOnly = $true
}

# Configuration
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$WEB_BUILD_DIR = Join-Path $SCRIPT_DIR "build\web"
$OUT_DIR = Join-Path $SCRIPT_DIR "build\web_single"
$FINAL_HTML = "game_standalone.html"

# Colors for better output
$script:Colors = @{
  Success = "Green"
  Warning = "Yellow"
  Error = "Red"
  Info = "Cyan"
}

function Write-ColorOutput {
  param($Message, $Color)
  Write-Host $Message -ForegroundColor $Color
}

function Test-WebBuildExists {
  $requiredFiles = @("index.html", "index.js", "index.wasm", "odin.js", "index.data")

  if (-not (Test-Path $WEB_BUILD_DIR)) {
    Write-ColorOutput "❌ Web build directory not found: $WEB_BUILD_DIR" $Colors.Error
    Write-ColorOutput "💡 Run the regular web build first: .\build_web.ps1" $Colors.Info
    return $false
  }

  foreach ($file in $requiredFiles) {
    $filePath = Join-Path $WEB_BUILD_DIR $file
    if (-not (Test-Path $filePath)) {
      Write-ColorOutput "❌ Required file missing: $file" $Colors.Error
      Write-ColorOutput "💡 Run the regular web build first: .\build_web.ps1" $Colors.Info
      return $false
    }
  }

  return $true
}

function Convert-FileToBase64 {
  param($FilePath)

  $bytes = [System.IO.File]::ReadAllBytes($FilePath)
  return [System.Convert]::ToBase64String($bytes)
}

function Read-TextFileContent {
  param($FilePath)

  return Get-Content $FilePath -Raw -Encoding UTF8
}

function New-SingleFileHTML {
  Write-ColorOutput "📄 Creating single-file HTML..." $Colors.Info

  # Read all source files
  $indexHtml = Read-TextFileContent (Join-Path $WEB_BUILD_DIR "index.html")
  $indexJs = Read-TextFileContent (Join-Path $WEB_BUILD_DIR "index.js")
  $odinJs = Read-TextFileContent (Join-Path $WEB_BUILD_DIR "odin.js")
  $wasmBase64 = Convert-FileToBase64 (Join-Path $WEB_BUILD_DIR "index.wasm")
  $dataBase64 = Convert-FileToBase64 (Join-Path $WEB_BUILD_DIR "index.data")

  # Calculate embedded sizes
  $wasmSize = (Get-Item (Join-Path $WEB_BUILD_DIR "index.wasm")).Length
  $dataSize = (Get-Item (Join-Path $WEB_BUILD_DIR "index.data")).Length

  Write-ColorOutput "📊 Embedding files:" $Colors.Info
  Write-ColorOutput "  • odin.js: $('{0:N0}' -f $odinJs.Length) characters" $Colors.Info
  Write-ColorOutput "  • index.js: $('{0:N0}' -f $indexJs.Length) characters" $Colors.Info
  Write-ColorOutput "  • index.wasm: $('{0:N0}' -f $wasmSize) bytes → $('{0:N0}' -f $wasmBase64.Length) base64" $Colors.Info
  Write-ColorOutput "  • index.data: $('{0:N0}' -f $dataSize) bytes → $('{0:N0}' -f $dataBase64.Length) base64" $Colors.Info

  $singleFileHtml = $indexHtml

  # 1. replace external odin.js script tag
  $odinScriptTag = '<script type="text/javascript" src="odin.js"></script>'
  $inlineOdinScript = "<script>$odinJs</script>"
  $singleFileHtml = $singleFileHtml.Replace($odinScriptTag, $inlineOdinScript)

  # 2. replace external index.js script tag
  $indexScriptTag = '<script async type="text/javascript" src="index.js"></script>'
  $inlineIndexScript = "<script>$indexJs</script>"
  $singleFileHtml = $singleFileHtml.Replace($indexScriptTag, $inlineIndexScript)

  # 3. replace fetch call for WASM
  $wasmFetchCall = 'fetch("index.wasm")'
  $wasmDataUrl = "data:application/wasm;base64,$wasmBase64"
  $wasmFetchReplacement = "fetch(`"$wasmDataUrl`")"
  $singleFileHtml = $singleFileHtml.Replace($wasmFetchCall, $wasmFetchReplacement)

  # 4. replace all index.data references with embedded data
  $dataDataUrl = "data:application/octet-stream;base64,$dataBase64"
  $singleFileHtml = $singleFileHtml.Replace('"index.data"', "`"$dataDataUrl`"")
  $singleFileHtml = $singleFileHtml.Replace("'index.data'", "'$dataDataUrl'")
  $singleFileHtml = $singleFileHtml.Replace('build/web/index.data', $dataDataUrl)
  $singleFileHtml = $singleFileHtml.Replace('index.data', $dataDataUrl)

  # 5. add window resize handling before closing </body> tag
  $resizeScript = @"

  <!-- Window Resize Handler -->
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

    // Resize on load
    window.addEventListener('load', resizeCanvas);

    // Resize on window resize
    window.addEventListener('resize', resizeCanvas);

    // Initial resize
    resizeCanvas();
  </script>
"@
  $singleFileHtml = $singleFileHtml.Replace('</body>', "$resizeScript`n</body>")

  # 6. Update title
  $oldTitle = '<title>Odin + Raylib on the web</title>'
  $newTitle = '<title>Odin + Raylib (Standalone)</title>'
  $singleFileHtml = $singleFileHtml.Replace($oldTitle, $newTitle)

  return $singleFileHtml
}

# Main execution
Write-ColorOutput "🚀 Odin Single-File Web Build (Post-Processing)" $Colors.Success
Write-ColorOutput "=============================================" $Colors.Success

# Verify web build exists
if (-not (Test-WebBuildExists)) {
  Write-ColorOutput "❌ Cannot proceed without valid web build" $Colors.Error
  exit 1
}

# Create output directory
if (Test-Path $OUT_DIR) {
  Write-ColorOutput "🧹 Cleaning existing single-file build directory..." $Colors.Info
  Remove-Item $OUT_DIR -Recurse -Force
}
New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null

# Create single-file HTML
$singleFileContent = New-SingleFileHTML

# Write output file
$outputPath = Join-Path $OUT_DIR $FINAL_HTML
Set-Content -Path $outputPath -Value $singleFileContent -Encoding UTF8

# Calculate final size
$finalSize = (Get-Item $outputPath).Length
$finalSizeMB = [math]::Round($finalSize / 1MB, 2)

Write-ColorOutput "✅ Single-file build complete!" $Colors.Success
Write-ColorOutput "📁 Output: $outputPath" $Colors.Success
Write-ColorOutput "📊 Final size: $('{0:N0}' -f $finalSize) bytes ($finalSizeMB MB)" $Colors.Success
Write-ColorOutput "" $Colors.Info
Write-ColorOutput "🌐 To test:" $Colors.Info
Write-ColorOutput "  • Open $outputPath directly in your browser" $Colors.Info
Write-ColorOutput "  • No web server required - it's completely self-contained!" $Colors.Success
Write-ColorOutput "" $Colors.Info
Write-ColorOutput "🎯 This build preserves the exact working architecture from build\web" $Colors.Info
Write-ColorOutput "🔧 All files embedded using post-processing - no build modifications" $Colors.Success

# Run if requested
if ($Run) {
  Write-ColorOutput "🌐 Opening standalone build..." $Colors.Info
  Start-Process $outputPath
}
