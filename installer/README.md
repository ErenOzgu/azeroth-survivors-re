# Windows installer

`azeroth-survivors.iss` is an [Inno Setup 6](https://jrsoftware.org/isinfo.php) script. The
installer asks where to install, copies the player build of `warcraft-survivors.exe`, downloads
the WoW 1.12.1 client data from archive.org (the same zip `scripts/fetch-data.sh` uses) and
extracts its `Data\*.MPQ` beside the exe. No Blizzard content is bundled in it.

CI builds it: `.github/workflows/windows-installer.yml` (artifact on every run, release asset on a
`v*` tag).

By hand, on Windows with Rust, the MSVC build tools and Inno Setup installed:

```powershell
# The player build: --no-default-features leaves out `dev`, which would stamp this machine's
# source path into the exe.
cargo build --release -p warcraft-survivors --no-default-features
iscc /DAppVersion=0.2.0 installer\azeroth-survivors.iss   # -> installer\output\AzerothSurvivors-Setup-0.2.0.exe
```

Notes:

- Per-user install (no admin prompt): the game writes its settings to `<install dir>\benilla-config`.
- The wizard asks where the game data comes from: download it, or use data the user already has by
  pointing at a folder. The folder may hold `1.12.1-5875_enUS.zip` (or another zip), or be the WoW
  `Data` folder (or the folder above it) with the `.MPQ` files; nothing is downloaded then, and the
  question is skipped when the install folder already has `Data\terrain.MPQ` and `Data\patch.MPQ`.
- A download goes to the user's `%TEMP%` first, then the MPQs are extracted into the install
  folder, so both drives need about 5.5 GB free at that point. A folder of MPQs is copied, not
  linked, so the install keeps its own copy.
- The download is interactive only (it runs when the user clicks Install); `/SILENT` installs skip it.
- `test-extract-data.ps1` tests the helper (`extract-data.ps1`); CI runs it, and compiles the `.iss`
  with a stand-in exe, before the full build starts.
