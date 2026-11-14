# Sonora

Sonora is a native macOS multitrack audio workstation built with AppKit and AVFoundation.

## Download

Download the macOS [`installer package`](Sonora-1.0.pkg) or [`disk image`](Sonora-1.0.dmg) from this repository or the [GitHub Releases page](https://github.com/thomaswales26-hash/sonoradaw/releases). The installer places Sonora in Applications; the disk image includes an Applications shortcut.

## Build

Open the project in CLion and build the `Sonora` CMake target with a Swift-capable Ninja toolchain. The output is a macOS `.app` bundle and is opened automatically after a successful build. The command-line equivalent is:

```sh
cmake -S . -B build -G Ninja
cmake --build build
```

Requires macOS 13 or later and Xcode command-line tools.

## Included

- Multitrack audio import, synchronized playback, track level/pan, mute and solo
- Save/open `.sonora` session documents; imported media remains at its original file paths
- Bundled real-time effects: parametric EQ, compressor, reverb, stereo delay, distortion and pitch shifting

The bundled effects are included with the app. Third-party plug-ins are not redistributed; the current version does not host external Audio Units.
