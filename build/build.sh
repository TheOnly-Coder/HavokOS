#!/bin/bash
# HavokOS ISO Builder v3.0 — Complete rewrite
# Based on research into live-boot internals, sysvinit in Debian 12,
# and how the initramfs → switch_root → init chain actually works.

set -ex

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/output"
WORK_DIR="/tmp/havokos-build"
CHROOT_DIR="$WORK_DIR/chroot"
ISO_DIR="$WORK_DIR/iso"

echo "========================================"
echo "       HavokOS ISO Builder v3.0        "
echo "========================================"

rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

###############################################################################
# Step 1: Create minimal Debian chroot (minbase)
###############################################################################
echo "[1/10] Creating Debian bookworm chroot..."
mkdir -p "$CHROOT_DIR"
debootstrap --variant=minbase --arch=amd64 bookworm "$CHROOT_DIR" http://deb.debian.org/debian

###############################################################################
# Step 2: Configure chroot basics
###############################################################################
echo "[2/10] Configuring chroot..."
echo "havokos" > "$CHROOT_DIR/etc/hostname"
cat > "$CHROOT_DIR/etc/hosts" << 'HOSTS'
127.0.0.1       havokos localhost
::1             localhost ip6-localhost ip6-loopback
HOSTS

cat > "$CHROOT_DIR/etc/apt/sources.list" << 'SOURCES'
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free-firmware
SOURCES

mount --bind /dev "$CHROOT_DIR/dev"
mount -t proc proc "$CHROOT_DIR/proc"
mount -t sysfs sysfs "$CHROOT_DIR/sys"
mount -t devpts devpts "$CHROOT_DIR/dev/pts"

# Block all service starts during chroot package installs
cat > "$CHROOT_DIR/usr/sbin/policy-rc.d" << 'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "$CHROOT_DIR/usr/sbin/policy-rc.d"

###############################################################################
# Step 3: CRITICAL — Install sysvinit FIRST, pin systemd out, then kernel
#
# WHY: debootstrap minbase installs systemd-sysv by default.
# linux-image-amd64 depends on an init system and will happily keep systemd.
# We MUST install sysvinit-core FIRST in a separate apt call, pin systemd
# to priority -1 so nothing can reinstall it, and THEN install the kernel.
#
# Without this, /sbin/init remains a symlink to systemd, which crashes
# in a live CD (no cgroups, no journald) → "Attempted to kill init!"
###############################################################################
echo "[3/10] Installing sysvinit and pinning out systemd..."

# Pin systemd to priority -1 — prevents ANY package from reinstalling it
mkdir -p "$CHROOT_DIR/etc/apt/preferences.d"
cat > "$CHROOT_DIR/etc/apt/preferences.d/no-systemd" << 'PIN'
Package: systemd systemd-sysv systemd-boot systemd-container systemd-coredump systemd-journal-remote systemd-journal-upload systemd-resolved systemd-timesyncd systemd-networkd systemd-oomd
Pin: release *
Pin-Priority: -1
PIN

# FIRST apt call: install sysvinit and essential init infrastructure
chroot "$CHROOT_DIR" apt-get update
chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    sysvinit-core \
    sysvinit-utils \
    sysv-rc \
    initscripts \
    bootlogd \
    elogind \
    libpam-elogind \
    orphan-sysvinit-scripts

# Verify systemd was removed and sysvinit owns /sbin/init
if [ -L "$CHROOT_DIR/sbin/init" ]; then
    INIT_TARGET=$(readlink "$CHROOT_DIR/sbin/init")
    echo "  /sbin/init -> $INIT_TARGET"
    if echo "$INIT_TARGET" | grep -q systemd; then
        echo "ERROR: /sbin/init still points to systemd! Fixing..."
        chroot "$CHROOT_DIR" apt-get remove -y --purge systemd systemd-sysv 2>/dev/null || true
        chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends sysvinit-core
    fi
fi
# Final check
if chroot "$CHROOT_DIR" dpkg -l systemd-sysv 2>/dev/null | grep -q '^ii'; then
    echo "ERROR: systemd-sysv is still installed! Purging..."
    chroot "$CHROOT_DIR" dpkg --purge --force-remove-reinstreq systemd-sysv 2>/dev/null || true
fi
if [ ! -x "$CHROOT_DIR/sbin/init" ]; then
    echo "ERROR: /sbin/init is not executable!"
    exit 1
fi
file "$CHROOT_DIR/sbin/init" | head -1
echo "  sysvinit installed and verified"

###############################################################################
# Step 4: Install kernel + live-boot + all packages (systemd is now pinned out)
###############################################################################
echo "[4/10] Installing kernel, live-boot, desktop packages..."
chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    linux-image-amd64 \
    live-boot \
    live-boot-initramfs-tools \
    initramfs-tools \
    xserver-xorg-core \
    xserver-xorg-video-vesa \
    xserver-xorg-video-fbdev \
    xserver-xorg-input-libinput \
    xinit \
    openbox \
    obconf \
    python3 \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gtk-3.0 \
    gir1.2-gtksource-4 \
    gir1.2-webkit2-4.1 \
    gir1.2-vte-2.91 \
    dbus-x11 \
    lightdm \
    lightdm-gtk-greeter \
    pcmanfm \
    lxterminal \
    network-manager \
    wpasupplicant \
    wireless-tools \
    iso-codes \
    locales \
    fonts-dejavu-core \
    fonts-liberation \
    curl \
    wget \
    sudo \
    policykit-1 \
    gvfs \
    gvfs-backends \
    xdg-utils \
    xdg-user-dirs \
    shared-mime-info \
    mime-support \
    htop \
    nano \
    kbd \
    console-setup \
    procps

# Re-verify /sbin/init after all packages installed (something may have pulled systemd back)
if [ -L "$CHROOT_DIR/sbin/init" ] && readlink "$CHROOT_DIR/sbin/init" | grep -q systemd; then
    echo "ERROR: A package reinstalled systemd! /sbin/init points to systemd."
    echo "  Forcing sysvinit..."
    chroot "$CHROOT_DIR" apt-get remove -y --purge systemd systemd-sysv 2>/dev/null || true
    chroot "$CHROOT_DIR" ln -sf /lib/sysvinit/init "$CHROOT_DIR/sbin/init"
fi
echo "  Final /sbin/init: $(ls -la $CHROOT_DIR/sbin/init)"

chroot "$CHROOT_DIR" sh -c 'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen'
chroot "$CHROOT_DIR" update-locale LANG=en_US.UTF-8

###############################################################################
# Step 5: Create user and configure autologin
###############################################################################
echo "[5/10] Setting up user and display manager..."
chroot "$CHROOT_DIR" useradd -m -s /bin/bash -G sudo,netdev,audio,video,plugdev,havok havok
echo "havok:havokos" | chroot "$CHROOT_DIR" chpasswd

cat > "$CHROOT_DIR/etc/lightdm/lightdm.conf" << 'LIGHTDM'
[SeatDefaults]
autologin-user=havok
autologin-user-timeout=0
user-session=openbox
LIGHTDM

###############################################################################
# Step 6: Copy HavokOS overlay files
###############################################################################
echo "[6/10] Installing HavokOS overlay..."

# HSL interpreter — install to BOTH /usr/bin/hsl AND /usr/share/havok/hsl/
# (havok-desktop imports it as a Python module from /usr/share/havok/hsl/)
cp "$PROJECT_DIR/hsl/interpreter.py" "$CHROOT_DIR/usr/bin/hsl"
chmod +x "$CHROOT_DIR/usr/bin/hsl"
mkdir -p "$CHROOT_DIR/usr/share/havok/hsl"
cp "$PROJECT_DIR/hsl/interpreter.py" "$CHROOT_DIR/usr/share/havok/hsl/interpreter.py"
cp -r "$PROJECT_DIR/hsl/stdlib/"* "$CHROOT_DIR/usr/share/havok/hsl/" 2>/dev/null || true

# Havok apps
cp "$PROJECT_DIR/overlay/usr/bin/"* "$CHROOT_DIR/usr/bin/" 2>/dev/null || true
chmod +x "$CHROOT_DIR/usr/bin/havok-"* 2>/dev/null || true

# Desktop entries
mkdir -p "$CHROOT_DIR/usr/share/applications"
cp "$PROJECT_DIR/overlay/usr/share/applications/"*.desktop "$CHROOT_DIR/usr/share/applications/" 2>/dev/null || true

# X11 config
cp -r "$PROJECT_DIR/overlay/etc/X11/"* "$CHROOT_DIR/etc/X11/" 2>/dev/null || true

# Autostart
mkdir -p "$CHROOT_DIR/etc/xdg/autostart"
cp "$PROJECT_DIR/overlay/etc/xdg/autostart/"*.desktop "$CHROOT_DIR/etc/xdg/autostart/" 2>/dev/null || true

# HavokCustom — desktop customizations via HSL
mkdir -p "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/IMPORTANT"
cp "$PROJECT_DIR/overlay/home/havok/Desktop/HavokCustom/IMPORTANT/readme.txt" "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/IMPORTANT/readme.txt" 2>/dev/null || true
cp "$PROJECT_DIR/overlay/home/havok/Desktop/HavokCustom/IMPORTANT/"*.hsl "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/IMPORTANT/" 2>/dev/null || true
mkdir -p "$CHROOT_DIR/home/havok/Desktop/HavokCustom/IMPORTANT"
cp -r "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/"* "$CHROOT_DIR/home/havok/Desktop/HavokCustom/" 2>/dev/null || true
chroot "$CHROOT_DIR" chown -R havok:havok /home/havok/Desktop

###############################################################################
# Step 7: Configure sysvinit, rc scripts, and desktop environment
###############################################################################
echo "[7/10] Configuring sysvinit and desktop..."

# Ensure /etc/init.d/rc and rcS exist (initscripts may fail in chroot)
if [ ! -x "$CHROOT_DIR/etc/init.d/rc" ]; then
    echo "  Creating fallback /etc/init.d/rc"
    cat > "$CHROOT_DIR/etc/init.d/rc" << 'RCD'
#!/bin/sh
runlevel=$1
export RUNLEVEL=$runlevel
PREVLEVEL=
[ -r /etc/runlevel.conf ] && . /etc/runlevel.conf
RC_DIR="/etc/rc${runlevel}.d"
if [ -d "$RC_DIR" ]; then
    for script in "$RC_DIR"/K*; do
        [ -x "$script" ] && "$script" stop 2>/dev/null || true
    done
    for script in "$RC_DIR"/S*; do
        [ -x "$script" ] && "$script" start 2>/dev/null || true
    done
fi
RCD
    chmod +x "$CHROOT_DIR/etc/init.d/rc"
fi
if [ ! -x "$CHROOT_DIR/etc/init.d/rcS" ]; then
    echo "  Creating fallback /etc/init.d/rcS"
    cat > "$CHROOT_DIR/etc/init.d/rcS" << 'RCS'
#!/bin/sh
export RUNLEVEL=S
export PREVLEVEL=N
RC_DIR="/etc/rcS.d"
if [ -d "$RC_DIR" ]; then
    for script in "$RC_DIR"/S*; do
        [ -x "$script" ] && "$script" start 2>/dev/null || true
    done
fi
RCS
    chmod +x "$CHROOT_DIR/etc/init.d/rcS"
fi

# Write inittab
cat > "$CHROOT_DIR/etc/inittab" << 'INITTAB'
id:2:initdefault:
si::sysinit:/etc/init.d/rcS
l0:0:wait:/etc/init.d/rc 0
l1:1:wait:/etc/init.d/rc 1
l2:2:wait:/etc/init.d/rc 2
l3:3:wait:/etc/init.d/rc 3
l4:4:wait:/etc/init.d/rc 4
l5:5:wait:/etc/init.d/rc 5
l6:6:wait:/etc/init.d/rc 6
1:2345:respawn:/sbin/getty 38400 tty1
2:23:respawn:/sbin/getty 38400 tty2
3:23:respawn:/sbin/getty 38400 tty3
ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now
INITTAB

# Essential directories
mkdir -p "$CHROOT_DIR/run" "$CHROOT_DIR/var/run" "$CHROOT_DIR/var/lock" \
         "$CHROOT_DIR/etc/rc2.d" "$CHROOT_DIR/etc/rcS.d"

# fstab
cat > "$CHROOT_DIR/etc/fstab" << 'FSTAB'
proc    /proc   proc    defaults    0 0
sysfs   /sys    sysfs   defaults    0 0
devpts  /dev/pts devpts  defaults    0 0
tmpfs   /tmp    tmpfs   defaults    0 0
tmpfs   /run    tmpfs   defaults    0 0
FSTAB

# Network
cat > "$CHROOT_DIR/etc/network/interfaces" << 'INTERFACES'
auto lo
iface lo inet loopback
allow-hotplug eth0
iface eth0 inet dhcp
INTERFACES

# Openbox desktop
mkdir -p "$CHROOT_DIR/etc/xdg/openbox"
cat > "$CHROOT_DIR/etc/xdg/openbox/autostart" << 'AUTOSTART'
xsetroot -solid "#1a1a2e" &
havok-desktop &
havok-panel &
nm-applet &
AUTOSTART

cat > "$CHROOT_DIR/etc/xdg/openbox/menu.xml" << 'MENU'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="havok-apps" label="Applications">
    <item label="Havok Browser"><action name="Execute"><command>havok-browser</command></action></item>
    <item label="Havok Files"><action name="Execute"><command>havok-files</command></action></item>
    <item label="Havok Editor"><action name="Execute"><command>havok-editor</command></action></item>
    <item label="Havok Settings"><action name="Execute"><command>havok-settings</command></action></item>
    <separator />
    <item label="Terminal"><action name="Execute"><command>lxterminal</command></action></item>
    <item label="HSL Console"><action name="Execute"><command>lxterminal -e hsl --repl</command></action></item>
  </menu>
  <menu id="root-menu" label="HavokOS">
    <menu id="havok-apps" />
    <separator />
    <item label="Reload HSL"><action name="Execute"><command>havok-desktop --reload</command></action></item>
    <separator />
    <item label="Log Out"><action name="Exit" /></item>
  </menu>
</openbox_menu>
MENU

cat > "$CHROOT_DIR/etc/xdg/openbox/rc.xml" << 'RCXML'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance><strength>10</strength><screen_edge_strength>20</screen_edge_strength></resistance>
  <focus><focusNew>yes</focusNew><followMouse>no</followMouse><focusLast>yes</focusLast></focus>
  <placement><policy>Smart</policy><center>yes</center></placement>
  <theme><name>Clearlooks</name><titleLayout>NLIMC</titleLayout><keepBorder>yes</keepBorder><animateIconify>no</animateIconify></theme>
  <desktops><number>1</number><firstdesk>0</firstdesk><names><name>Desktop</name></names></desktops>
  <resize><drawContents>yes</drawContents><popupShow>Nonpixel</popupShow><popupPosition>Center</popupPosition></resize>
  <margins><top>32</top><bottom>0</bottom><left>0</left><right>0</right></margins>
</openbox_config>
RCXML

# User xinitrc
cat > "$CHROOT_DIR/home/havok/.xinitrc" << 'XINITRC'
#!/bin/bash
export GTK_THEME=Adwaita:dark
exec openbox-session
XINITRC
chmod +x "$CHROOT_DIR/home/havok/.xinitrc"
chroot "$CHROOT_DIR" chown havok:havok /home/havok/.xinitrc

# Xsession entry
cat > "$CHROOT_DIR/usr/share/xsessions/havokos.desktop" << 'SESSION'
[Desktop Entry]
Name=HavokOS
Comment=HavokOS Desktop Environment
Exec=openbox-session
Type=Application
DesktopNames=HavokOS
SESSION

# rc.local — starts essential services at boot
cat > "$CHROOT_DIR/etc/rc.local" << 'RCLOCAL'
#!/bin/sh
echo "HavokOS rc.local: Starting services..."
# Mount essential virtual filesystems (live-boot should have done this, but be safe)
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devpts devpts /dev/pts 2>/dev/null || true
# Start D-Bus (required for GTK apps, polkit, NM)
if [ -x /etc/init.d/dbus ]; then
    /etc/init.d/dbus start 2>/dev/null || true
fi
# Start NetworkManager
if [ -x /etc/init.d/network-manager ]; then
    /etc/init.d/network-manager start 2>/dev/null || true
fi
# Start LightDM (display manager)
if [ -x /etc/init.d/lightdm ]; then
    /etc/init.d/lightdm start 2>/dev/null || true
fi
exit 0
RCLOCAL
chmod +x "$CHROOT_DIR/etc/rc.local"

# Register services in rc2.d
chroot "$CHROOT_DIR" update-rc.d dbus defaults 2>/dev/null || true
chroot "$CHROOT_DIR" update-rc.d network-manager defaults 2>/dev/null || true
chroot "$CHROOT_DIR" update-rc.d lightdm defaults 2>/dev/null || true
chroot "$CHROOT_DIR" update-rc.d console-setup defaults 2>/dev/null || true
# Ensure rc.local runs last
ln -sf /etc/rc.local "$CHROOT_DIR/etc/rc2.d/S99rc.local" 2>/dev/null || true

###############################################################################
# Step 8: Build initramfs with live-boot hooks
###############################################################################
echo "[8/10] Building initramfs..."

cat > "$CHROOT_DIR/etc/initramfs-tools/conf.d/havokos.conf" << 'INITCONF'
MODULES=most
COMPRESS=gzip
BUSYBOX=auto
KEYMAP=n
INITCONF

cat > "$CHROOT_DIR/etc/initramfs-tools/modules" << 'MODLIST'
vfat
nls_cp437
nls_iso8859_1
isofs
squashfs
loop
cdrom
sr_mod
usb_storage
uhci_hcd
ohci_hcd
ehci_hcd
xhci_hcd
virtio_blk
virtio_pci
MODLIST

echo "  Generating initramfs..."
chroot "$CHROOT_DIR" update-initramfs -c -k all

# Verify
INITRD_PATH=$(ls "$CHROOT_DIR/boot/initrd.img-"* | sort -V | tail -1)
if [ ! -f "$INITRD_PATH" ]; then
    echo "ERROR: initramfs was not created!"
    exit 1
fi
INITRD_SIZE=$(stat -c%s "$INITRD_PATH")
echo "  Initramfs size: $((INITRD_SIZE / 1024)) KB"
if [ "$INITRD_SIZE" -lt 100000 ]; then
    echo "ERROR: Initramfs too small ($INITRD_SIZE bytes)"
    exit 1
fi
gzip -t "$INITRD_PATH" 2>/dev/null && echo "  Gzip integrity: OK" || { echo "ERROR: Gzip check failed!"; exit 1; }
if (zcat "$INITRD_PATH" | cpio -t 2>/dev/null | grep -q 'live'); then
    echo "  live-boot scripts in initramfs: OK"
else
    echo "  WARNING: No live-boot scripts found in initramfs!"
fi

KERN_VER=$(ls "$CHROOT_DIR/boot/vmlinuz-"* | sort -V | tail -1 | xargs basename | sed 's/vmlinuz-//')
echo "  Kernel: $KERN_VER"

###############################################################################
# Step 9: Clean up and build squashfs
###############################################################################
echo "[9/10] Building squashfs..."

# Unmount chroot filesystems (needed before squashfs)
umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
umount "$CHROOT_DIR/sys" 2>/dev/null || true
umount "$CHROOT_DIR/proc" 2>/dev/null || true
umount "$CHROOT_DIR/dev" 2>/dev/null || true

# Remove build artifacts that should not be in the ISO
rm -f "$CHROOT_DIR/usr/sbin/policy-rc.d"
rm -f "$CHROOT_DIR/var/lib/dbus/machine-id"
rm -f "$CHROOT_DIR/etc/machine-id"
echo "" > "$CHROOT_DIR/etc/machine-id"  # Empty for live boot

# Ensure mount points exist (live-boot will mount over these)
mkdir -p "$CHROOT_DIR/proc" "$CHROOT_DIR/sys" "$CHROOT_DIR/dev" "$CHROOT_DIR/run" "$CHROOT_DIR/tmp"

# Create ISO directory structure
mkdir -p "$ISO_DIR/live" "$ISO_DIR/boot/isolinux"

echo "  Creating squashfs (this takes a while)..."
mksquashfs "$CHROOT_DIR" "$ISO_DIR/live/filesystem.squashfs" \
    -e boot -e proc -e sys -e dev -e run -e tmp -noappend

cp "$CHROOT_DIR/boot/vmlinuz-$KERN_VER" "$ISO_DIR/live/vmlinuz"
cp "$INITRD_PATH" "$ISO_DIR/live/initrd.img"

echo "  ISO filesystem contents:"
ls -lh "$ISO_DIR/live/"

###############################################################################
# Step 10: Bootloader + ISO creation
###############################################################################
echo "[10/10] Creating bootable ISO..."

cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_DIR/boot/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$ISO_DIR/boot/isolinux/"
cp /usr/lib/syslinux/modules/bios/libcom32.c32 "$ISO_DIR/boot/isolinux/"
cp /usr/lib/syslinux/modules/bios/libutil.c32 "$ISO_DIR/boot/isolinux/"

cat > "$ISO_DIR/boot/isolinux/isolinux.cfg" << 'ISOLINUX'
DEFAULT havokos
PROMPT 1
TIMEOUT 50

LABEL havokos
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live union=overlay noeject console=tty0
ISOLINUX

mkdir -p "$ISO_DIR/boot/grub"
cat > "$ISO_DIR/boot/grub/grub.cfg" << 'GRUB'
set timeout=10
set default=0

menuentry "HavokOS" {
    linux /live/vmlinuz boot=live union=overlay noeject console=tty0
    initrd /live/initrd.img
}
GRUB

echo "  Generating ISO..."
cd "$ISO_DIR"
xorriso \
    -as mkisofs \
    -o "$OUTPUT_DIR/HavokOS-1.0.0.iso" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c boot/isolinux/boot.cat \
    -b boot/isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -V "HAVOKOS" \
    -J -joliet-long \
    -r \
    .

rm -rf "$WORK_DIR"

ISO_SIZE=$(du -h "$OUTPUT_DIR/HavokOS-1.0.0.iso" | cut -f1)
echo ""
echo "========================================"
echo "  HavokOS ISO built successfully!     "
echo "  Output: $OUTPUT_DIR/HavokOS-1.0.0.iso"
echo "  Size:   $ISO_SIZE"
echo "========================================"
