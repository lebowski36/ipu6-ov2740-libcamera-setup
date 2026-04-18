# Intel IPU6 + OV2740 — libcamera / PipeWire setup

Helper for **Arch-based** distributions (**pacman**) on laptops with **Intel IPU6** and **OV2740** (common on some ThinkPads and similar). It installs **libcamera** + **pipewire-libcamera**, optionally applies a **WirePlumber** snippet, and can write community **IPA** tuning to `ov2740.yaml`.

**Default stack:** open source (kernel + libcamera + PipeWire). An optional **AUR** path (DKMS, relay) exists only for legacy `/dev/video*` workflows.

## Interactive wizard (recommended)

Run as your normal user (not root). The script will ask for `sudo` when needed:

```bash
bash setup-intel-ipu6-camera.sh
```

On a **non-interactive** terminal (no TTY), running with no arguments prints help instead.

You can also force the menu with:

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

## Privacy / portability

The script and this README **do not** embed hostnames, serial numbers, or user-specific paths except:

- Standard locations: `$HOME`, `~/.config`, `/usr/share/libcamera/...`
- Optional backup file: `~/ov2740-ipa-backup.yaml`

Clone or publish from your own account; replace any remote URL with yours.

## References

- [Arch forum — OV2740 / libcamera](https://bbs.archlinux.org/viewtopic.php?id=297262)
- [PipeWire + libcamera (Jan Grulich)](https://jgrulich.cz/)

## License

YAML fragments in the script are marked **CC0-1.0** in-file. Add a top-level `LICENSE` if you want a formal project license.
