# Pre-Canva Affinity on Linux

![Version](https://img.shields.io/github/v/release/ancym0n/precanva-affinity-linux?color=9171f8&label=Version&labelColor=efeaff&style=flat)
[![License](https://img.shields.io/badge/License-MIT-9171f8?labelColor=efeaff&style=flat)](./LICENSE)

Linux installers and launchers for pre-Canva Affinity V2 apps, focused on keeping paid lifetime licenses working with Affinity ID login.

If you bought a perpetual Affinity V2 license before Canva acquired Affinity, you paid for software you are supposed to own. Moving to Linux should not lock you out of a license you already paid for or push you onto a Canva account. This repo sets up a tested Wine prefix so you can install your official Windows V2 copy, sign in with your Affinity ID, and actually get work done.

## Supported apps

| App | Version | Folder | Notes |
| --- | --- | --- | --- |
| **Affinity Photo 2** | `2.6.5` | `apps/affinity-photo-2/2.6.5` | Tested on Arch Linux, Omarchy, Hyprland, and NVIDIA RTX 4060 |

Each app and version lives in its own folder under `apps/` and shares the common prefix setup in `shared/`. Adding Affinity Designer 2, Publisher 2, or another version just means adding a new folder.

## About Affinity V2 updates

Standalone Affinity V2 is not expected to get any new feature releases.

Version `2.6.5` (Windows build `2.6.5.3782`) is the final Windows build of the standalone V2 line. After Canva acquired Serif and moved development to the unified app, V2 was pulled from sale, version `2.6.6` was never released for Windows, and Serif's update server reports nothing newer than `2.6.5`. Existing lifetime license owners can still download `2.6.5` from their Affinity account and activate it with their Affinity ID. If a maintenance patch ever shows up, it can live in its own version folder without touching the `2.6.5` setup.

## Features

- **Affinity ID login**: Keeps Wine's builtin `crypt32` for valid HTTPS certificates, installs `.NET 4.8` WinRT facades into the GAC, deploys `Windows.winmd`, and moves conflicting Wine metadata files aside.
- **Readable dropdown menus**: Uses ElementalWarrior Wine `11.22-r2` with patched builtin `d3d9` instead of DXVK `d3d9`, avoiding solid black popup menus in WPF.
- **GPU rendering and responsiveness**: Runs Direct3D 11 and Direct2D canvas rendering on the GPU through Wine's patched Vulkan pipeline, deploys `vkd3d-proton`, configures GPU VRAM and persistent NVIDIA shader caches, and disables Wine OpenCL by default so tools like Mesh Warp update smoothly in real time.
- **Hyprland and Btrfs tweaks**: Applies opaque window rules without blur or animations for accurate colors and stable menus, cleans up leftover background `Photo.exe` processes, sizes `Window.xml` to your monitor before launch to prevent clipped canvases and PDFs, and sets `NOCOW` on temporary backstore and cache folders on Btrfs.
- **Desktop integration**: Installs the launcher, app menu entry, icon, `.afphoto` MIME type, and `affinity-photo2-auth://` handler wired straight to the dedicated prefix.

## Installation

### Prebuilt releases (recommended)

Grab the latest archive from the [Releases](https://github.com/ancym0n/precanva-affinity-linux/releases) page (for Photo 2, `affinity-photo-2-2.6.5.tar.gz`) and extract it.

1. Download your Windows x64 MSI installer from your Affinity account (`affinity-photo-msi-2.6.5.exe`, not MSIX and not ARM64).
2. Install the required host packages (example for Arch Linux and Omarchy):
   ```bash
   sudo pacman -S --needed wine winetricks curl tar xz zstd 7zip cabextract python jq
   ```
3. Run the installer and pass your downloaded `.exe`:
   ```bash
   ./apps/affinity-photo-2/2.6.5/install.sh ~/Downloads/affinity-photo-msi-2.6.5.exe
   ```

By default, the script fetches the tested ElementalWarrior Wine and `vkd3d-proton` builds pinned in `shared/runtime.env` from GitHub Releases and checks SHA-256 hashes. To pull the newest upstream GitHub Releases instead, pass `USE_LATEST_RELEASES=1`:

```bash
USE_LATEST_RELEASES=1 ./apps/affinity-photo-2/2.6.5/install.sh ~/Downloads/affinity-photo-msi-2.6.5.exe
```

### From source

```bash
git clone https://github.com/ancym0n/precanva-affinity-linux.git
cd precanva-affinity-linux
./apps/affinity-photo-2/2.6.5/install.sh ~/Downloads/affinity-photo-msi-2.6.5.exe
```

## Usage

1. Launch **Affinity Photo 2** from your app menu or run `affinity-photo-2` in a terminal.
2. Sign in with your Affinity ID email and password to activate your existing lifetime license.
3. OpenCL compute is disabled by default for smooth real-time previews while keeping GPU Direct3D 11 and Vulkan canvas rendering active. If you want to test OpenCL for heavy exports, run `AFFINITY_OPENCL=1 affinity-photo-2`.

## Project layout

```text
.
├── apps/
│   └── affinity-photo-2/
│       └── 2.6.5/
│           ├── AffinityPhoto2.desktop.in
│           ├── README.md
│           ├── affinity-photo2.xml
│           ├── install.sh
│           └── launcher.sh
├── shared/
│   ├── runtime.env
│   └── setup-prefix.sh
├── .github/
│   └── workflows/
│       └── release.yml
├── LICENSE
└── README.md
```

## Notes

No proprietary Affinity binaries are hosted here. Everything installs locally into your own Wine prefix using the official Windows installer from your Affinity account.

Built on top of community work from ElementalWarrior, [Affinity-Wine-Builder](https://github.com/jfacemyer/Affinity-Wine-Builder), [Linux-Affinity-Installer](https://github.com/ryzendew/Linux-Affinity-Installer), and [vkd3d-proton](https://github.com/HansKristian-Work/vkd3d-proton).

## License

[MIT](./LICENSE). Found a bug? [Open an issue](https://github.com/ancym0n/precanva-affinity-linux/issues).
