# Affinity Photo 2 (2.6.5)

Installer and launcher for Affinity Photo 2 version `2.6.5` on Linux with working Affinity ID login for paid lifetime licenses.

## Requirements

Download the official Windows x64 MSI installer (`affinity-photo-msi-2.6.5.exe`) from your Affinity account. Do not use the ARM64 build or the MSIX package.

Install the host dependencies first (Arch Linux and Omarchy):

```bash
sudo pacman -S --needed wine winetricks curl tar xz zstd 7zip cabextract python jq
```

## Installation

Run the installer script and point it at your downloaded `.exe`:

```bash
./apps/affinity-photo-2/2.6.5/install.sh ~/Downloads/affinity-photo-msi-2.6.5.exe
```

This sets up a dedicated Wine prefix at `~/.AffinityPhoto2`, installs the tested ElementalWarrior Wine `11.22-r2` build and `vkd3d-proton 3.1` from GitHub Releases, configures `.NET 4.8` and WinRT metadata, extracts and installs the embedded MSI silently, and registers the launcher and `.afphoto` file association.

Optional environment variables:

- `USE_LATEST_RELEASES=1`: Pulls the newest Wine and `vkd3d-proton` tags from GitHub Releases instead of the pinned ones in `shared/runtime.env`.
- `AFFINITY_PHOTO2_PREFIX`: Overrides the Wine prefix path (defaults to `~/.AffinityPhoto2`).

```bash
USE_LATEST_RELEASES=1 ./apps/affinity-photo-2/2.6.5/install.sh ~/Downloads/affinity-photo-msi-2.6.5.exe
```

## Usage

1. Open **Affinity Photo 2** from your app menu or run `affinity-photo-2`.
2. Sign in with your Affinity ID email and password to activate your lifetime license.
3. GPU canvas rendering runs through Direct3D 11 and Vulkan, while Wine OpenCL is disabled by default to avoid live-preview stalls in tools like Mesh Warp. To test OpenCL on heavy exports, launch with:
   ```bash
   AFFINITY_OPENCL=1 affinity-photo-2
   ```
