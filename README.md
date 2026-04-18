# Intel IPU6 webcam (OV2740) on Linux — libcamera, PipeWire, Arch

Fixes and tuning for **Intel IPU6** laptops with the **OV2740** sensor (often **ThinkPad X1 Carbon Gen 11** and similar) on **Arch Linux**, **CachyOS**, **Manjaro**, and other **pacman**-based distros. The built-in camera is **not a simple USB webcam**: there may be **no `/dev/video0`**, and apps need **libcamera** and **PipeWire** wired correctly.

If your **camera does not work**, shows a **black** or **very dark** image, **green** or **purple** skin tones, **magenta** highlights, a **frozen** still frame, **lag**, or **only updates once** in **Zoom**, **Teams**, **Google Meet**, or **Firefox** on **Wayland**, this repo automates the usual fixes: packages, **WirePlumber** settings, optional **IPA** profiles in `ov2740.yaml`, and an optional login **race** workaround.

## Interactive wizard (recommended)

Run as your normal user (not root). The script will ask for `sudo` when needed:

```bash
bash setup-intel-ipu6-camera.sh
```

On a **non-interactive** terminal (no TTY), running with no arguments prints help instead.

```bash
bash setup-intel-ipu6-camera.sh wizard
```

## Non-interactive examples

```bash
bash setup-intel-ipu6-camera.sh help
sudo bash setup-intel-ipu6-camera.sh libcamera
bash setup-intel-ipu6-camera.sh libcamera-user
bash setup-intel-ipu6-camera.sh wireplumber-ipu6
sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-lowlila-v2
bash setup-intel-ipu6-camera.sh camera-persist
bash setup-intel-ipu6-camera.sh backup-ov2740
bash setup-intel-ipu6-camera.sh status
```

**Firefox (Wayland):** `about:config` → `media.webrtc.camera.allow-pipewire` = `true`

## Credits & sources

This project **bundles and automates** steps documented by the community. Please cite them if you fork or write about this:

- **Arch Linux Forums** — [thread on X1 Carbon Gen 11, OV2740, `ov2740.yaml`, libcamera](https://bbs.archlinux.org/viewtopic.php?id=297262). IPA presets in the script trace back to community posts there, including contributions attributed in that thread to **platelminto** (CCM / tuning baseline), **aljinovic** (edits such as daylight / no-CCM ideas), and **frnkq** (alternative CCM matrix used in several presets). The thread is the canonical discussion; thank the posters there if their YAML helped you.
- **Jan Grulich** — [PipeWire and libcamera integration](https://jgrulich.cz/) (background on why **V4L2** monitoring and **libcamera** matter for this stack).

Embedded YAML fragments in the script are marked **SPDX-License-Identifier: CC0-1.0** in-file where applicable. This repository’s script and docs are offered as-is; add a top-level `LICENSE` if you want a formal project license.

## Privacy / portability

No hostnames or serial numbers are embedded. Paths used are standard: `$HOME`, `~/.config`, `/usr/share/libcamera/ipa/simple/ov2740.yaml`, and optional `~/ov2740-ipa-backup.yaml`.

## Repository visibility

This project is intended to stay **public** so others can find it when searching for **Intel IPU6 Linux camera**, **OV2740**, **libcamera**, **PipeWire webcam**, etc.
