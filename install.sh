#!/usr/bin/env bash
#
# 安装「农历月历」到用户级 plasmoid 目录（无需 root）。
#
# 用法：  ./install.sh
# 卸载：  kpackagetool6 --type Plasma/Applet --remove io.github.helloydh007.lunarcalendar
# ---------------------------------------------------------------------------

set -euo pipefail

ID="io.github.helloydh007.lunarcalendar"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v kpackagetool6 >/dev/null || {
    echo "错误：找不到 kpackagetool6，请先安装 plasma-workspace。" >&2
    exit 1
}

if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qw "$ID"; then
    echo "检测到已安装，执行升级……"
    kpackagetool6 --type Plasma/Applet --upgrade "$SRC"
    echo "✓ 已升级"
else
    kpackagetool6 --type Plasma/Applet --install "$SRC"
    echo "✓ 已安装"
fi

# 刷新组件索引，让「添加小组件」面板立即能看到它
kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

cat <<'EOF'

接下来：
  桌面右键 → 「添加小组件」→ 搜索「农历」→ 拖到桌面

小提示：首次拖入后请把组件拉伸到内容区高度 ≥ 400px，
否则公历数字与农历文字会叠印（每个格子要放两层文字）。

若在「添加小组件」里看不到它，请关闭并重新打开该面板（列表不会实时刷新），
或重启 plasmashell：  systemctl --user restart plasma-plasmashell.service
EOF
