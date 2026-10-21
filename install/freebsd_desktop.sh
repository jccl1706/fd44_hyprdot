#!/bin/sh
#
# freebsd_desktop.sh - KDE Plasma + SDDM on a booted FreeBSD, AMD/Intel   v0.1
#
# Runs ON the installed system (after install_freebsd.sh), as root:
#
#     sh freebsd_desktop.sh            # DRY RUN
#     sh freebsd_desktop.sh --go       # install + configure
#
# Stage two of the FreeBSD build, the desktop - the counterpart to Fedora's
# fedora_desktop.sh. Installs KDE Plasma 6 + SDDM, loads the right GPU KMS
# driver via drm-kmod, and enables dbus / seatd / sddm. See
# docs/freebsd-install-plan.md for why KDE (not niri/Hyprland) and why X11.
#
# ---------------------------------------------------------------------------
# WHAT THIS TARGETS, AND THE HONEST LIMITS
#
#   * GPU: AMD (amdgpu) and Intel (i915kms), auto-detected from pciconf, both
#     via graphics/drm-kmod. These are the FreeBSD-well-supported paths. NVIDIA
#     is NOT handled here (this line targets AMD/Intel, like the Framework).
#
#   * SESSION: X11, on purpose. The Plasma X11 session on FreeBSD is mature.
#     The Wayland session works in some setups but is version-sensitive and
#     unreliable (a Qt 6.11 bug blocked it in 2026) - add it only after it is
#     proven on the real target hardware. The plan says so at length.
#
#   * In a VM with no AMD/Intel GPU (QEMU VGA), there is no KMS driver. The
#     script falls back to the scfb X driver on the EFI framebuffer so a desktop
#     still comes up for testing the packaging and services. On real hardware
#     the detected KMS driver + Xorg's built-in modesetting driver are used and
#     scfb is not touched.
#
#   * seatd, not elogind: FreeBSD's seat/session manager. Plasma + SDDM reach
#     DRM/input through it, and the desktop user must be in the `video` group.
# ---------------------------------------------------------------------------

set -eu

# === CONFIG ================================================================
DESKTOP_USER="${DESKTOP_USER:-jc}"
# GPU_KLD: override detection. amdgpu | i915kms | radeonkms | scfb (= no KMS)
GPU_KLD="${GPU_KLD:-auto}"
# Extra apps worth having on a fresh desktop; trim to taste.
APPS="${APPS:-konsole dolphin}"

PKGS="drm-kmod xorg sddm plasma6-plasma seatd dbus doas"

GO=0; [ "${1:-}" = "--go" ] && GO=1
say() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
run() { printf '    %s\n' "$*"; [ "$GO" = 1 ] && eval "$*"; return 0; }
die() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root on the installed system"
[ -d /usr/local ] || die "no /usr/local - is this a booted FreeBSD (not the installer)?"

# === detect the GPU driver =================================================
# Match on the PCI VENDOR ID of the VGA controller, NOT the vendor name string.
# (A name match on "ATI" is a trap: "Intel CorporATIon" contains it, which made
# an earlier version pick amdgpu on an Intel ThinkPad.) The display-controller
# device line carries class=0x0300xx and vendor=0xNNNN; read the id off it.
#   0x1002 = AMD/ATI   0x8086 = Intel
detect_kld() {
    vline=$(pciconf -lv 2>/dev/null | grep -iE 'class=0x0300' | head -1)
    case "$vline" in
        *vendor=0x1002*) echo amdgpu  ;;
        *vendor=0x8086*) echo i915kms ;;
        *)               echo scfb    ;;   # QEMU VGA / VESA / unknown -> no KMS
    esac
}
[ "$GPU_KLD" = auto ] && GPU_KLD=$(detect_kld)

say "FreeBSD KDE desktop install"
echo "    desktop user : $DESKTOP_USER"
echo "    GPU driver   : $GPU_KLD $( [ "$GPU_KLD" = scfb ] && echo '(no KMS - framebuffer X, VM/VESA)' )"
echo "    mode         : $( [ "$GO" = 1 ] && echo GO || echo 'dry run (--go to apply)')"
id "$DESKTOP_USER" >/dev/null 2>&1 || die "user $DESKTOP_USER does not exist (create it first)"

# === Stage 1: packages =====================================================
say "Stage 1 - packages (Plasma 6, SDDM, Xorg, drm-kmod; ~1.5 GB)"
[ "$GPU_KLD" = scfb ] && PKGS="$PKGS xf86-video-scfb"
run "env ASSUME_ALWAYS_YES=yes pkg install -y $PKGS $APPS"

# === Stage 2: services + GPU in rc.conf ====================================
say "Stage 2 - enable services and the GPU driver"
run "sysrc dbus_enable=YES"
run "sysrc seatd_enable=YES"
run "sysrc sddm_enable=YES"
# XDG_DATA_DIRS: FreeBSD puts icons/mime/.desktop under /usr/local/share, and if
# this is unset KDE cannot find them - the symptom is a Plasma desktop with every
# icon blank, even though kf6-breeze-icons is installed and its cache is built.
# Set it for login shells; the SDDM session sources /etc/profile.
run "grep -q XDG_DATA_DIRS /etc/profile || printf '\\nXDG_DATA_DIRS=/usr/local/share:/usr/share\\nexport XDG_DATA_DIRS\\n' >> /etc/profile"
# procfs: various desktop tools expect /proc, which FreeBSD does not mount by
# default.
run "mount -t procfs proc /proc 2>/dev/null || true"
run "grep -q procfs /etc/fstab || printf 'proc\\t/proc\\tprocfs\\trw\\t0\\t0\\n' >> /etc/fstab"
if [ "$GPU_KLD" != scfb ]; then
    # drm-kmod wants the KMS module in kld_list (loaded after root mount),
    # NOT in loader.conf.
    run "sysrc kld_list+=$GPU_KLD"
fi
# the desktop user needs DRM/input access
run "pw groupmod video -m $DESKTOP_USER"
# create the user's standard folders (Desktop, Documents, ...) so Plasma's
# Folder View does not complain that ~/Desktop is missing on first login
run "su - $DESKTOP_USER -c 'XDG_DATA_DIRS=/usr/local/share:/usr/share xdg-user-dirs-update' 2>/dev/null || true"

# === Stage 3: X driver for the no-KMS (VM) case ============================
if [ "$GPU_KLD" = scfb ]; then
    say "Stage 3 - scfb Xorg driver + software greeter (framebuffer, VM/VESA only)"
    run "mkdir -p /usr/local/etc/X11/xorg.conf.d"
    run "cat > /usr/local/etc/X11/xorg.conf.d/driver-scfb.conf <<CONF
Section \"Device\"
    Identifier \"scfb\"
    Driver     \"scfb\"
EndSection
CONF"
    # Without KMS there is no GL, and SDDM's Qt6 Breeze greeter renders only its
    # wallpaper (the login form stays invisible) unless Qt is forced to software
    # rendering. Verified in the VM: with this, the full greeter appears; without
    # it, only the background. On real AMD/Intel (KMS/GL) this is unnecessary.
    run "mkdir -p /usr/local/etc/sddm.conf.d"
    run "cat > /usr/local/etc/sddm.conf.d/software-render.conf <<CONF
[General]
GreeterEnvironment=QT_QUICK_BACKEND=software,QT_XCB_FORCE_SOFTWARE_OPENGL=1
CONF"
fi

# === Stage 4: bring it up ==================================================
say "Stage 4 - start it"
if [ "$GPU_KLD" != scfb ]; then
    run "kldload $GPU_KLD || true"      # load now so this boot has it too
fi
run "service dbus start || true"
run "service seatd start || true"
run "service sddm start || true"

cat <<DONE

$( [ "$GO" = 1 ] && echo 'Done.' || echo 'Dry run - nothing changed.' )

  SDDM should now (or after a reboot) present a graphical login. Pick the
  "Plasma (X11)" session. The desktop user is $DESKTOP_USER; it was added to the
  video group - a FRESH LOGIN is needed for that to take.

  If the greeter does not appear:
    - check  service sddm status  and  /var/log/sddm.log
    - on real AMD/Intel, confirm the KMS driver loaded:  kldstat | grep $GPU_KLD
    - dmesg should show the drm device attach

  NOT here yet: the Plasma Wayland session (X11 only for now), and any fd44
  theming of Plasma. See docs/freebsd-install-plan.md.
DONE
