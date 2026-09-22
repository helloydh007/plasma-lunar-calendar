/*
 * 显示样式：迷你月历 + 今日
 *
 * 左边一个小月历（只有公历日号，今天高亮，节假日那天一个色点），
 * 右边今天的详情（星期、农历、学期周次、放不放假）。
 * 面积约为整月网格的一半，信息量接近「今日」。
 *
 * 小月历是自己画的，没有用官方 MonthView：那个会连农历文字一起画，
 * 在这个尺寸下塞不下，而且它的字号是按格子高度算的，缩小后会糊成一团。
 *
 * 窄的时候（宽高比 < 1.15）自动改成上下排。
 * 外层几何自己算，理由见 StyleToday.qml 顶部注释。
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: view

    property var cells: []              // 42 格（当月网格）
    property var cellHolidays: []       // 与 cells 等长
    property int todayIndex: -1
    property var todayHoliday: null
    property bool holidaysVisible: true
    property string termWeekLabel: ""
    property real cardOpacity: 1

    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color onAccent: Kirigami.Theme.highlightedTextColor
    readonly property color hairline: Qt.rgba(Kirigami.Theme.textColor.r,
                                              Kirigami.Theme.textColor.g,
                                              Kirigami.Theme.textColor.b,
                                              0.15 * view.cardOpacity)
    readonly property color cardFill: Qt.rgba(Kirigami.Theme.alternateBackgroundColor.r,
                                              Kirigami.Theme.alternateBackgroundColor.g,
                                              Kirigami.Theme.alternateBackgroundColor.b,
                                              view.cardOpacity)
    readonly property color dimText: Qt.rgba(Kirigami.Theme.textColor.r,
                                             Kirigami.Theme.textColor.g,
                                             Kirigami.Theme.textColor.b, 0.7)
    readonly property color faintText: Qt.rgba(Kirigami.Theme.textColor.r,
                                               Kirigami.Theme.textColor.g,
                                               Kirigami.Theme.textColor.b, 0.45)

    readonly property int radius: Kirigami.Units.cornerRadius + 3

    readonly property date todayDate: {
        const c = view.todayIndex >= 0 ? view.cells[view.todayIndex] : null;
        return c ? new Date(c.year, c.month - 1, c.day) : new Date();
    }
    readonly property int currentMonth: view.todayDate.getMonth() + 1
    readonly property int currentYear: view.todayDate.getFullYear()
    readonly property string monthTitle: Qt.locale()
        .standaloneMonthName(view.todayDate.getMonth(), Locale.LongFormat)
    readonly property string weekdayText: Qt.locale()
        .dayName(view.todayDate.getDay(), Locale.LongFormat)
    readonly property var todayCellData: view.todayIndex >= 0
        ? view.cells[view.todayIndex] : null
    // 开关关掉时当作今天没有节假日：徽章和详情里那句「放假」一起消失
    readonly property var shownHoliday: view.holidaysVisible ? view.todayHoliday : null

    // ── 几何 ──
    readonly property real margin: Kirigami.Units.largeSpacing
    readonly property real gap: Kirigami.Units.largeSpacing
    readonly property real contentW: Math.max(60, view.width - 2 * view.margin)
    readonly property real contentH: Math.max(60, view.height - 2 * view.margin)
    readonly property bool stacked: view.width < view.height * 0.9
    readonly property real leftW: view.stacked
        ? view.contentW : Math.max(110, Math.round((view.contentW - view.gap) * 0.52))
    readonly property real leftH: view.stacked
        ? Math.max(70, Math.round((view.contentH - view.gap) * 0.56)) : view.contentH

    // ── 小月历 ────────────────────────────────────────────────
    Rectangle {
        id: miniPanel

        x: view.margin
        y: view.margin
        width: view.leftW
        height: view.leftH

        color: view.cardFill
        radius: view.radius
        border.width: 1
        border.color: view.hairline

        readonly property real pad: Kirigami.Units.smallSpacing
        readonly property real titleH: Math.max(11, Kirigami.Theme.smallFont.pixelSize + 2)
        readonly property real headerH: Math.max(10, Kirigami.Theme.smallFont.pixelSize)
        readonly property real innerW: Math.max(1, width - 2 * pad)
        readonly property real innerH: Math.max(1, height - 2 * pad)
        readonly property int rowCount: Math.max(6, Math.ceil(view.cells.length / 7))
        // 格子取正方：宽高两个方向都塞得下，取小的那个；多出来的留白，
        // 这样面板是瘦高还是矮胖都不会把格子拉成长条。
        readonly property real cellSize: Math.max(9, Math.min(innerW / 7,
            (innerH - titleH - headerH) / rowCount))
        readonly property real gridW: cellSize * 7
        readonly property real gridH: cellSize * rowCount
        readonly property real gridX: Math.round((width - gridW) / 2)
        readonly property real gridY: Math.max(pad, Math.round(
            (height - (titleH + headerH + gridH)) / 2) + titleH + headerH)

        // 月份标题
        PlasmaComponents.Label {
            id: miniTitle

            x: miniPanel.gridX
            y: miniPanel.gridY - miniPanel.headerH - miniPanel.titleH
            width: miniPanel.gridW
            height: miniPanel.titleH
            verticalAlignment: Text.AlignVCenter
            text: view.monthTitle
            font.bold: true
            font.pixelSize: Math.max(9, Kirigami.Theme.smallFont.pixelSize)
        }

        // 星期名行
        Row {
            id: miniHeader

            x: miniPanel.gridX
            y: miniPanel.gridY - miniPanel.headerH
            width: miniPanel.gridW
            height: miniPanel.headerH

            Repeater {
                model: 7

                delegate: PlasmaComponents.Label {
                    required property int index

                    width: miniPanel.cellSize
                    height: miniPanel.headerH
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: view.faintText
                    font.pixelSize: Math.max(7, Math.min(
                        Math.round(Kirigami.Theme.smallFont.pixelSize * 0.9),
                        Math.round(miniPanel.cellSize * 0.30)))
                    text: Qt.locale().dayName((Qt.locale().firstDayOfWeek + index) % 7,
                                              Locale.ShortFormat)
                }
            }
        }

        // 日号网格
        Grid {
            id: miniGrid

            x: miniPanel.gridX
            y: miniPanel.gridY
            columns: 7
            spacing: 0

            Repeater {
                model: view.cells

                delegate: Item {
                    id: miniCell

                    required property int index
                    required property var modelData

                    readonly property var cell: modelData
                    readonly property bool isToday: index === view.todayIndex
                    readonly property bool inMonth: cell
                        && cell.year === view.currentYear && cell.month === view.currentMonth
                    readonly property var hol: view.holidaysVisible
                        ? (view.cellHolidays[index] || null) : null

                    width: miniPanel.cellSize
                    height: miniPanel.cellSize

                    // 今天：高亮块（不参与 cardOpacity）
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.max(10, Math.min(parent.width, parent.height) - 2)
                        height: width
                        radius: width / 2
                        visible: miniCell.isToday
                        color: view.accent
                    }

                    PlasmaComponents.Label {
                        anchors.centerIn: parent
                        text: miniCell.cell ? miniCell.cell.dayText : ""
                        font.pixelSize: Math.max(7, Math.min(15,
                            Math.round(miniCell.height * 0.52)))
                        color: {
                            if (miniCell.isToday) {
                                return view.onAccent;
                            }
                            if (!miniCell.inMonth) {
                                return view.faintText;
                            }
                            if (miniCell.hol && miniCell.hol.type === "off") {
                                return "#c0392b";
                            }
                            return Kirigami.Theme.textColor;
                        }
                    }

                    // 节假日色点（今天已经有高亮块了，不再叠点）
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        width: Math.max(3, Math.round(parent.height * 0.12))
                        height: width
                        radius: width / 2
                        visible: miniCell.hol !== null && !miniCell.isToday && miniCell.inMonth
                        color: miniCell.hol && miniCell.hol.type === "off"
                            ? "#c0392b" : "#6b7280"
                    }

                    HoverHandler { id: miniHover }

                    PlasmaComponents.ToolTip.delay: 500
                    PlasmaComponents.ToolTip.visible: miniHover.hovered && miniCell.cell
                    PlasmaComponents.ToolTip.text: {
                        if (!miniCell.cell) {
                            return "";
                        }
                        let t = Qt.formatDate(new Date(miniCell.cell.year,
                            miniCell.cell.month - 1, miniCell.cell.day), "M月d日 ddd");
                        if (miniCell.cell.full) {
                            t += " · " + miniCell.cell.full;
                        }
                        if (miniCell.hol) {
                            t += " · " + (miniCell.hol.type === "off"
                                ? i18n("%1放假", miniCell.hol.name)
                                : i18n("%1调休上班", miniCell.hol.name));
                        }
                        return t;
                    }
                }
            }
        }
    }

    // ── 今日详情 ──────────────────────────────────────────────
    Rectangle {
        id: detailPanel

        x: view.stacked ? view.margin : view.margin + view.leftW + view.gap
        y: view.stacked ? view.margin + view.leftH + view.gap : view.margin
        width: view.stacked ? view.contentW : Math.max(60, view.contentW - view.leftW - view.gap)
        height: view.stacked
            ? Math.max(40, view.contentH - view.leftH - view.gap) : view.contentH

        color: view.cardFill
        radius: view.radius
        border.width: 1
        border.color: view.hairline

        readonly property real pad: Kirigami.Units.smallSpacing * 1.5
        readonly property real innerW: Math.max(1, width - 2 * pad)

        Row {
            id: detailDateRow

            x: detailPanel.pad
            y: detailPanel.pad
            width: detailPanel.innerW
            height: Math.max(18, Math.round(detailPanel.height * 0.28))
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                id: detailDay

                height: detailDateRow.height
                verticalAlignment: Text.AlignVCenter
                text: view.todayCellData ? String(view.todayCellData.day) : ""
                font.bold: true
                font.pixelSize: Math.max(18, Math.min(46, Math.round(detailDateRow.height * 0.72)))
            }

            Column {
                width: Math.max(0, detailDateRow.width - detailDay.width
                                - detailDateRow.spacing - (badge.visible ? badge.width + detailDateRow.spacing : 0))
                y: Math.round((detailDateRow.height - height) / 2)
                spacing: 0

                PlasmaComponents.Label {
                    width: parent.width
                    elide: Text.ElideRight
                    text: view.monthTitle
                    font.bold: true
                    font.pixelSize: Math.max(9, Kirigami.Theme.smallFont.pixelSize)
                }

                PlasmaComponents.Label {
                    width: parent.width
                    elide: Text.ElideRight
                    text: view.weekdayText
                    color: view.dimText
                    font.pixelSize: Math.max(8, Math.round(Kirigami.Theme.smallFont.pixelSize * 0.95))
                }
            }

            Rectangle {
                id: badge

                visible: view.shownHoliday !== null
                width: visible ? Math.max(16, Math.round(detailDateRow.height * 0.42)) : 0
                height: width
                y: 0
                radius: 3
                color: view.shownHoliday && view.shownHoliday.type === "off"
                    ? "#c0392b" : "#6b7280"

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    color: "white"
                    font.pixelSize: Math.max(8, Math.round(parent.height * 0.66))
                    text: view.shownHoliday && view.shownHoliday.type === "off"
                        ? i18n("休") : i18n("班")
                }
            }
        }

        PlasmaComponents.Label {
            id: detailLunar

            x: detailPanel.pad
            y: detailDateRow.y + detailDateRow.height + Kirigami.Units.smallSpacing
            width: detailPanel.innerW
            height: Math.max(14, Math.round(detailPanel.height * 0.22))
            verticalAlignment: Text.AlignTop
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
            color: view.dimText
            // 字号同时受面板高度和宽度约束：面板很高的窄条里，
            // 只按高度算会得到 40px 的农历而且一行放不下
            font.pixelSize: Math.max(10, Math.min(Math.round(detailPanel.height * 0.10),
                                                  Math.round(detailPanel.innerW / 7), 24))
            text: view.todayCellData && view.todayCellData.full
                ? view.todayCellData.full : ""
        }

        PlasmaComponents.Label {
            id: detailNote

            x: detailPanel.pad
            y: detailPanel.height - detailPanel.pad - height
            width: detailPanel.innerW
            height: Math.max(11, Kirigami.Theme.smallFont.pixelSize + 1)
            verticalAlignment: Text.AlignBottom
            elide: Text.ElideRight
            visible: text !== ""
            color: view.faintText
            font.pixelSize: Math.max(8, Kirigami.Theme.smallFont.pixelSize)
            text: {
                const parts = [];
                if (view.shownHoliday) {
                    parts.push(view.shownHoliday.type === "off"
                        ? i18n("%1：放假", view.shownHoliday.name)
                        : i18n("%1：调休上班", view.shownHoliday.name));
                }
                if (view.termWeekLabel !== "") {
                    parts.push(view.termWeekLabel);
                }
                return parts.join(" · ");
            }
        }
    }
}
