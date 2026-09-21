# 农历月历 · Lunar Calendar (KDE Plasma 6)

一个常驻桌面的月历小组件，通过 KDE 官方的 `alternatecalendar` 日历引擎显示中国农历。

<img src="screenshot.png" width="420" alt="农历月历截图">

> **English:** A desktop calendar plasmoid for KDE Plasma 6 that displays the Chinese lunar
> calendar (农历). It reuses KDE's own `alternatecalendar` calendar plugin engine — the same
> engine behind the Digital Clock's calendar popup — so the lunar data is not reimplemented
> here, and it shares the calendar-system setting with the system tray clock.

## 特性

- 常驻桌面的月历，每个日期下方显示农历（初一、十五……）与节气（白露、秋分、寒露……）
- 农历数据来自 KDE 官方引擎（`plasma-calendar-addons` 提供的 `alternatecalendar` 插件），
  与系统托盘时钟共享同一份配置 —— **不是自己算的**
- 自动刷新：跨天更新「今天」高亮，跨月自动回到当前月
- 纯 QML，无需编译；约 4 MB 内存

## 为什么需要它

在 Plasma 6 里，农历是由**日历事件插件**渲染的：

| 组件 | 农历支持 |
| --- | --- |
| 数字时钟（系统托盘）的弹窗 | ✅ 有 —— 在「配置 → 日历 → 可用插件」里勾选 `alternatecalendar` |
| **独立的「日历」桌面组件** | ❌ 无 —— 它的配置项只有工作时间/周数/紧凑显示，QML 中也不加载日历插件 |
| 本组件 | ✅ 直接复用官方引擎 |

KDE 有一个 2020 年就提出的 feature request（为主日历组件加备用历法支持），至今未合入。
本组件用约 120 行 QML 补上这个缺口。

## 安装

```bash
git clone https://github.com/helloydh007/plasma-lunar-calendar.git
cd plasma-lunar-calendar
./install.sh
```

然后：**桌面右键 → 添加小组件 → 搜索「农历」→ 拖到桌面**。
首次拖入时建议放大到内容区高度 ≥ 400px（见下方「实现要点」第 4 条）。

手动安装等价于：

```bash
kpackagetool6 --type Plasma/Applet --install .
```

卸载：

```bash
kpackagetool6 --type Plasma/Applet --remove io.github.helloydh007.lunarcalendar
```

## 依赖

- KDE Plasma **6.0+**（`X-Plasma-API-Minimum-Version: 6.0`）
- `plasma-workspace` —— 提供 `org.kde.plasma.workspace.calendar`（`MonthView` 组件）
- `plasma-calendar-addons` —— 提供 `alternatecalendar` 农历插件

Debian / Ubuntu：

```bash
sudo apt install plasma-workspace plasma-calendar-addons
```

## 实现要点（踩过的坑）

如果你想基于 `MonthView` 写自己的组件，这四条能省你几个小时。

### 1. `main.qml` 的根元素必须是 `PlasmoidItem`

libPlasmaQuick 里有硬性检查：

```text
The root item of %1 must be of type PlasmoidItem
```

用普通 `Item` 作根，plasmashell 会**拒绝加载并静默移除组件**（只有在手动从组件面板添加时
才会弹出一个报错框）。调试时如果只看日志，容易误判成别的问题。

### 2. 驱动「显示哪个月」的是 `today:`，不是 `currentDate:`

```qml
PlasmaCalendar.MonthView {
    today: root.today      // ✅ 显示月份的驱动入口
    // currentDate: ...    // ❌ 这是「被选中的日期」，由组件内部在用户点击某天时赋值
}
```

传错属性会让日历后端停在未初始化的 `0` 年，整月显示成 `-5 -4 -3 … 36` 这种负数日期。
数字时钟传的就是 `today`。

### 3. `today` 必须是「活」的

```qml
property date today: new Date()      // ❌ 只在组件创建时求值一次
```

QML 里裸的 `new Date()` 不会自己前进。组件长期不重建（plasmashell 连续运行数天/数周）后，
「今天」高亮会停在组件创建那天，跨月后显示的仍是上个月。

官方组件的做法是把它绑在时钟数据源上：

```qml
P5Support.DataSource {
    interval: 60000
    intervalAlignment: P5Support.Types.AlignToMinute
}
MonthView { today: dataSource.data["Local"]["DateTime"] }
```

本组件用相同周期（60 秒）的 `Timer` 达到同样效果，并且额外做了**跨月重建**：日历后端的
`today` 与 `displayedDate` 是**相互独立**的两个属性，`today` 前进不会带着显示月份走，而
`MonthView` 没有公开的「跳转到某月」接口（`selectedMonth` / `selectedYear` 都是只读别名，
`resetToToday` 是内部实现），因此跨月时重建一次表示层让日历回到当前月。

### 4. 内容区高度 ≥ 400px

每个日期格子要放下两层文字（公历数字 + 农历），高度不足时两层会叠印在一起。

## 已知限制

- 只在**中国农历**下做了验证。引擎本身也支持希伯来历、伊斯兰历等，改系统托盘时钟的
  日历设置即可共享同一份配置。
- 跨月时如果你正翻看其它月份，视图会回到当前月（每月最多一次）。
- 桌面容器的初始摆放可能给组件一个很小的尺寸，拖入后请自行拉伸。

## 许可

GPL-2.0-or-later —— 与它所复用的 KDE 组件保持一致。
