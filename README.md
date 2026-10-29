<p align="center">
  <img src="assets/readme/banner-zh-Hans.png" alt="Baby Lock — 给 Mac 键盘的童锁" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Mirr0ch1/BabyLock-macOS/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/Mirr0ch1/BabyLock-macOS/build.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=build" alt="Build"></a>
  <a href="https://github.com/Mirr0ch1/BabyLock-macOS/releases/latest"><img src="https://img.shields.io/github/v/release/Mirr0ch1/BabyLock-macOS?sort=semver&style=for-the-badge&logo=github&logoColor=white&label=release" alt="Latest release"></a>
  <a href="https://github.com/Mirr0ch1/BabyLock-macOS/releases"><img src="https://img.shields.io/github/downloads/Mirr0ch1/BabyLock-macOS/total?style=for-the-badge&logo=github&logoColor=white&label=downloads" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/license-MIT-2ea44f?style=for-the-badge&logo=opensourceinitiative&logoColor=white" alt="MIT license">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 5">
  <img src="https://img.shields.io/badge/SwiftUI-native-0A84FF?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/i18n-5-8A2BE2?style=for-the-badge&logo=googletranslate&logoColor=white" alt="5 languages">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/telemetry-none-2ea44f?style=flat-square" alt="No telemetry">
  <img src="https://img.shields.io/badge/universal-arm64%20%7C%20x86__64-555555?style=flat-square&logo=apple&logoColor=white" alt="Universal binary">
  <img src="https://img.shields.io/badge/menu%20bar-native-8A2BE2?style=flat-square&logo=apple&logoColor=white" alt="Menu bar app">
</p>

<p align="center">
  <b>简体中文</b> · <a href="README.en.md">English</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.fr.md">Français</a> · <a href="README.ru.md">Русский</a>
</p>

<h1 align="center">Baby Lock</h1>

<p align="center">
  <b>给 Mac 键盘的童锁。</b><br>
  孩子在键盘上拍来拍去，你的 Mac 什么都不会做。
</p>

---

## 为什么做这个

我在家办公。女儿喜欢爬到我腿上，指着屏幕，然后非常热情地拍键盘。

大多数时候没什么大事。但偶尔会有手掌压到 `⌘W`，小手指按到电源键，或者一段乱码直接发进聊天窗口。关机太重，锁屏又没法给她看东西，把电脑挪开则会打断当下的兴致。

Baby Lock 是中间方案：**Mac 继续工作，屏幕保持可见，键盘暂时不听话。**

她靠近键盘之前，我从菜单栏打开它；她玩够了，我同时按住左右 `⌘` 三秒，一切恢复。

## 工作原理

1. 点击菜单栏里的 Baby Lock 图标。
2. 选择 **开启 Baby Lock**。
3. 屏幕底部出现一条浮动提示，键盘不再响应。
4. 解锁时，同时按住 **左右 Command 键 3 秒**。

默认情况下桌面保持原样：不黑屏、不切应用、不抢焦点。想擦键盘时，可以在设置里打开 **屏幕变黑**。

## 功能

- 屏蔽所有按键，包括快捷键和媒体键；可保留一个或多个豁免按键（例如用 🌐 Fn 触发语音输入，或添加 `⌃`、`C`、`V` 来保留复制粘贴）。
- 启动时和菜单栏中可检查 GitHub Release 更新，自动下载、校验、安装并重启。
- 锁定失效或更新后，可在权限页一键重置权限并重新授权。
- 可选屏蔽触控板和鼠标的点击、滚动、手势，并隐藏指针。
- 同时按住左右 `⌘` 三秒解锁，带进度环反馈。
- 可选全屏黑屏，默认关闭；支持所有屏幕或仅主屏幕。
- 自动解锁安全计时：5 / 10 / 20 分钟。
- 原生菜单栏应用（`LSUIElement`），不占 Dock。
- 默认跟随系统语言，非支持语言自动回落英语。
- 五种语言：English、简体中文、繁體中文、Français、Русский。
- 不收集分析、不记录按键；唯一的网络请求是检查 GitHub 更新。

## 和 CleanLock 的区别

Baby Lock 基于 [CleanLock](https://github.com/fromtimo/CleanLock) 改写，保留了它可靠的输入封锁内核，并针对有娃家庭做了调整：

| | CleanLock | Baby Lock |
|---|---|---|
| 用途 | 清洁 MacBook | 挡住孩子的误触 |
| 默认画面 | 全屏黑色遮罩 | 桌面保持可见，底部小浮窗 |
| 黑屏 | 始终开启 | 可选，默认关闭 |
| 屏幕范围 | 所有 / 仅主屏幕 | 相同，仅黑屏模式下生效 |
| 指针封锁 | 始终开启 | 可选，默认开启 |
| 语言 | 英语、俄语 | 英语、简体中文、繁體中文、法语、俄语 |
| 图标 | 键盘 + 锁 | 键盘 + 娃娃 |
| 构建 | 本地 Xcode | GitHub Actions（通用二进制） |

## 安装

1. 打开 [最新 Release](https://github.com/Mirr0ch1/BabyLock-macOS/releases)。
2. 下载 `BabyLock-macOS.zip` 并解压。
3. 把 **Baby Lock.app** 拖进 `/Applications`。
4. 当前构建是 ad-hoc 签名，**没有经过 Apple 公证**，首次打开可能被 macOS 拦截。如果提示“已损坏”，在终端执行：

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Baby Lock.app"
   ```

5. 启动 Baby Lock，按引导完成设置。

## 权限

Baby Lock 需要两项 macOS 权限：

- **辅助功能**：开启期间屏蔽键盘和指针事件。
- **输入监控**：识别左右 Command 解锁手势。

两项权限都只在本地使用。不会记录或上传按键；唯一的网络请求是检查 GitHub 更新。可选的豁免按键仅保存在本机偏好设置中。

> 因为发布包是 ad-hoc 签名，替换新版本后 macOS 可能要求重新授权。

如果系统设置里已经勾选，但 Baby Lock 仍提示未授权，说明系统里留下的是旧构建的授权记录。打开权限页，点 **重置权限并重试**：Baby Lock 会清除自己的辅助功能与输入监控记录、重启，然后重新请求授权。

## 设置

- **登录时启动**
- **语言**：跟随系统，或固定为五种语言之一
- **自动解锁**：安全计时（5 / 10 / 20 分钟）
- **锁定触控板和鼠标**：默认开启
- **豁免按键**：锁定期间仍可用；可添加多个按键，组合键需要把每个键分别加进来（例如 `⌃`、`C`、`V`）；如果 Fn 被输入法拦截，可直接点 **绑定 Fn 键**
- **屏幕变黑**：默认关闭，可选择所有屏幕或仅主屏幕
- **检查更新**（菜单栏）：检查 GitHub Release 并安装新版本

## 更新

Baby Lock 启动时会检查一次 GitHub Release。启动检查在后台静默进行：没有更新时菜单栏保持 **检查更新**，只有发现新版本才会直接显示版本号。也可以在菜单栏点 **检查更新**：

- 菜单会保持打开，先显示 **正在检查更新…**；
- 没有更新：显示 **未检测到更新**，3 秒后自动恢复成 **检查更新**；
- 有更新：显示 **有更新 vX.Y.Z — 点击安装**，确认后下载、校验 bundle ID、版本号和签名，替换当前 App，重置权限并自动重启。

更新要求 App 位于 `/Applications` 或 `~/Applications`。由于发布包使用 ad-hoc 临时签名，macOS 可能会在更新后要求重新授权；Baby Lock 会自动打开权限界面，并提供「重置权限并重试」按钮。

## 构建

### GitHub Actions

推送到 `main` 或打 `v*` tag 时，会在 macOS runner 上构建 `arm64 + x86_64` 通用包，ad-hoc 签名后上传 `BabyLock-macOS.zip`。打 tag 还会自动创建 GitHub Release。

### 本地开发

要求：macOS 13+、Xcode 15+。

```bash
open BabyLock.xcodeproj
# 或
./Scripts/run-debug.sh
```

`Scripts/build-debug.sh` 用 `swiftc` 组装 `build/Debug/Baby Lock.app`。`Scripts/reset-dev-state.sh` 会清掉偏好设置和 TCC 授权，方便干净地重测。

重新生成图标和横幅：

```bash
python3 -m pip install cairosvg pillow
python3 Scripts/generate-icons.py
python3 Scripts/generate-banner.py
```

## 本地化

所有界面文案都在标准 `.lproj/Localizable.strings` 里：

```text
BabyLock/Resources/en.lproj/Localizable.strings
BabyLock/Resources/zh-Hans.lproj/Localizable.strings
BabyLock/Resources/zh-Hant.lproj/Localizable.strings
BabyLock/Resources/fr.lproj/Localizable.strings
BabyLock/Resources/ru.lproj/Localizable.strings
```

缺少翻译时会自动回退英语。要新增语言，添加 `.lproj` 目录、在 `BabyLock.xcodeproj` 里注册，并在 `AppLanguage` 中加入对应语言。

## 致谢

Baby Lock 基于 **[CleanLock](https://github.com/fromtimo/CleanLock)** 改写，原作者是 [fromtimo](https://github.com/fromtimo)。输入封锁架构、权限处理和 Command 解锁手势都来自这个项目，非常感谢原作者。

原始 MIT 协议和版权声明均已保留，详见 [LICENSE](LICENSE)。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
