/*
 * 显示样式：农历详情
 *
 * 给「今天是什么农历日子」一个完整的交代：
 *   · 干支纪年 + 生肖（丙午年 · 马）
 *   · 农历月日（八月十二）作为主角，公历与星期在下面一行
 *   · 学期周次、放假/调休徽章
 *   · 下个节气还有几天（秋分 · 明天）
 *   · 下一个农历节日，窗口里看不到就退成「下个假期」（法定）
 *   · 本月有哪两个节气（白露 9/7 · 秋分 9/23）
 *
 * 越靠下的内容越先被舍弃：高度不够时先去掉「本月节气」那一行，再去掉倒计时块。
 * 外层几何自己算，理由见 StyleToday.qml 顶部注释。
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
    property string lunarText: ""       // 「八月十二」
    property var ganzhi: null           // { name: "丙午", zodiac: "马" }
    property var holiday: null          // { type, name }
    property string termWeekLabel: ""   // 「第 3 周」
    property var nextTerm: null         // { name, date, daysAway }
    property var nextFestival: null     // { name, date, daysAway, isLunar }
    property var monthTerms: []         // [{ name, date }]
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
                                               Kirigami.Theme.textColor.b, 0.5)

    readonly property int radius: Kirigami.Units.cornerRadius + 3
    readonly property int pad: Kirigami.Units.largeSpacing

    // 倒计时文案。样式文件之间不共享代码，和 StyleUpcoming 里那份是重复的
    // （只有三行，比为了共用而引入一层基类简单）。
    function countdownText(days) {
        if (days <= 0) {
            return i18n("今天");
        }
        if (days === 1) {
            return i18n("明天");
        }
        return i18n("%1 天后", days);
    }

    // 「9月7日」这种短日期，用于本月节气
    function shortDate(d) {
        return Qt.formatDate(d, "M/d");
    }

    // ── 几何 ──
    readonly property real margin: Kirigami.Units.largeSpacing
    readonly property real gap: Kirigami.Units.largeSpacing
    readonly property real contentW: Math.max(40, view.width - 2 * view.margin)
    readonly property real contentH: Math.max(40, view.height - 2 * view.margin)
    // 高度不够时先砍这两块
    readonly property bool showMonthTerms: view.height >= 300
    readonly property bool showFestivalRow: view.height >= 250
    readonly property real rowH: Math.max(16, Math.round(contentH * 0.085))
    // 下面那张卡实际需要多高：内边距 + 各行 + 行距
    readonly property real daysNeeded: view.pad * 2 + view.rowH + Kirigami.Units.smallSpacing
        + (view.showFestivalRow ? view.rowH + Kirigami.Units.smallSpacing : 0)
        + (view.showMonthTerms ? Math.round(view.rowH * 0.8) : 0)
    readonly property real heroH: Math.max(60, contentH - view.gap - view.daysNeeded)

    readonly property date todayDate: view.todayCell
        ? new Date(view.todayCell.year, view.todayCell.month - 1, view.todayCell.day)
        : new Date()

    // ── 主卡：干支 + 农历 + 公历 + 徽章 ──────────────────────
    Rectangle {
        id: heroCard

        x: view.margin
        y: view.margin
        width: view.contentW
        height: view.heroH

        color: view.cardFill
        radius: view.radius
        border.width: 1
        border.color: view.hairline

        readonly property real lunarFont: Math.max(20, Math.min(52,
            Math.round(height * 0.28)))
        readonly property real subFont: Math.max(9, Math.min(14,
            Math.round(height * 0.085)))
        readonly property real ganzhiH: Math.max(12, Math.round(subFont * 1.4))
        readonly property real chipH: Math.max(14, Math.round(Kirigami.Theme.smallFont.pixelSize * 1.6))
        readonly property real lunarHeroH: Math.max(20, Math.round(lunarFont * 1.35))
        readonly property real subH: Math.max(12, Math.round(subFont * 1.5))
        // 农历月日 + 公历这一块在「干支行」和「周次 chip」之间垂直居中
        readonly property real midTop: view.pad + ganzhiH
        readonly property real midH: Math.max(0,
            height - view.pad * 2 - ganzhiH - chipH)
        readonly property real blockY: midTop + Math.max(0,
            Math.round((midH - (lunarHeroH + Kirigami.Units.smallSpacing + subH)) / 2))

        // 干支纪年 · 生肖
        PlasmaComponents.Label {
            id: ganzhiLabel

            x: view.pad
            y: view.pad
            width: Math.max(1, heroCard.width - 2 * view.pad - badge.width)
            height: heroCard.ganzhiH
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: view.dimText
            font.pixelSize: Math.max(10, Math.round(heroCard.subFont * 1.05))
            text: view.ganzhi
                ? i18n("%1年 · %2", view.ganzhi.name, view.ganzhi.zodiac)
                : ""
        }

        // 休 / 班 徽章：语义信息，不跟着卡片一起淡
        Rectangle {
            id: badge

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: view.pad
            visible: view.holiday !== null
            width: visible ? badgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5 : 0
            height: Math.max(16, Math.round(heroCard.height * 0.12))
            radius: Kirigami.Units.cornerRadius
            color: view.holiday && view.holiday.type === "off" ? "#c0392b" : "#6b7280"

            PlasmaComponents.Label {
                id: badgeText
                anchors.centerIn: parent
                color: "white"
                font.bold: true
                font.pixelSize: Math.max(9, Math.round(badge.height * 0.62))
                text: view.holiday && view.holiday.type === "off" ? i18n("休") : i18n("班")
            }

            PlasmaComponents.ToolTip.delay: 400
            PlasmaComponents.ToolTip.text: view.holiday
                ? (view.holiday.type === "off"
                    ? i18n("%1：放假", view.holiday.name)
                    : i18n("%1：调休上班", view.holiday.name))
                : ""
        }

        // 农历月日（主角）
        PlasmaComponents.Label {
            id: lunarHero

            x: view.pad
            y: heroCard.blockY
            width: Math.max(1, heroCard.width - 2 * view.pad)
            height: heroCard.lunarHeroH
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            font.bold: true
            font.pixelSize: heroCard.lunarFont
            text: view.lunarText !== "" ? view.lunarText
                : (view.todayCell ? view.todayCell.dayText : "")
        }

        // 公历 + 星期（+ 节气名）
        PlasmaComponents.Label {
            id: subLine

            x: view.pad
            y: lunarHero.y + lunarHero.height + Kirigami.Units.smallSpacing
            width: Math.max(1, heroCard.width - 2 * view.pad)
            height: heroCard.subH
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: view.dimText
            font.pixelSize: heroCard.subFont
            text: {
                let t = Qt.formatDate(view.todayDate, "yyyy年M月d日")
                    + " " + Qt.locale().dayName(view.todayDate.getDay(), Locale.LongFormat);
                if (view.todayCell && view.todayCell.isTerm) {
                    t += " · " + view.todayCell.lunar;
                }
                return t;
            }
        }

        // 学期周次
        Rectangle {
            id: weekChip

            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: view.pad
            visible: view.termWeekLabel !== ""
            width: visible ? weekText.implicitWidth + Kirigami.Units.largeSpacing : 0
            height: heroCard.chipH
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
        }
    }

    // ── 倒计时卡：下个节气 / 下个节日 / 本月节气 ─────────────
    Rectangle {
        id: daysCard

        x: view.margin
        y: view.margin + view.heroH + view.gap
        width: view.contentW
        height: Math.max(0, view.contentH - view.heroH - view.gap)
        visible: height > 20

        color: view.cardFill
        radius: view.radius
        border.width: 1
        border.color: view.hairline

        readonly property real rowFont: Math.max(9, Math.min(15, Math.round(view.rowH * 0.55)))

        Column {
            id: daysColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: view.pad
            spacing: Kirigami.Units.smallSpacing

            // 下个节气
            Item {
                id: termRow

                width: daysColumn.width
                height: view.nextTerm ? view.rowH : 0
                visible: height > 0

                PlasmaComponents.Label {
                    id: termTag

                    width: Math.round(daysColumn.width * 0.34)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: view.faintText
                    font.pixelSize: daysCard.rowFont
                    text: i18n("下个节气")
                }

                PlasmaComponents.Label {
                    id: termName

                    x: termTag.width
                    width: Math.max(0, parent.width - termTag.width - termAway.width
                                    - Kirigami.Units.smallSpacing * 2)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.bold: true
                    font.pixelSize: daysCard.rowFont
                    text: view.nextTerm ? view.nextTerm.name : ""
                }

                PlasmaComponents.Label {
                    id: termAway

                    anchors.right: parent.right
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    color: view.nextTerm && view.nextTerm.daysAway <= 3
                        ? Kirigami.Theme.negativeTextColor : view.dimText
                    font.pixelSize: daysCard.rowFont
                    text: view.nextTerm ? view.countdownText(view.nextTerm.daysAway) : ""
                }
            }

            // 下个农历节日（窗口里看不到就退成下个法定假期）
            Item {
                id: festivalRow

                width: daysColumn.width
                height: (view.showFestivalRow && view.nextFestival) ? view.rowH : 0
                visible: height > 0

                PlasmaComponents.Label {
                    id: festivalTag

                    width: Math.round(daysColumn.width * 0.34)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: view.faintText
                    font.pixelSize: daysCard.rowFont
                    text: view.nextFestival && view.nextFestival.isLunar
                        ? i18n("下个农历节日") : i18n("下个假期")
                }

                PlasmaComponents.Label {
                    id: festivalName

                    x: festivalTag.width
                    width: Math.max(0, parent.width - festivalTag.width - festivalAway.width
                                    - Kirigami.Units.smallSpacing * 2)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.bold: true
                    font.pixelSize: daysCard.rowFont
                    text: view.nextFestival ? view.nextFestival.name : ""
                }

                PlasmaComponents.Label {
                    id: festivalAway

                    anchors.right: parent.right
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    color: view.nextFestival && view.nextFestival.daysAway <= 3
                        ? Kirigami.Theme.negativeTextColor : view.dimText
                    font.pixelSize: daysCard.rowFont
                    text: view.nextFestival ? view.countdownText(view.nextFestival.daysAway) : ""
                }
            }

            // 本月节气
            PlasmaComponents.Label {
                id: monthTermsLine

                width: daysColumn.width
                height: view.showMonthTerms ? Math.max(12, view.rowH * 0.8) : 0
                visible: height > 0 && view.monthTerms.length > 0
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                color: view.faintText
                font.pixelSize: Math.max(8, Math.round(daysCard.rowFont * 0.92))
                text: {
                    const parts = [];
                    for (let i = 0; i < view.monthTerms.length; ++i) {
                        parts.push(view.monthTerms[i].name + " " + view.shortDate(view.monthTerms[i].date));
                    }
                    return i18n("本月节气：%1", parts.join(" · "));
                }
            }
        }
    }
}
