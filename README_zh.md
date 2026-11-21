## Auto USB

  [English](README.md)

Magisk / KernelSU / APatch 通用
插数据线自动打开adb拔出关闭

许可：GPL-3.0-or-later **或** Apache-2.0全文见 [`LICENSE`](LICENSE)。

## 安装

从[Releases](../../releases)下载 在管理器里刷入重启

在 WebUI 里打开模块，选一个模式：MTP / PTP / USB 网卡 / MIDI / 仅充电

插上数据线电脑验证

## 构建

```sh
python3 build.py
```

## 安全

默认情况下 ADB 需要主机授权。`config/autousb.conf` 里的 `INSECURE_ADB=1` 会关闭 ADB 的主机指纹校验（`ro.adb.secure=0`），**默认关闭**，只在完全信任所连电脑时才打开。模块不会修改 `ro.debuggable` 或 `service.adb.root`。
