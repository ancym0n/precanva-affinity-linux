#!/usr/bin/env bash
set -euo pipefail

PREFIX="${AFFINITY_PHOTO2_PREFIX:-$HOME/.AffinityPhoto2}"
WINE_USER="${USER:-$(id -un)}"
WINE_BIN="$PREFIX/ElementalWarriorWine/bin"
APP_EXE="$PREFIX/drive_c/Program Files/Affinity/Photo 2/Photo.exe"
WIN_XML="$PREFIX/drive_c/users/${WINE_USER}/AppData/Roaming/Affinity/Photo/2.0/Settings/Window.xml"

export WINEPREFIX="$PREFIX"
export WINE="$WINE_BIN/wine"
export WINELOADER="$WINE_BIN/wine"
export WINESERVER="$WINE_BIN/wineserver"
export PATH="$WINE_BIN:$PATH"
export WINEBOOT_HIDE_DIALOG=1
export DISPLAY="${DISPLAY:-:0}"

# Force en_US.UTF-8 locale to prevent known Affinity locale startup crashes
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# Suppress hot-loop fixme and warn spam while keeping real Wine errors visible
export WINEDEBUG="${WINEDEBUG:-fixme-all,warn-all}"

# Explicit DLL overrides: vkd3d-proton for D3D12, builtin crypt32 for TLS login.
# Keep Wine 11.22 builtin d3d9 (patch 0054 prevents black WPF popup menus)
# and builtin d3d11 and dxgi (patched Direct2D Vulkan pipeline).
# OpenCL compute is disabled by default because Wine OpenCL synchronization causes
# live-preview stalls and visual glitches in tools like Mesh Warp (canvas rendering
# still runs hardware-accelerated on the GPU via Direct3D 11 and Vulkan).
# Set AFFINITY_OPENCL=1 to re-enable OpenCL compute acceleration.
if [ -z "${WINEDLLOVERRIDES:-}" ]; then
    if [ "${AFFINITY_OPENCL:-0}" = "1" ]; then
        export WINEDLLOVERRIDES="d3d12=n,b;d3d12core=n,b;crypt32=b"
    else
        export WINEDLLOVERRIDES="d3d12=n,b;d3d12core=n,b;crypt32=b;opencl=d"
    fi
fi

# Dedicated persistent NVIDIA shader and compute caches (1 GiB and 2 GiB)
# so compiled pipelines are not evicted by other desktop apps.
NV_SHADER_CACHE="$PREFIX/.cache/nv-shaders"
NV_COMPUTE_CACHE="$PREFIX/.cache/nv-compute"

# On NVIDIA systems, pin NVIDIA ICDs to avoid Mesa dri2 probing warnings
if [ -f /usr/share/vulkan/icd.d/nvidia_icd.json ] && [ -e /dev/nvidia0 ]; then
    export VK_DRIVER_FILES="/usr/share/vulkan/icd.d/nvidia_icd.json"
    export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/nvidia_icd.json"
    export __GLX_VENDOR_LIBRARY_NAME="nvidia"
    if [ -f /usr/share/glvnd/egl_vendor.d/10_nvidia.json ]; then
        export __EGL_VENDOR_LIBRARY_FILENAMES="/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
    fi
    mkdir -p "$NV_SHADER_CACHE" "$NV_COMPUTE_CACHE"
    chattr +C "$NV_SHADER_CACHE" "$NV_COMPUTE_CACHE" 2>/dev/null || true
    export __GL_SHADER_DISK_CACHE=1
    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
    export __GL_SHADER_DISK_CACHE_SIZE=1073741824
    export __GL_SHADER_DISK_CACHE_PATH="$NV_SHADER_CACHE"
    export CUDA_CACHE_MAXSIZE=2147483648
    export CUDA_CACHE_PATH="$NV_COMPUTE_CACHE"
fi

# Leave DXVK_CONFIG unset (d3d9.deferSurfaceCreation=True causes blank dialogs)
unset DXVK_CONFIG
export DXVK_ASYNC=0
export DXVK_LOG_LEVEL=none

# vkd3d-proton D3D12 runtime settings for Wayland and XWayland
export VKD3D_DEBUG=none
export VKD3D_FEATURE_LEVEL=12_1
export VKD3D_SHADER_DEBUG=none
export VKD3D_SHADER_MODEL=6_5
if [ "${XDG_SESSION_TYPE:-wayland}" = "wayland" ]; then
    export VKD3D_DISABLE_EXTENSIONS="VK_KHR_present_id,VK_KHR_present_wait"
    if [ -e /dev/nvidia0 ]; then
        export VKD3D_CONFIG="swapchain_legacy"
    fi
else
    export VKD3D_DISABLE_EXTENSIONS="VK_KHR_present_id"
fi

FRESH_LAUNCH=1
HYPR_EVAL_OK=0
HYPR_RULES_LUA='hl.window_rule({ name = "affinity-photo-2-runtime", enabled = true, match = { class = "(?i)^photo\\.exe$" }, opaque = true, opacity = "1.0 override 1.0 override 1.0 override", no_blur = true, no_shadow = true, no_anim = true, no_follow_mouse = true }); hl.window_rule({ name = "affinity-photo-2-portal-runtime", enabled = true, match = { class = "(?i)^xdg-desktop-portal-gtk$", title = ".*\\(Photo\\)$" }, float = true, center = true, no_anim = true }); hl.exec_scheduled_prop_refresh_immediately()'
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
    # Apply runtime Hyprland window rules for color accuracy (100% opaque, no blur),
    # stable dropdown menus (no animations, no follow_mouse focus jumps), and centered file portals.
    if hyprctl eval "$HYPR_RULES_LUA" >/dev/null 2>&1; then
        HYPR_EVAL_OK=1
    fi

    if command -v jq >/dev/null 2>&1; then
        # Sync XWayland keyboard layout with Hyprland's active layout so AltGr diacritics work reliably.
        if command -v setxkbmap >/dev/null 2>&1; then
            HYPR_KB_LAYOUT="$(hyprctl devices -j 2>/dev/null | jq -r '([.keyboards[] | select(.main == true)][0] // .keyboards[0]) | .layout // empty' 2>/dev/null | cut -d',' -f1 || true)"
            if [ -n "$HYPR_KB_LAYOUT" ]; then
                X11_KB_LAYOUT="$(DISPLAY="$DISPLAY" setxkbmap -query 2>/dev/null | awk '/^layout:/{print $2}' || true)"
                if [ "${X11_KB_LAYOUT%%,*}" != "$HYPR_KB_LAYOUT" ]; then
                    DISPLAY="$DISPLAY" setxkbmap "$HYPR_KB_LAYOUT" >/dev/null 2>&1 || true
                fi
            fi
        fi

        # Clean up stale windowless Photo.exe processes left behind after closing the window.
        STALE_PIDS="$(pgrep -f 'Affinity/Photo 2/Phot[o]\.exe' 2>/dev/null || true)"
        if [ -n "$STALE_PIDS" ]; then
            MAPPED_COUNT="$(hyprctl clients -j 2>/dev/null | jq '[.[] | select((.class | test("^photo\\.exe$"; "i")) and .mapped == true)] | length' 2>/dev/null || echo 1)"
            if [ "$MAPPED_COUNT" = "0" ]; then
                ALL_OLD=1
                for pid in $STALE_PIDS; do
                    ETIMES="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)"
                    if [ "${ETIMES:-0}" -lt 15 ]; then
                        ALL_OLD=0
                    fi
                done
                if [ "$ALL_OLD" = "1" ]; then
                    for pid in $STALE_PIDS; do
                        kill "$pid" 2>/dev/null || true
                    done
                    sleep 1
                    for pid in $STALE_PIDS; do
                        kill -9 "$pid" 2>/dev/null || true
                    done
                    "$WINESERVER" -k 2>/dev/null || true
                    sleep 1
                fi
            else
                FRESH_LAUNCH=0
            fi
        fi

        # Prevent Hyprland tiling viewport clipping on startup:
        # If Window.xml stores a smaller size than the assigned tile, Hyprland expands
        # the window at map time before WPF attaches its swapchain, clipping the canvas.
        # Initializing Window.xml to the monitor's usable size before a fresh launch
        # makes Hyprland shrink rather than expand the initial surface.
        if [ "$FRESH_LAUNCH" = "1" ] && [ -f "$WIN_XML" ] && command -v python3 >/dev/null 2>&1; then
            MON_SIZE="$(hyprctl monitors -j 2>/dev/null | jq -r '([.[] | select(.focused == true)][0] // .[0]) | "\(((.width / .scale) - ((.reserved[0] // 0) + (.reserved[2] // 0))) | floor) \(((.height / .scale) - ((.reserved[1] // 0) + (.reserved[3] // 0))) | floor)"' 2>/dev/null || true)"
            if [ -n "$MON_SIZE" ]; then
                read -r MW MH <<< "$MON_SIZE"
                if [ "${MW:-0}" -ge 800 ] && [ "${MH:-0}" -ge 600 ]; then
                    python3 - "$WIN_XML" "$MW" "$MH" <<'PYEOF' 2>/dev/null || true
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
mw, mh = sys.argv[2], sys.argv[3]
txt = p.read_text(encoding="utf-8")
new_txt = re.sub(
    r"(<Size>\s*<Width>)\d+(</Width>\s*<Height>)\d+(</Height>\s*</Size>)",
    rf"\g<1>{mw}\g<2>{mh}\g<3>",
    txt,
    count=1,
)
if new_txt != txt:
    p.write_text(new_txt, encoding="utf-8")
PYEOF
                fi
            fi
        fi
    fi
fi

# Ensure Affinity hot write directories use NOCOW on Btrfs (no-op on ext4 or xfs)
if [ "$FRESH_LAUNCH" = "1" ]; then
    for d in \
        "$PREFIX/drive_c/users/${WINE_USER}/AppData/Roaming/Affinity/Photo/2.0/temp" \
        "$PREFIX/drive_c/users/${WINE_USER}/AppData/Roaming/Affinity/Photo/2.0/autosave" \
        "$PREFIX/drive_c/users/${WINE_USER}/AppData/Roaming/Affinity/Common/2.0/clipboard"; do
        if [ -d "$d" ]; then
            chattr +C "$d" 2>/dev/null || true
        fi
    done

    # If no Photo.exe is running, shut down any lingering wineserver from a previous Wine version
    if ! pgrep -f 'Affinity/Photo 2/Phot[o]\.exe' >/dev/null 2>&1; then
        CURRENT_WINE_REAL="$(readlink -f "$WINE_BIN/wineserver" 2>/dev/null || true)"
        for ws_pid in $(pgrep -x wineserver 2>/dev/null || true); do
            ws_exe="$(readlink -f "/proc/$ws_pid/exe" 2>/dev/null || true)"
            if [ -n "$ws_exe" ] && [ -n "$CURRENT_WINE_REAL" ] && [ "$ws_exe" != "$CURRENT_WINE_REAL" ] && [[ "$ws_exe" == "$PREFIX"/* ]]; then
                kill "$ws_pid" 2>/dev/null || true
                sleep 0.5
            fi
        done
    fi
fi

# Keep shadowing per-namespace Wine winmd files out of the way of Windows.winmd
for WM_DIR in \
    "$PREFIX/drive_c/windows/system32/winmetadata" \
    "$PREFIX/drive_c/windows/system32/WinMetadata"; do
    if [ -f "$WM_DIR/Windows.winmd" ]; then
        for f in "$WM_DIR"/*.winmd; do
            [ -e "$f" ] || continue
            base="$(basename "$f")"
            if [ "$base" != "Windows.winmd" ]; then
                mkdir -p "$WM_DIR/.wine-shadowed"
                mv -f "$f" "$WM_DIR/.wine-shadowed/$base" 2>/dev/null || true
            fi
        done
    fi
done

args=()
for arg in "$@"; do
    case "$arg" in
        affinity-photo2-auth:*|affinity-photo2-dropbox-auth:*|affinity:*)
            args+=("$arg")
            ;;
        file://*)
            decoded="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))' "$arg" 2>/dev/null || echo "${arg#file://}")"
            args+=("$("$WINE_BIN/winepath" -w "$decoded")")
            ;;
        *)
            if [ -e "$arg" ]; then
                args+=("$("$WINE_BIN/winepath" -w "$arg")")
            else
                args+=("$arg")
            fi
            ;;
    esac
done

# Re-apply runtime Hyprland rules after config reloads or theme switches
# (such as hyprctl reload or dotfiles sync timers) until Photo.exe exits.
if [ "$HYPR_EVAL_OK" = "1" ] && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v python3 >/dev/null 2>&1; then
    HYPR_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    HYPR_WATCHER_LOCK="$PREFIX/.cache/hypr-watcher.lock"
    if [ -S "$HYPR_SOCK" ]; then
        mkdir -p "$PREFIX/.cache"
        python3 - "$HYPR_SOCK" "$HYPR_RULES_LUA" "$HYPR_WATCHER_LOCK" </dev/null >/dev/null 2>&1 <<'PYEOF' &
import fcntl, os, socket, subprocess, sys, time

sock_path, rules_lua, lock_path = sys.argv[1:4]
needle_exe = "Affinity/Photo 2/Photo.exe"

try:
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(0)

def photo_running():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmd = f.read().decode("utf-8", "ignore").replace("\\", "/")
            if needle_exe in cmd:
                return True
        except OSError:
            continue
    return False

try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(sock_path)
    sock.settimeout(3.0)
except OSError:
    sys.exit(0)

start = time.monotonic()
seen_photo = False
buf = ""
try:
    while True:
        running = photo_running()
        if running:
            seen_photo = True
        elif seen_photo or (time.monotonic() - start) > 30.0:
            break
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        if not chunk:
            break
        buf += chunk.decode("utf-8", "ignore")
        while "\n" in buf:
            line, buf = buf.split("\n", 1)
            if line.startswith("configreloaded>>"):
                time.sleep(0.2)
                if photo_running():
                    subprocess.run(
                        ["hyprctl", "eval", rules_lua],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
finally:
    sock.close()
    try:
        os.close(lock_fd)
    except OSError:
        pass
PYEOF
    fi
fi

exec "$WINE" "$APP_EXE" "${args[@]}"
