#!/bin/zsh
# One-step install: builds Device Battery from source, copies it into Applications and
# starts it. A locally built app is not quarantined, so macOS opens it without a
# Gatekeeper warning.
set -euo pipefail
cd "${0:A:h}/.."

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "未找到 Swift 编译器。请先运行：xcode-select --install，安装完成后再执行本脚本。"
  exit 1
fi

./scripts/build-app.sh

app="Device Battery.app"
target="/Applications"
[[ -w "$target" ]] || target="$HOME/Applications"
mkdir -p "$target"

# Quit a running copy so the new build replaces it cleanly.
if pgrep -x DeviceBattery >/dev/null; then
  pkill -x DeviceBattery || true
  for _ in {1..25}; do
    pgrep -x DeviceBattery >/dev/null || break
    sleep 0.2
  done
fi

rm -rf "$target/$app"
cp -R "$app" "$target/"
open "$target/$app"

echo ""
echo "✅ 已安装到 $target/$app 并启动，挂件出现在屏幕右上角。"
echo "   右键挂件 → 勾选「登录时打开」，开机后会自动显示。"
