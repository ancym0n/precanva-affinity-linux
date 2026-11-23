#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=../../../shared/runtime.env
source "$REPO_ROOT/shared/runtime.env"
# shellcheck source=../../../shared/setup-prefix.sh
source "$REPO_ROOT/shared/setup-prefix.sh"

PREFIX="${AFFINITY_PHOTO2_PREFIX:-$HOME/.AffinityPhoto2}"
ICON_URL="https://upload.wikimedia.org/wikipedia/commons/f/f5/Affinity_Photo_V2_icon.svg"

usage() {
    cat <<EOF
Usage: $(basename "$0") [PATH_TO_INSTALLER]

Installs Affinity Photo 2 (2.6.5, Windows x64 MSI installer) into a dedicated
Wine prefix at $PREFIX.

Arguments:
  PATH_TO_INSTALLER   Path to affinity-photo-msi-2.6.5.exe downloaded from your
                      Affinity account. If omitted, the script checks the
                      current directory and ~/Downloads.

Environment variables:
  AFFINITY_PHOTO2_PREFIX   Override target Wine prefix (default: ~/.AffinityPhoto2)
  USE_LATEST_RELEASES=1    Fetch the newest Wine and vkd3d-proton tags from GitHub
                           instead of the pinned versions in shared/runtime.env
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

find_installer() {
    if [ -n "${1:-}" ]; then
        printf '%s\n' "$1"
        return 0
    fi

    local candidate
    for candidate in \
        "./affinity-photo-msi-2.6.5.exe" \
        "$HOME/Downloads/affinity-photo-msi-2.6.5.exe"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

INSTALLER="$(find_installer "${1:-}" || true)"
if [ -z "$INSTALLER" ] || [ ! -f "$INSTALLER" ]; then
    log_err "Could not find affinity-photo-msi-2.6.5.exe."
    log_info "Download the Windows x64 MSI EXE installer from your Affinity account and run:"
    log_info "  $0 /path/to/affinity-photo-msi-2.6.5.exe"
    exit 1
fi

case "$(basename "$INSTALLER")" in
    *arm64*|*ARM64*)
        log_err "ARM64 installers do not run on x86_64 Linux. Download the x64 MSI EXE installer instead."
        exit 1
        ;;
    *.msix|*.MSIX)
        log_err "MSIX packages are not supported under Wine. Download the MSI EXE installer (affinity-photo-msi-2.6.5.exe)."
        exit 1
        ;;
esac

check_dependencies
setup_wine_and_vkd3d "$PREFIX"
init_prefix_and_runtimes "$PREFIX"
install_winrt_and_fix_fonts "$PREFIX"

export_prefix_env "$PREFIX"

log_step "Extracting and installing Affinity Photo 2.6.5"
WORK_DIR="$PREFIX/drive_c/affinity_install_tmp"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

extract_embedded_msi "$INSTALLER" "$WORK_DIR/Affinity.msi"

"$WINESERVER" -k 2>/dev/null || true
"$WINE" msiexec /i 'C:\affinity_install_tmp\Affinity.msi' /qn /norestart \
    INSTALL_DESKTOP_SHORTCUT_PROPERTY=0 REBOOT=ReallySuppress \
    /l*v 'C:\affinity_install_tmp\msi_install.log'
"$WINESERVER" -w

APP_DIR="$PREFIX/drive_c/Program Files/Affinity/Photo 2"
if [ ! -f "$APP_DIR/Photo.exe" ]; then
    log_err "Installation finished without creating $APP_DIR/Photo.exe"
    log_info "Inspect $WORK_DIR/msi_install.log for details."
    exit 1
fi

log_step "Configuring vkd3d-proton, performance defaults, and cleaning WinMetadata"
cp -f "$PREFIX/vkd3d_dlls/d3d12.dll" "$APP_DIR/d3d12.dll"
cp -f "$PREFIX/vkd3d_dlls/d3d12core.dll" "$APP_DIR/d3d12core.dll"
clear_shadowing_winmds "$PREFIX"
seed_affinity_performance_prefs "$PREFIX" "Photo/2.0"
rm -rf "$WORK_DIR"

log_step "Installing launcher, icon, desktop entry, and file associations"
mkdir -p "$HOME/.local/bin" \
         "$HOME/.local/share/applications" \
         "$HOME/.local/share/icons/hicolor/scalable/apps" \
         "$HOME/.local/share/mime/packages"

install -m 755 "$SCRIPT_DIR/launcher.sh" "$HOME/.local/bin/affinity-photo-2"

ICON_DEST="$HOME/.local/share/icons/AffinityPhoto.svg"
if [ ! -f "$ICON_DEST" ]; then
    curl -fsSL "$ICON_URL" -o "$ICON_DEST" || true
fi
if [ -f "$ICON_DEST" ]; then
    cp -f "$ICON_DEST" "$HOME/.local/share/icons/hicolor/scalable/apps/affinity-photo-2.svg"
fi

DESKTOP_DEST="$HOME/.local/share/applications/AffinityPhoto2.desktop"
sed -e "s|@HOME@|$HOME|g" -e "s|@PREFIX@|$PREFIX|g" \
    "$SCRIPT_DIR/AffinityPhoto2.desktop.in" > "$DESKTOP_DEST"
chmod 755 "$DESKTOP_DEST"

# Remove auto-generated Wine desktop entries so the app menu has one clean entry
# and auth callbacks do not route to the default ~/.wine prefix.
rm -f "$HOME/.local/share/applications/wine/Programs/Affinity Photo 2.desktop" \
      "$HOME/.local/share/applications/wine-extension-afphoto.desktop" \
      "$HOME/.local/share/applications/wine-protocol-affinity-photo2-auth.desktop" \
      "$HOME/.local/share/applications/wine-protocol-affinity-photo2-dropbox-auth.desktop"

cp -f "$SCRIPT_DIR/affinity-photo2.xml" "$HOME/.local/share/mime/packages/affinity-photo2.xml"
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default AffinityPhoto2.desktop application/afphoto || true
    xdg-mime default AffinityPhoto2.desktop x-scheme-handler/affinity-photo2-auth || true
    xdg-mime default AffinityPhoto2.desktop x-scheme-handler/affinity-photo2-dropbox-auth || true
fi

log_step "Done"
log_info "Launch Affinity Photo 2 from your app menu or run: affinity-photo-2"
log_info "Sign in with your Affinity ID email and password to activate your lifetime license."
