/*
 * 显示样式：倒计时
 *
 * 一张主卡 + 若干小行，每条目标一张：
 *   · 倒计时模式（down）：「距离 考研 88 天」，那天结束
 *   · 正向模式（up）：那天算第 1 天，「开学 第 22 天」
 *
 * 第 1 条是主卡（大字号），其余排成小行；放不下的少显示几行并在下面说明，
 * 不滚动也不压扁。已过目标（倒计时模式）和未开始目标（正向模式）用灰字，
 * 不删除也不报错 —— 用户自己决定留不留。
 *
 * 目标在「配置 → 倒计时」页里增删；这里只管画，条目由 main.qml 校验过，
 * date 一定是合法的 Date。
 *
 * 外层几何自己算，理由见 StyleToday.qml 顶部注释。
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: view

    // [{ name, date: Date, mode: "down"|"up", diff }]
    property var entries: []
    property real cardOpacity: 1

    readonly property color accent: Kirigami.Theme.highlightColor
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
    readonly property int pad: Kirigami.Units.largeSpacing

    // 「2026年12月19日 周六」—— 星期名用 Qt.locale().dayName，
    // 不用 Qt.formatDate 的 ddd（那个跟随进程 locale，见 StyleToday 顶部）。
    function longDate(d) {
        return Qt.formatDate(d, "yyyy年M月d日")
            + " " + Qt.locale().dayName(d.getDay(), Locale.LongFormat);
    }

    // ── 一条目标的三个文案段 ──
    function captionOf(e) {
        if (e.mode === "up") {
            return e.diff > 0 ? e.name + i18n("（尚未开始）") : e.name;
        }
        if (e.diff > 0) {
            return i18n("距离 %1", e.name);
        }
        return e.diff === 0 ? e.name : i18n("%1 已过", e.name);
    }

    function bigOf(e) {
        if (e.mode === "up") {
            if (e.diff > 0) {
                return i18n("还有 %1 天", e.diff);
            }
            // 那天算第 1 天：昨天开学 → 今天第 2 天
            return i18n("第 %1 天", 1 - e.diff);
        }
        if (e.diff === 0) {
            return i18n("就是今天");
        }
        return i18n("%1 天", Math.abs(e.diff));
    }

    function subOf(e) {
        if (e.mode === "up") {
            return e.diff > 0 ? longDate(e.date) + i18n(" 开始")
                              : i18n("自 %1 起", longDate(e.date));
        }
        return longDate(e.date);
    }

    // 过了期的倒计时 / 还没开始的正向计数：灰显，但照样显示天数
    function isDim(e) {
        return (e.mode === "down" && e.diff < 0) || (e.mode === "up" && e.diff > 0);
    }

    // ── 几何 ──
    readonly property real margin: Kirigami.Units.largeSpacing
    readonly property real gap: Kirigami.Units.largeSpacing
    readonly property real rowGap: Kirigami.Units.smallSpacing
    readonly property real contentW: Math.max(60, view.width - 2 * view.margin)
    readonly property real contentH: Math.max(50, view.height - 2 * view.margin)
    readonly property bool hasEntries: view.entries.length > 0
    readonly property real heroH: !view.hasEntries ? 0
        : Math.max(84, Math.min(Math.round(view.contentH * 0.42), 150))
    readonly property real rowsAreaY: view.margin + view.heroH + (view.hasEntries ? view.gap : 0)
    readonly property real rowsAreaH: Math.max(0, view.contentH + view.margin - view.rowsAreaY)
    readonly property real rowH: Math.max(40, Math.min(64, Math.round(view.contentH * 0.13)))
    readonly property real noteH: Math.max(11, Kirigami.Theme.smallFont.pixelSize + 2)
    readonly property int maxRows: Math.max(0, Math.floor(
        (view.rowsAreaH - (view.needsNote ? view.noteH + view.rowGap : 0) + view.rowGap)
        / (view.rowH + view.rowGap)))
    readonly property int restCount: Math.max(0, view.entries.length - 1)
    // 先按「不占提示行」算能放几行；放不下才把提示行的位置让出来重算
    readonly property int rowsWithoutNote: Math.max(0, Math.floor(
        (view.rowsAreaH + view.rowGap) / (view.rowH + view.rowGap)))
    readonly property bool needsNote: view.restCount > view.rowsWithoutNote
    readonly property int shownRows: Math.min(view.restCount, view.maxRows)
    readonly property real rowsBlockH: view.shownRows > 0
        ? view.shownRows * view.rowH + (view.shownRows - 1) * view.rowGap : 0
    readonly property real rowsY: view.rowsAreaY + Math.max(0, Math.round(
        (view.rowsAreaH - (view.needsNote ? view.noteH + view.rowGap : 0) - view.rowsBlockH) / 2))

    readonly property string noteText: view.restCount > view.shownRows
        ? i18n("还有 %1 个目标未显示（组件再高一点就看得见）",
               view.restCount - view.shownRows)
        : ""

    // ── 主卡（第 1 条）──────────────────────────────────────
    Rectangle {
        id: heroCard

        x: view.margin
        y: view.margin
        width: view.contentW
        height: view.heroH
        visible: view.hasEntries

        color: view.cardFill
        radius: view.radius
        border.width: 1
        border.color: view.hairline

        readonly property var e: view.entries.length > 0 ? view.entries[0] : null
        readonly property bool dim: e ? view.isDim(e) : false
        readonly property real bigFont: Math.max(26, Math.min(58,
            Math.round(height * 0.40)))
        readonly property real smallFont: Math.max(9, Math.min(13,
            Math.round(height * 0.10)))

        // 目标名（小、灰）
        PlasmaComponents.Label {
            id: heroCaption

            x: view.pad
            y: view.pad
            width: Math.max(1, heroCard.width - 2 * view.pad)
            height: Math.max(12, Math.round(heroCard.smallFont * 1.4))
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: view.dimText
            font.pixelSize: heroCard.smallFont
            text: heroCard.e ? view.captionOf(heroCard.e) : ""
        }

        // 大字：88 天 / 第 22 天 / 就是今天
        PlasmaComponents.Label {
            id: heroBig

            x: view.pad
            y: heroCaption.y + heroCaption.height
            width: Math.max(1, heroCard.width - 2 * view.pad)
            height: Math.max(20, heroCard.height - heroCaption.height
                             - heroSub.height - 2 * view.pad)
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            font.bold: true
            font.pixelSize: heroCard.bigFont
            color: heroCard.dim ? view.faintText : view.accent
            text: heroCard.e ? view.bigOf(heroCard.e) : ""
        }

        // 日期
        PlasmaComponents.Label {
            id: heroSub

            x: view.pad
            y: heroCard.height - view.pad - height
            width: Math.max(1, heroCard.width - 2 * view.pad)
            height: Math.max(11, Math.round(heroCard.smallFont * 1.2))
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: view.faintText
            font.pixelSize: Math.max(8, Math.round(heroCard.smallFont * 0.92))
            text: heroCard.e ? view.subOf(heroCard.e) : ""
        }
    }

    // ── 其余目标排成小行 ──────────────────────────────────────
    Repeater {
        id: rowsRepeater

        model: view.entries.slice(1, 1 + view.shownRows)

        delegate: Rectangle {
            id: rowCard

            required property int index
            required property var modelData

            readonly property var e: modelData
            readonly property bool dim: view.isDim(e)
            readonly property real nameFont: Math.max(10, Math.round(view.rowH * 0.24))
            readonly property real numFont: Math.max(11, Math.round(view.rowH * 0.34))

            x: view.margin
            y: view.rowsY + index * (view.rowH + view.rowGap)
            width: view.contentW
            height: view.rowH

            color: view.cardFill
            radius: view.radius
            border.width: 1
            border.color: view.hairline

            Column {
                anchors.left: parent.left
                anchors.leftMargin: view.pad
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, parent.width - 3 * view.pad - daysLabel.width)
                spacing: 0

                PlasmaComponents.Label {
                    width: parent.width
                    elide: Text.ElideRight
                    font.bold: true
                    font.pixelSize: rowCard.nameFont
                    color: rowCard.dim ? view.faintText : Kirigami.Theme.textColor
                    text: rowCard.e ? rowCard.e.name : ""
                }

                PlasmaComponents.Label {
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: Math.max(8, Math.round(rowCard.nameFont * 0.82))
                    color: view.faintText
                    text: rowCard.e ? view.subOf(rowCard.e) : ""
                }
            }

            PlasmaComponents.Label {
                id: daysLabel

                anchors.right: parent.right
                anchors.rightMargin: view.pad
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.bold: true
                font.pixelSize: rowCard.numFont
                color: {
                    if (rowCard.dim) {
                        return view.faintText;
                    }
                    if (rowCard.e && rowCard.e.diff === 0) {
                        return view.accent;
                    }
                    return view.dimText;
                }
                text: rowCard.e ? view.bigOf(rowCard.e) : ""
            }
        }
    }

    // 放不下时的说明
    PlasmaComponents.Label {
        x: view.margin
        y: view.margin + view.contentH - height
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
    Rectangle {
        x: view.margin
        y: view.margin
        width: view.contentW
        height: view.contentH
        visible: !view.hasEntries

        color: view.cardFill
        radius: view.radius
        border.width: 1
        border.color: view.hairline

        PlasmaComponents.Label {
            anchors.centerIn: parent
            width: Math.min(parent.width, Kirigami.Units.gridUnit * 14)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: view.faintText
            font.pixelSize: Math.max(9, Kirigami.Theme.defaultFont.pixelSize)
            text: i18n("还没有倒计时目标。\n右键组件 →「配置农历月历…」→「倒计时」里添加，"
                       + "支持倒计时与正向计数两种模式。")
        }
    }
}
