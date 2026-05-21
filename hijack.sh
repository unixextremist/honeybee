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
NET_PKGS="curl openssl gnutls ca-certificates"
GUI_PKGS="gtk+3 glib pango cairo gdk-pixbuf qt5 pam libcap"
FONT_PKGS="dejavu-fonts-ttf liberation-fonts-ttf terminus-font noto-fonts-emoji"
XDG_PKGS="xdg-user-dirs xdg-user-dirs-gtk xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk"
DBUS_PKGS="dbus dbus-x11"

ALL_PKGS="$CORE_PKGS $GRAPHICS_PKGS $NET_PKGS $GUI_PKGS $FONT_PKGS $XDG_PKGS $DBUS_PKGS"

QUICK_MODE=false
PRESELECTED_SEAT=""

show_help() {
    printf "${AMBER}honeybee - Void Linux Post-Install Hijack Script${RC}\n"
    printf "\n"
    printf "Usage:\n"
    printf "  ./honeybee.sh [options]\n"
    printf "\n"
    printf "Options:\n"
    printf "  -q, --quick           Skip confirmation prompts (non-interactive mode)\n"
    printf "  -s, --seat=STACK      Pre-select session/seat management stack:\n"
    printf "                        Options: elogind, turnstile-elogind, turnstile, seatd, manual\n"
    printf "  -h, --help            Show this help message\n"
    printf "\n"
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
            printf "${RED}Unknown argument: $1${RC}\n"
            show_help
            ;;
    esac
done

if [ ! -f /etc/void-release ] && ! command -v xbps-install >/dev/null 2>&1; then
    printf "${RED}Error: This script is intended to run on Void Linux.${RC}\n" >&2
    exit 1
fi

print_banner() {
    printf "${AMBER}\n"
    printf "  ,  ,\n"
    printf " ( \\/ )\n"
    printf "() == ()   honeybee\n"
    printf " ( /\\ )    a user-friendly hijack/after-install script for Void Linux\n"
    printf "  \`  \`\n"
    printf "${RC}\n"
}

print_banner

run_priv() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        if command -v sudo >/dev/null 2>&1; then
            sudo "$@"
        else
            printf "${RED}Error: Root privileges are required. Please run this script with sudo or as root.${RC}\n" >&2
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
        printf "%s [Y/n]: " "$prompt"
        read -r choice
        case "$choice" in
            [nN]|[nN][oO]) return 1 ;;
            *) return 0 ;;
        esac
    else
        printf "%s [y/N]: " "$prompt"
        read -r choice
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
            printf "${BLUE}Enabling service: $service...${RC}\n"
            run_priv ln -sf "/etc/sv/$service" /var/service/
        else
            printf "${GREEN}Service already enabled: $service${RC}\n"
        fi
    else
        printf "${RED}Warning: Service configuration for '$service' not found in /etc/sv/.${RC}\n"
    fi
}

configure_turnstile() {
    local val="$1"
    local config_file="/etc/turnstile/turnstiled.conf"
    
    if [ ! -f "$config_file" ]; then
        printf "${BLUE}Creating directory and configuration at $config_file...${RC}\n"
        run_priv mkdir -p /etc/turnstile
        printf "manage_rundir = %s\n" "$val" | run_priv tee "$config_file" > /dev/null
    else
        printf "${BLUE}Configuring $config_file: setting manage_rundir = $val...${RC}\n"
        if grep -q "^[# ]*manage_rundir" "$config_file"; then
            run_priv sed -i "s/^[# ]*manage_rundir[[:space:]]*=.*/manage_rundir = $val/" "$config_file"
        else
            printf "manage_rundir = %s\n" "$val" | run_priv tee -a "$config_file" > /dev/null
        fi
    fi
}

if [ -n "$PRESELECTED_SEAT" ]; then
    if [ "$PRESELECTED_SEAT" = "turnstile-elogind" ] || [ "$PRESELECTED_SEAT" = "turnstile+elogind" ]; then
        PRESELECTED_SEAT="turnstile-elogind"
    fi
    printf "${BLUE}Seat stack selected via CLI: ${AMBER}%s${RC}\n" "$PRESELECTED_SEAT"
else
    printf "${YELLOW}Please select a session/seat management stack:${RC}\n"
    printf "1) elogind : full session management, auto XDG_RUNTIME_DIR, power control.\n"
    printf "   Best for: Desktop Environments, Wayland compositors, rootless Xorg.\n"
    printf "\n"
    printf "2) turnstile + elogind : turnstile manages sessions, elogind handles rundir/power.\n"
    printf "   Best for: per-user services, running D-Bus without dbus-run-session.\n"
    printf "\n"
    printf "3) turnstile : standalone session tracker, seatd for seats, acpid for power.\n"
    printf "   Best for: minimal setups, wlroots-based wayland compositors.\n"
    printf "\n"
    printf "4) seatd : minimal seat management daemon only.\n"
    printf "   Best for: sway, dwl, river. (You handle XDG_RUNTIME_DIR & D-Bus yourself)\n"
    printf "\n"
    printf "5) manual : no session manager. DIY XDG_RUNTIME_DIR.\n"
    printf "   Best for: minimalists who want full manual control.\n"
    printf "\n"
    
    while true; do
        printf "Select option (1-5): "
        read -r choice
        case "$choice" in
            1) PRESELECTED_SEAT="elogind"; break ;;
            2) PRESELECTED_SEAT="turnstile-elogind"; break ;;
            3) PRESELECTED_SEAT="turnstile"; break ;;
            4) PRESELECTED_SEAT="seatd"; break ;;
            5) PRESELECTED_SEAT="manual"; break ;;
            *) printf "${RED}Invalid selection. Please enter 1-5.${RC}\n" ;;
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

printf "\n${YELLOW}=== Honeybee Installation Plan ===${RC}\n"
printf "User context:    ${BLUE}%s${RC}\n" "$TARGET_USER"
printf "Execution mode:  ${BLUE}%s${RC}\n" "$( [ "$QUICK_MODE" = "true" ] && printf "Quick (Non-interactive)" || printf "Interactive" )"
printf "Seat stack:      ${BLUE}%s${RC}\n" "$PRESELECTED_SEAT"
printf "Target packages to install:\n"
printf "  - Core:        ${BLUE}%s${RC}\n" "$CORE_PKGS"
printf "  - Graphics:    ${BLUE}%s${RC}\n" "$GRAPHICS_PKGS"
printf "  - Network:     ${BLUE}%s${RC}\n" "$NET_PKGS"
printf "  - GUI:         ${BLUE}%s${RC}\n" "$GUI_PKGS"
printf "  - Fonts:       ${BLUE}%s${RC}\n" "$FONT_PKGS"
printf "  - XDG tools:   ${BLUE}%s${RC}\n" "$XDG_PKGS"
printf "  - D-Bus:       ${BLUE}%s${RC}\n" "$DBUS_PKGS"
if [ -n "$SEAT_PKGS" ]; then
    printf "  - Seat/Session:${BLUE}%s${RC}\n" "$SEAT_PKGS"
fi
printf "\n"

if ! confirm "Proceed with the installation plan?" "y"; then
    printf "${RED}Installation cancelled by user.${RC}\n"
    exit 0
fi

printf "\n${YELLOW}>>> [Step 1/5] Updating System Repositories & Packages...${RC}\n"
printf "${BLUE}Synchronizing repositories and checking if XBPS needs updates...${RC}\n"
run_priv xbps-install -Sy xbps

printf "${BLUE}Upgrading all installed packages (pass 1)...${RC}\n"
run_priv xbps-install -Su

printf "${BLUE}Upgrading all installed packages (pass 2 - verifying backlog)...${RC}\n"
run_priv xbps-install -Su

printf "\n${YELLOW}>>> [Step 2/5] Installing Core Libraries & Base Software...${RC}\n"
FINAL_INSTALL_LIST="$ALL_PKGS $SEAT_PKGS"
run_priv xbps-install -y $FINAL_INSTALL_LIST

printf "\n${YELLOW}>>> [Step 3/5] Configuring Session & Seat Management Stack...${RC}\n"
case "$PRESELECTED_SEAT" in
    elogind)
        printf "${BLUE}Enabling elogind service...${RC}\n"
        enable_service elogind
        ;;
        
    turnstile-elogind)
        printf "${BLUE}Configuring turnstile to cooperate with elogind...${RC}\n"
        configure_turnstile no
        printf "${BLUE}Enabling elogind and turnstiled services...${RC}\n"
        enable_service elogind
        enable_service turnstiled
        ;;
        
    turnstile)
        printf "${BLUE}Configuring turnstile to manage rundir autonomously...${RC}\n"
        configure_turnstile yes
        printf "${BLUE}Enabling seatd, acpid and turnstiled services...${RC}\n"
        enable_service seatd
        enable_service acpid
        enable_service turnstiled
        if [ "$TARGET_USER" != "root" ]; then
            printf "${BLUE}Adding user '$TARGET_USER' to group '_seatd' for seat management...${RC}\n"
            run_priv usermod -aG _seatd "$TARGET_USER"
        fi
        ;;
        
    seatd)
        printf "${BLUE}Enabling seatd service...${RC}\n"
        enable_service seatd
        if [ "$TARGET_USER" != "root" ]; then
            printf "${BLUE}Adding user '$TARGET_USER' to group '_seatd' for seat management...${RC}\n"
            run_priv usermod -aG _seatd "$TARGET_USER"
        fi
        ;;
        
    manual)
        printf "${BLUE}Manual mode selected: skipping session manager service setup.${RC}\n"
        ;;
esac

printf "\n${YELLOW}>>> [Step 4/5] Configuring D-Bus Services...${RC}\n"
enable_service dbus

printf "\n${YELLOW}>>> [Step 5/5] Configuring XDG User Directories...${RC}\n"
if [ "$(id -u)" -eq 0 ]; then
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        printf "${BLUE}Initializing XDG user dirs as '$SUDO_USER'...${RC}\n"
        sudo -u "$SUDO_USER" xdg-user-dirs-update
    else
        printf "${RED}Warning: Script run as root directly. Skipping automatic XDG directory generation to prevent write conflicts inside /root.${RC}\n"
    fi
else
    printf "${BLUE}Initializing XDG user dirs...${RC}\n"
    xdg-user-dirs-update
fi

printf "\n${GREEN}✔ Installation completed successfully!${RC}\n"
printf "${YELLOW}===============================================${RC}\n"
printf "${AMBER}             Honeybee Post-Install Summary     ${RC}\n"
printf "${YELLOW}===============================================${RC}\n"
printf "Seat Stack configured: ${GREEN}%s${RC}\n" "$PRESELECTED_SEAT"
printf "\n"

case "$PRESELECTED_SEAT" in
    elogind)
        printf "elogind is active. System services 'dbus' and 'elogind' are enabled.\n"
        printf "XDG_RUNTIME_DIR will be automatically configured for you upon login.\n"
        ;;
    turnstile-elogind)
        printf "turnstile + elogind stack configured.\n"
        printf "Services 'dbus', 'elogind', and 'turnstiled' are enabled.\n"
        printf "/etc/turnstile/turnstiled.conf has been adjusted ('manage_rundir = no').\n"
        printf "You can manage per-user services by copying runit templates from:\n"
        printf "  /usr/share/examples/turnstile/\n"
        printf "into your user directory:\n"
        printf "  ~/.config/service/\n"
        ;;
    turnstile)
        printf "Standalone turnstile + seatd stack configured.\n"
        printf "Services 'dbus', 'turnstiled', 'seatd', and 'acpid' are enabled.\n"
        printf "/etc/turnstile/turnstiled.conf has been adjusted ('manage_rundir = yes').\n"
        printf "User '%s' has been added to the '_seatd' group.\n" "$TARGET_USER"
        printf "Ensure you log out or reboot for group changes to take effect.\n"
        ;;
    seatd)
        printf "Minimal seatd setup configured.\n"
        printf "Service 'seatd' is enabled and user '%s' added to the '_seatd' group.\n" "$TARGET_USER"
        printf "${RED}Note:${RC} You must configure XDG_RUNTIME_DIR and start D-Bus manually.\n"
        printf "Ensure you log out or reboot for group changes to take effect.\n"
        ;;
    manual)
        printf "No session management daemon is configured.\n"
        printf "${YELLOW}Manual Action Required:${RC} Add the following block to your shell profile\n"
        printf "(e.g., ~/.bash_profile or ~/.zprofile) to configure XDG_RUNTIME_DIR:\n"
        printf "\n"
        printf "${BLUE}  if [ -z \"\${XDG_RUNTIME_DIR}\" ]; then\n"
        printf "      export XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\"\n"
        printf "      if [ ! -d \"\${XDG_RUNTIME_DIR}\" ]; then\n"
        printf "          mkdir -p \"\${XDG_RUNTIME_DIR}\"\n"
        printf "          chmod 700 \"\${XDG_RUNTIME_DIR}\"\n"
        printf "      fi\n"
        printf "  fi${RC}\n"
        printf "\n"
        ;;
esac

printf "\n${YELLOW}It is highly recommended to REBOOT your system now for all changes to take effect.${RC}\n\n"
