# 自动USB MTP

Xposed/LSPosed 模块：插线后自动把USB 连接模式切到MTP，不用每次手动下拉通知栏点选。
-----

[中文](README.md)

## 功能

- 插入数据线后自动将USB 模式切换为MTP
- 钩，`UsbDeviceManager`AdbService`，在system_server 层生效

## 环境要求

- Android 12 及以上（模块minApiVersion / targetApiVersion = 102）
- LSPosed（Zygisk 或Riru 均可）
- Root 权限（KernelSU / Magisk 均可）

## 安装

1. 从 [发布](../../releases)  下载最新的APK
2. 安装后打开LSPosed 管理器
3. 在模块列表中启用**Auto USB MTP**
4. 作用域勾选**系统框架**（system）
5. 重启设备

## 配置
改动立即写入，下次插线按新设置生效。

## 更新日志

### v1.2
- 优化Hook 安装流程
- 修复部分机型插线后模式未生效的问题


## 许可

本项目使用木兰公共许可证，第2 版（Mulan PubL v2）。完整授权见 [执照](https://license.coscl.org.cn/MulanPubL-2.0)。

## 发布与反馈
* 发布页面：<https://github.com/Shuoh118/Auto-USB/releases>
* 其他发布页面：<https://github.com/Xposed-Modules-Repo/io.github.shuoh118.autousbmtp/releases>
* 问题反馈：<https://github.com/Shuoh118/Auto-USB/issues>

## 最后
* 如果你觉得本项目对你有用，请点上右上角的star，这是对我的最佳鼓励。
* 最后感谢@https://github.com/TigerSpirit217
* 本项目基于https://github.com/TigerSpirit217/USBManager?tab=readme-ov-file
* 修改而来没有他就没有此项目
