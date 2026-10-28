#!/bin/bash
# GitSpace MVP 打包脚本：release 构建 → 组装 .app（ad-hoc 签名）→ 产出 DMG
# 用法：scripts/package-dmg.sh [arch ...]    默认 arm64 x86_64
# 产物：dist/GitSpace-<version>-<arch>.dmg
# 注意：ad-hoc 签名仅本机可无警告运行；对外分发需 Developer ID 签名 + 公证（TechStack §12，M1 打磨）。
set -euo pipefail

VERSION="0.1.0"
APP_NAME="GitSpace"
BUNDLE_ID="dev.gitspace.GitSpace"   # 占位：正式 Bundle ID 随 MRD 17.2-4 商标/命名决策调整
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
ARCHS=("$@")
[ ${#ARCHS[@]} -eq 0 ] && ARCHS=(arm64 x86_64)
# 架构白名单，防止任意参数拼入命令
for a in "${ARCHS[@]}"; do
  case "$a" in
    arm64|x86_64) ;;
    *) echo "错误：不支持的架构 \"$a\"（仅允许 arm64 / x86_64）"; exit 1 ;;
  esac
done

mkdir -p "$DIST"

for arch in "${ARCHS[@]}"; do
  echo "==> [1/4] swift build -c release --arch $arch"
  swift build -c release --arch "$arch" --package-path "$ROOT"
  BIN_DIR="$(swift build -c release --arch "$arch" --package-path "$ROOT" --show-bin-path)"
  BIN="$BIN_DIR/GitSpaceApp"
  [ -x "$BIN" ] || { echo "错误：找不到二进制 $BIN"; exit 1; }
  file "$BIN"

  echo "==> [2/4] 组装 $APP_NAME.app ($arch)"
  STAGE="$DIST/staging-$arch"
  APP="$STAGE/$APP_NAME.app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
  printf 'APPL????' > "$APP/Contents/PkgInfo"

  echo "==> [3/4] ad-hoc 签名校验"
  codesign --force --sign - "$APP"
  codesign --verify --strict "$APP"

  echo "==> [4/4] hdiutil 打 DMG"
  ln -sfn /Applications "$STAGE/Applications"
  hdiutil create -volname "$APP_NAME $VERSION ($arch)" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME-$VERSION-$arch.dmg"
done

echo ""
echo "==> 产物清单："
ls -lh "$DIST"/*.dmg
