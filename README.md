# Gero Audio

Native macOS music player for Apple Silicon. Build is automated on GitHub Actions; each push to `main` creates an unsigned `.app` bundle and a ZIP artifact.

## Build

The workflow runs on a GitHub-hosted macOS runner using the Swift toolchain. Download `GeroAudio-macOS-arm64.zip` from the Actions run artifacts, unzip it, then move `GeroAudio.app` to Applications. Because this first development build is ad-hoc signed, macOS may require right-click → Open on first launch.

## Current prototype

- Resizable dark SwiftUI interface
- Album, artist and track views
- Search and sorting
- Recursive folder scan with local preferences
- Artwork and common metadata where supported by macOS
- Audio output device selector independent of the system default
- Basic playback and volume

This is an early prototype. Format decoding depends on macOS AVFoundation support; bit-perfect/exclusive mode, shared playlists, gapless playback and EQ are not claimed as implemented yet. Test on the M4 and M1 Macs before relying on it for critical listening.
