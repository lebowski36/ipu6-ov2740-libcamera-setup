# Intel IPU6 + OV2740 — libcamera / PipeWire setup

Helper script for **Arch Linux / CachyOS** (pacman) machines with **Intel IPU6** and **OV2740** (e.g. ThinkPad X1 Carbon Gen 11): install **libcamera** + **pipewire-libcamera**, optional **WirePlumber** snippet, **OV2740 IPA** presets, optional login **persist** workaround.

**Confirmed path in use:** open stack only (no AUR `intel-ipu6*` / `v4l2-relayd`). See script header for commands.

## Quick start

```bash
sudo bash setup-intel-ipu6-camera.sh libcamera
bash setup-intel-ipu6-camera.sh libcamera-user
bash setup-intel-ipu6-camera.sh wireplumber-ipu6
sudo bash setup-intel-ipu6-camera.sh ov2740-ipa-lowlila-v2   # tuned preset (see script)
```

Optional: `bash setup-intel-ipu6-camera.sh camera-persist`, `bash setup-intel-ipu6-camera.sh backup-ov2740`, `bash setup-intel-ipu6-camera.sh status`.

## References

- [Arch forum — X1 Carbon Gen 11 / OV2740](https://bbs.archlinux.org/viewtopic.php?id=297262)
- [PipeWire + libcamera (Jan Grulich)](https://jgrulich.cz/)

## Clone / publish

```bash
git clone git@github.com:lebowski36/ipu6-ov2740-libcamera-setup.git
```

To recreate the remote from a local copy: `gh repo create ipu6-ov2740-libcamera-setup --public --source=. --remote=origin --push`

## License

Script comments reference community YAML / CC0-1.0 snippets; add a `LICENSE` file if you want a formal statement.
