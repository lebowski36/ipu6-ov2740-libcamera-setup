#!/usr/bin/env bash
# Intel IPU6 + OV2740 — libcamera / PipeWire helper for Arch-based systems (pacman).
#
# Expectation:
# - On recent kernels, the open stack often works: kernel + firmware + libcamera +
#   pipewire-libcamera. Many laptops with OV2740 (e.g. some ThinkPads) benefit from
#   community IPA tuning in ov2740.yaml.
# - If apps require classic V4L2 (/dev/video*) only, an optional AUR path exists
#   (DKMS, relay) — heavy, use only when needed.
#
# Usage:
#   bash setup-intel-ipu6-camera.sh              # interactive wizard (TTY only)
#   bash setup-intel-ipu6-camera.sh help           # list non-interactive commands
#   sudo bash setup-intel-ipu6-camera.sh libcamera
#   bash setup-intel-ipu6-camera.sh libcamera-user
#   bash setup-intel-ipu6-camera.sh wireplumber-ipu6
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-lowlila-v2
#   bash setup-intel-ipu6-camera.sh status
#
# References:
#   https://bbs.archlinux.org/viewtopic.php?id=297262
#   https://jgrulich.cz/

set -euo pipefail

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

die() { echo "Error: $*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

need_pacman() {
  have_cmd pacman || die "This script targets Arch-based distributions (pacman not found)."
}

aur_install() {
  if [[ "$(id -u)" -eq 0 ]]; then
    local u="${SUDO_USER:-}"
    [[ -n "$u" && "$u" != root ]] || die "AUR: run as: sudo $0 aur (from your normal user account, not a root login)."
    if have_cmd paru; then runuser -u "$u" -- paru -S --needed --noconfirm "$@"; return; fi
    if have_cmd yay; then runuser -u "$u" -- yay -S --needed --noconfirm "$@"; return; fi
    die "No paru/yay found. Install paru as user $u, then run: sudo $0 aur"
  fi
  if have_cmd paru; then paru -S --needed --noconfirm "$@"; return; fi
  if have_cmd yay; then yay -S --needed --noconfirm "$@"; return; fi
  die "No paru/yay found: https://github.com/Morganamilo/paru"
}

kernel_headers_pkg() {
  if pacman -Q linux-cachyos &>/dev/null; then
    echo linux-cachyos-headers
    return
  fi
  if pacman -Q linux-cachyos-lts &>/dev/null; then
    echo linux-cachyos-lts-headers
    return
  fi
  for meta in linux linux-zen linux-hardened linux-lts; do
    if pacman -Q "$meta" &>/dev/null; then
      echo "${meta}-headers"
      return
    fi
  done
  die "Could not detect an installed kernel meta-package (linux, linux-zen, linux-cachyos, …). Install matching *-headers manually."
}

cmd_help() {
  cat <<'EOF'
Intel IPU6 + OV2740 — libcamera / PipeWire (Arch-based, pacman)

Interactive:
  bash setup-intel-ipu6-camera.sh
 Starts the menu wizard on a terminal (TTY). In non-interactive contexts, prints this help.

Non-interactive commands:
  help, -h, --help          Show this text
  status, diag             Diagnostics (kernel, PCI, dmesg, packages)
  libcamera                Install repo packages (requires root)
  libcamera-user           Restart user PipeWire session (no root)
  wireplumber-ipu6         Write WirePlumber snippet for libcamera path (no root)
  camera-persist           User systemd oneshot: restart stack after login (no root)
  backup-ov2740            Copy /usr/share/.../ov2740.yaml to ~/ov2740-ipa-backup.yaml
  aur                      Optional AUR relay stack — DKMS, long build (requires root)

OV2740 IPA profiles (writes /usr/share/libcamera/ipa/simple/ov2740.yaml; requires root):
  ov2740-ipa | ov2740 | ov2740-yaml
  ov2740-ipa-lowlila | ov2740-lowlila | ov2740-ipa-plus
  ov2740-ipa-lowlila-v2 | ov2740-lowlila-v2   (common recommendation)
  ov2740-ipa-daylight | ov2740-daylight
  ov2740-ipa-daylight-vivid | ov2740-daylight-vivid | daylight-vivid
  ov2740-ipa-daylight-cool | ov2740-daylight-cool | daylight-cool
  ov2740-ipa-frnkq | ov2740-frnkq
  ov2740-ipa-frnkq-agc | ov2740-frnkq-agc
  ov2740-ipa-frnkq-agc-neutral | ov2740-frnkq-neutral | ov2740-neutral

After changing IPA: restart qcam; optionally run: bash setup-intel-ipu6-camera.sh libcamera-user
Firefox (Wayland): about:config → media.webrtc.camera.allow-pipewire = true
EOF
}

prompt_yn() {
  # $1 default y|n, $2 prompt text
  local def="$1"
  local text="$2"
  local hint
  [[ "$def" == y ]] && hint="[Y/n]" || hint="[y/N]"
  local r
  read -r -p "$text $hint " r || true
  r=${r,,}
  r=${r:0:1}
  if [[ -z "$r" ]]; then
    [[ "$def" == y ]] && return 0 || return 1
  fi
  [[ "$r" == y ]]
}

read_one_letter() {
  local r
  read -r -p "$1 " r || true
  printf '%s' "${r,,}"
}

interactive_wizard() {
  need_pacman
  if [[ "$(id -u)" -eq 0 ]]; then
    die "Run the wizard as your normal user (not root). It will invoke sudo when needed."
  fi

  cat <<'EOF'

================================================================================
 Intel IPU6 + OV2740 — libcamera / PipeWire setup wizard
  Target: Arch-based systems (pacman). Other distros are not automated here.
================================================================================

EOF

  if prompt_yn y "Run diagnostics now (kernel, PCI, packages)?"; then
    echo
    cmd_status
    echo
  fi

  if prompt_yn y "Install official repo packages (libcamera, pipewire-libcamera, …)?"; then
    sudo "$SCRIPT_PATH" libcamera || die "Package install failed."
    echo
  fi

  if prompt_yn y "Restart your user PipeWire / WirePlumber session now?"; then
    "$SCRIPT_PATH" libcamera-user
    echo
  fi

  if prompt_yn y "Install WirePlumber snippet (disable V4L2 monitor, enable libcamera path)?"; then
    "$SCRIPT_PATH" wireplumber-ipu6
    echo
  fi

  cat <<'EOF'
OV2740 IPA profile (writes system ov2740.yaml; affects image color/exposure).
  s — Skip (keep current system file)
  a — platelminto CCM, no AGC (less flicker; can clip harshly in bright scenes)
  b — platelminto + strict AGC / highlight limit
  c — Like (b), softer CCM (often less magenta on clipped highlights) [recommended default]
  d — No CCM (washed; can reduce pink in sunlight)
  e — No AGC + mild color lift
  f — Cool-tint heuristic CCM, no AGC
  g — frnkq CCM, no AGC (can be dark after cold start without AGC)
  h — frnkq + AGC
  i — frnkq/platelminto blend + AGC

EOF
  local p  p=$(read_one_letter "Enter letter [s/a/b/c/d/e/f/g/h/i], then Enter: ")
  p=${p:0:1}
  case "$p" in
    s|'') echo "Skipping IPA write." ;;
    a) sudo "$SCRIPT_PATH" ov2740-ipa ;;
    b) sudo "$SCRIPT_PATH" ov2740-ipa-lowlila ;;
    c) sudo "$SCRIPT_PATH" ov2740-ipa-lowlila-v2 ;;
    d) sudo "$SCRIPT_PATH" ov2740-ipa-daylight ;;
    e) sudo "$SCRIPT_PATH" ov2740-ipa-daylight-vivid ;;
    f) sudo "$SCRIPT_PATH" ov2740-ipa-daylight-cool ;;
    g) sudo "$SCRIPT_PATH" ov2740-ipa-frnkq ;;
    h) sudo "$SCRIPT_PATH" ov2740-ipa-frnkq-agc ;;
    i) sudo "$SCRIPT_PATH" ov2740-ipa-frnkq-agc-neutral ;;
    *) echo "Unknown choice; skipping IPA write." ;;
  esac
  echo

  if prompt_yn n "Enable optional login workaround (user systemd restarts PipeWire ~5s after login)?"; then
    "$SCRIPT_PATH" camera-persist
    echo
  fi

  if prompt_yn n "Backup current ov2740.yaml to ~/ov2740-ipa-backup.yaml?"; then
    "$SCRIPT_PATH" backup-ov2740
    echo
  fi

  cat <<'EOF'
Optional AUR path: DKMS modules, Intel camera binaries, v4l2loopback, v4l2-relayd.
Only choose this if you need a legacy /dev/video-style device or libcamera is not enough.
Long build time; proprietary components; not required for most PipeWire/libcamera setups.

EOF
  if prompt_yn n "Install the AUR relay stack now?"; then
    sudo "$SCRIPT_PATH" aur
  else
    echo "Skipped AUR stack."
  fi

  cat <<'EOF'

Done. Suggested checks:
  qcam
  wpctl status # look for camera / ov2740
  bash setup-intel-ipu6-camera.sh status

EOF
}

cmd_status() {
  echo "=== Kernel ==="
  uname -r
  echo
  echo "=== PCI (IPU / imaging) ==="
  if have_cmd lspci; then
    lspci -nn 2>/dev/null | grep -Ei 'ipu|imaging|visual|mipi' || lspci -nn 2>/dev/null | grep -Ei '8086:.*(0480|462e|a75d|7d19)' || true
  else
    echo "(lspci not found)"
  fi
  echo
  echo "=== Video devices ==="
  ls -la /dev/video* 2>/dev/null || echo "(no /dev/video*)"
  echo
  echo "=== dmesg (filtered, last lines) ==="
  if have_cmd dmesg; then
    dmesg 2>/dev/null | grep -Ei 'ipu6|ipu |ovti|ov[0-9]|mipi|int3472|libcamera' | tail -n 30 || true
  else
    echo "(dmesg not available)"
  fi
  echo
  echo "=== Packages (libcamera) ==="
  pacman -Q libcamera libcamera-ipa pipewire-libcamera 2>/dev/null || true
  echo
  echo "=== Browser note (Firefox, Wayland) ==="
  echo "  about:config → media.webrtc.camera.allow-pipewire = true"
}

cmd_libcamera() {
  need_pacman
  [[ "$(id -u)" -eq 0 ]] || die "libcamera: run with sudo."
  echo "Installing repository packages (libcamera + PipeWire integration) …"
  pacman -S --needed --noconfirm \
    libcamera libcamera-ipa libcamera-tools gst-plugin-libcamera pipewire-libcamera
  echo
  echo "Repository install finished."
  echo "As your user run: bash $SCRIPT_PATH libcamera-user"
  echo "Test with: qcam"
  echo "Firefox: media.webrtc.camera.allow-pipewire = true"
}

cmd_libcamera_user() {
  [[ "$(id -u)" -ne 0 ]] || die "libcamera-user: run as your normal user (no sudo)."
  if have_cmd systemctl; then
    systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
  fi
  echo "User PipeWire session restarted (if systemd user session is available)."
}

cmd_wireplumber_ipu6() {
  [[ "$(id -u)" -ne 0 ]] || die "wireplumber-ipu6: run as your normal user (no sudo)."
  local d="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d"
  local f="$d/99-ipu6-libcamera.conf"
  mkdir -p "$d"
  cat >"$f" <<'EOF'
wireplumber.profiles = {
  main = {
    monitor.v4l2 = disabled
    monitor.libcamera = optional
  }
}
EOF
  echo "Wrote: $f"
  if have_cmd systemctl; then
    systemctl --user restart pipewire wireplumber 2>/dev/null || systemctl --user restart wireplumber pipewire 2>/dev/null || true
  fi
  echo "Restarted PipeWire/WirePlumber (user). Check: wpctl status | grep -i camera"
}

cmd_camera_persist() {
  [[ "$(id -u)" -ne 0 ]] || die "camera-persist: run as your normal user (no sudo)."
  local udir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  local unit="$udir/restart-wireplumber-ipu6.service"
  mkdir -p "$udir"
  cat >"$unit" <<'EOF'
[Unit]
Description=Restart PipeWire/WirePlumber after login (Intel IPU6 / libcamera)
After=pipewire.service wireplumber.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 5
ExecStart=/usr/bin/systemctl --user restart pipewire.service wireplumber.service pipewire-pulse.service

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now restart-wireplumber-ipu6.service
  echo "Enabled: $unit"
  echo "On each login, ~5s after session start, the audio/video stack restarts once."
  echo "Disable: systemctl --user disable --now restart-wireplumber-ipu6.service"
}

cmd_backup_ov2740() {
  [[ "$(id -u)" -ne 0 ]] || die "backup-ov2740: run as your normal user (no sudo)."
  local src=/usr/share/libcamera/ipa/simple/ov2740.yaml
  local dst="${HOME}/ov2740-ipa-backup.yaml"
  [[ -r "$src" ]] || die "Cannot read: $src (IPA file missing?)"
  cp -a "$src" "$dst"
  echo "Copied to: $dst"
  echo "Restore: sudo cp $dst $src && sudo chmod 644 $src"
}

# Community IPA for OV2740 — without a tuned file, libcamera may use generic tuning.
# Source: Arch forum (platelminto et al.) — https://bbs.archlinux.org/viewtopic.php?id=297262
cmd_ov2740_ipa() {
  [[ "$(id -u)" -eq 0 ]] || die "ov2740-ipa: run with sudo."
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — platelminto CCM (community). No AGC (often less exposure flicker).
# Very bright scenes may show strong magenta — try daylight preset if needed.
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
  - Ccm:
      ccms:
        - ct: 6500
          ccm:
            - 2.25
            - -1.00
            - -0.25
            - -0.45
            - 1.35
            - -0.20
            - 0.00
            - -0.60
            - 1.60
EOF
  chmod 644 "$dest"
  echo "Wrote: $dest"
  echo "Restart qcam; for browsers restart user PipeWire: bash $SCRIPT_PATH libcamera-user"
}

cmd_ov2740_ipa_lowlila() {
  [[ "$(id -u)" -eq 0 ]] || die "ov2740-ipa-lowlila: run with sudo."
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — platelminto CCM + AGC with strong highlight limiting.
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
  - Agc:
      AeConstraintMode:
        ConstraintNormal:
          lower:
            qLo: 0.98
            qHi: 1.0
            yTarget: 0.34
        ConstraintHighlight:
          upper:
            qLo: 0.98
            qHi: 1.0
            yTarget: 0.52
  - Ccm:
      ccms:
        - ct: 6500
          ccm:
            - 2.25
            - -1.00
            - -0.25
            - -0.45
            - 1.35
            - -0.20
            - 0.00
            - -0.60
            - 1.60
EOF
  chmod 644 "$dest"
  echo "Wrote (platelminto + strict AGC/highlight): $dest"
  echo "Tune: higher Normal yTarget = brighter frame; lower Highlight yTarget = less clipping (e.g. 0.48)."
  echo "Restart qcam; PipeWire: bash $SCRIPT_PATH libcamera-user"
}

cmd_ov2740_ipa_lowlila_v2() {
  [[ "$(id -u)" -eq 0 ]] || die "ov2740-ipa-lowlila-v2: run with sudo."
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — Same AGC as lowlila; CCM slightly softened (92% platelminto blend).
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
  - Agc:
      AeConstraintMode:
        ConstraintNormal:
          lower:
            qLo: 0.98
            qHi: 1.0
            yTarget: 0.34
        ConstraintHighlight:
          upper:
            qLo: 0.98
            qHi: 1.0
            yTarget: 0.52
  - Ccm:
      ccms:
        - ct: 6500
          ccm:
            - 2.15
            - -0.92
            - -0.23
            - -0.41
            - 1.32
            - -0.18
            - 0.00
            - -0.55
            - 1.55
EOF
  chmod 644 "$dest"
  echo "Wrote (lowlila-v2): $dest"
  echo "Restart qcam; PipeWire: bash $SCRIPT_PATH libcamera-user"
}

cmd_ov2740_ipa_daylight() {
  [[ "$(id -u)" -eq 0 ]] || die "ov2740-ipa-daylight: run with sudo."
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — No CCM (often less pink in daylight; looks washed).
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
EOF
  chmod 644 "$dest"
  echo "Wrote (daylight, no CCM): $dest"
  echo "PipeWire: bash $SCRIPT_PATH libcamera-user"
}

cmd_ov2740_ipa_daylight_vivid() {
  [[ "$(id -u)" -eq 0 ]] || die "ov2740-ipa-daylight-vivid: run with sudo."
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — No AGC; mild CCM (8% frnkq blend).
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
  - Ccm:
      ccms:
        - ct: 6500
          ccm:
            - 1.16
            - -0.11
            - -0.01
            - -0.03
            - 1.14
            - -0.08
            - 0.00
            - -0.12
            - 1.21
EOF
  chmod 644 "$dest"
  echo "Wrote (daylight-vivid): $dest"
  echo "PipeWire: bash $SCRIPT_PATH libcamera-user"
}

cmd_ov2740_ipa_daylight_cool() {
  [[ "$(id -u)" -eq 0 ]] || die "ov2740-ipa-daylight-cool: run with sudo."
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — Cool heuristic CCM, no AGC.
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
  - Ccm:
      ccms:
        - ct: 6500
          ccm:
            - 1.04
            - -0.07
            - 0.03
            - -0.05
            - 0.96
            - -0.05
            - 0.02
            - -0.10
            - 1.08
EOF
  chmod 644 "$dest"
  echo "Wrote (daylight-cool): $dest"
  echo "PipeWire: bash $SCRIPT_PATH libcamera-user"
}

cmd_ov2740_ipa_frnkq() {
  [[ "$(id -u)" -eq 0 ]] || die "ov2740-ipa-frnkq: run with sudo."
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — frnkq CCM (community). No AGC.
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
  - Ccm:
      ccms:
        - ct: 6500
          ccm:
            - 3.05
            - -1.40
            - -0.15
            - -0.40
            - 2.70
            - -0.95
            - 0.00
            - -1.50
            - 3.60
EOF
  chmod 644 "$dest"
  echo "Wrote (frnkq): $dest"
  echo "Without AGC the image can stay very dark after startup — then use ov2740-ipa-frnkq-agc."
  echo "PipeWire: bash $SCRIPT_PATH libcamera-user"
}

cmd_ov2740_ipa_frnkq_agc() {
  [[ "$(id -u)" -eq 0 ]] || die "ov2740-ipa-frnkq-agc: run with sudo."
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — frnkq CCM + AGC (yTarget 0.38).
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
  - Agc:
      AeConstraintMode:
        ConstraintNormal:
          lower:
            qLo: 0.98
            qHi: 1.0
            yTarget: 0.38
  - Ccm:
      ccms:
        - ct: 6500
          ccm:
            - 3.05
            - -1.40
            - -0.15
            - -0.40
            - 2.70
            - -0.95
            - 0.00
            - -1.50
            - 3.60
EOF
  chmod 644 "$dest"
  echo "Wrote (frnkq + AGC): $dest"
  echo "If too dark: raise yTarget toward 0.42; if too bright: lower toward 0.34."
  echo "PipeWire: bash $SCRIPT_PATH libcamera-user"
}

cmd_ov2740_ipa_frnkq_agc_neutral() {
  [[ "$(id -u)" -eq 0 ]] || die "ov2740-ipa-frnkq-agc-neutral: run with sudo."
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — 75% frnkq / 25% platelminto CCM + AGC yTarget 0.38.
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
  - Agc:
      AeConstraintMode:
        ConstraintNormal:
          lower:
            qLo: 0.98
            qHi: 1.0
            yTarget: 0.38
  - Ccm:
      ccms:
        - ct: 6500
          ccm:
            - 2.85
            - -1.30
            - -0.18
            - -0.41
            - 2.36
            - -0.76
            - 0.00
            - -1.28
            - 3.10
EOF
  chmod 644 "$dest"
  echo "Wrote (frnkq-agc neutral blend): $dest"
  echo "PipeWire: bash $SCRIPT_PATH libcamera-user"
}

cmd_aur() {
  need_pacman
  [[ "$(id -u)" -eq 0 ]] || die "aur: run with sudo."
  echo "Installing build dependencies …"
  local hdr
  hdr="$(kernel_headers_pkg)"
  pacman -S --needed --noconfirm base-devel dkms "$hdr"

  echo "Building/installing AUR packages (slow) …"
  aur_install \
    intel-ipu6-dkms-git \
    intel-ipu6-camera-bin \
    intel-ipu6ep-camera-hal-git \
    icamerasrc-git \
    v4l2loopback-dkms \
    v4l2-relayd

  echo "Rebuilding DKMS modules …"
  dkms autoinstall 2>/dev/null || true

  echo "v4l2loopback modprobe config …"
  install -d /etc/modprobe.d
  cat >/etc/modprobe.d/ipu6-v4l2loopback.conf <<'EOF'
# Intel IPU6 → v4l2-relayd
options v4l2loopback card_label="Intel IPU6 Webcam" exclusive_caps=1
EOF
  modprobe v4l2loopback 2>/dev/null || true

  echo "v4l2-relayd service …"
  systemctl enable --now v4l2-relayd@intel-ipu.service 2>/dev/null \
    || systemctl enable --now v4l2-relayd.service 2>/dev/null \
    || echo "Note: could not start v4l2-relayd unit — check after reboot: systemctl status 'v4l2-relayd*'"

  echo
  echo "AUR stack installed. Reboot is often required for clean module load."
  echo "Then check: ls -l /dev/video*"
}

main() {
  if [[ $# -eq 0 ]]; then
    if [[ -t 0 && -t 1 ]]; then
      interactive_wizard
    else
      cmd_help
    fi
    exit 0
  fi

  local sub="$1"
  case "$sub" in
    help|-h|--help) cmd_help ;;
    status|diag) cmd_status ;;
    libcamera) cmd_libcamera ;;
    libcamera-user) cmd_libcamera_user ;;
    ov2740-ipa|ov2740|ov2740-yaml) cmd_ov2740_ipa ;;
    ov2740-ipa-lowlila|ov2740-lowlila|ov2740-ipa-plus) cmd_ov2740_ipa_lowlila ;;
    ov2740-ipa-lowlila-v2|ov2740-lowlila-v2) cmd_ov2740_ipa_lowlila_v2 ;;
    ov2740-ipa-daylight|ov2740-daylight) cmd_ov2740_ipa_daylight ;;
    ov2740-ipa-daylight-vivid|ov2740-daylight-vivid|daylight-vivid) cmd_ov2740_ipa_daylight_vivid ;;
    ov2740-ipa-daylight-cool|ov2740-daylight-cool|daylight-cool) cmd_ov2740_ipa_daylight_cool ;;
    ov2740-ipa-frnkq|ov2740-frnkq) cmd_ov2740_ipa_frnkq ;;
    ov2740-ipa-frnkq-agc|ov2740-frnkq-agc) cmd_ov2740_ipa_frnkq_agc ;;
    ov2740-ipa-frnkq-agc-neutral|ov2740-frnkq-neutral|ov2740-neutral) cmd_ov2740_ipa_frnkq_agc_neutral ;;
    wireplumber-ipu6|wp-ipu6) cmd_wireplumber_ipu6 ;;
    camera-persist|persist) cmd_camera_persist ;;
    backup-ov2740|backup-ipa) cmd_backup_ov2740 ;;
    aur|fallback|relay) cmd_aur ;;
    interactive|wizard|menu) interactive_wizard ;;
    *) die "Unknown command: $sub — see: $SCRIPT_PATH help" ;;
  esac
}

main "$@"
