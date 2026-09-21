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
import "holidays.js" as Holidays
import "holidays-update.js" as HolidaysNet

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
    readonly property bool holidaysVisible: Plasmoid.configuration.showHolidays


    // 联网获取到的节假日数据（只含内置数据未覆盖的年份）。配置里的 JSON 串
    // 解析失败时静默降级为空缓存，此时仅使用内置数据。
    readonly property var holidayCache: HolidaysNet.parseCache(Plasmoid.configuration.holidayCache)

    // 第 index 个日期格子（0 … rows*cols-1）对应的日期。
    // 月历网格固定 7 列；行首日期由下方 Repeater 从官方 daysModel 读入，
    // 列偏移按天数相加，Date 会自行处理跨月进位。
    function cellDateAt(index) {
        const rowStart = rowStartDates[Math.floor(index / 7)];
        if (!rowStart) {
            return null;
        }
        return new Date(rowStart.getFullYear(), rowStart.getMonth(),
                        rowStart.getDate() + (index % 7));
    }

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

    // 自动更新：仅当配置为 auto 时才动作。每小时核对一次节律，
    // 真正联网拉取受 AUTO_CHECK_INTERVAL_DAYS（30 天）限制，
    // 且只会去取「内置数据与缓存都没有的年份」。
    Timer {
        interval: 3600000
        running: Plasmoid.configuration.holidayUpdateMode === "auto"
        repeat: true
        triggeredOnStart: true

        onTriggered: {
            const now = new Date();
            if (!HolidaysNet.shouldAutoCheck(root.holidayCache, now)) {
                return;
            }
            HolidaysNet.runUpdate(root.holidayCache, now, Holidays.COVERED_YEARS, null, function (result) {
                if (result.fetched.length > 0) {
                    Plasmoid.configuration.holidayCache = HolidaysNet.serializeCache(result.cache);
                    console.log("holidays: 自动更新成功，年份 " + result.fetched.join(", "));
                } else {
                    // 即便没取到也要记录检查时间，避免每小时重复尝试
                    Plasmoid.configuration.holidayCache = HolidaysNet.serializeCache(result.cache);
                    console.log("holidays: 自动检查完成，无新增（" + result.messages.join("；") + "）");
                }
            });
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
            id: calendarRow

            spacing: 0

            // MonthView 有「日 / 月 / 年」三种视图（内部 swipeView.currentIndex 为 0/1/2，
            // 对应 DayView / MonthView / YearView）。周数列与节假日标记都叠在「日视图」
            // 网格上、用的是日视图的格子几何，因此非日视图时必须一并隐藏，
            // 否则它们会固定在原位置不动。
            //
            // 注意：本属性必须定义在这个 Component 内部——monthView 只在此作用域可见，
            // 定义在 PlasmoidItem 层级会得到 ReferenceError，而失败的绑定会让
            // visible 停留在默认值 true，症状正是「切视图后标记不消失」。
            readonly property bool dayView: monthView.currentIndex === 0

            // ── 自定义周数列 ──────────────────────────────────────────
            Item {
                id: weekColumn

                Layout.fillHeight: true
                Layout.preferredWidth: root.termWeeksVisible && calendarRow.dayView
                    ? Math.max(24, Math.round(monthView.cellHeight * 0.62))
                    : 0
                visible: root.termWeeksVisible && calendarRow.dayView
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

            // ── 官方月历 + 节假日标记 ──────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                PlasmaCalendar.MonthView {
                    id: monthView

                    anchors.fill: parent

                    eventPluginsManager: eventPluginsManager

                    // 不要改成 currentDate：那是「被选中的日期」，
                    // 不是显示月份的驱动入口。
                    today: root.today

                    // 内建的 ISO 周数列保持关闭——自定义周数列见上。
                    showWeekNumbers: false
                }

                // 法定节假日（休）/ 调休上班（班）标记层。
                // 官方网格的文字无法注入，所以在格子上叠一层自己的标记。
                Item {
                    id: holidayLayer

                    anchors.fill: parent
                    visible: root.holidaysVisible && calendarRow.dayView

                    // 按 DaysCalendar 的公式反推格子几何，勿硬编码像素：
                    //   cellWidth    = floor((width - (columns+1)*borderWidth) / columns)
                    //   第 j 列左边界 = borderWidth + j * (cellWidth + borderWidth)
                    //   第 i 行上边界 = viewHeader.height + cellHeight + 2*borderWidth
                    //                  + i * (cellHeight + borderWidth)
                    readonly property int cols: monthView.columns
                    readonly property int bw: monthView.borderWidth
                    readonly property int cw: Math.max(1, Math.floor((monthView.width - (cols + 1) * bw) / cols))
                    readonly property int ch: monthView.cellHeight
                    readonly property int gridTop: monthView.viewHeader.height + ch + 2 * bw

                    Repeater {
                        model: holidayLayer.cols * monthView.rows

                        delegate: Item {
                            id: cellMarker

                            required property int index

                            readonly property var cellDate: root.cellDateAt(index)
                            // 缓存优先（联网获取到的年份），未命中回落到内置数据表
                            readonly property var holiday: {
                                if (!cellDate) {
                                    return null;
                                }
                                const y = cellDate.getFullYear();
                                const m = cellDate.getMonth() + 1;
                                const d = cellDate.getDate();
                                return HolidaysNet.statusFromCache(y, m, d, root.holidayCache)
                                    || Holidays.statusFor(y, m, d);
                            }

                            // 覆盖整个格子（而不只是小标记），这样悬停整格都能看提示。
                            // 未命中节假日的格子不可见 → 不拦截任何鼠标事件。
                            width: holidayLayer.cw
                            height: holidayLayer.ch
                            x: holidayLayer.bw
                                + (index % holidayLayer.cols) * (holidayLayer.cw + holidayLayer.bw)
                            y: holidayLayer.gridTop
                                + Math.floor(index / holidayLayer.cols) * (holidayLayer.ch + holidayLayer.bw)
                            visible: holiday !== null

                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: 1
                                anchors.rightMargin: 1

                                width: Math.min(18, Math.max(12, Math.round(cellMarker.width * 0.5)))
                                height: Math.max(9, Math.round(cellMarker.height * 0.22))
                                radius: 3
                                color: cellMarker.holiday && cellMarker.holiday.type === "off"
                                    ? "#c0392b"   // 放假
                                    : "#6b7280"   // 调休上班

                                PlasmaComponents.Label {
                                    anchors.centerIn: parent
                                    color: "white"
                                    font.pixelSize: Math.max(7, Math.round(parent.height * 0.7))
                                    text: cellMarker.holiday && cellMarker.holiday.type === "off"
                                        ? i18n("休") : i18n("班")
                                }
                            }

                            HoverHandler {
                                id: markerHover
                            }

                            PlasmaComponents.ToolTip.delay: 400
                            PlasmaComponents.ToolTip.visible: markerHover.hovered
                            PlasmaComponents.ToolTip.text: cellMarker.holiday
                                ? (cellMarker.holiday.type === "off"
                                    ? i18n("%1：放假", cellMarker.holiday.name)
                                    : i18n("%1：调休上班", cellMarker.holiday.name))
                                : ""
                        }
                    }
                }
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
