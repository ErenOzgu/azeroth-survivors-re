# Windows installer (draft)

A setup wizard for the native Windows build of Azeroth Survivors.

## What it does

1. Asks for the user's own WoW 1.12.1 (build 5875) `Data` folder and checks `terrain.MPQ` / `patch.MPQ`.
2. Installs Visual Studio Build Tools 2022 (C++ tools + Windows 11 SDK) if missing.
3. Installs Git for Windows and rustup if missing, then the Rust toolchain pinned in `rust-toolchain.toml`.
4. Clones the repository and runs `cargo build --release -p warcraft-survivors`.
5. Creates Start Menu (and optional desktop) shortcuts that start the game with `WOW_DATA` set.

It does not bundle or download any Blizzard content.

## Build the installer

Install [Inno Setup 6](https://jrsoftware.org/isinfo.php), then:

```
ISCC.exe AzerothSurvivors.iss
```

Output: `Output\AzerothSurvivors-Setup.exe`.

## Status

Draft, not yet tested on a clean Windows machine. Things to verify:

- Build Tools component IDs and the silent install flags on a fresh system (Windows Sandbox or a VM).
- Total disk space and build time (the `ExtraDiskSpaceRequired` value is a placeholder).
- That `build.rs` (`benilla_buildstamp`) works with the full clone the script makes.
- Uninstall removes the game but leaves Build Tools, Git and Rust in place.
