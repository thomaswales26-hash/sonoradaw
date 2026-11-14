# Sonora

Sonora is a native macOS multitrack audio workstation built with AppKit and AVFoundation.

## Download

The macOS installer is available as [`Sonora-1.0.dmg`](Sonora-1.0.dmg). Open the disk image, then drag Sonora to Applications.

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
