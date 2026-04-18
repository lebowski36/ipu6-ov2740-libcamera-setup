#!/usr/bin/env bash
# Intel MIPI / IPU6 Webcam auf Arch/CachyOS — libcamera zuerst, optional AUR+V4L2-Relay
#
# Realistische Erwartung:
# - Auf aktuellen Kerneln (6.18+, dein CachyOS 7.x) funktioniert die offene Pipeline oft:
#   Kernel-Treiber + libcamera + pipewire-libcamera. ThinkPad X1 Carbon Gen 11 wird im Arch-Forum
#   mit Sensor OV2740 und libcamera genannt — Bild kann ohne IPA-Tuning blass/zittrig wirken;
#   Tuning: https://bbs.archlinux.org/viewtopic.php?id=297262 (Beitrag „X1 Carbon Gen 11 … ov2740.yaml“)
# - Wenn Browser/Apps nur klassisches V4L2 (/dev/video*) nutzen und libcamera nicht reicht,
#   hilft der zweite Weg: DKMS + Intel-Blobs + v4l2loopback + v4l2-relayd (AUR, längere Builds).
#
# Nutzung:
#   bash setup-intel-ipu6-camera.sh libcamera          # empfohlen zuerst (nur offizielle Repos)
#   bash setup-intel-ipu6-camera.sh libcamera-user     # PipeWire neu starten (ohne sudo)
#   sudo bash setup-intel-ipu6-camera.sh aur           # Fallback: AUR-Stack + Loopback + Relay
#   bash setup-intel-ipu6-camera.sh status             # Diagnose
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa # IPA platelminto (Original, kein Agc)
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-lowlila    # platelminto + strengeres Agc (Highlights drosseln)
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-lowlila-v2 # wie lowlila, CCM 92% platelminto — oft weniger Magenta bei Clipping
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-daylight  # IPA ohne CCM — weniger Lila/Pink bei Sonne (leichter Grünstich)
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-daylight-vivid  # daylight + milde CCM (8% frnkq) — etwas Farbe, weniger Lila als voller CCM
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-daylight-cool   # gegen Gelb/Grün: leicht kühler (heuristische CCM), kein Agc
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-frnkq      # alternativ. CCM (Forum frnkq): oft weniger Grün, evtl. mehr Lila bei Sonne
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-frnkq-agc  # frnkq+Agc+yTarget 0.38 (aktueller Standard)
#   sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-frnkq-agc-neutral  # 75/25 frnkq+platelminto — oft etwas weniger Grün
#   bash setup-intel-ipu6-camera.sh wireplumber-ipu6  # V4L2-Monitor aus, libcamera für Chrome/Meet (ohne sudo)
#   bash setup-intel-ipu6-camera.sh camera-persist   # Nach jedem Login: PipeWire/WirePlumber kurz neu (IPU6-Race)
#   bash setup-intel-ipu6-camera.sh backup-ov2740     # Kopie der IPA-Datei nach ~ (Backup)
#   bash setup-intel-ipu6-camera.sh help

set -euo pipefail

die() { echo "Fehler: $*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

aur_install() {
  # paru/yay nicht als root ausführen (Pacman-Regel / AUR-Helfer)
  if [[ "$(id -u)" -eq 0 ]]; then
    local u="${SUDO_USER:-}"
    [[ -n "$u" && "$u" != root ]] || die "AUR: bitte ausführen: sudo $0 aur   (von deinem normalen User, nicht reines root-Login)."
    if have_cmd paru; then runuser -u "$u" -- paru -S --needed --noconfirm "$@"; return; fi
    if have_cmd yay; then runuser -u "$u" -- yay -S --needed --noconfirm "$@"; return; fi
    die "Kein paru/yay gefunden. User $u: paru installieren, dann erneut sudo $0 aur"
  fi
  if have_cmd paru; then paru -S --needed --noconfirm "$@"; return; fi
  if have_cmd yay; then yay -S --needed --noconfirm "$@"; return; fi
  die "Kein paru/yay gefunden: https://github.com/Morganamilo/paru"
}

kernel_headers_pkg() {
  # Passende Headers zum installierten Kernel (CachyOS vs. Arch-Standard)
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
  die "Konnte kein passendes Kernel-Paket ermitteln (linux / linux-cachyos …). Headers manuell installieren."
}

cmd_help() {
  sed -n '1,25p' "$0" | tail -n +2
}

cmd_status() {
  echo "=== Kernel ==="
  uname -r
  echo
  echo "=== PCI (IPU / VSC) ==="
  lspci -nn 2>/dev/null | rg -i 'ipu|imaging|visual|mipi' || lspci -nn | rg -i '8086:.*(0480|462e|a75d|7d19)' || true
  echo
  echo "=== Video-Geräte ==="
  ls -la /dev/video* 2>/dev/null || echo "(keine /dev/video*)"
  echo
  echo "=== Dmesg (Auszug) ==="
  dmesg 2>/dev/null | rg -i 'ipu6|ipu |ovti|ov[0-9]|mipi|int3472|libcamera' | tail -n 30 || true
  echo
  echo "=== Pakete (libcamera) ==="
  pacman -Q libcamera libcamera-ipa pipewire-libcamera 2>/dev/null || true
  echo
  echo "=== Hinweis Browser (Firefox, Wayland) ==="
  echo "  about:config → media.webrtc.camera.allow-pipewire = true"
}

cmd_libcamera() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus libcamera: sudo $0 libcamera"
  echo "Installiere Repo-Pakete (libcamera + PipeWire-Integration) …"
  pacman -S --needed --noconfirm \
    libcamera libcamera-ipa libcamera-tools gst-plugin-libcamera pipewire-libcamera
  echo
  echo "Fertig (Repo)."
  echo "Als normaler Benutzer ausführen: $0 libcamera-user"
  echo "Test:  qcam"
  echo "Firefox: media.webrtc.camera.allow-pipewire = true"
}

cmd_libcamera_user() {
  [[ "$(id -u)" -ne 0 ]] || die "Modus libcamera-user ohne sudo (als dein Login-User)."
  if have_cmd systemctl; then
    systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
  fi
  echo "PipeWire (User) neu gestartet (falls vorhanden)."
}

# IPU6: Raw V4L2 ist oft nutzlos (Bayer); Browser brauchen libcamera über PipeWire.
# Siehe u. a. https://jgrulich.cz/ — monitor.v4l2 aus, libcamera optional.
cmd_wireplumber_ipu6() {
  [[ "$(id -u)" -ne 0 ]] || die "wireplumber-ipu6 ohne sudo ausführen (Konfiguration in ~)."
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
  echo "Geschrieben: $f"
  if have_cmd systemctl; then
    systemctl --user restart pipewire wireplumber 2>/dev/null || systemctl --user restart wireplumber pipewire 2>/dev/null || true
  fi
  echo "PipeWire/WirePlumber neu gestartet. Prüfen: wpctl status | rg -i camera"
  echo "Chrome: meet.google.com — Kamera erlauben; ggf. chrome://settings/content/camera"
}

# Nach Login: kurz warten, dann PipeWire/WirePlumber neu — behebt oft „nach Reboot andere Bildqualität / kein Gerät“.
# Idee wie im Arch-Forum (platelminto); optional, stört nicht merklich.
cmd_camera_persist() {
  [[ "$(id -u)" -ne 0 ]] || die "camera-persist ohne sudo (User-Systemd)."
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
  echo "Aktiviert: $unit"
  echo "Beim nächsten Login startet der Dienst einmalig ~5s nach Session-Start und startet Audio/Video-Stack neu."
  echo "Deaktivieren: systemctl --user disable --now restart-wireplumber-ipu6.service"
}

cmd_backup_ov2740() {
  [[ "$(id -u)" -ne 0 ]] || die "backup-ov2740 ohne sudo."
  local src=/usr/share/libcamera/ipa/simple/ov2740.yaml
  local dst="$HOME/ov2740-x1c-backup.yaml"
  [[ -r "$src" ]] || die "Nicht lesbar: $src (IPA gesetzt?)"
  cp -a "$src" "$dst"
  echo "Kopie: $dst"
  echo "Wiederherstellen nach Verlust: sudo cp $dst $src && sudo chmod 644 $src"
}

# Community-IPA für OV2740 (ThinkPad X1 Carbon Gen 11 u.ä.): ohne diese Datei nutzt libcamera
# uncalibrated.yaml → Grünstich, flackerndes AGC. Quelle: Arch-Forum platelminto et al.
# https://bbs.archlinux.org/viewtopic.php?id=297262
cmd_ov2740_ipa() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus ov2740-ipa: sudo $0 ov2740-ipa"
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — platelminto CCM (Arch forum). Kein Agc (weniger Flackern).
# Autor-Hinweis: bei sehr hellem Licht kann diese CCM „aggressives Pink“ erzeugen — dann ov2740-ipa-daylight nutzen.
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
  echo "Geschrieben: $dest"
  echo "qcam neu starten; bei Meet/Chrome PipeWire-Session ggf.: systemctl --user restart wireplumber pipewire"
}

# Wie ov2740-ipa (identische platelminto-CCM), aber mit Agc + strenger Highlight-Bremse (niedrigere yTargets).
# Magenta in Lampe/Specular: oft Sensor-Clipping — nie perfekt wegzutunen; v2 = etwas weichere CCM.
# libcamera: AgcMeanLuminance / AeConstraintMode (u. a. ConstraintHighlight.upper).
cmd_ov2740_ipa_lowlila() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus ov2740-ipa-lowlila: sudo $0 ov2740-ipa-lowlila"
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — platelminto CCM + Agc (Highlight hart drosseln). Magenta kommt oft von ausgefressenen Highlights + CCM.
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
  echo "Geschrieben (platelminto + strenges Agc/Highlight): $dest"
  echo "Original ohne Agc: sudo $0 ov2740-ipa   | noch Lila: sudo $0 ov2740-ipa-lowlila-v2"
  echo "Feintune: Normal yTarget hoch = heller; Highlight upper yTarget runter = weniger Ausfressen (z. B. 0.48)."
  echo "qcam neu starten; PipeWire: bash $0 libcamera-user"
}

# Wie lowlila (gleiches Agc), aber CCM 92% platelminto + 8% Einheit — weniger Farbübertreibung auf Clipping, näher am Look von ov2740-ipa.
cmd_ov2740_ipa_lowlila_v2() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus ov2740-ipa-lowlila-v2: sudo $0 ov2740-ipa-lowlila-v2"
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — lowlila-v2: gleiches Agc wie lowlila, CCM leicht entschärft (92% platelminto)
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
  echo "Geschrieben (lowlila-v2, weichere CCM): $dest"
  echo "Zu blass/fade: sudo $0 ov2740-ipa-lowlila"
  echo "qcam neu starten; PipeWire: bash $0 libcamera-user"
}

# aljinovic / platelminto: ohne Ccm — bei Tageslicht oft weniger Lila als mit CCM; insgesamt etwas „washed out“.
cmd_ov2740_ipa_daylight() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus ov2740-ipa-daylight: sudo $0 ov2740-ipa-daylight"
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — ohne CCM (Arch forum aljinovic / platelminto Edit: lieber blass als Pink bei Helligkeit)
%YAML 1.1
---
version: 1
algorithms:
  - BlackLevel:
  - Awb:
  - Adjust:
EOF
  chmod 644 "$dest"
  echo "Geschrieben (Tageslicht-Preset, ohne CCM): $dest"
  echo "qcam neu starten; PipeWire: bash $0 libcamera-user"
}

# Wie daylight (kein Agc), aber sanfte Farbanhebung: CCM = 92% Identität + 8% frnkq (weicher als früher 12%).
cmd_ov2740_ipa_daylight_vivid() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus ov2740-ipa-daylight-vivid: sudo $0 ov2740-ipa-daylight-vivid"
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — „daylight vivid“: kein Agc; leichte CCM (8% frnkq, 92% Einheit)
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
  echo "Geschrieben (daylight-vivid, 8%): $dest"
  echo "Zu gelb/grün: sudo $0 ov2740-ipa-daylight-cool   | Zu blass: sudo $0 ov2740-ipa-daylight"
  echo "PipeWire: bash $0 libcamera-user"
}

# Gegen Gelb- und Grünstich: kleine „kühlere“ CCM (Community-Heuristik), kein Agc — bei Lila wieder daylight.
cmd_ov2740_ipa_daylight_cool() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus ov2740-ipa-daylight-cool: sudo $0 ov2740-ipa-daylight-cool"
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — „daylight cool“: kein Agc; milde CCM gegen warm/gelb und etwas Grün (heuristisch)
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
  echo "Geschrieben (daylight-cool): $dest"
  echo "Zu kühl/Lila: sudo $0 ov2740-ipa-daylight   | Mehr Farbe: sudo $0 ov2740-ipa-daylight-vivid"
  echo "PipeWire: bash $0 libcamera-user"
}

# frnkq (X1 Nano G3, Arch forum): heller, weniger krasser Grünstich als „daylight“, Autor: evtl. leichter Grünstich verbleibend.
cmd_ov2740_ipa_frnkq() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus ov2740-ipa-frnkq: sudo $0 ov2740-ipa-frnkq"
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — CCM frnkq (Arch forum). Kein Agc.
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
  echo "Geschrieben (frnkq-CCM): $dest"
  echo "Hinweis: Ohne Agc kann die Kamera nach Neustart fast schwarz bleiben — dann: sudo $0 ov2740-ipa-frnkq-agc"
  echo "qcam testen; bei Lila in Sonne wieder: sudo $0 ov2740-ipa-daylight"
  echo "PipeWire: bash $0 libcamera-user"
}

# frnkq + Agc: Helligkeit ähnlicher „wie früher im gleichen Raum“; Agc kann bei sehr hellem Bild flackern (dann ohne Agc: frnkq).
# yTarget niedriger → weniger Überbelichtung (libcamera-Doku: ConstraintNormal.lower.yTarget, typ. ~0.5).
cmd_ov2740_ipa_frnkq_agc() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus ov2740-ipa-frnkq-agc: sudo $0 ov2740-ipa-frnkq-agc"
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — frnkq CCM + Agc (getunte Belichtung: yTarget 0.38 gegen Überbelichtung)
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
  echo "Geschrieben (frnkq + Agc, yTarget gedimmt): $dest"
  echo "qcam neu starten. Zu dunkel: yTarget in der Datei auf 0.42 erhöhen; zu hell: auf 0.34 senken."
  echo "Bei Flackern: sudo $0 ov2740-ipa-frnkq"
}

# Gleiche Belichtung wie frnkq-agc, aber CCM gemischt (75 % frnkq + 25 % platelminto) — weniger Grün, ggf. leicht rötlicher.
cmd_ov2740_ipa_frnkq_agc_neutral() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus ov2740-ipa-frnkq-agc-neutral: sudo $0 ov2740-ipa-frnkq-agc-neutral"
  local dest=/usr/share/libcamera/ipa/simple/ov2740.yaml
  install -d /usr/share/libcamera/ipa/simple
  cat >"$dest" <<'EOF'
# SPDX-License-Identifier: CC0-1.0
# OV2740 — frnkq+platelminto CCM (75/25) + Agc yTarget 0.38 — Kompromiss weniger Grün
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
  echo "Geschrieben (frnkq-agc + neutraler CCM-Mix): $dest"
  echo "qcam testen. Zu warm/Lila: sudo $0 ov2740-ipa-frnkq-agc"
  echo "PipeWire: bash $0 libcamera-user"
}

cmd_aur() {
  [[ "$(id -u)" -eq 0 ]] || die "Modus aur: sudo $0 aur"
  echo "Installiere Build-Abhängigkeiten …"
  local hdr
  hdr="$(kernel_headers_pkg)"
  pacman -S --needed --noconfirm base-devel dkms "$hdr"

  echo "AUR-Pakete bauen/installieren (dauert) …"
  # Raptor Lake / „IPU6 EP“: HAL-Variante ipu6ep; Binaries + DKMS + GStreamer-Quelle + Relay-Pipeline
  aur_install \
    intel-ipu6-dkms-git \
    intel-ipu6-camera-bin \
    intel-ipu6ep-camera-hal-git \
    icamerasrc-git \
    v4l2loopback-dkms \
    v4l2-relayd

  echo "DKMS-Module neu bauen …"
  dkms autoinstall 2>/dev/null || true

  echo "v4l2loopback-Modprobe-Konfiguration …"
  install -d /etc/modprobe.d
  cat >/etc/modprobe.d/ipu6-v4l2loopback.conf <<'EOF'
# Intel IPU6 → v4l2-relayd; card_label erscheint in Apps als Kamera-Name
options v4l2loopback card_label="Intel IPU6 Webcam" exclusive_caps=1
EOF
  modprobe v4l2loopback 2>/dev/null || true

  echo "v4l2-relayd Dienst …"
  systemctl enable --now v4l2-relayd@intel-ipu.service 2>/dev/null \
    || systemctl enable --now v4l2-relayd.service 2>/dev/null \
    || echo "Hinweis: v4l2-relayd-Unit nicht gestartet — nach Neustart prüfen: systemctl status 'v4l2-relayd*'"

  echo
  echo "AUR-Weg installiert. Neustart wird oft benötigt, damit ipu6/psys/loopback sauber laden."
  echo "Danach prüfen:  ls -l /dev/video*   und in Chrome Meet die Kamera wählen."
}

main() {
  local sub="${1:-help}"
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
    *) die "Unbekannter Befehl: $sub — siehe: $0 help" ;;
  esac
}

main "$@"
