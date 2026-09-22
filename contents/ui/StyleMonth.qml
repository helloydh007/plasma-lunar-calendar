/*
 * 显示样式：整月网格（原来的样子）
 *
 * 这个文件原来是 main.qml 里的一个 Component，拆出来是为了和另外四个样式
 * 平级；行为没有变化：
 *   · 中间是官方 MonthView（农历文字由 alternatecalendar 插件提供）
 *   · 左侧是可选的「学期周数」列，叠在网格左边
 *   · 上面再叠一层法定节假日标记（休 / 班）
 *
 * 日期一律取自 main.qml 传进来的 cells（同一个独立日历后端算出来的 42 天），
 * 不再从 MonthView 的 daysModel 里读 —— 这样五个样式共用一份日期数据，
 * 也就没有了「换月时读到的还是上个月」这类陈旧数据问题。
 *
 * ── 格子几何（勿硬编码像素，全部由 MonthView 自己报）──
 *   cellWidth    = floor((width - (columns+1)*borderWidth) / columns)
 *   第 j 列左边界 = borderWidth + j * (cellWidth + borderWidth)
 *   第 i 行上边界 = viewHeader.height + cellHeight + 2*borderWidth
 *                  + i * (cellHeight + borderWidth)
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.workspace.calendar as PlasmaCalendar

import "termweek.js" as TermWeek

Item {
    id: view

    // ── 输入（main.qml 传入）──
    property var cells: []              // 42 格：{ year, month, day, dayText, lunar, full, isTerm }
    property var cellHolidays: []       // 与 cells 等长；null | { type, name }
    property bool termWeeksVisible: false
    property var termStartDate: null    // Date 或 null
    property bool holidaysVisible: true
    property var eventPluginsManager: null
    property date today: new Date()

    // MonthView 有「日 / 月 / 年」三种视图（内部 swipeView.currentIndex 为 0/1/2）。
    // 周数列与节假日标记都叠在「日视图」网格上、用的是日视图的格子几何，
    // 因此非日视图时必须一并隐藏，否则它们会固定在原位置不动。
    //
    // 注意：monthView 只在本文件的作用域里可见，所以这个属性必须定义在这里。
    // 定义到别的文件（比如 main.qml 的 PlasmoidItem 层级）会得到 ReferenceError，
    // 而失败的绑定会让 visible 停在默认值 true —— 症状就是「切视图后标记不消失」。
    readonly property bool dayView: monthView.currentIndex === 0

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── 学期周数列 ────────────────────────────────────────
        Item {
            id: weekColumn

            Layout.fillHeight: true
            Layout.preferredWidth: view.termWeeksVisible && view.dayView
                ? Math.max(24, Math.round(monthView.cellHeight * 0.62))
                : 0
            visible: view.termWeeksVisible && view.dayView
            clip: true

            // 表头位置的「周」字提示，避免与 ISO 周数混淆
            PlasmaComponents.Label {
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

                        // 每行起始日 = 该行第一格（索引 index*7）
                        readonly property var rowStart: view.cells[index * 7] || null

                        text: {
                            if (!rowStart) {
                                return "";
                            }
                            const d = new Date(rowStart.year, rowStart.month - 1, rowStart.day);
                            const w = TermWeek.termWeekOf(d, view.termStartDate,
                                Qt.locale().firstDayOfWeek);
                            return w >= 1 ? String(w) : "";
                        }

                        PlasmaComponents.ToolTip.delay: 600
                        PlasmaComponents.ToolTip.visible: hoverHandler.hovered && text !== ""
                        PlasmaComponents.ToolTip.text: {
                            if (!rowStart) {
                                return "";
                            }
                            const d = new Date(rowStart.year, rowStart.month - 1, rowStart.day);
                            const w = TermWeek.termWeekOf(d, view.termStartDate,
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

        // ── 官方月历 + 节假日标记 ──────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PlasmaCalendar.MonthView {
                id: monthView

                anchors.fill: parent

                eventPluginsManager: view.eventPluginsManager

                // 不要改成 currentDate：那是「被选中的日期」，
                // 不是显示月份的驱动入口。
                today: view.today

                // 内建的 ISO 周数列保持关闭——自定义周数列见上。
                showWeekNumbers: false
            }

            // 法定节假日（休）/ 调休上班（班）标记层。
            // 官方网格的文字无法注入，所以在格子上叠一层自己的标记。
            Item {
                id: holidayLayer

                anchors.fill: parent
                visible: view.holidaysVisible && view.dayView

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

                        readonly property var holiday: view.cellHolidays[index] || null

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
