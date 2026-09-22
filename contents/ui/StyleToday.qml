/*
 * 显示样式：今日
 *
 * 大字号只讲今天：日期、星期、农历（含节气）、学期周次、今天放不放假，
 * 下面一条本周七天作为上下文。
 *
 * 所有数据由 main.qml 通过属性传进来 —— 本文件只管画。
 * 农历文字来自 alternatecalendar 插件，创建后一小会儿才到，所以这里一律
 * 用绑定读（不要在 onCompleted 里快照），数据到了会自动刷新。
 *
 * ── 外层为什么自己算几何，不用 ColumnLayout ──
 *   卡片里的内容全是锚定子项，锚定子项不参与父项的 implicit 尺寸计算，
 *   于是卡片的 implicitHeight 是 0。这样的项放进 ColumnLayout，实测会被
 *   分到 3px，而旁边那个有 preferredHeight 的行把整块高度全吃掉。
 *   所以外层用 x/y/width/height 手工排，几何完全确定。
 *   固定尺寸容器内部的 Row/Column 是安全的（尺寸不来自内容）。
 *
 * ── 字号为什么要压上限 ──
 *   数字的字号按卡片高度算，但一个字号为 N 的 Label 实际要 N*1.37 高，
 *   不封顶会顶出所在行（探针里量到过 126 > 101）。这里连行高一并算出来。
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: view

    // ── 输入（main.qml 传入）──
    property var todayCell: null        // { year, month, day, dayText, lunar, full, isTerm }
    property var weekCells: []          // 本周 7 格（可能含 null）
    property int todayColumn: -1        // 今天在 weekCells 里的下标，-1 = 未知
    property var weekHolidays: []       // 与 weekCells 等长；null | { type, name }
    property var holiday: null          // 今天的假期状态
    property string termWeekLabel: ""   // 「第 3 周」，无则空串
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
    readonly property int pad: Kirigami.Units.largeSpacing

    // 「9月25日 周五」——不用 Qt.formatDate 的 ddd：那个跟随进程 locale，
    // 实测在英文 locale 下会给出 Fri，而 Qt.locale() 给的是中文星期名。
    function dateWithWeekday(d) {
        return Qt.formatDate(d, "M月d日") + " " + Qt.locale().dayName(d.getDay(), Locale.ShortFormat);
    }

    // ── 几何：全部自己算 ──
    readonly property real margin: Kirigami.Units.largeSpacing
    readonly property real gap: Kirigami.Units.largeSpacing
    readonly property real contentW: Math.max(40, view.width - 2 * view.margin)
    readonly property real contentH: Math.max(40, view.height - 2 * view.margin)
    // 本周条高度封顶：格子太瘦长会很难看
    readonly property real stripH: Math.max(44, Math.min(Math.round(contentH * 0.30), 96))
    readonly property real cardH: Math.max(40, contentH - view.gap - view.stripH)

    readonly property date todayDate: view.todayCell
        ? new Date(view.todayCell.year, view.todayCell.month - 1, view.todayCell.day)
        : new Date()

    // 「九月」，与月历头部的写法一致
    readonly property string monthText: Qt.locale()
        .standaloneMonthName(view.todayDate.getMonth(), Locale.LongFormat)
    readonly property string weekdayText: Qt.locale()
        .dayName(view.todayDate.getDay(), Locale.LongFormat)

    // ── 主卡 ──────────────────────────────────────────────────
    Rectangle {
        id: mainCard

        x: view.margin
        y: view.margin
        width: view.contentW
        height: view.cardH

        color: view.cardFill
        radius: view.radius
        border.width: 1
        border.color: view.hairline

        // 字号与行高配对算出来：Label 的实际高度约等于 1.37 × pixelSize
        readonly property real dayFontSize: Math.max(22, Math.min(84,
            Math.round(height * 0.34)))
        readonly property real dateRowH: Math.round(mainCard.dayFontSize * 1.45)
        readonly property real lunarRowH: Math.max(16, Math.round(height * 0.15))
        readonly property real blockH: mainCard.dateRowH + Kirigami.Units.smallSpacing
            + mainCard.lunarRowH
        readonly property real blockY: Math.max(view.pad, Math.round((height - blockH) / 2))

        // 休 / 班 徽章：语义信息，不跟着卡片一起淡
        Rectangle {
            id: holidayBadge

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: view.pad
            visible: view.holiday !== null
            width: visible ? Math.max(18, Math.round(mainCard.height * 0.11)) : 0
            height: width
            radius: Kirigami.Units.cornerRadius
            color: view.holiday && view.holiday.type === "off" ? "#c0392b" : "#6b7280"

            PlasmaComponents.Label {
                anchors.centerIn: parent
                color: "white"
                font.bold: true
                font.pixelSize: Math.max(9, Math.round(parent.height * 0.62))
                text: view.holiday && view.holiday.type === "off" ? i18n("休") : i18n("班")
            }

            PlasmaComponents.ToolTip.delay: 400
            PlasmaComponents.ToolTip.text: view.holiday
                ? (view.holiday.type === "off"
                    ? i18n("%1：放假", view.holiday.name)
                    : i18n("%1：调休上班", view.holiday.name))
                : ""
        }

        Row {
            id: dateRow

            x: view.pad
            y: mainCard.blockY
            width: Math.max(1, mainCard.width - 2 * view.pad)
            height: mainCard.dateRowH
            spacing: Kirigami.Units.smallSpacing * 1.5

            PlasmaComponents.Label {
                id: dayNumber

                height: dateRow.height
                verticalAlignment: Text.AlignBottom
                text: view.todayCell ? String(view.todayCell.day) : "--"
                font.bold: true
                font.pixelSize: mainCard.dayFontSize
            }

            Column {
                id: monthColumn

                width: Math.max(monthLabel.implicitWidth, weekdayLabel.implicitWidth)
                height: dateRow.height
                spacing: 0

                // 顶部弹簧：把下面两行顶到行底，和大日号对齐
                Item {
                    width: 1
                    height: Math.max(0, monthColumn.height
                                        - monthLabel.implicitHeight - weekdayLabel.implicitHeight)
                }

                PlasmaComponents.Label {
                    id: monthLabel
                    width: monthColumn.width
                    elide: Text.ElideRight
                    text: view.monthText
                    font.bold: true
                    font.pixelSize: Math.max(11, Math.round(mainCard.dayFontSize * 0.26))
                }

                PlasmaComponents.Label {
                    id: weekdayLabel
                    width: monthColumn.width
                    elide: Text.ElideRight
                    text: view.weekdayText
                    color: view.dimText
                    font.pixelSize: Math.max(9, Math.round(mainCard.dayFontSize * 0.21))
                }
            }
        }

        // 农历整句。subLabel 是「丙午八月十二」这种完整写法，
        // 节气当天会带括号，例如「丙午七月廿六 (白露)」。
        Row {
            id: lunarRow

            x: view.pad
            y: mainCard.blockY + mainCard.dateRowH + Kirigami.Units.smallSpacing
            width: Math.max(1, mainCard.width - 2 * view.pad)
            height: mainCard.lunarRowH
            spacing: Kirigami.Units.smallSpacing

            // 学期周次（放左边，宽度固定）
            Rectangle {
                id: weekChip

                visible: view.termWeekLabel !== ""
                width: visible ? weekText.implicitWidth + Kirigami.Units.largeSpacing : 0
                height: Math.min(lunarRow.height, weekText.implicitHeight + Kirigami.Units.smallSpacing)
                // Row 只管 x，y 自己摆（Positioner 的子项不能挂锚）
                y: Math.round((lunarRow.height - height) / 2)
                radius: height / 2
                color: view.cardOpacity > 0
                    ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.08)
                    : "transparent"
                border.width: 1
                border.color: view.hairline

                PlasmaComponents.Label {
                    id: weekText
                    anchors.centerIn: parent
                    text: view.termWeekLabel
                    color: view.dimText
                    font.pixelSize: Math.max(9, Kirigami.Theme.smallFont.pixelSize)
                }

                PlasmaComponents.ToolTip.delay: 400
                PlasmaComponents.ToolTip.text: view.termWeekLabel !== ""
                    ? i18n("以设置的开学日为第 1 周推算") : ""
            }

            PlasmaComponents.Label {
                id: lunarLabel

                width: Math.max(1, lunarRow.width - weekChip.width
                                - (weekChip.visible ? lunarRow.spacing : 0))
                height: lunarRow.height
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                color: view.dimText
                font.pixelSize: Math.max(10, Math.round(mainCard.height * 0.072))
                text: view.todayCell && view.todayCell.full ? view.todayCell.full : ""
            }
        }
    }

    // ── 本周条 ────────────────────────────────────────────────
    Row {
        id: strip

        x: view.margin
        y: view.margin + view.cardH + view.gap
        width: view.contentW
        height: view.stripH
        spacing: Kirigami.Units.smallSpacing

        readonly property real cellW: Math.max(8,
            (width - 6 * spacing) / Math.max(1, view.weekCells.length))

        Repeater {
            model: view.weekCells

            delegate: Rectangle {
                id: stripCell

                required property int index
                required property var modelData

                readonly property var cell: modelData
                readonly property bool isToday: index === view.todayColumn
                readonly property var hol: view.weekHolidays[index] || null
                readonly property date cellDate: cell
                    ? new Date(cell.year, cell.month - 1, cell.day) : null
                // 窄而高的格子里，字号跟着宽度走更稳
                readonly property real numFont: Math.max(11, Math.min(
                    Math.round(stripCell.width * 0.46), Math.round(stripCell.height * 0.38)))
                readonly property real smallFont: Math.max(7, Math.min(
                    Math.round(stripCell.width * 0.21), Math.round(stripCell.height * 0.15)))

                width: strip.cellW
                height: strip.height

                // 今天的高亮不参与 cardOpacity：它是信息，跟着淡就没法认了
                color: isToday ? view.accent : view.cardFill
                radius: view.radius
                border.width: 1
                border.color: isToday ? "transparent" : view.hairline

                Column {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 0

                    PlasmaComponents.Label {
                        width: parent.width
                        height: stripCell.smallFont * 1.6
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: stripCell.cellDate
                            ? Qt.locale().dayName(stripCell.cellDate.getDay(), Locale.ShortFormat)
                            : ""
                        color: stripCell.isToday ? view.onAccent : view.faintText
                        font.pixelSize: stripCell.smallFont
                    }

                    PlasmaComponents.Label {
                        width: parent.width
                        height: Math.max(0, parent.height - stripCell.smallFont * 3.2)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: stripCell.cell ? stripCell.cell.dayText : ""
                        font.bold: true
                        font.pixelSize: stripCell.numFont
                        color: stripCell.isToday ? view.onAccent : Kirigami.Theme.textColor
                    }

                    // 第三行：节假日显示 休 / 班，其余显示农历
                    PlasmaComponents.Label {
                        width: parent.width
                        height: stripCell.smallFont * 1.6
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        font.pixelSize: stripCell.smallFont
                        text: {
                            if (stripCell.hol) {
                                return stripCell.hol.type === "off" ? i18n("休") : i18n("班");
                            }
                            return stripCell.cell ? stripCell.cell.lunar : "";
                        }
                        color: {
                            if (stripCell.hol) {
                                return stripCell.hol.type === "off" ? "#c0392b" : "#6b7280";
                            }
                            return stripCell.isToday ? view.onAccent : view.faintText;
                        }
                    }
                }

                HoverHandler { id: stripHover }

                PlasmaComponents.ToolTip.delay: 500
                PlasmaComponents.ToolTip.visible: stripHover.hovered && stripCell.cell
                PlasmaComponents.ToolTip.text: {
                    if (!stripCell.cell) {
                        return "";
                    }
                    let t = view.dateWithWeekday(stripCell.cellDate);
                    if (stripCell.cell.full) {
                        t += " · " + stripCell.cell.full;
                    }
                    if (stripCell.hol) {
                        t += " · " + (stripCell.hol.type === "off"
                            ? i18n("%1放假", stripCell.hol.name)
                            : i18n("%1调休上班", stripCell.hol.name));
                    }
                    return t;
                }
            }
        }
    }
}
