#!/bin/bash

set -e

AMBER='\033[38;5;214m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
RC='\033[0m'

CORE_PKGS="libstdc++ libgcc ncurses readline zlib bzip2 xz lz4 zstd brotli libpng libjpeg-turbo tiff libwebp icu-libs"
GRAPHICS_PKGS="libX11 libxcb libXext libXrender libXft fontconfig freetype libxkbcommon mesa-dri"
NET_PKGS="libcurl libressl gnutls ca-certificates"
GUI_PKGS="gtk+3 glib pango cairo gdk-pixbuf qt5 pam libcap"
FONT_PKGS="dejavu-fonts-ttf liberation-fonts-ttf terminus-font noto-fonts-emoji"
XDG_PKGS="xdg-user-dirs xdg-user-dirs-gtk xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk"
DBUS_PKGS="dbus dbus-x11"

ALL_PKGS="$CORE_PKGS $GRAPHICS_PKGS $NET_PKGS $GUI_PKGS $FONT_PKGS $XDG_PKGS $DBUS_PKGS"

QUICK_MODE=false
PRESELECTED_SEAT=""

show_help() {
    echo -e "${AMBER}honeybee - Void Linux Post-Install Hijack Script${RC}"
    echo ""
    echo "Usage:"
    echo "  ./honeybee.sh [options]"
    echo ""
    echo "Options:"
    echo "  -q, --quick           Skip confirmation prompts (non-interactive mode)"
    echo "  -s, --seat=STACK      Pre-select session/seat management stack:"
    echo "                        Options: elogind, turnstile-elogind, turnstile, seatd, manual"
    echo "  -h, --help            Show this help message"
    echo ""
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        -q|--quick)
            QUICK_MODE=true
            shift
            ;;
        -s|--seat)
            PRESELECTED_SEAT="$2"
            shift 2
            ;;
        --seat=*)
            PRESELECTED_SEAT="${1#*=}"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${RC}"
            show_help
            ;;
    esac
done

if [ ! -f /etc/void-release ] && ! command -v xbps-install >/dev/null 2>&1; then
    echo -e "${RED}Error: This script is intended to run on Void Linux.${RC}" >&2
    exit 1
fi

print_banner() {
    echo -e "${AMBER}"
    echo "  ,  ,"
    echo " ( \\/ )"
    echo "() == ()   honeybee"
    echo " ( /\\ )    a user-friendly hijack/after-install script for Void Linux"
    echo "  \`  \`"
    echo -e "${RC}"
}

print_banner

run_priv() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        if command -v sudo >/dev/null 2>&1; then
            sudo "$@"
        else
            echo -e "${RED}Error: Root privileges are required. Please run this script with sudo or as root.${RC}" >&2
            exit 1
        fi
    fi
}

TARGET_USER="${SUDO_USER:-$(whoami)}"
if [ "$TARGET_USER" = "root" ] && [ -n "$USER" ] && [ "$USER" != "root" ]; then
    TARGET_USER="$USER"
fi

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    
    if [ "$QUICK_MODE" = "true" ]; then
        return 0
    fi
    
    local choice
    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n]: " choice
        case "$choice" in
            [nN]|[nN][oO]) return 1 ;;
            *) return 0 ;;
        esac
    else
        read -p "$prompt [y/N]: " choice
        case "$choice" in
            [yY]|[yY][eE][sS]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

enable_service() {
    local service="$1"
    if [ -d "/etc/sv/$service" ]; then
        if [ ! -L "/var/service/$service" ]; then
            echo -e "${BLUE}Enabling service: $service...${RC}"
            run_priv ln -sf "/etc/sv/$service" /var/service/
        else
            echo -e "${GREEN}Service already enabled: $service${RC}"
        fi
    else
        echo -e "${RED}Warning: Service configuration for '$service' not found in /etc/sv/.${RC}"
    fi
}

configure_turnstile() {
    local val="$1"
    local config_file="/etc/turnstile/turnstiled.conf"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${BLUE}Creating directory and configuration at $config_file...${RC}"
        run_priv mkdir -p /etc/turnstile
        echo "manage_rundir = $val" | run_priv tee "$config_file" > /dev/null
    else
        echo -e "${BLUE}Configuring $config_file: setting manage_rundir = $val...${RC}"
        if grep -q "^[# ]*manage_rundir" "$config_file"; then
            run_priv sed -i "s/^[# ]*manage_rundir[[:space:]]*=.*/manage_rundir = $val/" "$config_file"
        else
            echo "manage_rundir = $val" | run_priv tee -a "$config_file" > /dev/null
        fi
    fi
}

if [ -n "$PRESELECTED_SEAT" ]; then
    if [ "$PRESELECTED_SEAT" = "turnstile-elogind" ] || [ "$PRESELECTED_SEAT" = "turnstile+elogind" ]; then
        PRESELECTED_SEAT="turnstile-elogind"
    fi
    echo -e "${BLUE}Seat stack selected via CLI: ${AMBER}$PRESELECTED_SEAT${RC}"
else
    echo -e "${YELLOW}Please select a session/seat management stack:${RC}"
    echo "1) elogind : full session management, auto XDG_RUNTIME_DIR, power control."
    echo "   Best for: Desktop Environments, Wayland compositors, rootless Xorg."
    echo ""
    echo "2) turnstile + elogind : turnstile manages sessions, elogind handles rundir/power."
    echo "   Best for: per-user services, running D-Bus without dbus-run-session."
    echo ""
    echo "3) turnstile : standalone session tracker, seatd for seats, acpid for power."
    echo "   Best for: minimal setups, wlroots-based wayland compositors."
    echo ""
    echo "4) seatd : minimal seat management daemon only."
    echo "   Best for: sway, dwl, river. (You handle XDG_RUNTIME_DIR & D-Bus yourself)"
    echo ""
    echo "5) manual : no session manager. DIY XDG_RUNTIME_DIR."
    echo "   Best for: minimalists who want full manual control."
    echo ""
    
    while true; do
        read -p "Select option (1-5): " choice
        case "$choice" in
            1) PRESELECTED_SEAT="elogind"; break ;;
            2) PRESELECTED_SEAT="turnstile-elogind"; break ;;
            3) PRESELECTED_SEAT="turnstile"; break ;;
            4) PRESELECTED_SEAT="seatd"; break ;;
            5) PRESELECTED_SEAT="manual"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter 1-5.${RC}" ;;
        esac
    done
fi

SEAT_PKGS=""
case "$PRESELECTED_SEAT" in
    elogind)
        SEAT_PKGS="elogind"
        ;;
    turnstile-elogind)
        SEAT_PKGS="turnstile elogind"
        ;;
    turnstile)
        SEAT_PKGS="turnstile seatd acpid"
        ;;
    seatd)
        SEAT_PKGS="seatd"
        ;;
    manual)
        SEAT_PKGS=""
        ;;
esac

echo -e "\n${YELLOW}=== Honeybee Installation Plan ===${RC}"
echo -e "User context:    ${BLUE}$TARGET_USER${RC}"
echo -e "Execution mode:  ${BLUE}$( [ "$QUICK_MODE" = "true" ] && echo "Quick (Non-interactive)" || echo "Interactive" )${RC}"
echo -e "Seat stack:      ${BLUE}$PRESELECTED_SEAT${RC}"
echo -e "Target packages to install:"
echo -e "  - Core:        ${BLUE}$CORE_PKGS${RC}"
echo -e "  - Graphics:    ${BLUE}$GRAPHICS_PKGS${RC}"
echo -e "  - Network:     ${BLUE}$NET_PKGS${RC}"
echo -e "  - GUI:         ${BLUE}$GUI_PKGS${RC}"
echo -e "  - Fonts:       ${BLUE}$FONT_PKGS${RC}"
echo -e "  - XDG tools:   ${BLUE}$XDG_PKGS${RC}"
echo -e "  - D-Bus:       ${BLUE}$DBUS_PKGS${RC}"
if [ -n "$SEAT_PKGS" ]; then
    echo -e "  - Seat/Session:${BLUE}$SEAT_PKGS${RC}"
fi
echo ""

if ! confirm "Proceed with the installation plan?" "y"; then
    echo -e "${RED}Installation cancelled by user.${RC}"
    exit 0
fi

echo -e "\n${YELLOW}>>> [Step 1/5] Updating System Repositories & Packages...${RC}"
echo -e "${BLUE}Synchronizing repositories and checking if XBPS needs updates...${RC}"
run_priv xbps-install -Sy xbps

echo -e "${BLUE}Upgrading all installed packages (pass 1)...${RC}"
run_priv xbps-install -Su

echo -e "${BLUE}Upgrading all installed packages (pass 2 - verifying backlog)...${RC}"
run_priv xbps-install -Su

echo -e "\n${YELLOW}>>> [Step 2/5] Installing Core Libraries & Base Software...${RC}"
FINAL_INSTALL_LIST="$ALL_PKGS $SEAT_PKGS"
run_priv xbps-install -y $FINAL_INSTALL_LIST

echo -e "\n${YELLOW}>>> [Step 3/5] Configuring Session & Seat Management Stack...${RC}"
case "$PRESELECTED_SEAT" in
    elogind)
        echo -e "${BLUE}Enabling elogind service...${RC}"
        enable_service elogind
        ;;
        
    turnstile-elogind)
        echo -e "${BLUE}Configuring turnstile to cooperate with elogind...${RC}"
        configure_turnstile no
        echo -e "${BLUE}Enabling elogind and turnstiled services...${RC}"
        enable_service elogind
        enable_service turnstiled
        ;;
        
    turnstile)
        echo -e "${BLUE}Configuring turnstile to manage rundir autonomously...${RC}"
        configure_turnstile yes
        echo -e "${BLUE}Enabling seatd, acpid and turnstiled services...${RC}"
        enable_service seatd
        enable_service acpid
        enable_service turnstiled
        if [ "$TARGET_USER" != "root" ]; then
            echo -e "${BLUE}Adding user '$TARGET_USER' to group '_seatd' for seat management...${RC}"
            run_priv usermod -aG _seatd "$TARGET_USER"
        fi
        ;;
        
    seatd)
        echo -e "${BLUE}Enabling seatd service...${RC}"
        enable_service seatd
        if [ "$TARGET_USER" != "root" ]; then
            echo -e "${BLUE}Adding user '$TARGET_USER' to group '_seatd' for seat management...${RC}"
            run_priv usermod -aG _seatd "$TARGET_USER"
        fi
        ;;
        
    manual)
        echo -e "${BLUE}Manual mode selected: skipping session manager service setup.${RC}"
        ;;
esac

echo -e "\n${YELLOW}>>> [Step 4/5] Configuring D-Bus Services...${RC}"
enable_service dbus

echo -e "\n${YELLOW}>>> [Step 5/5] Configuring XDG User Directories...${RC}"
if [ "$(id -u)" -eq 0 ]; then
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        echo -e "${BLUE}Initializing XDG user dirs as '$SUDO_USER'...${RC}"
        sudo -u "$SUDO_USER" xdg-user-dirs-update
    else
        echo -e "${RED}Warning: Script run as root directly. Skipping automatic XDG directory generation to prevent write conflicts inside /root.${RC}"
    fi
else
    echo -e "${BLUE}Initializing XDG user dirs...${RC}"
    xdg-user-dirs-update
fi

echo -e "\n${GREEN}✔ Installation completed successfully!${RC}"
echo -e "${YELLOW}===============================================${RC}"
echo -e "${AMBER}             Honeybee Post-Install Summary     ${RC}"
echo -e "${YELLOW}===============================================${RC}"
echo -e "Seat Stack configured: ${GREEN}$PRESELECTED_SEAT${RC}"
echo ""

case "$PRESELECTED_SEAT" in
    elogind)
        echo "elogind is active. System services 'dbus' and 'elogind' are enabled."
        echo "XDG_RUNTIME_DIR will be automatically configured for you upon login."
        ;;
    turnstile-elogind)
        echo "turnstile + elogind stack configured."
        echo "Services 'dbus', 'elogind', and 'turnstiled' are enabled."
        echo "/etc/turnstile/turnstiled.conf has been adjusted ('manage_rundir = no')."
        echo "You can manage per-user services by copying runit templates from:"
        echo "  /usr/share/examples/turnstile/"
        echo "into your user directory:"
        echo "  ~/.config/service/"
        ;;
    turnstile)
        echo "Standalone turnstile + seatd stack configured."
        echo "Services 'dbus', 'turnstiled', 'seatd', and 'acpid' are enabled."
        echo "/etc/turnstile/turnstiled.conf has been adjusted ('manage_rundir = yes')."
        echo "User '$TARGET_USER' has been added to the '_seatd' group."
        echo "Ensure you log out or reboot for group changes to take effect."
        ;;
    seatd)
        echo "Minimal seatd setup configured."
        echo "Service 'seatd' is enabled and user '$TARGET_USER' added to the '_seatd' group."
        echo -e "${RED}Note:${RC} You must configure XDG_RUNTIME_DIR and start D-Bus manually."
        echo "Ensure you log out or reboot for group changes to take effect."
        ;;
    manual)
        echo "No session management daemon is configured."
        echo -e "${YELLOW}Manual Action Required:${RC} Add the following block to your shell profile"
        echo "(e.g., ~/.bash_profile or ~/.zprofile) to configure XDG_RUNTIME_DIR:"
        echo ""
        echo -e "${BLUE}  if [ -z \"\${XDG_RUNTIME_DIR}\" ]; then"
        echo -e "      export XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\""
        echo -e "      if [ ! -d \"\${XDG_RUNTIME_DIR}\" ]; then"
        echo -e "          mkdir -p \"\${XDG_RUNTIME_DIR}\""
        echo -e "          chmod 700 \"\${XDG_RUNTIME_DIR}\""
        echo -e "      fi"
        echo -e "  fi${RC}"
        echo ""
        ;;
esac

echo -e "\n${YELLOW}It is highly recommended to REBOOT your system now for all changes to take effect.${RC}\n"
