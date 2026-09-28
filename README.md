# XPanOverlay 1.2 — Sony PMCA 相机 XPan 遮幅取景工具

目标机型：**Sony α7 II (ILCE-7M2)**，固件 **4.01**（其他支持 PlayMemories Apps 的机型也可用）。

在相机屏幕上叠加 XPan 宽幅遮幅黑边 + 双层安全框，**实时取景画面由 App 自行渲染**，快门/对焦可用。

## 1.2 架构（参照 voxivoid/recipe-lab-sony-pmca，已实机验证的社区方案）

1.0/1.1 黑屏的根本原因：**PMCA App 窗口之下，相机系统的原生 LiveView 不会渲染**，透明窗口无法透出画面。
Recipe Lab（在 A6000 上实机工作）证明了唯一可行方式——**App 自己渲染预览**：

- `CameraEx.open(0, null)`（反射调用索尼 scalar API）→ `getNormalCamera()` 拿到标准 `android.hardware.Camera`
- `camera.setPreviewDisplay(surfaceHolder); camera.startPreview()` 把实时取景画到 App 的 SurfaceView
- 遮幅黑边用普通 View 叠加在 SurfaceView 上层（XPan 黑条 + 90%/80% 安全框）
- **按键按索尼扫描码匹配**（`KeyEvent.getScanCode()`，`ScalarInput` 体系）：
  `232`=ENTER（画幅循环）、`103`=UP（遮幅开关）、`108`=DOWN（安全框开关）、
  `516`=S1 半按（`camera.autoFocus`）、`518`=S2 全按（`camera.takePicture`）、`514`=MENU 退出

## 产物

| 文件 | 说明 |
|---|---|
| `XPanOverlay-1.2.apk` | 已签名的安装包（v1+v2 签名，dex 035，SurfaceView 预览版） |
| `src/` | Java 源码（MainActivity / OverlayView） |
| `build.sh` | 一键重建脚本（Git Bash / WSL / macOS / Linux） |
| `build.ps1` | 一键重建脚本（Windows 原生 PowerShell，推荐） |
| `debug.keystore` | 开发签名密钥（重打包用，密码 xpan1234；被 `.gitignore` 排除，脚本首次运行自动生成） |
| `third_party/recipe-lab-sony-pmca/` | 参考项目源码（配置/预览/按键完整实现） |
| `third_party/openmemories-framework/` | OpenMemories 框架源码（含索尼 scalar API stubs） |

## 安装步骤

### 1. 准备
- A7M2 固件必须为 **4.01**（PMCA 应用机制仅存于此固件；升级官方固件会清除所有自定义 App）。
- 电脑安装 [PMCA-RE](https://github.com/ma1co/PMCA-RE) 工具链。
- Windows：用 [Zadig](https://zadig.akeo.ie/) 把 A7M2 的 USB 驱动替换为 WinUSB。
- Linux / macOS：使用 `pmca-console`。

### 2. 安装（先卸载旧版）
```
pmca-gui → Uninstall 旧版 → Install App → 选择 XPanOverlay-1.2.apk

# Linux / macOS
pmca-console install XPanOverlay-1.2.apk
```

### 3. 使用
相机 PlayMemories 应用列表 → 打开 **XPanOverlay**，取景画面立即出现遮幅。

| 按键（索尼扫描码） | 功能 |
|---|---|
| ENTER (232) | 循环画幅：XPan 2.7:1 → 2.39:1 → 3:2 |
| UP (103) | 遮幅黑边 开 / 关 |
| DOWN (108) | 安全框（90% 动作安全 + 80% 标题安全）开 / 关 |
| S1 半按 (516) | 自动对焦（`camera.autoFocus`） |
| S2 全按 (518) | 拍摄（`camera.takePicture`） |
| MENU (514) / 返回 | 退出，回到相机界面 |

默认：XPan 遮幅开、安全框开。

## 功能与边界（重要）

- 实时取景由 App 自己渲染到 SurfaceView，遮幅/安全框叠加在其上，LCD / EVF 均可见。
- 快门（S2）通过 `camera.takePicture()` 触发相机拍摄流程；若 A7M2 固件不自动落盘 JPEG，需要补 jpeg 回调写卡（下一版可加）。
- **机内 SD 卡录制的视频与照片不含遮幅**：App 图层不进入相机成像编码流，文件仍是原生 3:2 / 16:9 画面。
- **HDMI 输出**：App 自渲染的预览与遮幅是否进入 HDMI 取决于相机系统行为，需要实机验证。
- 若需录制文件自带 XPan 画幅，请使用硬件方案（传感器前插入式遮罩）或后期裁切。

## 风险提示

- 属于非官方侧载（PMCA 逆向机制），索尼官方不认可，检测到会拒绝保修。
- 安装/删除应用不触及系统分区，变砖风险极低；卸载方法：pmca-gui 卸载或恢复官方固件。

## 重建 APK

需要 JDK 8+ 与 Android SDK（platform android-10 + build-tools 25.0.3）。两个脚本都会自动探测
`JAVA_HOME` / `ANDROID_HOME`，探测不到时也可以自动下载。

Windows（原生 PowerShell，不需要 Git Bash）：

```powershell
.\build.ps1                 # 输出 build\XPanOverlay-1.2.apk
.\build.ps1 -Bootstrap      # 顺带下载 cmdline-tools + platform + build-tools
.\build.ps1 -Clean
```

Git Bash / WSL / macOS / Linux：

```bash
./build.sh                  # 输出 build/XPanOverlay-1.2.apk
./build.sh --bootstrap
./build.sh --clean
```

可用环境变量覆盖自动探测：`JAVA_HOME`、`ANDROID_HOME`（或 `ANDROID_SDK_ROOT`）、
`BT_VERSION`（默认 25.0.3）、`PLATFORM`（默认 android-10）。

输出文件名跟随 `AndroidManifest.xml` 里的 `android:versionName`。

### 已在 Windows 上验证

环境：Windows + Microsoft OpenJDK 17 + Android build-tools 25.0.3 + platform android-10。
产出的 `classes.dex` 与本仓库 `XPanOverlay-1.2.apk` 内的 dex **逐字节一致**
（md5 `deb6ba907b38daf84007209c2fcd9a2a`），即新脚本在字节码层面精确复现了原产物。

脚本里为绕开老工具链在新环境下的坑做了三处适配：

| 问题 | 处理 |
|---|---|
| Windows 版 javac 默认按 GBK 读源码，源码含 UTF-8 字符 | 强制 `-encoding UTF-8` |
| `dx`（build-tools ≤ 30）读不了 Java 7 之后的字节码（v52 会报 unsupported class file version） | 用 `--release 7` 出 v51；若装了 build-tools 26+ 则改用 d8 + `--release 8` |
| `apksigner` 25.x 访问 `java.io.Console` 与 `sun.security.*`，被 JDK 9+ 模块系统拦截 | 追加 `--add-opens` / `--add-exports` |
