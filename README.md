# honeybee

a user-friendly hijacK? script for void linux.

# what does it do?

archinstall after-install but for void linux. it handles the 14 month backlog of updates since the last image release, installs finnicky libraries that void does not ship by default (ex: libstdc++ which alacritty needs on older systems), sets up d-bus, xdg user directories, xdg runtime dir, and lets you pick a session/seat management stack.

# what it installs

- core libraries: libstdc++, libgcc, ncurses, readline, zlib, bzip2, xz, lz4, zstd, brotli, libpng, libjpeg-turbo, tiff, libwebp, icu-libs
- graphics stack: libX11, libxcb, libXext, libXrender, libXft, fontconfig, freetype, libxkbcommon, mesa-dri
- networking & crypto: libcurl, libressl, gnutls, ca-certificates
- gui toolkits: gtk+3, glib, pango, cairo, gdk-pixbuf, qt5, pam, libcap
- fonts: dejavu-fonts-ttf, liberation-fonts-ttf, terminus-font, noto-fonts-emoji
- xdg tools: xdg-user-dirs, xdg-user-dirs-gtk, xdg-utils, xdg-desktop-portal, xdg-desktop-portal-gtk
- d-bus: dbus, dbus-x11

# session and seat management

the script walks you through picking one of five session/seat stacks per the void linux handbook:

1. **elogind** 
2. **turnstile + elogind**
3. **turnstile**
4. **seatd** 
5. **manual** 

# who this is for

people who want an easier start to void, or people who dont wanna go through the 2 hours of finnicky setup when installing it again for the 60th time. (also me!!!) (and people who may not know that void has a 14 month backlog of updates!!!)

# usage

```bash
chmod +x honeybee.sh
./honeybee.sh              # interactive mode
./honeybee.sh --quick      # skip confirmation prompts
./honeybee.sh --seat=elogind   # pre-select a stack
