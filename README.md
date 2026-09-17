# Auto-USB
Android 自动开启USB调试
一个基于 LSPosed 框架的 Android 系统模块。手机通过数据线连接电脑时，它会自动开启默认USB模式 让用户能够通过adb访问你的设备
-----
# 本项目基于<https://github.com/TigerSpirit217/USBManager?tab=readme-ov-file> 进行修改而来
## 功能

* **自动检测连接**：自动识别手机以设备模式连接电脑的事件
* **自动开启USB调试**：接入电脑自动开启USB调试
* **默认文件传输（MTP）模式**

## 安装

### 前置条件

* 已解锁 Bootloader 并取得 root 的 Android 设备。

* 已安装 **LSPosed** 框架。

* Android 11 或更高版本，推荐 Android 12+。

### 步骤

1. 从 [Releases](../../releases/tag/main) 下载最新 APK。
2. 安装 APK。
3. 在 **LSPosed Manager → 模块**中启用 **Auto USB MTP**。
4. 作用域勾选 system（系统框架）。
5. 重启设备。

## 使用

1. 插入连接电脑的数据线
2. 查看状态栏通知提示
3. 命令行输入“adb devices”查看连接状态

## 许可证

本项目使用木兰公共许可证，第 2 版（Mulan PubL v2）。完整授权见 [LICENSE](https://license.coscl.org.cn/MulanPubL-2.0)。

## 发布与反馈
* 发布页面：<https://github.com/Shuoh118/Auto-USB/releases/tag/main>
* 问题反馈：<https://github.com/Shuoh118/Auto-USB/issues>

## 鸣谢
最后感谢@https://github.com/TigerSpirit217