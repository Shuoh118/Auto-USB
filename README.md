## Auto USB

  [简体中文](README_zh.md)

Works on Magisk / KernelSU / APatch
Plug in a data cable and adb turns on automatically, unplug and it turns off

License: GPL-3.0-or-later. See [`LICENSE`](LICENSE) for the full text.

## Install

Download from [Releases](../../releases), flash it in your manager, reboot

Open the module in a WebUI and pick a mode: MTP / PTP / USB Ethernet / MIDI / Charge only

| Manager | Minimum version |
|---|---|
| Magisk | 20.4+ |
| KernelSU | 0.9.0+ |
| APatch | 10.7+ |

## WebUI

| Manager | How to open it |
|---|---|
| KernelSU / KernelSU Next | Module card → WebUI |
| APatch | Module card → WebUI |
| Magisk | Install [MMRL](https://github.com/MMRLApp/MMRL) and allow the **Advanced KernelSU API** |

## Build

```sh
python3 build.py
```