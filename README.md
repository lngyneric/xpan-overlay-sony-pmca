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
| `build.sh` | 一键重建脚本 |
| `debug.keystore` | 开发签名密钥（重打包用，密码 xpan1234） |
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

需要 Android SDK platform-10 + build-tools 25.0.3 + JDK：

```bash
./build.sh
# 输出 build/XPanOverlay-1.0.apk（复制为 XPanOverlay-1.2.apk 交付）
```
