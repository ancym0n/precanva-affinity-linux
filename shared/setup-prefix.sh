#!/usr/bin/env bash
set -euo pipefail

# Shared Wine prefix setup for pre-Canva Affinity V2 apps.
# Sourced by per-app install.sh scripts.

log_step() { printf '\n==> %s\n' "$1"; }
log_info() { printf '  %s\n' "$1"; }
log_err()  { printf 'Error: %s\n' "$1" >&2; }

check_dependencies() {
    local missing=()
    local cmd
    for cmd in curl tar xz unzstd 7z cabextract winetricks python3 jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        log_err "Missing required tools: ${missing[*]}"
        log_info "On Arch Linux or Omarchy, install them with:"
        log_info "  sudo pacman -S --needed wine winetricks curl tar xz zstd 7zip cabextract python jq"
        exit 1
    fi
}

resolve_latest_github_asset() {
    local repo="$1"
    local pattern="$2"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | jq -r --arg pat "$pattern" '.assets[] | select(.name | test($pat)) | .browser_download_url' \
        | head -n 1
}

download_checked() {
    local url="$1"
    local dest="$2"
    local expected_sha="${3:-}"

    if [ -f "$dest" ] && [ -n "$expected_sha" ]; then
        if printf '%s  %s\n' "$expected_sha" "$dest" | sha256sum -c - >/dev/null 2>&1; then
            log_info "Using cached $(basename "$dest")"
            return 0
        fi
        rm -f "$dest"
    fi

    log_info "Downloading $(basename "$dest")..."
    curl -fL --retry 3 --progress-bar "$url" -o "${dest}.part"
    mv -f "${dest}.part" "$dest"

    if [ -n "$expected_sha" ]; then
        printf '%s  %s\n' "$expected_sha" "$dest" | sha256sum -c - >/dev/null
        log_info "Verified SHA-256 for $(basename "$dest")"
    fi
}

setup_wine_and_vkd3d() {
    local prefix="$1"
    local cache="$prefix/.cache"
    mkdir -p "$prefix" "$cache"

    local wine_url="$WINE_URL"
    local wine_sha="$WINE_SHA256"
    local wine_file="$WINE_ASSET"

    local vkd3d_url="$VKD3D_URL"
    local vkd3d_sha="$VKD3D_SHA256"
    local vkd3d_file="$VKD3D_ASSET"

    if [ "${USE_LATEST_RELEASES:-0}" = "1" ]; then
        log_step "Checking latest GitHub releases for Wine and vkd3d-proton"
        local latest_wine
        latest_wine="$(resolve_latest_github_asset "$WINE_REPO" '^ElementalWarrior-wine-.*\.tar\.xz$' || true)"
        if [ -n "$latest_wine" ]; then
            wine_url="$latest_wine"
            wine_file="$(basename "$latest_wine")"
            wine_sha=""
        fi

        local latest_vkd3d
        latest_vkd3d="$(resolve_latest_github_asset "$VKD3D_REPO" '^vkd3d-proton-.*\.tar\.zst$' || true)"
        if [ -n "$latest_vkd3d" ]; then
            vkd3d_url="$latest_vkd3d"
            vkd3d_file="$(basename "$latest_vkd3d")"
            vkd3d_sha=""
        fi
    fi

    log_step "Fetching ElementalWarrior Wine and vkd3d-proton"
    download_checked "$wine_url" "$cache/$wine_file" "$wine_sha"
    download_checked "$vkd3d_url" "$cache/$vkd3d_file" "$vkd3d_sha"
    download_checked "$WINMETADATA_URL" "$cache/WinMetadata.tar.xz" ""
    download_checked "$WINE_DARK_THEME_URL" "$cache/wine-dark-theme.reg" ""

    log_step "Extracting Wine runtime"
    rm -rf "$prefix"/ElementalWarrior-wine-* "$prefix/ElementalWarriorWine"
    tar -xf "$cache/$wine_file" -C "$prefix"
    local wine_dir
    wine_dir="$(find "$prefix" -maxdepth 1 -type d -name 'ElementalWarrior-wine-*' | head -n 1)"
    if [ -z "$wine_dir" ] || [ ! -x "$wine_dir/bin/wine" ]; then
        log_err "Could not locate extracted Wine binary inside $prefix"
        exit 1
    fi
    ln -sfn "$wine_dir" "$prefix/ElementalWarriorWine"
    log_info "Wine version: $("$prefix/ElementalWarriorWine/bin/wine" --version)"

    log_step "Extracting vkd3d-proton"
    rm -rf "$cache/vkd3d-extract" "$prefix/vkd3d_dlls"
    mkdir -p "$cache/vkd3d-extract" "$prefix/vkd3d_dlls"
    tar --use-compress-program=unzstd -xf "$cache/$vkd3d_file" -C "$cache/vkd3d-extract"
    local x64_dir
    x64_dir="$(find "$cache/vkd3d-extract" -type d -name x64 | head -n 1)"
    cp -f "$x64_dir/d3d12.dll" "$x64_dir/d3d12core.dll" "$prefix/vkd3d_dlls/"
    mkdir -p "$prefix/ElementalWarriorWine/lib/wine/vkd3d-proton/x86_64-windows"
    cp -f "$prefix/vkd3d_dlls/d3d12.dll" "$prefix/vkd3d_dlls/d3d12core.dll" \
        "$prefix/ElementalWarriorWine/lib/wine/vkd3d-proton/x86_64-windows/"
    rm -rf "$cache/vkd3d-extract" "$cache/$wine_file" "$cache/$vkd3d_file"
}

export_prefix_env() {
    local prefix="$1"
    local wine_bin="$prefix/ElementalWarriorWine/bin"

    export WINEPREFIX="$prefix"
    export WINE="$wine_bin/wine"
    export WINELOADER="$wine_bin/wine"
    export WINESERVER="$wine_bin/wineserver"
    export PATH="$wine_bin:$PATH"
    export WINEARCH="win64"
    export WINETRICKS_GUI="0"
    export WINEBOOT_HIDE_DIALOG="1"
    export DISPLAY="${DISPLAY:-:0}"

    if [ -f /usr/share/vulkan/icd.d/nvidia_icd.json ]; then
        export VK_DRIVER_FILES="/usr/share/vulkan/icd.d/nvidia_icd.json"
        export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/nvidia_icd.json"
    fi
    if [ -f /usr/share/glvnd/egl_vendor.d/10_nvidia.json ]; then
        export __EGL_VENDOR_LIBRARY_FILENAMES="/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
    fi
}

init_prefix_and_runtimes() {
    local prefix="$1"
    local wine_bin="$prefix/ElementalWarriorWine/bin"
    export_prefix_env "$prefix"

    log_step "Initializing 64-bit Wine prefix at $prefix"
    "$WINESERVER" -k 2>/dev/null || true
    WINEDLLOVERRIDES="mscoree=;mshtml=" "$wine_bin/wineboot" --init
    "$WINESERVER" -w
    mkdir -p "$prefix/drive_c/windows/temp"

    log_step "Installing .NET Framework 4.8 (this usually takes 3 to 5 minutes)"
    "$WINESERVER" -k 2>/dev/null || true
    WINEDLLOVERRIDES="mshtml=" winetricks --unattended --no-isolate --optout dotnet48
    "$WINESERVER" -w

    log_step "Installing Visual C++ runtimes, XML, fonts, and Vulkan renderer"
    # Intentionally skip crypt32: native crypt32 breaks TLS certificate validation
    # and prevents signing into paid Affinity ID lifetime licenses.
    local verb
    for verb in corefonts vcrun2022 msxml3 msxml6 tahoma renderer=vulkan; do
        log_info "Installing $verb..."
        "$WINESERVER" -k 2>/dev/null || true
        WINEDLLOVERRIDES="mshtml=" winetricks --unattended --no-isolate --optout --force "$verb" || {
            log_info "Retrying $verb once..."
            "$WINESERVER" -k 2>/dev/null || true
            sleep 2
            WINEDLLOVERRIDES="mshtml=" winetricks --unattended --no-isolate --optout --force "$verb"
        }
        "$WINESERVER" -w
    done

    log_step "Applying Windows 11 version, X11 driver settings, TLS fix, and dark theme"
    "$WINESERVER" -k 2>/dev/null || true
    "$wine_bin/winecfg" -v win11
    "$WINESERVER" -w

    # Keep builtin crypt32 for working HTTPS login, force X11 driver on Wayland sessions,
    # disable WM_TAKE_FOCUS conflicts with tiling compositors, and enable vkd3d-proton D3D12.
    "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v '*crypt32' /t REG_SZ /d 'builtin' /f
    "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v 'd3d12' /t REG_SZ /d 'native,builtin' /f
    "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v 'd3d12core' /t REG_SZ /d 'native,builtin' /f
    "$WINE" reg add 'HKCU\Software\Wine\Drivers' /v 'Graphics' /t REG_SZ /d 'x11' /f
    "$WINE" reg add 'HKCU\Software\Wine\X11 Driver' /v 'UseTakeFocus' /t REG_SZ /d 'N' /f
    "$WINE" reg add 'HKCU\Software\Wine\Direct3D' /v 'MailboxPresent' /t REG_DWORD /d 1 /f

    local vram_mb=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        vram_mb="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -dc '0-9' || true)"
    fi
    if [ -z "$vram_mb" ]; then
        local vram_bytes
        vram_bytes="$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | sort -nr | head -n 1 || true)"
        if [ -n "$vram_bytes" ] && [ "$vram_bytes" -gt 0 ] 2>/dev/null; then
            vram_mb="$((vram_bytes / 1024 / 1024))"
        fi
    fi
    if [ -n "$vram_mb" ] && [ "$vram_mb" -ge 1024 ] 2>/dev/null; then
        "$WINE" reg add 'HKCU\Software\Wine\Direct3D' /v 'VideoMemorySize' /t REG_SZ /d "$vram_mb" /f
        log_info "Configured Wine Direct3D VideoMemorySize=${vram_mb} MiB"
    fi

    "$wine_bin/regedit" /S "$prefix/.cache/wine-dark-theme.reg"
    "$WINESERVER" -w

    # Disable Btrfs Copy-on-Write on shader caches and Affinity temp folders if supported
    mkdir -p "$prefix/.cache/nv-shaders" "$prefix/.cache/nv-compute"
    chattr +C "$prefix/.cache/nv-shaders" "$prefix/.cache/nv-compute" 2>/dev/null || true
}

install_winrt_and_fix_fonts() {
    local prefix="$1"
    export_prefix_env "$prefix"

    log_step "Installing .NET 4.8 WinRT facades, Windows.winmd, and checking 64-bit fonts"
    local ndp_cache="${XDG_CACHE_HOME:-$HOME/.cache}/winetricks/dotnet48"
    mkdir -p "$ndp_cache"
    download_checked "$NDP48_URL" "$ndp_cache/ndp48-x86-x64-allos-enu.exe" "$NDP48_SHA256"

    python3 - "$prefix" "$ndp_cache/ndp48-x86-x64-allos-enu.exe" \
        "$WINRT_FACADE_CORE_SHA256" "$WINRT_FACADE_XAML_SHA256" <<'PYEOF'
import hashlib, lzma, os, shutil, struct, subprocess, sys, tarfile, tempfile
from pathlib import Path

prefix = Path(sys.argv[1])
ndp = Path(sys.argv[2])
facades = {
    "System.Runtime.WindowsRuntime": sys.argv[3],
    "System.Runtime.WindowsRuntime.UI.Xaml": sys.argv[4],
}
wine_bin = prefix / "ElementalWarriorWine" / "bin"
env = os.environ.copy()

gac_base = prefix / "drive_c" / "windows" / "Microsoft.NET" / "assembly" / "GAC_MSIL"
with tempfile.TemporaryDirectory(prefix=".winrt-", dir=prefix) as tmp:
    tmp_path = Path(tmp)
    cab_name = "x64-Windows10.0-KB4486153-x64.cab"
    subprocess.run(["7z", "e", "-y", f"-o{tmp_path}", str(ndp), cab_name], check=False, capture_output=True)
    cab = tmp_path / cab_name
    if not cab.is_file():
        raise SystemExit(f"Failed to extract {cab_name} from .NET 4.8 installer")

    dll_dir = tmp_path / "dll"
    patterns = [f"msil_{name.lower()}_b77a5c561934e089_*/*" for name in facades]
    subprocess.run(["7z", "e", "-y", f"-o{dll_dir}", str(cab)] + patterns, check=False, capture_output=True)

    for name, expected_sha in facades.items():
        src = dll_dir / f"{name.lower()}.dll"
        if not src.is_file():
            raise SystemExit(f"Missing extracted facade: {name}")
        got = hashlib.sha256(src.read_bytes()).hexdigest()
        if got != expected_sha:
            raise SystemExit(f"Checksum mismatch for {name}: {got}")
        dest = gac_base / name / "v4.0_4.0.0.0__b77a5c561934e089" / f"{name}.dll"
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        print(f"  Installed {name}.dll into GAC")

sys32 = prefix / "drive_c" / "windows" / "system32"
wm_dir = sys32 / "winmetadata" if (sys32 / "winmetadata").is_dir() else sys32 / "WinMetadata"
wm_dir.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=prefix) as tmp:
    with lzma.open(prefix / ".cache" / "WinMetadata.tar.xz", "rb") as xz:
        with tarfile.open(fileobj=xz, mode="r") as tar:
            tar.extractall(tmp, filter="data")
    src_winmd = Path(tmp) / "WinMetadata" / "Windows.winmd"
    shutil.copy2(src_winmd, wm_dir / "Windows.winmd")

aside = wm_dir / ".wine-shadowed"
aside.mkdir(exist_ok=True)
moved = 0
for f in wm_dir.glob("*.winmd"):
    if f.name != "Windows.winmd":
        shutil.move(str(f), str(aside / f.name))
        moved += 1
print(f"  Installed Windows.winmd (moved {moved} shadowing Wine winmd files aside)")

def font_full_name(path):
    try:
        data = Path(path).read_bytes()
        count = struct.unpack_from(">H", data, 4)[0]
        table = None
        for i in range(count):
            tag, _, offset, _ = struct.unpack_from(">4sIII", data, 12 + 16 * i)
            if tag == b"name":
                table = offset
                break
        if table is None:
            return None
        _, n, strings = struct.unpack_from(">HHH", data, table)
        found = {}
        for i in range(n):
            platform_id, _, language, name_id, length, offset = struct.unpack_from(">HHHHHH", data, table + 6 + 12 * i)
            if name_id != 4:
                continue
            raw = data[table + strings + offset: table + strings + offset + length]
            if platform_id == 3 and language == 0x409:
                found.setdefault(0, raw.decode("utf-16-be", "replace"))
            elif platform_id == 3:
                found.setdefault(1, raw.decode("utf-16-be", "replace"))
            elif platform_id == 1:
                found.setdefault(2, raw.decode("mac_roman", "replace"))
        name = found.get(0) or found.get(1) or found.get(2)
        return name.strip() if name else None
    except Exception:
        return None

def parse_reg(text):
    vals = {}
    for line in text.splitlines():
        name, sep, data = line.strip("\r\n").partition("    REG_SZ    ")
        if sep:
            vals[name.strip()] = data.strip()
    return vals

font_keys = (
    r"HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts",
    r"HKLM\Software\Microsoft\Windows\CurrentVersion\Fonts",
)
registered = {}
for k in font_keys:
    res = subprocess.run([str(wine_bin / "wine"), "reg", "query", k, "/reg:64"], env=env, text=True, capture_output=True)
    registered[k] = parse_reg(res.stdout)

by_file = {}
for k, vals in registered.items():
    for name, data in vals.items():
        by_file.setdefault(data.rsplit("\\", 1)[-1].lower(), set()).add((k, name))

fonts_dir = prefix / "drive_c" / "windows" / "Fonts"
add = {}
if fonts_dir.is_dir():
    for f in sorted(fonts_dir.iterdir()):
        if f.suffix.lower() in (".ttf", ".otf") and f.is_file():
            keys_with = {k for k, _ in by_file.get(f.name.lower(), set())}
            if all(k in keys_with for k in font_keys):
                continue
            names = {n for _, n in by_file.get(f.name.lower(), set())}
            if names:
                name = sorted(names)[0]
            else:
                full = font_full_name(f)
                if not full:
                    continue
                name = f"{full} (TrueType)"
            add[name] = f.name

if add:
    lines = ["Windows Registry Editor Version 5.00", ""]
    for k in font_keys:
        full_k = k.replace("HKLM\\", "HKEY_LOCAL_MACHINE\\")
        lines.append(f"[{full_k}]")
        for n, fn in sorted(add.items()):
            esc_n = n.replace("\\", "\\\\").replace('"', '\\"')
            esc_fn = fn.replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'"{esc_n}"="{esc_fn}"')
        lines.append("")
    freg = prefix / "fonts-repair.reg"
    freg.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")
    subprocess.run([str(wine_bin / "regedit"), "/S", str(freg)], env=env, check=False)
    freg.unlink(missing_ok=True)
    print(f"  Repaired {len(add)} 64-bit font registry entries")
else:
    print("  All 64-bit font registrations are intact")
PYEOF
    "$WINESERVER" -w
}

extract_embedded_msi() {
    local exe_path="$1"
    local out_msi="$2"

    python3 - "$exe_path" "$out_msi" <<'PYEOF'
import struct, sys
from pathlib import Path

exe = Path(sys.argv[1])
out = Path(sys.argv[2])
data = exe.read_bytes()

if data[:2] != b"MZ":
    raise SystemExit("Input file is not a Windows PE executable.")

pe_off = struct.unpack_from("<I", data, 0x3C)[0]
if data[pe_off:pe_off+4] != b"PE\x00\x00":
    raise SystemExit("Invalid PE header in installer.")

num_sections = struct.unpack_from("<H", data, pe_off + 6)[0]
opt_size = struct.unpack_from("<H", data, pe_off + 20)[0]
sec_off = pe_off + 24 + opt_size

rsrc_vaddr = rsrc_ptr = rsrc_size = 0
for i in range(num_sections):
    s = sec_off + i * 40
    name = data[s:s+8].rstrip(b"\x00").decode("ascii", "replace")
    if name == ".rsrc":
        _, rsrc_vaddr, rsrc_size, rsrc_ptr = struct.unpack_from("<IIII", data, s + 8)
        break

if not rsrc_ptr:
    raise SystemExit("Could not locate .rsrc section inside installer.")

msi_magic = b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"
found = None

def walk(dir_off):
    global found
    if found is not None:
        return
    num_named, num_id = struct.unpack_from("<HH", data, rsrc_ptr + dir_off + 12)
    for i in range(num_named + num_id):
        e_off = rsrc_ptr + dir_off + 16 + i * 8
        _, data_or_sub = struct.unpack_from("<II", data, e_off)
        if data_or_sub & 0x80000000:
            walk(data_or_sub & 0x7FFFFFFF)
        else:
            rva, size, _, _ = struct.unpack_from("<IIII", data, rsrc_ptr + data_or_sub)
            file_off = rsrc_ptr + (rva - rsrc_vaddr)
            if size > 10_000_000 and data[file_off:file_off+8] == msi_magic:
                found = (file_off, size)
                return

walk(0)
if found is None:
    raise SystemExit("No embedded MSI package found inside the executable.")

off, size = found
with open(out, "wb") as dst:
    dst.write(data[off:off+size])
print(f"  Extracted embedded MSI ({size // (1024 * 1024)} MiB) from PE resources")
PYEOF
}

clear_shadowing_winmds() {
    local prefix="$1"
    local wm_dir f base
    for wm_dir in \
        "$prefix/drive_c/windows/system32/winmetadata" \
        "$prefix/drive_c/windows/system32/WinMetadata"; do
        [ -f "$wm_dir/Windows.winmd" ] || continue
        mkdir -p "$wm_dir/.wine-shadowed"
        for f in "$wm_dir"/*.winmd; do
            [ -e "$f" ] || continue
            base="$(basename "$f")"
            if [ "$base" != "Windows.winmd" ]; then
                mv -f "$f" "$wm_dir/.wine-shadowed/$base" 2>/dev/null || true
            fi
        done
    done
}
