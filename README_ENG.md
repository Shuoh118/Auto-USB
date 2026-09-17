# Auto-USB
Automatically enable USB debugging on Android
An Android system module based on the LSPosed framework. When your phone is connected to a computer via a USB cable, it automatically switches to the default USB mode, allowing users to access your device through ADB.
-----
# This project is modified from<https://github.com/TigerSpirit217/USBManager?tab=readme-ov-file>
## Features
* **Automatic connection detection**: Automatically detects when your phone connects to a computer in device mode.
* **Automatic enabling of USB debugging**: Automatically enables USB debugging upon connecting to a computer.
* **Default file transfer (MTP) mode**
## Installation
### Prerequisites
* An Android device with an unlocked bootloader and root access.
* The **LSPosed** framework installed.
* Android 11 or later; Android 12+ is recommended.
### Steps
1. Download the latest APK from [Releases](../../releases/tag/main).
2. Install the APK.
3. In **LSPosed Manager → Modules**, enable **Auto USB MTP**.
4. Select "system" as the scope.
5. Restart your device.
## Usage
1. Plug in the USB cable to connect to your computer.
2. Check the status bar notification.
3. Run `adb devices` in the command line to verify the connection status.
## License
This project is licensed under the Mulan Public License, Version 2.0. For the full license text, see [LICENSE](https://license.coscl.org.cn/MulanPubL-2.0).
## Releases and Feedback
* Release page:<https://github.com/Shuoh118/Auto-USB/releases/tag/main>
* Issue feedback:<https://github.com/Shuoh118/Auto-USB/issues>
If you find this project useful, please click the “star” button in the upper-right corner—your support means the world to me.
## Acknowledgments
Finally, thanks to @https://github.com/TigerSpirit217