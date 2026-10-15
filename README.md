# 静态勋章制作

使用图形界面裁剪圆形勋章：选择一张图片，拖动/缩放正方形裁剪框（内切圆会同步显示），一键导出圆形透明背景的 WebP。
能直接裁剪圆形的软件比较少，PS又比较大，所以写了这个软件。
![静态勋章制作](Snipaste_2026-01-09_10-49-21.png)

## 功能

- 添加图片并显示
- 正方形裁剪框：可拖动/缩放，保持正方形且不超出原图
- 圆形裁剪框：内切正方形裁剪框（仅用于预览/导出遮罩）
- 选择保存目录（默认与原图同目录）
- 运行：按正方形裁剪并将圆形外区域置为透明，导出 WebP

导出文件默认命名为 `原文件名.webp`；若已存在，会自动追加 `_1`、`_2` 后缀避免覆盖。

## Swift 版（当前实现）

- Swift 5 + AppKit，没有第三方依赖；核心逻辑（裁剪几何、导出、命名）在 `StaticBadgeCore`，可单独测试。
- 产物是 arm64 + x86_64 通用二进制，Apple 芯片和 Intel Mac 都能直接运行，最低系统 macOS 12。
- WebP 编码内嵌了 libwebp 1.5.0 源码：macOS 的 ImageIO 不支持写 WebP（`CGImageDestinationCopyTypeIdentifiers()` 的列表里没有 `public.webp`），所以只能自带编码器。解码仍走系统的 ImageIO，png / jpg / bmp / tiff / webp / heic 都能读，EXIF 方向会自动摆正。

### 开发与测试

```bash
swift build                              # 调试构建
swift test                               # 19 项单元测试（裁剪规则、圆形遮罩、方向、命名）
swift run                                # 直接跑界面，不需要先打包
```

### 打包

```bash
chmod +x build_swift.sh
./build_swift.sh            # 通用包（arm64 + x86_64）
./build_swift.sh --host     # 只编当前架构，调试时更快
```

产物：

- `dist_swift/静态勋章制作.app`
- `dist_swift/静态勋章制作-mac-universal.zip`（建议分发这个压缩包）

打包脚本会做通用构建、组装 `.app`、写入 `Info.plist` 并做 ad-hoc 签名。未签名应用在其他电脑上首次打开可能会被 Gatekeeper 拦截，需要右键“打开”或在系统设置中允许。

应用图标取自根目录的 `1.webp`：打包时用 `tools/make-icns.swift` 缩放出 10 个尺寸，再交给 `iconutil` 合成 `Sources/StaticBadge/Resources/AppIcon.icns`。图标源图按 `1.icns`、`1.webp`、`1.png` 的顺序查找，三者都没有时用 `tools/make-icon.swift` 画一张兜底图标。换图标只要替换根目录的源图，然后重新执行 `./build_swift.sh`。

### 目录

```text
Package.swift                     Swift 工程定义
Sources/CWebP/                    内嵌的 libwebp 源码 + 一层精简 C 封装
Sources/StaticBadgeCore/          裁剪几何、图片解码、圆形遮罩导出、文件名递增
Sources/StaticBadge/              AppKit 界面（窗口、菜单、画布）
Tests/StaticBadgeCoreTests/       核心逻辑测试
tools/make-icns.swift             由源图生成 10 个尺寸的应用图标
tools/make-icon.swift             画一张兜底应用图标
build_swift.sh                    通用包打包脚本
1.webp                            应用图标源图（不参与界面显示）
```

### 不入库的文件

`.gitignore` 已经排除掉构建产物和本地环境，提交时不用管：

- Swift：`.build/`、`dist_swift/`、`DerivedData/`、`Package.resolved`
- Python：`.venv/`、`dist_x64/`、`build_x64/`、`.pyinstaller/`、`__pycache__/`、`*.pyc`
- 系统与其它：`.DS_Store`；本地图标 `1.icns`（想固定图标就换成提交 `1.webp` 这条路）

## Python 版（原实现）

```bash
python -m venv .venv
source .venv/bin/activate   # win 运行  .venv\Scripts\activate
pip install -r requirements.txt
python main.py
```

### 打包（macOS x64）

```bash
chmod +x build_macos_x64.sh
./build_macos_x64.sh
```

图标：将 `1.icns` 放在项目根目录（脚本会自动打包为应用图标）。

产物：

- `dist_x64/静态勋章制作.app`
- `dist_x64/静态勋章制作-mac-x64.zip`（建议分发这个压缩包）
