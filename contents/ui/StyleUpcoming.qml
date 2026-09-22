/*
 * 显示样式：假期倒计时
 *
 * 一个列表：接下来的几个法定节假日，每行是节日名、日期、倒计时天数。
 * 连续的同名放假日算一段（春节 7 天是一行，不是 7 行）。
 *
 * 条数不固定：按可用高度决定能显示几行，放不下就少显示几行，不滚动也不压扁。
 * 外层几何自己算，理由见 StyleToday.qml 顶部注释。
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: view

    // [{ name, date: Date, length, daysAway }]
    property var upcoming: []
    property var todayCell: null
    property string termWeekLabel: ""
    property bool dataCoversFuture: true
    property real cardOpacity: 1

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
                                               Kirigami.Theme.textColor.b, 0.5)

    readonly property int radius: Kirigami.Units.cornerRadius + 3

    // 倒计时文案
    function countdownText(days) {
        if (days <= 0) {
            return i18n("今天");
        }
        if (days === 1) {
            return i18n("明天");
        }
        return i18n("%1 天后", days);
    }

    // 「9月25日 周五」——不用 Qt.formatDate 的 ddd：那个跟随进程 locale，
    // 实测在英文 locale 下会给出 Fri，而 Qt.locale() 给的是中文星期名。
    function dateWithWeekday(d) {
        return Qt.formatDate(d, "M月d日") + " " + Qt.locale().dayName(d.getDay(), Locale.ShortFormat);
    }

    // ── 几何 ──
    readonly property real margin: Kirigami.Units.largeSpacing
    readonly property real gap: Kirigami.Units.smallSpacing
    readonly property real rowGap: Kirigami.Units.smallSpacing
    readonly property real contentW: Math.max(60, view.width - 2 * view.margin)
    readonly property real contentH: Math.max(50, view.height - 2 * view.margin)
    readonly property real headerH: Math.max(34, Math.min(Math.round(view.contentH * 0.26), 78))
    readonly property real listH: Math.max(0, view.contentH - view.headerH - view.gap)
    readonly property real listY: view.margin + view.headerH + view.gap
    readonly property real minRowH: Math.max(28, Kirigami.Units.gridUnit * 1.8)
    // 行高封顶：一年只剩两个假期时，不该把每行拉到 150px 高
    readonly property real maxRowH: 76
    readonly property real noteH: Math.max(11, Kirigami.Theme.smallFont.pixelSize + 2)

    // 先按「不占提示行」算能放几行；放不下才把提示行的位置让出来重算
    readonly property int rowsWithoutNote: Math.max(1,
        Math.floor((view.listH + view.rowGap) / (view.minRowH + view.rowGap)))
    readonly property bool needsNote: view.upcoming.length > view.rowsWithoutNote
        || (!view.dataCoversFuture && view.upcoming.length > 0)
    readonly property real rowsAreaH: Math.max(view.minRowH,
        view.listH - (view.needsNote ? view.noteH + view.rowGap : 0))
    readonly property int maxRows: Math.max(1, Math.floor(
        (view.rowsAreaH + view.rowGap) / (view.minRowH + view.rowGap)))
    readonly property int shownCount: Math.min(view.upcoming.length, view.maxRows)
    readonly property real rowH: view.shownCount > 0
        ? Math.max(view.minRowH, Math.min(view.maxRowH,
            (view.rowsAreaH - (view.shownCount - 1) * view.rowGap) / view.shownCount))
        : 0
    readonly property real rowsBlockH: view.shownCount > 0
        ? view.shownCount * view.rowH + (view.shownCount - 1) * view.rowGap : 0
    // 行数少的时候整块垂直居中，免得顶上留一大片空白
    readonly property real rowsY: view.listY + Math.max(0,
        Math.round((view.rowsAreaH - view.rowsBlockH) / 2))

    function nameFont(h) {
        return Math.max(10, Math.min(Math.round(h * 0.28), 16));
    }
    function subFont(h) {
        return Math.max(8, Math.min(Math.round(h * 0.20), 12));
    }
    function countdownFont(h) {
        return Math.max(10, Math.min(Math.round(h * 0.30), 18));
    }

    readonly property string noteText: {
        const parts = [];
        if (view.shownCount < view.upcoming.length) {
            parts.push(i18n("还有 %1 个假期未显示（组件再高一点就看得见）",
                            view.upcoming.length - view.shownCount));
        }
        if (!view.dataCoversFuture && view.upcoming.length > 0) {
            parts.push(i18n("更远的假期数据尚未获取（设置 → 立即更新）"));
        }
        return parts.join("；");
    }

    // ── 今天的摘要 ────────────────────────────────────────────
    Rectangle {
        id: headerBox

        x: view.margin
        y: view.margin
        width: view.contentW
        height: view.headerH

        color: view.cardFill
        radius: view.radius
        border.width: 1
        border.color: view.hairline

        readonly property real pad: Kirigami.Units.smallSpacing * 1.5

        Row {
            id: headerLine

            x: headerBox.pad
            y: headerBox.pad
            width: Math.max(1, headerBox.width - 2 * headerBox.pad)
            height: Math.max(13, Math.round(headerBox.height * 0.46))
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                id: todayTag

                height: headerLine.height
                verticalAlignment: Text.AlignVCenter
                text: i18n("今天")
                color: view.faintText
                font.pixelSize: Math.max(9, Kirigami.Theme.smallFont.pixelSize)
            }

            PlasmaComponents.Label {
                height: headerLine.height
                width: Math.max(0, headerLine.width - todayTag.width - headerLine.spacing)
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.bold: true
                font.pixelSize: Math.max(10, Math.round(headerLine.height * 0.72))
                text: {
                    const d = new Date();
                    let t = view.dateWithWeekday(d);
                    if (view.todayCell && view.todayCell.full) {
                        t += " · " + view.todayCell.full;
                    }
                    return t;
                }
            }
        }

        PlasmaComponents.Label {
            id: headerNote

            x: headerBox.pad
            y: headerBox.height - headerBox.pad - height
            width: Math.max(1, headerBox.width - 2 * headerBox.pad)
            height: Math.max(11, Kirigami.Theme.smallFont.pixelSize + 1)
            verticalAlignment: Text.AlignBottom
            elide: Text.ElideRight
            visible: text !== ""
            color: view.faintText
            font.pixelSize: Math.max(8, Kirigami.Theme.smallFont.pixelSize)
            text: view.termWeekLabel
        }
    }

    // ── 假期列表 ──────────────────────────────────────────────
    Column {
        id: holidayList

        x: view.margin
        y: view.rowsY
        width: view.contentW
        height: view.rowsBlockH
        spacing: view.rowGap

        Repeater {
            model: view.upcoming.slice(0, view.shownCount)

            delegate: Rectangle {
                id: holidayRow

                required property int index
                required property var modelData

                readonly property var item: modelData

                width: holidayList.width
                height: view.rowH

                color: view.cardFill
                radius: view.radius
                border.width: 1
                border.color: view.hairline

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
                    anchors.rightMargin: Kirigami.Units.smallSpacing * 1.5
                    spacing: Kirigami.Units.smallSpacing

                    // 休 徽章：语义信息，不跟着卡片一起淡
                    Rectangle {
                        implicitWidth: offLabel.implicitWidth + Kirigami.Units.smallSpacing
                        implicitHeight: offLabel.implicitHeight + 2
                        radius: 3
                        color: "#c0392b"

                        PlasmaComponents.Label {
                            id: offLabel
                            anchors.centerIn: parent
                            color: "white"
                            font.pixelSize: Math.max(8, view.subFont(holidayRow.height))
                            text: i18n("休")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.bold: true
                            font.pixelSize: view.nameFont(holidayRow.height)
                            text: holidayRow.item.name
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: view.faintText
                            font.pixelSize: view.subFont(holidayRow.height)
                            text: {
                                let t = view.dateWithWeekday(holidayRow.item.date);
                                if (holidayRow.item.length > 1) {
                                    t += i18n("（连休 %1 天）", holidayRow.item.length);
                                }
                                return t;
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        font.bold: true
                        elide: Text.ElideRight
                        font.pixelSize: view.countdownFont(holidayRow.height)
                        color: holidayRow.item.daysAway <= 3
                            ? Kirigami.Theme.negativeTextColor : view.dimText
                        text: view.countdownText(holidayRow.item.daysAway)
                    }
                }
            }
        }
    }

    // 放不下 / 数据没取全时给一句解释，避免看起来像坏了
    PlasmaComponents.Label {
        id: listNote

        x: view.margin
        y: view.listY + view.listH - height
        width: view.contentW
        height: view.noteH
        verticalAlignment: Text.AlignBottom
        visible: view.noteText !== ""
        elide: Text.ElideRight
        color: view.faintText
        font.pixelSize: Math.max(8, Kirigami.Theme.smallFont.pixelSize)
        text: view.noteText
    }

    // 空状态
    Item {
        id: emptyState

        x: view.margin
        y: view.listY
        width: view.contentW
        height: view.listH
        visible: view.upcoming.length === 0

        PlasmaComponents.Label {
            anchors.centerIn: parent
            width: Math.min(parent.width, Kirigami.Units.gridUnit * 14)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: view.faintText
            font.pixelSize: Math.max(9, Kirigami.Theme.defaultFont.pixelSize)
            text: view.dataCoversFuture
                ? i18n("接下来一年没有法定节假日。")
                : i18n("没有可用的节假日数据。\n在组件设置里点「立即更新」获取。")
        }
    }
}
