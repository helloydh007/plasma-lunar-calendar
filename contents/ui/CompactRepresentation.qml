/*
 * 面板上的紧凑视图
 *
 * 放任务栏时用它：一行「22 八月十二」，今天放假/调休时带一个 休/班 徽章。
 * 点一下展开完整视图（fullRepresentation），也就是桌面上的那套样式。
 *
 * 尺寸全按面板高度算 —— 面板高度由外面定死，不会回流。
 * 注意 Positioner（Row）的子项不要挂锚：Row 只管 x，纵向位置自己写 y。
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: view

    // 展开/收起交给 main.qml（它才拿得到 PlasmoidItem 的 expanded）
    signal activated()

    property string dayText: ""
    property string lunarText: ""
    property var holiday: null
    property bool holidaysVisible: true

    readonly property color faintText: Qt.rgba(Kirigami.Theme.textColor.r,
                                               Kirigami.Theme.textColor.g,
                                               Kirigami.Theme.textColor.b, 0.6)
    readonly property int bigFont: Math.max(11, Math.min(22, Math.round(view.height * 0.46)))
    readonly property int smallFont: Math.max(8, Math.min(15, Math.round(view.height * 0.34)))

    implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    implicitHeight: Math.max(Kirigami.Units.gridUnit, row.implicitHeight)

    // 面板里的尺寸靠 Layout 附加属性，只写 implicit* 面板会当成默认小方块
    Layout.minimumWidth: Kirigami.Units.gridUnit * 2
    Layout.preferredWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.maximumWidth: Kirigami.Units.gridUnit * 9
    Layout.minimumHeight: Math.round(Kirigami.Units.gridUnit * 1.2)

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: view.dayText
            font.bold: true
            font.pixelSize: view.bigFont
            y: Math.round((row.height - height) / 2)
        }

        PlasmaComponents.Label {
            text: view.lunarText
            color: view.faintText
            font.pixelSize: view.smallFont
            elide: Text.ElideRight
            y: Math.round((row.height - height) / 2)
        }

        // 休 / 班 徽章：语义信息，不跟着淡化
        Rectangle {
            id: badge

            visible: view.holidaysVisible && view.holiday !== null
            width: visible ? badgeText.implicitWidth + Kirigami.Units.smallSpacing * 1.5 : 0
            height: Math.max(12, Math.round(view.smallFont * 1.5))
            radius: 3
            color: view.holiday && view.holiday.type === "off" ? "#c0392b" : "#6b7280"
            y: Math.round((row.height - height) / 2)

            PlasmaComponents.Label {
                id: badgeText

                anchors.centerIn: parent
                color: "white"
                font.pixelSize: Math.max(8, Math.round(badge.height * 0.65))
                text: view.holiday && view.holiday.type === "off" ? i18n("休") : i18n("班")
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: view.activated()
    }
}
