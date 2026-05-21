#!/bin/bash

set -euo pipefail

version="2.1"
sudo=""
seat_choice=""

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
magenta='\033[0;35m'
nc='\033[0m'

info() { echo -e "${blue}[*]${nc} $*"; }
ok() { echo -e "${green}[+]${nc} $*"; }
warn() { echo -e "${yellow}[!]${nc} $*"; }
die() { echo -e "${red}[-]${nc} $*" >&2; exit 1; }
step() { echo -e "${magenta}==>${nc} $*"; }

check_void() {
    if [[ ! -f /etc/os-release ]] || ! grep -q "void linux" /etc/os-release; then
        die "this ain't void linux, chief. exiting."
    fi
}

check_privs() {
    if [[ "$euid" -eq 0 ]]; then
        sudo=""
    elif command -v sudo &>/dev/null; then
        sudo="sudo"
    else
        die "need root or sudo. run as root or install sudo first."
    fi
}

enable_service() {
    local svc="$1"
    if [[ -L "/var/service/${svc}" ]]; then
        warn "${svc} already enabled"
        return 0
    fi
    info "enabling ${svc} service..."
    $sudo ln -sf "/etc/sv/${svc}" /var/service/ || die "failed to enable ${svc}"
    ok "${svc} enabled"
}

sync_repos() {
    info "syncing repositories..."
    $sudo xbps-install -sy || die "failed to sync repos"
}

update_system() {
    info "updating system (yes, all 14 months of it)..."
    $sudo xbps-install -su || die "system update failed"
    ok "system is fresh and current"
}

install_core() {
    info "installing core libraries..."
    $sudo xbps-install -sy \
        libstdc++ libgcc ncurses readline \
        zlib bzip2 xz lz4 zstd brotli \
        libpng libjpeg-turbo tiff libwebp \
        icu-libs \
        || die "core libraries failed"
    ok "core libraries installed"
}

install_graphics() {
    info "installing x11/wayland graphics stack..."
    $sudo xbps-install -sy \
        libx11 libxcb libxext libxrender libxft \
        fontconfig freetype libxkbcommon \
        mesa-dri \
        || die "graphics stack failed"
    ok "graphics stack ready"
}

install_network() {
    info "installing networking & crypto..."
    $sudo xbps-install -sy \
        libcurl libressl gnutls ca-certificates \
        || die "network libraries failed"
    ok "network stack ready"
}

install_toolkits() {
    info "installing gtk3/qt5 toolkits..."
    $sudo xbps-install -sy \
        gtk+3 glib pango cairo gdk-pixbuf \
        qt5 \
        pam libcap \
        || die "gui toolkits failed"
    ok "gui toolkits ready"
}

setup_fonts() {
    info "installing default fonts..."
    $sudo xbps-install -sy \
        dejavu-fonts-ttf \
        liberation-fonts-ttf \
        terminus-font \
        noto-fonts-emoji \
        || warn "some font packages failed (non-critical)"
    ok "fonts installed"
}

setup_dbus() {
    info "installing d-bus (system bus)..."
    $sudo xbps-install -sy dbus || die "d-bus install failed"
    enable_service "dbus"
    
    info "installing dbus-x11 (for startx / .xinitrc users)..."
    $sudo xbps-install -sy dbus-x11 || warn "dbus-x11 not available"
    
    ok "d-bus system bus configured"
}

setup_xdg_dirs() {
    info "installing xdg user directory tools..."
    $sudo xbps-install -sy \
        xdg-user-dirs \
        xdg-user-dirs-gtk \
        xdg-utils \
        xdg-desktop-portal \
        xdg-desktop-portal-gtk \
        || die "xdg tools install failed"
    
    local target_user=""
    if [[ -n "${sudo_user:-}" ]]; then
        target_user="$sudo_user"
    elif [[ "$euid" -ne 0 ]]; then
        target_user="$(whoami)"
    fi
    
    if [[ -n "$target_user" ]]; then
        info "generating user dirs for '${target_user}'..."
        if $sudo -u "$target_user" xdg-user-dirs-update 2>/dev/null; then
            ok "user directories created in ~${target_user}"
        else
            warn "xdg-user-dirs-update failed — run it manually after login"
        fi
    else
        warn "running as root with no sudo_user — run 'xdg-user-dirs-update' manually as your user"
    fi
}

seat_elogind() {
    step "configuring elogind session management..."
    
    info "installing elogind + polkit..."
    $sudo xbps-install -sy elogind polkit || die "elogind install failed"
    
    info "enabling elogind service (docs recommend this over d-bus activation)..."
    enable_service "elogind"
    
    ok "elogind configured — xdg_runtime_dir will be auto-set on next login"
    warn "you must log out and back in for elogind to take effect"
}

seat_turnstile_with_elogind() {
    step "configuring turnstile + elogind..."
    
    info "installing turnstile + elogind + polkit..."
    $sudo xbps-install -sy turnstile elogind polkit || die "install failed"
    
    info "disabling turnstile rundir management (elogind handles xdg_runtime_dir)..."
    if [[ -f /etc/turnstile/turnstiled.conf ]]; then
        $sudo sed -i 's/^manage_rundir.*/manage_rundir no/' /etc/turnstile/turnstiled.conf
    else
        $sudo mkdir -p /etc/turnstile
        echo "manage_rundir no" | $sudo tee /etc/turnstile/turnstiled.conf >/dev/null
    fi
    
    enable_service "elogind"
    enable_service "turnstiled"
    
    ok "turnstile + elogind configured"
    warn "log out and back in. turnstile manages d-bus session — no dbus-run-session needed"
}

seat_turnstile_standalone() {
    step "configuring turnstile (standalone, no elogind)..."
    
    info "installing turnstile + seatd + acpid..."
    $sudo xbps-install -sy turnstile seatd acpid || die "install failed"
    
    enable_service "seatd"
    enable_service "acpid"
    enable_service "turnstiled"
    
    local target_user="${sudo_user:-$(whoami)}"
    if [[ "$target_user" != "root" ]]; then
        info "adding ${target_user} to _seatd group..."
        $sudo usermod -ag _seatd "$target_user" || warn "failed to add to _seatd group"
    fi
    
    ok "turnstile standalone configured"
    warn "log out and back in. seatd handles seats, acpid handles power, turnstile handles rundir + d-bus"
}

seat_seatd() {
    step "configuring seatd (minimal, for wlroots compositors)..."
    
    info "installing seatd..."
    $sudo xbps-install -sy seatd || die "seatd install failed"
    
    enable_service "seatd"
    
    local target_user="${sudo_user:-$(whoami)}"
    if [[ "$target_user" != "root" ]]; then
        info "adding ${target_user} to _seatd group..."
        $sudo usermod -ag _seatd "$target_user" || warn "failed to add to _seatd group"
    fi
    
    ok "seatd configured"
    warn "seatd only manages seats — you still need to handle xdg_runtime_dir and d-bus yourself"
    info "for d-bus session: wrap your wm with dbus-run-session in .xinitrc"
    info "for xdg_runtime_dir: use the manual method or install turnstile/elogind"
}

seat_manual() {
    step "configuring manual xdg_runtime_dir (no session manager)..."
    
    warn "manual mode — you are responsible for xdg_runtime_dir and d-bus"
    
    local uid
    uid="$(id -u "${sudo_user:-$(whoami)}")"
    local rundir="/run/user/${uid}"
    
    info "creating ${rundir} with 0700 permissions..."
    $sudo mkdir -p "$rundir"
    $sudo chmod 700 "$rundir"
    
    local profile_file=""
    if [[ -n "${sudo_user:-}" ]]; then
        local user_home
        user_home="$(getent passwd "$sudo_user" | cut -d: -f6)"
        for f in "${user_home}/.bashrc" "${user_home}/.profile"; do
            if [[ -f "$f" ]]; then profile_file="$f"; break; fi
        done
    else
        for f in "$home/.bashrc" "$home/.profile"; do
            if [[ -f "$f" ]]; then profile_file="$f"; break; fi
        done
    fi
    
    if [[ -n "$profile_file" ]]; then
        if ! grep -q "xdg_runtime_dir" "$profile_file" 2>/dev/null; then
            info "adding xdg_runtime_dir export to ${profile_file}..."
            cat <<eof | $sudo tee -a "$profile_file" >/dev/null

export xdg_runtime_dir="${rundir}"
eof
            ok "added to ${profile_file}"
        else
            warn "xdg_runtime_dir already set in ${profile_file}"
        fi
    fi
    
    ok "manual xdg_runtime_dir configured at ${rundir}"
    warn "this dir is not persistent across reboots — add a tmpfiles.d rule or use a session manager"
    info "for d-bus: wrap your wm with dbus-run-session in .xinitrc"
}

configure_seat() {
    echo
    step "session and seat management"
    echo
    
    if [[ -z "$seat_choice" ]]; then
        echo "pick your session/seat stack (per void docs):"
        echo
        echo "  1) elogind      — full session mgmt, auto xdg_runtime_dir, power control"
        echo "                     best for: des, most wayland compositors, rootless xorg"
        echo
        echo "  2) turnstile+elogind — turnstile manages sessions, elogind handles rundir/power"
        echo "                     best for: per-user services, d-bus without dbus-run-session"
        echo
        echo "  3) turnstile    — standalone, seatd for seats, acpid for power"
        echo "                     best for: minimal setups, wlroots compositors"
        echo
        echo "  4) seatd        — minimal seat daemon only (wlroots compositors)"
        echo "                     best for: sway, dwl, river — you handle rundir + d-bus"
        echo
        echo "  5) manual       — no session manager, diy xdg_runtime_dir"
        echo "                     best for: purists who know what they're doing"
        echo
        read -rp "choice [1-5]: " choice
        case "$choice" in
            1) seat_choice="elogind" ;;
            2) seat_choice="turnstile+elogind" ;;
            3) seat_choice="turnstile" ;;
            4) seat_choice="seatd" ;;
            5) seat_choice="manual" ;;
            *) die "invalid choice. run again with --seat=..." ;;
        esac
        echo
    fi
    
    case "$seat_choice" in
        elogind) seat_elogind ;;
        turnstile+elogind) seat_turnstile_with_elogind ;;
        turnstile) seat_turnstile_standalone ;;
        seatd) seat_seatd ;;
        manual) seat_manual ;;
        *) die "unknown seat choice: $seat_choice" ;;
    esac
}

banner() {
    echo -e "${cyan}"
    cat <<'eof'
    __    __    __    __    __    __    __    __
   /  \  /  \  /  \  /  \  /  \  /  \  /  \  /  \
  (    )(    )(    )(    )(    )(    )(    )(    )
   \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/
                     h o n e y b e e
               void linux post-install helper
eof
    echo -e "${nc}"
}

usage() {
    echo "honeybee v${version}"
    echo ""
    echo "usage: $0 [options]"
    echo "  --quick                 skip confirmation prompts"
    echo "  --seat=choice           pre-select session/seat stack:"
    echo "                          elogind, turnstile+elogind, turnstile, seatd, manual"
    echo "  --help                  show this help"
    echo ""
    echo "installs libraries, sets up d-bus, xdg dirs, and configures session"
    echo "management per the void linux handbook."
    exit 0
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick) shift ;;
            --seat=*)
                seat_choice="${1#*=}"
                shift
                ;;
            --help) usage ;;
            *) die "unknown option: $1 (try --help)" ;;
        esac
    done

    banner
    check_void
    check_privs
    
    warn "this will update your system and install packages."
    read -rp "buzz along? [y/n] " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && exit 0
    
    sync_repos
    update_system
    
    install_core
    install_graphics
    install_network
    install_toolkits
    setup_fonts
    
    setup_dbus
    setup_xdg_dirs
    
    configure_seat
    
    echo
    ok "honeybee complete!"
    echo
    info "important: log out and log back in for session management to take effect."
    info "if using startx/.xinitrc, you may need dbus-run-session or turnstile."
    info "then install your wm/de: xbps-install -s sway alacritty foot pipewire"
}

main "$@"
