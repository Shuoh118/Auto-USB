## Auto USB

  [简体中文](README_zh.md)

Works on Magisk / KernelSU / APatch
Plug in a data cable and adb turns on automatically, unplug and it turns off

License: GPL-3.0-or-later **OR** Apache-2.0. See [`LICENSE`](LICENSE) for full texts.

## Install

Download from [Releases](../../releases), flash it in your manager, reboot

Open the module in a WebUI and pick a mode: MTP / PTP / USB Ethernet / MIDI / Charge only

Plug in a data cable and verify on your computer

## Build

```sh
python3 build.py
```

## Security

ADB over USB requires host authorization by default. Setting `INSECURE_ADB=1` in `config/autousb.conf` disables ADB host-key verification (`ro.adb.secure=0`); it is **off by default** — enable it only for computers you fully trust. The module never sets `ro.debuggable` or `service.adb.root`.
