/*
 * 农历月历 —— 桌面常驻月历，农历数据来自 KDE 官方 alternatecalendar
 * 插件（plasma-calendar-addons），与系统托盘时钟的农历完全同源。
 *
 * ── 四个必须遵守的约束（都踩过坑，改代码前先读）──
 *  1. root 必须是 PlasmoidItem。libPlasmaQuick 有硬性检查
 *     "The root item of %1 must be of type PlasmoidItem"，
 *     用普通 Item 作根会被 plasmashell 拒绝加载并静默移除组件。
 *  2. 驱动「显示哪个月」的是 today（对应内部 backend 的 today），
 *     与数字时钟的用法一致。currentDate 是「被选中的日期」，由组件
 *     内部在用户点击某天时赋值，不是初始化入口；不设 today 会让后端
 *     停在未初始化的 0 年，整月显示成负数日期。
 *  3. 每个月格子要容纳「公历数字 + 农历文字」两层文字，内容区高度
 *     不足约 400px 时两层会叠印在一起。
 *  4. 自定义周数列（见下）靠 MonthView 暴露的 cellHeight / borderWidth /
 *     viewHeader / rows 来对齐，勿硬编码像素值。
 *
 * ── 自动刷新 ──
 *   today 若在创建时只求值一次，长时间不重启 plasmashell 就会停在过去：
 *   「今天」高亮不再移动，跨月后显示的还是上个月。下面用每分钟检查一次
 *   的 Timer 修正。
 *
 *   日历后端的 today 与 displayedDate 是相互独立的两个属性（见
 *   calendarplugin.qmltypes），因此更新 today 只更新高亮判定，不会移动
 *   用户正在浏览的月份；只有真正跨月时才重建表示层，让日历回到当前月。
 *
 * ── 自定义「学期周数」列 ──
 *   MonthView 内建的周数列只支持 ISO 周数，无法注入自定义编号，所以这一列
 *   自己画，叠在 MonthView 左侧：
 *     · 每行的周次 = 该行起始日（周一）落在「以起始日为第 1 周」序列中的位置
 *     · 行起始日直接从官方 daysModel 读（索引 0,7,14,21,28,35 即每行首日），
 *       不做推算，因此与历法/月首无关地准确
 *     · 列的纵向位置用 MonthView 自己的几何参数推出：
 *       viewHeader.height + cellHeight + 2 * borderWidth 即为首行顶端
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.workspace.calendar as PlasmaCalendar

import "termweek.js" as TermWeek

PlasmoidItem {
    id: root

    // 当前日期。必须可变：创建时取一次的静态值会随时间变旧。
    property date today: new Date()

    // 表示层重建计数器。跨月时 +1，触发日历重建以显示新的当前月。
    property int generation: 0

    // 每行起始日（索引 0…rows-1），由下方 Repeater 从 daysModel 填充。
    property var rowStartDates: []

    // 配置
    readonly property var termStartDate: TermWeek.parseIsoDate(Plasmoid.configuration.termStart)
    readonly property bool termWeeksVisible: Plasmoid.configuration.showTermWeeks
        && termStartDate !== null

    // 首次拖到桌面时的默认尺寸。注意桌面容器存下来的几何值会比实际
    // 内容区大约 48px，所以 ItemGeometries 里存 464x464 左右较合适。
    implicitWidth: 420
    implicitHeight: 410

    // 每分钟核对一次日期：跨天则更新「今天」高亮，跨月则额外重建表示层。
    Timer {
        interval: 60000
        running: true
        repeat: true

        onTriggered: {
            const now = new Date();
            const dayChanged = now.getDate() !== root.today.getDate();
            const monthChanged = now.getMonth() !== root.today.getMonth()
                || now.getFullYear() !== root.today.getFullYear();

            if (dayChanged || monthChanged) {
                root.today = now;
            }
            if (monthChanged) {
                root.generation += 1;
            }
        }
    }

    fullRepresentation: Item {
        id: representation

        implicitWidth: 420
        implicitHeight: 410

        Loader {
            id: calendarLoader

            anchors.fill: parent
            sourceComponent: calendarComponent

            // 跨月时重建整棵子树：新的 today 生效，且日历回到当前月。
            Connections {
                target: root

                function onGenerationChanged() {
                    calendarLoader.active = false;
                    calendarLoader.active = true;
                }
            }
        }
    }

    Component {
        id: calendarComponent

        RowLayout {
            spacing: 0

            // ── 自定义周数列 ──────────────────────────────────────────
            Item {
                id: weekColumn

                Layout.fillHeight: true
                Layout.preferredWidth: root.termWeeksVisible
                    ? Math.max(24, Math.round(monthView.cellHeight * 0.62))
                    : 0
                clip: true

                // 从官方 daysModel 读每一行的起始日（索引 0,7,14,21,28,35）。
                // 放在这里而不是 MonthView 内部，是因为 MonthView 用内部
                // GridLayout 排布子项，往里加东西会打乱它的布局。
                Repeater {
                    model: monthView.daysModel

                    delegate: Item {
                        required property int index
                        required property var model

                        visible: false
                        width: 0
                        height: 0

                        Component.onCompleted: {
                            if (index % 7 === 0) {
                                const arr = root.rowStartDates.slice();
                                arr[Math.floor(index / 7)] =
                                    new Date(model.yearNumber, model.monthNumber - 1, model.dayNumber);
                                root.rowStartDates = arr;
                            }
                        }
                    }
                }

                // 表头位置的「周」字提示，避免与 ISO 周数混淆
                PlasmaComponents.Label {
                    id: weekHeaderHint

                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: monthView.viewHeader.height
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: i18n("周")
                    opacity: 0.45
                    font.pixelSize: Math.max(9, Math.round(monthView.cellHeight * 0.28))
                }

                Column {
                    id: weekRows

                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    // 与日历网格首行对齐：头部 + 星期名行 + 上下两条边框线
                    anchors.topMargin: monthView.viewHeader.height
                        + monthView.cellHeight + 2 * monthView.borderWidth
                    spacing: monthView.borderWidth

                    Repeater {
                        model: monthView.rows

                        delegate: PlasmaComponents.Label {
                            required property int index

                            width: weekColumn.width
                            height: monthView.cellHeight
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: 0.8
                            font.pixelSize: Math.max(9, Math.round(monthView.cellHeight * 0.30))

                            text: {
                                const d = root.rowStartDates[index];
                                if (!d) {
                                    return "";
                                }
                                const w = TermWeek.termWeekOf(d, root.termStartDate,
                                    Qt.locale().firstDayOfWeek);
                                return w >= 1 ? String(w) : "";
                            }

                            PlasmaComponents.ToolTip.delay: 600
                            PlasmaComponents.ToolTip.visible: hoverHandler.hovered && text !== ""
                            PlasmaComponents.ToolTip.text: {
                                const d = root.rowStartDates[index];
                                if (!d) {
                                    return "";
                                }
                                const w = TermWeek.termWeekOf(d, root.termStartDate,
                                    Qt.locale().firstDayOfWeek);
                                return w >= 1
                                    ? i18n("第 %1 周（自 %2 起）", w, Qt.formatDate(d, "M月d日"))
                                    : "";
                            }

                            HoverHandler {
                                id: hoverHandler
                            }
                        }
                    }
                }
            }

            // ── 官方月历 ──────────────────────────────────────────────
            PlasmaCalendar.MonthView {
                id: monthView

                Layout.fillWidth: true
                Layout.fillHeight: true

                eventPluginsManager: eventPluginsManager

                // 不要改成 currentDate：那是「被选中的日期」，
                // 不是显示月份的驱动入口。
                today: root.today

                // 内建的 ISO 周数列保持关闭——自定义周数列见上。
                showWeekNumbers: false
            }
        }
    }

    PlasmaCalendar.EventPluginsManager {
        id: eventPluginsManager

        // 只加载 alternatecalendar 这一个日历事件插件。它的历法
        // 选择默认跟随系统 locale（zh_CN → 中国农历），与托盘
        // 时钟未写配置时的行为一致。
        enabledPlugins: ["alternatecalendar"]
    }
}
