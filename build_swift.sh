#!/usr/bin/env bash
# 打包 arm64 + x86_64 通用二进制版应用。
#
#   ./build_swift.sh            通用包（默认）
#   ./build_swift.sh --host     只编当前架构，调试时更快
#
# 产物：dist_swift/静态勋章制作.app 与 dist_swift/静态勋章制作-mac-universal.zip
set -euo pipefail

APP_NAME="静态勋章制作"
EXECUTABLE="StaticBadge"
BUNDLE_ID="com.nandieling.static-badge"
SHORT_VERSION="1.0.0"
BUILD_VERSION="1"
MIN_MACOS="12.0"
DIST_DIR="dist_swift"
ICON_FILE="Sources/StaticBadge/Resources/AppIcon.icns"
ICONSET_DIR="${DIST_DIR}/AppIcon.iconset"

cd "$(dirname "$0")"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS only." >&2
  exit 1
fi

ARCH_ARGS=(--arch arm64 --arch x86_64)
if [[ "${1:-}" == "--host" ]]; then
  ARCH_ARGS=(--arch "$(uname -m)")
  shift
fi

# 图标丢了也能重新画出来（内容只依赖系统框架）。
if [[ ! -f "${ICON_FILE}" ]]; then
  echo "==> ${ICON_FILE} 不存在，重新生成图标"
  mkdir -p "${DIST_DIR}" "${ICONSET_DIR}"
  swift tools/make-icon.swift "${ICONSET_DIR}"
  iconutil -c icns "${ICONSET_DIR}" -o "${ICON_FILE}"
  rm -rf "${ICONSET_DIR}"
fi

echo "==> swift build -c release ${ARCH_ARGS[*]}"
swift build -c release "${ARCH_ARGS[@]}"

BIN_DIR="$(swift build -c release "${ARCH_ARGS[@]}" --show-bin-path)"
BIN="${BIN_DIR}/${EXECUTABLE}"
if [[ ! -f "${BIN}" ]]; then
  echo "找不到可执行文件：${BIN}" >&2
  exit 1
fi

APP="${DIST_DIR}/${APP_NAME}.app"
echo "==> 组装 ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${EXECUTABLE}"
cp "${ICON_FILE}" "${APP}/Contents/Resources/AppIcon.icns"
printf 'APPL????' >"${APP}/Contents/PkgInfo"

cat >"${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>图片</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.image</string>
			</array>
		</dict>
	</array>
	<key>CFBundleExecutable</key>
	<string>${EXECUTABLE}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${SHORT_VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_VERSION}</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.graphics-design</string>
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_MACOS}</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>静态勋章制作 ${SHORT_VERSION}</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSSupportsSuddenTermination</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc 签名"
codesign --force --sign - --timestamp=none "${APP}" >/dev/null

echo
echo "Built app: ${APP}"
lipo -info "${APP}/Contents/MacOS/${EXECUTABLE}"
codesign --verify --verbose=1 "${APP}" 2>&1 | tail -1

ZIP="${DIST_DIR}/${APP_NAME}-mac-universal.zip"
echo "Zipping..."
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"
echo "Zip: ${ZIP}"
