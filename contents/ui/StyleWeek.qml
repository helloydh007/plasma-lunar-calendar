/*
 * 显示样式：本周
 *
 * 最省地方的一种：一行标题 + 本周七天。每格是星期、日号、农历（节假日那天
 * 换成 休 / 班）。今天整格高亮。
 *
 * 数据由 main.qml 传入；农历是插件异步给的，所以一律用绑定读。
 * 外层几何自己算（原因见 StyleToday.qml 顶部注释）：卡片内的内容都是锚定子项，
 * 放进 Layout 会被分不到空间。
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: view

    property var weekCells: []
    property int todayColumn: -1
    property var weekHolidays: []
    property bool holidaysVisible: true
    property string termWeekLabel: ""
    property string monthText: ""       // 「九月」
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
                                               Kirigami.Theme.textColor.b, 0.55)

    readonly property int radius: Kirigami.Units.cornerRadius + 3

    // 「9月25日 周五」——不用 Qt.formatDate 的 ddd：那个跟随进程 locale，
    // 实测在英文 locale 下会给出 Fri，而 Qt.locale() 给的是中文星期名。
    function dateWithWeekday(d) {
        return Qt.formatDate(d, "M月d日") + " " + Qt.locale().dayName(d.getDay(), Locale.ShortFormat);
    }

    // ── 几何 ──
    readonly property real margin: Kirigami.Units.smallSpacing * 1.5
    readonly property real gap: Kirigami.Units.smallSpacing
    readonly property real contentW: Math.max(40, view.width - 2 * view.margin)
    readonly property real contentH: Math.max(20, view.height - 2 * view.margin)
    readonly property real headerH: Math.max(13, Math.min(Math.round(contentH * 0.30), 34))
    // 一周只有一行，格子不必跟着组件高度无限拉长；封顶之后整块垂直居中
    readonly property real rowH: Math.max(20, Math.min(contentH - view.headerH - view.gap, 128))
    readonly property real blockY: Math.max(view.margin, Math.round(
        (view.height - (view.headerH + view.gap + view.rowH)) / 2))

    // ── 标题：九月 · 第 3 周 ──────────────────────────────────
    Row {
        id: header

        x: view.margin
        y: view.blockY
        width: view.contentW
        height: view.headerH
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            id: monthLabel

            height: header.height
            verticalAlignment: Text.AlignVCenter
            text: view.monthText
            font.bold: true
            font.pixelSize: Math.max(9, Math.round(header.height * 0.62))
        }

        PlasmaComponents.Label {
            height: header.height
            verticalAlignment: Text.AlignVCenter
            width: Math.max(0, header.width - monthLabel.width - header.spacing)
            elide: Text.ElideRight
            text: view.termWeekLabel
            color: view.dimText
            font.pixelSize: Math.max(9, Kirigami.Theme.smallFont.pixelSize)
        }
    }

    // ── 七天 ──────────────────────────────────────────────────
    Row {
        id: weekRow

        x: view.margin
        y: view.blockY + view.headerH + view.gap
        width: view.contentW
        height: view.rowH
        spacing: Kirigami.Units.smallSpacing

        readonly property real cellW: Math.max(8,
            (width - 6 * spacing) / Math.max(1, view.weekCells.length))

        Repeater {
            model: view.weekCells

            delegate: Rectangle {
                id: weekCell

                required property int index
                required property var modelData

                readonly property var cell: modelData
                readonly property bool isToday: index === view.todayColumn
                readonly property var hol: view.holidaysVisible
                    ? (view.weekHolidays[index] || null) : null
                readonly property date cellDate: cell
                    ? new Date(cell.year, cell.month - 1, cell.day) : null
                // 窄而高的格子里，字号跟着宽度走更稳
                readonly property real numFont: Math.max(12, Math.min(
                    Math.round(weekCell.width * 0.46), Math.round(weekCell.height * 0.36)))
                readonly property real smallFont: Math.max(8, Math.min(
                    Math.round(weekCell.width * 0.21), Math.round(weekCell.height * 0.16)))

                width: weekRow.cellW
                height: weekRow.height

                color: isToday ? view.accent : view.cardFill
                radius: view.radius
                border.width: 1
                border.color: isToday ? "transparent" : view.hairline

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 0

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: weekCell.cellDate
                            ? Qt.locale().dayName(weekCell.cellDate.getDay(), Locale.ShortFormat)
                            : ""
                        color: weekCell.isToday ? view.onAccent : view.faintText
                        font.pixelSize: weekCell.smallFont
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: weekCell.cell ? weekCell.cell.dayText : ""
                        font.bold: true
                        font.pixelSize: weekCell.numFont
                        color: weekCell.isToday ? view.onAccent : Kirigami.Theme.textColor
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: weekCell.smallFont
                        text: {
                            if (weekCell.hol) {
                                return weekCell.hol.type === "off" ? i18n("休") : i18n("班");
                            }
                            return weekCell.cell ? weekCell.cell.lunar : "";
                        }
                        color: {
                            if (weekCell.hol) {
                                return weekCell.hol.type === "off" ? "#c0392b" : "#6b7280";
                            }
                            return weekCell.isToday ? view.onAccent : view.faintText;
                        }
                    }
                }

                HoverHandler { id: weekHover }

                PlasmaComponents.ToolTip.delay: 500
                PlasmaComponents.ToolTip.visible: weekHover.hovered && weekCell.cell
                PlasmaComponents.ToolTip.text: {
                    if (!weekCell.cell) {
                        return "";
                    }
                    let t = view.dateWithWeekday(weekCell.cellDate);
                    if (weekCell.cell.full) {
                        t += " · " + weekCell.cell.full;
                    }
                    if (weekCell.hol) {
                        t += " · " + (weekCell.hol.type === "off"
                            ? i18n("%1放假", weekCell.hol.name)
                            : i18n("%1调休上班", weekCell.hol.name));
                    }
                    return t;
                }
            }
        }
    }
}
