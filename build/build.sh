#!/bin/bash
# HavokOS ISO Builder
# Creates a minimal Debian-based live ISO with HavokOS desktop

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/output"
WORK_DIR="/tmp/havokos-build"
CHROOT_DIR="$WORK_DIR/chroot"
ISO_DIR="$WORK_DIR/iso"
SQUASHFS="$WORK_DIR/live/filesystem.squashfs"

echo "========================================"
echo "       HavokOS ISO Builder v1.0.0       "
echo "========================================"

# Cleanup
rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ============================================================
# Step 1: Create minimal Debian chroot
# ============================================================
echo "[1/8] Creating Debian chroot..."
mkdir -p "$CHROOT_DIR"
debootstrap --variant=minbase --arch=amd64 bookworm "$CHROOT_DIR" http://deb.debian.org/debian

# ============================================================
# Step 2: Configure the chroot
# ============================================================
echo "[2/8] Configuring system..."

# Basic config
echo "havokos" > "$CHROOT_DIR/etc/hostname"
cat > "$CHROOT_DIR/etc/hosts" << 'HOSTS'
127.0.0.1       havokos localhost
::1             localhost ip6-localhost ip6-loopback
HOSTS

# Apt sources (include contrib for firmware if needed)
cat > "$CHROOT_DIR/etc/apt/sources.list" << 'SOURCES'
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free-firmware
SOURCES

# Mount proc, sys, dev for chroot operations
mount --bind /dev "$CHROOT_DIR/dev"
mount -t proc proc "$CHROOT_DIR/proc"
mount -t sysfs sysfs "$CHROOT_DIR/sys"
mount -t devpts devpts "$CHROOT_DIR/dev/pts"

# Prevent daemons from starting
cat > "$CHROOT_DIR/usr/sbin/policy-rc.d" << 'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "$CHROOT_DIR/usr/sbin/policy-rc.d"

# ============================================================
# Step 3: Install packages
# ============================================================
echo "[3/8] Installing packages (this may take a while)..."

chroot "$CHROOT_DIR" apt-get update
chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    linux-image-amd64 \
    live-boot \
    systemd-sysv \
    initramfs-tools \
    xserver-xorg \
    xserver-xorg-video-vesa \
    xserver-xorg-video-fbdev \
    xserver-xorg-input-libinput \
    xinit \
    openbox \
    python3 \
    python3-gi \
    gir1.2-gtk-3.0 \
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
    nano

# Set locale
chroot "$CHROOT_DIR" sh -c 'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen'
chroot "$CHROOT_DIR" update-locale LANG=en_US.UTF-8

# ============================================================
# Step 4: Create user and configure autologin
# ============================================================
echo "[4/8] Setting up user and autologin..."

chroot "$CHROOT_DIR" useradd -m -s /bin/bash -G sudo,netdev,audio,video,plugdev havok
echo "havok:havokos" | chroot "$CHROOT_DIR" chpasswd

# Configure LightDM autologin
cat > "$CHROOT_DIR/etc/lightdm/lightdm.conf" << 'LIGHTDM'
[SeatDefaults]
autologin-user=havok
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
user-session=openbox
LIGHTDM

# ============================================================
# Step 5: Copy HavokOS overlay files
# ============================================================
echo "[5/8] Installing HavokOS files..."

# Copy HSL interpreter
cp "$PROJECT_DIR/hsl/interpreter.py" "$CHROOT_DIR/usr/bin/hsl"
chmod +x "$CHROOT_DIR/usr/bin/hsl"

# Copy HSL stdlib
mkdir -p "$CHROOT_DIR/usr/share/havok/hsl"
cp -r "$PROJECT_DIR/hsl/stdlib/"* "$CHROOT_DIR/usr/share/havok/hsl/" 2>/dev/null || true

# Copy HavokOS applications
cp "$PROJECT_DIR/overlay/usr/bin/"* "$CHROOT_DIR/usr/bin/" 2>/dev/null || true
chmod +x "$CHROOT_DIR/usr/bin/havok-"* 2>/dev/null || true

# Copy desktop entries
cp "$PROJECT_DIR/overlay/usr/share/applications/"*.desktop "$CHROOT_DIR/usr/share/applications/" 2>/dev/null || true

# Copy icons and themes
mkdir -p "$CHROOT_DIR/usr/share/pixmaps"
cp "$PROJECT_DIR/overlay/usr/share/pixmaps/"* "$CHROOT_DIR/usr/share/pixmaps/" 2>/dev/null || true
mkdir -p "$CHROOT_DIR/usr/share/havok/themes"
cp -r "$PROJECT_DIR/overlay/usr/share/havok/themes/"* "$CHROOT_DIR/usr/share/havok/themes/" 2>/dev/null || true

# Copy X11 config
cp "$PROJECT_DIR/overlay/etc/X11/"* "$CHROOT_DIR/etc/X11/" 2>/dev/null || true

# Copy xdg autostart
cp "$PROJECT_DIR/overlay/etc/xdg/autostart/"*.desktop "$CHROOT_DIR/etc/xdg/autostart/" 2>/dev/null || true

# Set up skel with HavokCustom folder
mkdir -p "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/IMPORTANT"
cp "$PROJECT_DIR/overlay/home/havok/Desktop/HavokCustom/IMPORTANT/readme.txt" \
   "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/IMPORTANT/readme.txt" 2>/dev/null || true

# Copy IMPORTANT HSL files (desktop system files)
cp "$PROJECT_DIR/overlay/home/havok/Desktop/HavokCustom/IMPORTANT/"*.hsl \
   "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/IMPORTANT/" 2>/dev/null || true

# Copy the IMPORTANT files to the live user's home
cp -r "$CHROOT_DIR/etc/skel/Desktop/HavokCustom" "/home/havok/Desktop/HavokCustom" 2>/dev/null || true
mkdir -p "$CHROOT_DIR/home/havok/Desktop/HavokCustom/IMPORTANT"
cp -r "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/"* "$CHROOT_DIR/home/havok/Desktop/HavokCustom/" 2>/dev/null || true
chroot "$CHROOT_DIR" chown -R havok:havok /home/havok/Desktop

# ============================================================
# Step 6: Configure Openbox and startup
# ============================================================
echo "[6/8] Configuring desktop environment..."

# Openbox autostart
mkdir -p "$CHROOT_DIR/etc/xdg/openbox"
cat > "$CHROOT_DIR/etc/xdg/openbox/autostart" << 'AUTOSTART'
# HavokOS autostart
# Set wallpaper with a solid color via xsetroot
xsetroot -solid "#1a1a2e" &

# Launch HavokOS Desktop Shell
havok-desktop &

# Launch panel
havok-panel &

# Network manager applet
nm-applet &
AUTOSTART

# Openbox menu
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

# Openbox RC config (minimal theme)
mkdir -p "$CHROOT_DIR/etc/xdg/openbox"
cat > "$CHROOT_DIR/etc/xdg/openbox/rc.xml" << 'RCXML'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <unfocusOnLeave>no</unfocusOnLeave>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>no</animateIconify>
    <font place="ActiveWindow">
      <name>Sans</name>
      <size>11</size>
      <weight>bold</weight>
    </font>
    <font place="InactiveWindow">
      <name>Sans</name>
      <size>11</size>
    </font>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>0</firstdesk>
    <names><name>Desktop</name></names>
  </desktops>
  <resize>
    <drawContents>yes</drawContents>
    <popupShow>Nonpixel</popupShow>
    <popupPosition>Center</popupPosition>
  </resize>
  <margins>
    <top>32</top>
    <bottom>0</bottom>
    <left>0</left>
    <right>0</right>
  </margins>
</openbox_config>
RCXML

# .xinitrc for havok user
cat > "$CHROOT_DIR/home/havok/.xinitrc" << 'XINITRC'
#!/bin/bash
export GTK_THEME=Adwaita:dark
exec openbox-session
XINITRC
chmod +x "$CHROOT_DIR/home/havok/.xinitrc"
chroot "$CHROOT_DIR" chown havok:havok /home/havok/.xinitrc

# LightDM session entry for HavokOS
cat > "$CHROOT_DIR/usr/share/xsessions/havokos.desktop" << 'SESSION'
[Desktop Entry]
Name=HavokOS
Comment=HavokOS Desktop Environment
Exec=openbox-session
Type=Application
DesktopNames=HavokOS
SESSION

# ============================================================
# Step 7: Create kernel and initramfs
# ============================================================
echo "[7/8] Building initramfs..."

# Configure initramfs for live boot
cat > "$CHROOT_DIR/etc/initramfs-tools/conf.d/havokos.conf" << 'INITRAMFS'
MODULES=most
COMPRESS=xz
INITRAMFS_COMPRESS_OPTIONS="-9 -T4"
INITRAMFS

# Add live boot modules
cat >> "$CHROOT_DIR/etc/initramfs-tools/modules" << 'MODULES'
vfat
nls_cp437
nls_iso8859_1
isofs
squashfs
loop
MODULES

chroot "$CHROOT_DIR" update-initramfs -c -k all

# Copy kernel and initramfs out of chroot
KERN_VER=$(ls "$CHROOT_DIR/boot/vmlinuz-"* | sort -V | tail -1 | xargs basename)
INITRD=$(ls "$CHROOT_DIR/boot/initrd.img-"* | sort -V | tail -1 | xargs basename)

# ============================================================
# Step 8: Build the ISO
# ============================================================
echo "[8/8] Creating ISO image..."

mkdir -p "$WORK_DIR/live" "$ISO_DIR"

# Create squashfs
echo "  Creating squashfs (compressing filesystem)..."
mksquashfs "$CHROOT_DIR" "$SQUASHFS" -e boot -e proc -e sys -e dev -e run -e tmp

# Copy live boot files
cp "$CHROOT_DIR/boot/$KERN_VER" "$WORK_DIR/live/vmlinuz"
cp "$CHROOT_DIR/boot/$INITRD" "$WORK_DIR/live/initrd.img"

# Setup ISO directory structure
mkdir -p "$ISO_DIR/boot/grub" "$ISO_DIR/boot/isolinux" "$ISO_DIR/live"

cp "$WORK_DIR/live/vmlinuz" "$ISO_DIR/live/vmlinuz"
cp "$WORK_DIR/live/initrd.img" "$ISO_DIR/live/initrd.img"
cp "$SQUASHFS" "$ISO_DIR/live/filesystem.squashfs"

# ISOLINUX (BIOS boot)
cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_DIR/boot/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "$ISO_DIR/boot/isolinux/"
cp /usr/lib/syslinux/modules/bios/libcom32.c32 "$ISO_DIR/boot/isolinux/"
cp /usr/lib/syslinux/modules/bios/libutil.c32 "$ISO_DIR/boot/isolinux/"

cat > "$ISO_DIR/boot/isolinux/isolinux.cfg" << 'ISOLINUX'
DEFAULT havokos
PROMPT 0
TIMEOUT 30

LABEL havokos
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live components splash quiet
    INITRD /live/initrd.img
ISOLINUX

# GRUB (EFI boot)
cat > "$ISO_DIR/boot/grub/grub.cfg" << 'GRUB'
set timeout=10
set default=0

menuentry "HavokOS" {
    linux /live/vmlinuz boot=live components splash quiet
    initrd /live/initrd.img
}
GRUB

# Create the ISO
echo "  Generating ISO (this may take a while)..."
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
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2_start_$(expr $(stat -c %s "$OUTPUT_DIR/HavokOS-1.0.0.iso") / 512 + 1)s:appended_part_2:0:' \
    -no-emul-boot \
    -partition_offset 16 \
    -V "HAVOKOS" \
    -J \
    -joliet-long \
    -r \
    -m "$OUTPUT_DIR" \
    .

# ============================================================
# Cleanup and summary
# ============================================================

# Unmount chroot
umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
umount "$CHROOT_DIR/sys" 2>/dev/null || true
umount "$CHROOT_DIR/proc" 2>/dev/null || true
umount "$CHROOT_DIR/dev" 2>/dev/null || true

ISO_SIZE=$(du -h "$OUTPUT_DIR/HavokOS-1.0.0.iso" | cut -f1)
echo ""
echo "========================================"
echo "  HavokOS ISO built successfully!     "
echo "  Output: $OUTPUT_DIR/HavokOS-1.0.0.iso"
echo "  Size:   $ISO_SIZE"
echo "========================================"
