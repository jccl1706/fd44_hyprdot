#!/bin/sh
#
# freebsd_desktop.sh - a desktop on a booted FreeBSD, AMD/Intel        v0.2
#
# Runs ON the installed system (after install_freebsd.sh), as root:
#
#     sh freebsd_desktop.sh                    # DRY RUN  (Plasma)
#     sh freebsd_desktop.sh --go               # install + configure Plasma
#     DESKTOP=sway sh freebsd_desktop.sh --go  # install + configure sway
#
# Stage two of the FreeBSD build, the desktop - the counterpart to Fedora's
# fedora_desktop.sh. Loads the right GPU KMS driver via drm-kmod, enables
# dbus / seatd, and sets up ONE of two desktops:
#
#     DESKTOP=plasma   KDE Plasma 6 + SDDM, X11 session   (default; VALIDATED
#                      on the T480 - Intel i5-8250U / UHD 620)
#     DESKTOP=sway     sway (Wayland, wlroots) + waybar + foot + wofi
#                      (EXPERIMENTAL - packaged and configured here but NOT yet
#                      proven on real hardware; closest thing to the fd44 niri
#                      tiling feel that FreeBSD actually supports)
#
# See docs/freebsd-install-plan.md for the why.
#
# ---------------------------------------------------------------------------
# WHAT THIS TARGETS, AND THE HONEST LIMITS
#
#   * GPU: AMD (amdgpu) and Intel (i915kms), auto-detected from the PCI vendor
#     id. The DRM package is chosen to match:
#       - Intel  -> graphics/drm-kmod   (the generic meta; proven on the T480)
#       - AMD    -> graphics/drm-612-kmod + gpu-firmware-kmod
#         RDNA3 (Framework's Radeon 760M/780M, Phoenix) needs a RECENT DRM -
#         mesa 26.1+ wants DRM 6.6+, so the generic drm-kmod can be too old.
#         drm-612-kmod (6.12) is the current best for RDNA3 on 15.x; swap to
#         drm-66-kmod if 6.12 misbehaves. gpu-firmware-kmod must be recent
#         (20260519+). This is the community-documented RDNA3 recipe.
#     NVIDIA is NOT handled here (this line targets AMD/Intel, like the
#     Framework and the T480).
#
#   * AMD / Framework BIOS: enable ReBAR / Smart Access Memory, and DISABLE
#     Secure Boot - FreeBSD will not boot with Secure Boot on. (The amdgpu
#     RDNA3 path also wants ReBAR.) These are firmware settings this script
#     cannot make; set them by hand before trusting AMD graphics.
#
#   * SESSION: Plasma runs X11 on purpose (the FreeBSD Plasma Wayland session
#     is version-sensitive and was blocked by a Qt 6.11 bug in 2026). sway is
#     Wayland by nature (wlroots) - no X11/xorg.conf, and wlroots does its own
#     vsync so no TearFree is needed there.
#
#   * VM (QEMU VGA, no KMS): Plasma falls back to the scfb framebuffer X driver
#     so the packaging/services can be tested. sway CANNOT use scfb - wlroots
#     needs a real DRM device - so sway is a real-hardware-only path.
#
#   * seatd, not elogind: FreeBSD's seat/session manager. The desktop reaches
#     DRM/input through it, and the desktop user must be in the `video` group.
# ---------------------------------------------------------------------------

set -eu

# === CONFIG ================================================================
DESKTOP_USER="${DESKTOP_USER:-jc}"
# DESKTOP: plasma (default, validated) | sway (experimental)
DESKTOP="${DESKTOP:-plasma}"
# GPU_KLD: override detection. amdgpu | i915kms | radeonkms | scfb (= no KMS)
GPU_KLD="${GPU_KLD:-auto}"
# Extra apps worth having; trim to taste. (Plasma defaults; sway brings foot.)
APPS="${APPS:-konsole dolphin}"

GO=0; [ "${1:-}" = "--go" ] && GO=1
say() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
run() { printf '    %s\n' "$*"; [ "$GO" = 1 ] && eval "$*"; return 0; }
die() { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root on the installed system"
[ -d /usr/local ] || die "no /usr/local - is this a booted FreeBSD (not the installer)?"
case "$DESKTOP" in plasma|sway) ;; *) die "DESKTOP must be plasma or sway (got '$DESKTOP')" ;; esac

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

# DRM package to match the GPU (see the header note on RDNA3).
case "$GPU_KLD" in
    amdgpu)  DRM_PKGS="drm-612-kmod gpu-firmware-kmod" ;;  # RDNA3 needs 6.12
    i915kms) DRM_PKGS="drm-kmod" ;;                         # Intel: generic, proven
    *)       DRM_PKGS="drm-kmod" ;;                         # scfb/VM: harmless
esac

say "FreeBSD desktop install - $DESKTOP"
echo "    desktop user : $DESKTOP_USER"
echo "    GPU driver   : $GPU_KLD $( [ "$GPU_KLD" = scfb ] && echo '(no KMS - framebuffer, VM/VESA)' )"
echo "    DRM package  : $DRM_PKGS"
echo "    mode         : $( [ "$GO" = 1 ] && echo GO || echo 'dry run (--go to apply)')"
id "$DESKTOP_USER" >/dev/null 2>&1 || die "user $DESKTOP_USER does not exist (create it first)"
[ "$DESKTOP" = sway ] && [ "$GPU_KLD" = scfb ] && \
    die "sway needs a real DRM/KMS GPU (wlroots has no scfb path) - not a pure-VGA VM"

# === Stage 1: packages =====================================================
if [ "$DESKTOP" = plasma ]; then
    PKGS="$DRM_PKGS xorg sddm plasma6-plasma seatd dbus doas"
    [ "$GPU_KLD" = scfb ] && PKGS="$PKGS xf86-video-scfb"
    PKGS="$PKGS $APPS"
    say "Stage 1 - packages (Plasma 6, SDDM, Xorg, $DRM_PKGS; ~1.5 GB)"
else
    # sway + a minimal, usable wlroots stack. foot=terminal, wofi=launcher,
    # waybar=bar, swaylock/swayidle=lock/idle, wmenu=dmenu-for-wayland.
    PKGS="$DRM_PKGS sway foot waybar wofi swaylock swayidle wmenu seatd dbus doas"
    say "Stage 1 - packages (sway + waybar/foot/wofi, $DRM_PKGS; ~0.7 GB)"
fi
run "env ASSUME_ALWAYS_YES=yes pkg install -y $PKGS"

# === Stage 2: services + GPU (common to both desktops) =====================
say "Stage 2 - services and the GPU driver"
run "sysrc dbus_enable=YES"
run "sysrc seatd_enable=YES"
# the desktop user needs DRM/input access through seatd
run "pw groupmod video -m $DESKTOP_USER"
if [ "$GPU_KLD" != scfb ]; then
    # drm-kmod wants the KMS module in kld_list (loaded after root mount),
    # NOT in loader.conf.
    run "sysrc kld_list+=$GPU_KLD"
fi
# procfs: various desktop tools expect /proc, which FreeBSD does not mount by
# default.
run "mount -t procfs proc /proc 2>/dev/null || true"
run "grep -q procfs /etc/fstab || printf 'proc\\t/proc\\tprocfs\\trw\\t0\\t0\\n' >> /etc/fstab"

if [ "$DESKTOP" = plasma ]; then
    # --- Plasma / SDDM / X11 ------------------------------------------------
    run "sysrc sddm_enable=YES"
    # XDG_DATA_DIRS: FreeBSD puts icons/mime/.desktop under /usr/local/share, and
    # if this is unset KDE cannot find them - the symptom is a Plasma desktop with
    # every icon blank, even though kf6-breeze-icons is installed. The SDDM session
    # sources /etc/profile.
    run "grep -q XDG_DATA_DIRS /etc/profile || printf '\\nXDG_DATA_DIRS=/usr/local/share:/usr/share\\nexport XDG_DATA_DIRS\\n' >> /etc/profile"
    if [ "$GPU_KLD" != scfb ]; then
        # TearFree stops screen tearing on the modesetting driver (Intel and AMD).
        # Without it the X11 desktop tears even though GL is fully accelerated -
        # verified on the T480's i915. DRI 3 is the modern path. (Wayland/sway does
        # not need this - wlroots vsyncs itself.)
        run "mkdir -p /usr/local/etc/X11/xorg.conf.d"
        run "cat > /usr/local/etc/X11/xorg.conf.d/20-tearfree.conf <<CONF
Section \"Device\"
    Identifier \"GPU\"
    Driver     \"modesetting\"
    Option     \"TearFree\" \"true\"
    Option     \"DRI\"      \"3\"
EndSection
CONF"
    fi
    # standard XDG folders (Desktop, Documents, ...) so Plasma's Folder View does
    # not complain ~/Desktop is missing on first login
    run "su - $DESKTOP_USER -c 'XDG_DATA_DIRS=/usr/local/share:/usr/share xdg-user-dirs-update' 2>/dev/null || true"
    # scfb (VM) only: no GL, so force SDDM's Qt6 greeter to software rendering or
    # it renders only its wallpaper (login form invisible). Unnecessary on KMS/GL.
    if [ "$GPU_KLD" = scfb ]; then
        run "mkdir -p /usr/local/etc/X11/xorg.conf.d /usr/local/etc/sddm.conf.d"
        run "cat > /usr/local/etc/X11/xorg.conf.d/driver-scfb.conf <<CONF
Section \"Device\"
    Identifier \"scfb\"
    Driver     \"scfb\"
EndSection
CONF"
        run "cat > /usr/local/etc/sddm.conf.d/software-render.conf <<CONF
[General]
GreeterEnvironment=QT_QUICK_BACKEND=software,QT_XCB_FORCE_SOFTWARE_OPENGL=1
CONF"
    fi
else
    # --- sway / Wayland -----------------------------------------------------
    # XDG_RUNTIME_DIR: Wayland requires it, and FreeBSD has no systemd/elogind to
    # create it. pam_xdg (FreeBSD 14.1+) makes /var/run/user/<uid> at login - the
    # clean way. It is `optional`, so if the module is absent login still works.
    run "grep -q pam_xdg /etc/pam.d/system || printf 'session\\toptional\\tpam_xdg.so\\n' >> /etc/pam.d/system"
    # a minimal sway config for the user: start from the packaged default, point
    # the bar at waybar and the terminal at foot.
    run "su - $DESKTOP_USER -c 'mkdir -p ~/.config/sway ~/.config/waybar'"
    run "su - $DESKTOP_USER -c '[ -f ~/.config/sway/config ] || cp /usr/local/etc/sway/config ~/.config/sway/config'"
    run "su - $DESKTOP_USER -c \"sed -i '' -e 's|^set .term.*|set \\\$term foot|' ~/.config/sway/config 2>/dev/null || true\""
    # launch sway from the first tty on login (no display manager). Appended to
    # the user's ~/.profile; /bin/sh reads it. ttyv0 is FreeBSD's first VT.
    run "su - $DESKTOP_USER -c 'grep -q \"exec dbus-run-session sway\" ~/.profile 2>/dev/null || cat >> ~/.profile <<PROF

# start sway on the first virtual terminal (FreeBSD has no display manager here)
if [ -z \"\\\${WAYLAND_DISPLAY:-}\" ] && [ \"\\\$(tty)\" = \"/dev/ttyv0\" ]; then
    exec dbus-run-session sway
fi
PROF'"
fi

# === Stage 3: bring it up ==================================================
say "Stage 3 - start it"
if [ "$GPU_KLD" != scfb ]; then
    run "kldload $GPU_KLD || true"      # load now so this boot has it too
fi
run "service dbus start || true"
run "service seatd start || true"
if [ "$DESKTOP" = plasma ]; then
    run "service sddm start || true"
fi

# === done ==================================================================
if [ "$DESKTOP" = plasma ]; then
cat <<DONE

$( [ "$GO" = 1 ] && echo 'Done.' || echo 'Dry run - nothing changed.' )

  SDDM should now (or after a reboot) present a graphical login. Pick the
  "Plasma (X11)" session. The desktop user is $DESKTOP_USER; it was added to the
  video group - a FRESH LOGIN is needed for that to take.

  If the greeter does not appear:
    - check  service sddm status  and  /var/log/sddm.log
    - on real AMD/Intel, confirm the KMS driver loaded:  kldstat | grep $GPU_KLD
    - AMD RDNA3: confirm amdgpu attached in dmesg; if not, check ReBAR is on and
      Secure Boot off in BIOS, and try drm-66-kmod instead of drm-612-kmod
    - dmesg should show the drm device attach

  NOT here yet: the Plasma Wayland session (X11 only for now), and any fd44
  theming. See docs/freebsd-install-plan.md.
DONE
else
cat <<DONE

$( [ "$GO" = 1 ] && echo 'Done.' || echo 'Dry run - nothing changed.' )

  sway is EXPERIMENTAL here - packaged and configured, but not yet proven on
  real hardware. There is NO display manager: log in on the first text console
  (ttyv0) as $DESKTOP_USER and sway starts automatically (via ~/.profile).

  A FRESH LOGIN is needed for the video-group membership to take. If sway does
  not start or exits immediately:
    - confirm the KMS driver loaded:  kldstat | grep $GPU_KLD
    - AMD RDNA3: confirm amdgpu attached in dmesg; if not, check ReBAR on /
      Secure Boot off, and try drm-66-kmod instead of drm-612-kmod
    - check XDG_RUNTIME_DIR is set after login (pam_xdg):  echo \$XDG_RUNTIME_DIR
    - run  dbus-run-session sway  by hand to see its startup log
    - seatd must be running:  service seatd status

  Config lives in ~/.config/sway/config (started from the packaged default).
  See docs/freebsd-install-plan.md.
DONE
fi
