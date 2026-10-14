#!/bin/zsh
# One-step install: builds Device Battery from source, copies it into Applications and
# starts it. A locally built app is not quarantined, so macOS opens it without a
# Gatekeeper warning. Messages follow the macOS language (English, 한국어, 简体中文).
set -euo pipefail
cd "${0:A:h}/.."

language="$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')"
say() {
  case "$language" in
    ko*) print -r -- "$2" ;;
    zh*) print -r -- "$3" ;;
    *)   print -r -- "$1" ;;
  esac
}

if ! xcrun --find swift >/dev/null 2>&1; then
  say "Swift was not found. Run: xcode-select --install — then run this script again." \
      "Swift를 찾을 수 없습니다. 먼저 xcode-select --install 을 실행한 뒤 이 스크립트를 다시 실행하세요." \
      "未找到 Swift 编译器。请先运行：xcode-select --install，安装完成后再执行本脚本。"
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
say "✅ Installed to $target/$app and started. The widget is in the top-right corner of your screen." \
    "✅ $target/$app 에 설치하고 실행했습니다. 위젯은 화면 오른쪽 위에 있습니다." \
    "✅ 已安装到 $target/$app 并启动，挂件出现在屏幕右上角。"
say "   Right-click the widget → Open at Login to start it automatically." \
    "   위젯을 오른쪽 클릭 → ‘로그인 시 열기’를 켜면 로그인할 때 자동으로 실행됩니다." \
    "   右键挂件 → 勾选「登录时打开」，开机后会自动显示。"
