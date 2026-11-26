## Auto USB

  [English](README.md)

Magisk / KernelSU / APatch 通用
插数据线自动打开adb拔出关闭

许可：GPL-3.0-or-later 全文见 [`LICENSE`](LICENSE)。

## 安装

从[Releases](../../releases)下载 在管理器里刷入重启

在 WebUI 里打开模块，选一个模式：MTP / PTP / USB 网卡 / MIDI / 仅充电

| 管理器 | 版本要求 |
|---|---|
| Magisk | 20.4+ |
| KernelSU | 0.9.0+ |
| APatch | 10.7+ |


## WebUI

| 管理器 | 打开方式 |
|---|---|
| KernelSU / KernelSU Next | 模块卡片 → WebUI |
| APatch | 模块卡片 → WebUI |
| Magisk | 安装 [MMRL](https://github.com/MMRLApp/MMRL)，并允许 **高级 KernelSU API** |

## 构建

```sh
python3 build.py
```