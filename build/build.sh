#!/bin/bash
# HavokOS ISO Builder v2.2
# Fixed: v2.0 initramfs (gzip), v2.1 sysvinit-core, v2.2 initscripts+sysv-rc (init crash fix)

set -ex

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/output"
WORK_DIR="/tmp/havokos-build"
CHROOT_DIR="$WORK_DIR/chroot"
ISO_DIR="$WORK_DIR/iso"

echo "========================================"
echo "       HavokOS ISO Builder v2.2        "
echo "========================================"

rm -rf "$WORK_DIR" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Step 1: Create minimal Debian chroot
echo "[1/9] Creating Debian chroot..."
mkdir -p "$CHROOT_DIR"
debootstrap --variant=minbase --arch=amd64 bookworm "$CHROOT_DIR" http://deb.debian.org/debian

# Step 2: Configure the chroot
echo "[2/9] Configuring system..."
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

cat > "$CHROOT_DIR/usr/sbin/policy-rc.d" << 'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "$CHROOT_DIR/usr/sbin/policy-rc.d"

# Step 3: Install packages
echo "[3/9] Installing packages..."
chroot "$CHROOT_DIR" apt-get update
chroot "$CHROOT_DIR" apt-get install -y --no-install-recommends \
    linux-image-amd64 \
    live-boot \
    live-boot-initramfs-tools \
    sysvinit-core \
    sysvinit-utils \
    initscripts \
    sysv-rc \
    bootlogd \
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
    nano \
    kbd \
    console-setup

chroot "$CHROOT_DIR" sh -c 'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen'
chroot "$CHROOT_DIR" update-locale LANG=en_US.UTF-8

# Step 4: Create user and configure autologin
echo "[4/9] Setting up user..."
chroot "$CHROOT_DIR" useradd -m -s /bin/bash -G sudo,netdev,audio,video,plugdev havok
echo "havok:havokos" | chroot "$CHROOT_DIR" chpasswd

cat > "$CHROOT_DIR/etc/lightdm/lightdm.conf" << 'LIGHTDM'
[SeatDefaults]
autologin-user=havok
autologin-user-timeout=0
user-session=openbox
LIGHTDM

# Step 5: Copy HavokOS overlay
echo "[5/9] Installing HavokOS files..."
cp "$PROJECT_DIR/hsl/interpreter.py" "$CHROOT_DIR/usr/bin/hsl"
chmod +x "$CHROOT_DIR/usr/bin/hsl"
mkdir -p "$CHROOT_DIR/usr/share/havok/hsl"
cp -r "$PROJECT_DIR/hsl/stdlib/"* "$CHROOT_DIR/usr/share/havok/hsl/" 2>/dev/null || true
cp "$PROJECT_DIR/overlay/usr/bin/"* "$CHROOT_DIR/usr/bin/" 2>/dev/null || true
chmod +x "$CHROOT_DIR/usr/bin/havok-"* 2>/dev/null || true
mkdir -p "$CHROOT_DIR/usr/share/applications"
cp "$PROJECT_DIR/overlay/usr/share/applications/"*.desktop "$CHROOT_DIR/usr/share/applications/" 2>/dev/null || true
cp -r "$PROJECT_DIR/overlay/etc/X11/"* "$CHROOT_DIR/etc/X11/" 2>/dev/null || true
mkdir -p "$CHROOT_DIR/etc/xdg/autostart"
cp "$PROJECT_DIR/overlay/etc/xdg/autostart/"*.desktop "$CHROOT_DIR/etc/xdg/autostart/" 2>/dev/null || true

mkdir -p "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/IMPORTANT"
cp "$PROJECT_DIR/overlay/home/havok/Desktop/HavokCustom/IMPORTANT/readme.txt" "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/IMPORTANT/readme.txt" 2>/dev/null || true
cp "$PROJECT_DIR/overlay/home/havok/Desktop/HavokCustom/IMPORTANT/"*.hsl "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/IMPORTANT/" 2>/dev/null || true
mkdir -p "$CHROOT_DIR/home/havok/Desktop/HavokCustom/IMPORTANT"
cp -r "$CHROOT_DIR/etc/skel/Desktop/HavokCustom/"* "$CHROOT_DIR/home/havok/Desktop/HavokCustom/" 2>/dev/null || true
chroot "$CHROOT_DIR" chown -R havok:havok /home/havok/Desktop

# Step 6: Configure sysvinit and desktop
echo "[6/9] Configuring sysvinit and desktop..."

# Ensure initscripts are present — these provide /etc/init.d/rc and /etc/init.d/rcS
if [ ! -x "$CHROOT_DIR/etc/init.d/rc" ]; then
    echo "ERROR: /etc/init.d/rc not found! initscripts package may not have installed correctly."
    exit 1
fi
if [ ! -x "$CHROOT_DIR/etc/init.d/rcS" ]; then
    echo "ERROR: /etc/init.d/rcS not found! initscripts package may not have installed correctly."
    exit 1
fi
echo "  Verified: /etc/init.d/rc and rcS present"

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

mkdir -p "$CHROOT_DIR/run" "$CHROOT_DIR/var/run" "$CHROOT_DIR/var/lock"

cat > "$CHROOT_DIR/etc/fstab" << 'FSTAB'
proc    /proc   proc    defaults    0 0
sysfs   /sys    sysfs   defaults    0 0
devpts  /dev/pts devpts  defaults    0 0
tmpfs   /tmp    tmpfs   defaults    0 0
tmpfs   /run    tmpfs   defaults    0 0
FSTAB

cat > "$CHROOT_DIR/etc/network/interfaces" << 'INTERFACES'
auto lo
iface lo inet loopback
allow-hotplug eth0
iface eth0 inet dhcp
INTERFACES

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

cat > "$CHROOT_DIR/home/havok/.xinitrc" << 'XINITRC'
#!/bin/bash
export GTK_THEME=Adwaita:dark
exec openbox-session
XINITRC
chmod +x "$CHROOT_DIR/home/havok/.xinitrc"
chroot "$CHROOT_DIR" chown havok:havok /home/havok/.xinitrc

cat > "$CHROOT_DIR/usr/share/xsessions/havokos.desktop" << 'SESSION'
[Desktop Entry]
Name=HavokOS
Comment=HavokOS Desktop Environment
Exec=openbox-session
Type=Application
DesktopNames=HavokOS
SESSION

cat > "$CHROOT_DIR/etc/rc.local" << 'RCLOCAL'
#!/bin/sh
echo "HavokOS rc.local: Starting services..."
if [ -x /etc/init.d/dbus ]; then
    /etc/init.d/dbus start 2>/dev/null || true
fi
if [ -x /etc/init.d/network-manager ]; then
    /etc/init.d/network-manager start 2>/dev/null || true
fi
if [ -x /etc/init.d/lightdm ]; then
    /etc/init.d/lightdm start 2>/dev/null || true
fi
exit 0
RCLOCAL
chmod +x "$CHROOT_DIR/etc/rc.local"
ln -sf /etc/rc.local "$CHROOT_DIR/etc/rc2.d/S99rc.local" 2>/dev/null || true

chroot "$CHROOT_DIR" update-rc.d lightdm defaults 2>/dev/null || true
chroot "$CHROOT_DIR" update-rc.d dbus defaults 2>/dev/null || true
chroot "$CHROOT_DIR" update-rc.d network-manager defaults 2>/dev/null || true

# Step 7: Build initramfs
echo "[7/9] Building initramfs for live boot..."

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

echo "  Verifying initramfs..."
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

# Step 8: Build ISO filesystem
echo "[8/9] Creating ISO filesystem..."

umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
umount "$CHROOT_DIR/sys" 2>/dev/null || true
umount "$CHROOT_DIR/proc" 2>/dev/null || true
umount "$CHROOT_DIR/dev" 2>/dev/null || true

mkdir -p "$CHROOT_DIR/proc" "$CHROOT_DIR/sys" "$CHROOT_DIR/dev" "$CHROOT_DIR/run" "$CHROOT_DIR/tmp"

mkdir -p "$ISO_DIR/live" "$ISO_DIR/boot/isolinux"

echo "  Creating squashfs..."
mksquashfs "$CHROOT_DIR" "$ISO_DIR/live/filesystem.squashfs" -e boot -e proc -e sys -e dev -e run -e tmp -noappend

cp "$CHROOT_DIR/boot/vmlinuz-$KERN_VER" "$ISO_DIR/live/vmlinuz"
cp "$INITRD_PATH" "$ISO_DIR/live/initrd.img"

echo "  Files on ISO:"
ls -lh "$ISO_DIR/live/"

# Step 9: Bootloader and ISO creation
echo "[9/9] Creating bootable ISO..."

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
