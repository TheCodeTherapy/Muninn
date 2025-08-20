#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Odin Web Build Script with Automatic EMSDK Management
.DESCRIPTION
  Builds the game for web using WebAssembly through EMSDK. Automatically installs
  and manages EMSDK if not present or outdated.
.PARAMETER Run
  Start a local web server after building
.PARAMETER BuildOnly
  Build only, don't start web server
.PARAMETER ForceUpdate
  Force update EMSDK even if already installed
.EXAMPLE
  .\build_web.ps1
  Build web version (default)
.EXAMPLE
  .\build_web.ps1 -Run
  Build and start local web server
.EXAMPLE
  .\build_web.ps1 -ForceUpdate
  Force EMSDK update and build
#>

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
$OUT_DIR = "build\web"
$SOURCE_DIR = "source\main_web"
$ASSETS_DIR = "assets"
$EMSDK_DIR = "$env:USERPROFILE\.emsdk"
$EMSDK_REPO = "https://github.com/emscripten-core/emsdk.git"

# Colors for better output
$script:Colors = @{
  Success = "Green"
  Warning = "Yellow"
  Error = "Red"
  Info = "Cyan"
  Debug = "Gray"
}

function Write-ColorOutput {
  param(
    [string]$Message,
    [string]$Color = "White"
  )
  Write-Host $Message -ForegroundColor $Color
}

function Test-CommandExists {
  param([string]$Command)
  try {
    Get-Command $Command -ErrorAction Stop | Out-Null
    return $true
  }
  catch {
    return $false
  }
}

function Test-EmsdkInstalled {
  return (Test-Path $EMSDK_DIR) -and (Test-Path "$EMSDK_DIR\emsdk.bat") -and (Test-Path "$EMSDK_DIR\emsdk_env.bat")
}

function Test-EmsdkActivated {
  try {
    # Test if emcc is available and working
    $env:EMSDK_QUIET = "1"
    & "$EMSDK_DIR\emsdk_env.bat" *>$null
    $emccPath = (Get-Command emcc -ErrorAction SilentlyContinue).Source
    if ($emccPath) {
      $version = & emcc --version 2>$null | Select-Object -First 1
      return $version -match "emcc"
    }
  }
  catch {
    return $false
  }
  return $false
}

function Install-Emsdk {
  Write-ColorOutput "📦 Installing EMSDK..." $Colors.Info

  # Check prerequisites
  if (-not (Test-CommandExists "git")) {
    Write-ColorOutput "❌ Git is required but not found. Please install Git first." $Colors.Error
    Write-ColorOutput "   Download from: https://git-scm.com/download/win" $Colors.Info
    return $false
  }

  if (-not (Test-CommandExists "python")) {
    Write-ColorOutput "❌ Python is required but not found. Please install Python first." $Colors.Error
    Write-ColorOutput "   Download from: https://python.org/downloads/" $Colors.Info
    return $false
  }

  try {
    # Clone EMSDK repository
    Write-ColorOutput "Cloning EMSDK repository to $EMSDK_DIR..." $Colors.Info
    if (Test-Path $EMSDK_DIR) {
      Remove-Item $EMSDK_DIR -Recurse -Force
    }

    & git clone $EMSDK_REPO $EMSDK_DIR 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
      Write-ColorOutput "❌ Failed to clone EMSDK repository" $Colors.Error
      return $false
    }

    # Install and activate latest EMSDK
    Push-Location $EMSDK_DIR
    try {
      Write-ColorOutput "Installing latest EMSDK..." $Colors.Info
      & .\emsdk.bat install latest 2>&1 | Out-Host
      if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Failed to install EMSDK" $Colors.Error
        return $false
      }

      Write-ColorOutput "Activating EMSDK..." $Colors.Info
      & .\emsdk.bat activate latest 2>&1 | Out-Host
      if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Failed to activate EMSDK" $Colors.Error
        return $false
      }

      Write-ColorOutput "✅ EMSDK installed and activated successfully!" $Colors.Success
      return $true
    }
    finally {
      Pop-Location
    }
  }
  catch {
    Write-ColorOutput "❌ EMSDK installation error: $($_.Exception.Message)" $Colors.Error
    return $false
  }
}

function Update-Emsdk {
  Write-ColorOutput "🔄 Updating EMSDK..." $Colors.Info

  try {
    Push-Location $EMSDK_DIR
    try {
      # Pull latest changes
      & git pull 2>&1 | Out-Host
      if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Failed to update EMSDK repository" $Colors.Error
        return $false
      }

      # Install and activate latest
      & .\emsdk.bat install latest 2>&1 | Out-Host
      if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Failed to install latest EMSDK" $Colors.Error
        return $false
      }

      & .\emsdk.bat activate latest 2>&1 | Out-Host
      if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Failed to activate latest EMSDK" $Colors.Error
        return $false
      }

      Write-ColorOutput "✅ EMSDK updated successfully!" $Colors.Success
      return $true
    }
    finally {
      Pop-Location
    }
  }
  catch {
    Write-ColorOutput "❌ EMSDK update error: $($_.Exception.Message)" $Colors.Error
    return $false
  }
}

function Set-EmsdkEnvironment {
  try {
    # Set core EMSDK environment variables
    $env:EMSDK = $EMSDK_DIR -replace '\\', '/'

    # Find Node.js installation (look for pattern like "22.16.0_64bit")
    $nodePattern = Get-ChildItem "$EMSDK_DIR\node" -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '\d+\.\d+\.\d+_64bit' } |
                   Sort-Object Name -Descending |
                   Select-Object -First 1
    if ($nodePattern) {
      $env:EMSDK_NODE = "$($nodePattern.FullName)\bin\node.exe"
      Write-ColorOutput "Found Node.js: $($nodePattern.Name)" $Colors.Debug
    }

    # Find Python installation (look for pattern like "3.13.3_64bit")
    $pythonPattern = Get-ChildItem "$EMSDK_DIR\python" -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '\d+\.\d+\.\d+_64bit' } |
                     Sort-Object Name -Descending |
                     Select-Object -First 1
    if ($pythonPattern) {
      $env:EMSDK_PYTHON = "$($pythonPattern.FullName)\python.exe"
      Write-ColorOutput "Found Python: $($pythonPattern.Name)" $Colors.Debug
    }

    # Clear any existing EMSDK paths from PATH to avoid duplicates
    $pathParts = $env:PATH -split ';' | Where-Object { $_ -notlike "*emsdk*" }

    # Add EMSDK paths to PATH in correct order
    $emsdkPaths = @(
      "$EMSDK_DIR\upstream\emscripten",
      $EMSDK_DIR
    )

    # Build new PATH
    $newPath = ($emsdkPaths + $pathParts) -join ';'
    $env:PATH = $newPath

    # Debug: Show what we're adding to PATH
    foreach ($path in $emsdkPaths) {
      if (Test-Path $path) {
        Write-ColorOutput "Added to PATH: $path" $Colors.Debug
      }
      else {
        Write-ColorOutput "Path not found: $path" $Colors.Warning
      }
    }

    Write-ColorOutput "✅ EMSDK environment configured for PowerShell" $Colors.Success
    return $true
  }
  catch {
    Write-ColorOutput "❌ Failed to set EMSDK environment: $($_.Exception.Message)" $Colors.Error
    return $false
  }
}

function Initialize-Emsdk {
  if ($ForceUpdate -or -not (Test-EmsdkInstalled)) {
    if (-not (Install-Emsdk)) {
      return $false
    }
  }
  elseif (Test-EmsdkInstalled -and -not (Test-EmsdkActivated)) {
    Write-ColorOutput "EMSDK found but not activated, updating..." $Colors.Info
    if (-not (Update-Emsdk)) {
      return $false
    }
  }
  else {
    Write-ColorOutput "✅ EMSDK already installed and activated" $Colors.Success
  }

  # Set EMSDK environment for this PowerShell session
  if (-not (Set-EmsdkEnvironment)) {
    return $false
  }

  # Verify emcc is now available
  try {
    Write-ColorOutput "Testing emcc availability..." $Colors.Debug

    # First check if emcc exists in PATH
    $emccPath = Get-Command emcc -ErrorAction SilentlyContinue
    if ($emccPath) {
      Write-ColorOutput "Found emcc at: $($emccPath.Source)" $Colors.Debug
      $emccVersion = & emcc --version 2>&1 | Select-Object -First 1
      Write-ColorOutput "emcc version: $emccVersion" $Colors.Debug

      if ($emccVersion -match "emcc") {
        Write-ColorOutput "✅ EMSDK environment activated for build" $Colors.Success
        return $true
      }
      else {
        Write-ColorOutput "❌ emcc exists but version check failed" $Colors.Error
        return $false
      }
    }
    else {
      Write-ColorOutput "❌ emcc not found in PATH" $Colors.Error
      Write-ColorOutput "Current PATH includes:" $Colors.Debug
      $env:PATH -split ';' | Where-Object { $_ -like "*emsdk*" } | ForEach-Object {
        Write-ColorOutput "  $_" $Colors.Debug
      }

      # Check if emcc exists in expected location
      $expectedEmcc = "$EMSDK_DIR\upstream\emscripten\emcc.bat"
      if (Test-Path $expectedEmcc) {
        Write-ColorOutput "Found emcc.bat at expected location: $expectedEmcc" $Colors.Info
        Write-ColorOutput "Trying direct execution..." $Colors.Info
        try {
          $directVersion = & "$expectedEmcc" --version 2>&1 | Select-Object -First 1
          Write-ColorOutput "Direct execution result: $directVersion" $Colors.Info
        }
        catch {
          Write-ColorOutput "Direct execution failed: $($_.Exception.Message)" $Colors.Error
        }
      }
      else {
        Write-ColorOutput "emcc.bat not found at: $expectedEmcc" $Colors.Error
      }

      return $false
    }
  }
  catch {
    Write-ColorOutput "❌ Failed to verify emcc: $($_.Exception.Message)" $Colors.Error
    Write-ColorOutput "Exception details: $($_.Exception.ToString())" $Colors.Debug
    return $false
  }
}

function Initialize-BuildDirectories {
  if (-not (Test-Path $OUT_DIR)) {
    New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null
    Write-ColorOutput "Created build directory: $OUT_DIR" $Colors.Debug
  }

  # Clean the output directory for fresh web build
  Write-ColorOutput "Cleaning web build directory..." $Colors.Info
  if (Test-Path $OUT_DIR) {
    Remove-Item "$OUT_DIR\*" -Recurse -Force -ErrorAction SilentlyContinue
  }
  New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null
}

function Build-WebGame {
  Write-ColorOutput "Building WebAssembly game..." $Colors.Info

  try {
    # Build Odin WebAssembly object
    $buildArgs = @(
      "build", $SOURCE_DIR,
      "-target:js_wasm32", "-build-mode:obj",
      "-define:RAYLIB_WASM_LIB=env.o", "-define:RAYGUI_WASM_LIB=env.o",
      "-vet", "-strict-style",
      "-out:$OUT_DIR\game.wasm.o"
    )

    $output = & odin @buildArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
      Write-ColorOutput "❌ Odin build failed!" $Colors.Error
      if ($output) {
        Write-ColorOutput ($output | Out-String) $Colors.Error
      }
      return $false
    }

    # Get Odin root path for library files
    $odinPath = & odin root
    if ($LASTEXITCODE -ne 0) {
      Write-ColorOutput "❌ Failed to get Odin root path" $Colors.Error
      return $false
    }

    # Copy odin.js runtime
    $odinJsSource = "$odinPath\core\sys\wasm\js\odin.js"
    if (Test-Path $odinJsSource) {
      Copy-Item $odinJsSource "$OUT_DIR\odin.js" -Force
      Write-ColorOutput "✅ Copied Odin WebAssembly runtime" $Colors.Success
    }
    else {
      Write-ColorOutput "❌ odin.js not found at $odinJsSource" $Colors.Error
      return $false
    }

    # Build final WebAssembly with emcc
    Write-ColorOutput "Linking WebAssembly with emcc..." $Colors.Info

    $files = @(
      "$OUT_DIR\game.wasm.o",
      "$odinPath\vendor\raylib\wasm\libraylib.a",
      "$odinPath\vendor\raylib\wasm\libraygui.a"
    )

    $flags = @(
      "-sUSE_GLFW=3", "-sWASM_BIGINT", "-sWARN_ON_UNDEFINED_SYMBOLS=0", "-sASSERTIONS",
      "--shell-file", "$SOURCE_DIR\index_template.html",
      "--preload-file", $ASSETS_DIR
    )

    $emccArgs = @("-o", "$OUT_DIR\index.html") + $files + $flags

    & emcc @emccArgs 2>&1 | Out-Host
    $exitCode = $LASTEXITCODE

    # Clean up temporary object file
    if (Test-Path "$OUT_DIR\game.wasm.o") {
      Remove-Item "$OUT_DIR\game.wasm.o" -Force
    }

    if ($exitCode -ne 0) {
      Write-ColorOutput "❌ emcc linking failed!" $Colors.Error
      return $false
    }

    Write-ColorOutput "✅ WebAssembly game built successfully!" $Colors.Success
    return $true
  }
  catch {
    Write-ColorOutput "❌ Build error: $($_.Exception.Message)" $Colors.Error
    return $false
  }
}

function Start-WebServer {
  Write-ColorOutput "🌐 Starting local web server..." $Colors.Info

  try {
    # Try to find a suitable web server
    if (Test-CommandExists "python") {
      Write-ColorOutput "Starting Python HTTP server on http://localhost:8000" $Colors.Info
      Push-Location $OUT_DIR
      try {
        & python -m http.server 8000
      }
      finally {
        Pop-Location
      }
    }
    elseif (Test-CommandExists "npx") {
      Write-ColorOutput "Starting Node.js HTTP server on http://localhost:8000" $Colors.Info
      Push-Location $OUT_DIR
      try {
        & npx http-server -p 8000
      }
      finally {
        Pop-Location
      }
    }
    else {
      Write-ColorOutput "⚠️  No suitable web server found. Please serve files from $OUT_DIR manually." $Colors.Warning
      Write-ColorOutput "   You can use: python -m http.server 8000" $Colors.Info
      Write-ColorOutput "   Or install Node.js and use: npx http-server" $Colors.Info
    }
  }
  catch {
    Write-ColorOutput "❌ Failed to start web server: $($_.Exception.Message)" $Colors.Error
  }
}

function Main {
  Write-ColorOutput "🌐 Odin Web Build Script" $Colors.Info
  Write-ColorOutput "========================" $Colors.Info

  # Platform detection (for consistency with other scripts)
  Write-ColorOutput "Platform detected: windows" $Colors.Debug

  # Initialize EMSDK
  if (-not (Initialize-Emsdk)) {
    exit 1
  }

  # Initialize build environment
  Initialize-BuildDirectories

  # Build the web game
  if (-not (Build-WebGame)) {
    exit 1
  }

  # Handle run mode
  if ($Run) {
    Start-WebServer
  }

  Write-ColorOutput "🎉 Web build complete!" $Colors.Success
  Write-ColorOutput "Web build created in $OUT_DIR" $Colors.Info

  if (-not $Run) {
    Write-ColorOutput "To test, serve files from $OUT_DIR with a web server:" $Colors.Info
    Write-ColorOutput "  python -m http.server 8000" $Colors.Info
  }
}

# Run the main function
Main
