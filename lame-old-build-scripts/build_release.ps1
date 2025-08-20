#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Odin Release Build Script
.DESCRIPTION
  Builds an optimized release version of the game with no debugging symbols.
  Creates a fast, distributable build with optimizations enabled.
.PARAMETER Run
  Start the game after building
.PARAMETER BuildOnly
  Build only, don't run the game
.EXAMPLE
  .\build_release.ps1
  Build release version (default)
.EXAMPLE
  .\build_release.ps1 -Run
  Build and start the release version
.EXAMPLE
  .\build_release.ps1 -BuildOnly
  Build only and exit
#>

param(
  [switch]$Run,
  [switch]$BuildOnly
)

# If no parameters are provided, default to BuildOnly mode
if (-not $Run -and -not $BuildOnly) {
  $BuildOnly = $true
}

# Configuration
$OUT_DIR = "build\release"
$EXE = "game_release.exe"
$SOURCE_DIR = "source\main_release"
$ASSETS_DIR = "assets"

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

function Initialize-BuildDirectories {
  if (-not (Test-Path $OUT_DIR)) {
    New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null
    Write-ColorOutput "Created build directory: $OUT_DIR" $Colors.Debug
  }

  # Clean the output directory for fresh release build
  Write-ColorOutput "Cleaning release build directory..." $Colors.Info
  if (Test-Path $OUT_DIR) {
    Remove-Item "$OUT_DIR\*" -Recurse -Force -ErrorAction SilentlyContinue
  }
  New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null
}

function Build-ReleaseGame {
  Write-ColorOutput "Building optimized release executable..." $Colors.Info

  try {
    $buildArgs = @(
      "build", $SOURCE_DIR,
      "-strict-style", "-vet",
      "-no-bounds-check", "-o:speed",
      "-subsystem:windows",
      "-out:$OUT_DIR\$EXE"
    )

    # Use & operator for direct execution
    $output = & odin @buildArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
      Write-ColorOutput "❌ Build failed!" $Colors.Error
      if ($output) {
        Write-ColorOutput ($output | Out-String) $Colors.Error
      }
      return $false
    }

    Write-ColorOutput "✅ Release executable built successfully!" $Colors.Success
    return $true
  }
  catch {
    Write-ColorOutput "❌ Build error: $($_.Exception.Message)" $Colors.Error
    return $false
  }
}

function Copy-Assets {
  if (Test-Path $ASSETS_DIR) {
    Write-ColorOutput "Copying assets..." $Colors.Info

    try {
      # Copy assets to output directory
      Copy-Item -Path $ASSETS_DIR -Destination "$OUT_DIR\$ASSETS_DIR" -Recurse -Force
      Write-ColorOutput "✅ Assets copied successfully!" $Colors.Success
      return $true
    }
    catch {
      Write-ColorOutput "❌ Failed to copy assets: $($_.Exception.Message)" $Colors.Error
      return $false
    }
  }
  else {
    Write-ColorOutput "⚠️  Assets directory not found, skipping..." $Colors.Warning
    return $true
  }
}

function Copy-RaylibDll {
  if (-not (Test-Path "$OUT_DIR\raylib.dll")) {
    try {
      $odinRoot = & odin root
      $raylibSource = "$odinRoot\vendor\raylib\windows\raylib.dll"

      if (Test-Path $raylibSource) {
        Copy-Item -Path $raylibSource -Destination "$OUT_DIR\raylib.dll" -Force
        Write-ColorOutput "✅ raylib.dll copied to build directory" $Colors.Success
      }
      else {
        Write-ColorOutput "⚠️  raylib.dll not found in Odin installation" $Colors.Warning
      }
      return $true
    }
    catch {
      Write-ColorOutput "❌ Failed to copy raylib.dll: $($_.Exception.Message)" $Colors.Error
      return $false
    }
  }
  return $true
}

function Main {
  Write-ColorOutput "🚀 Odin Release Build Script" $Colors.Info
  Write-ColorOutput "============================" $Colors.Info

  # Platform detection (for consistency with other scripts)
  Write-ColorOutput "Platform detected: windows" $Colors.Debug

  # Initialize build environment
  Initialize-BuildDirectories

  # Build the release executable
  if (-not (Build-ReleaseGame)) {
    exit 1
  }

  # Copy assets
  if (-not (Copy-Assets)) {
    exit 1
  }

  # Copy raylib.dll if needed
  if (-not (Copy-RaylibDll)) {
    exit 1
  }

  # Handle run mode
  if ($Run) {
    Write-ColorOutput "Starting release game..." $Colors.Info
    try {
      Start-Process -FilePath "$OUT_DIR\$EXE" -WorkingDirectory $OUT_DIR
      Write-ColorOutput "🎮 Release game started!" $Colors.Success
    }
    catch {
      Write-ColorOutput "❌ Failed to start game: $($_.Exception.Message)" $Colors.Error
      exit 1
    }
  }

  Write-ColorOutput "🎉 Release build complete!" $Colors.Success
  Write-ColorOutput "Release build created in $OUT_DIR" $Colors.Info
}

# Run the main function
Main
