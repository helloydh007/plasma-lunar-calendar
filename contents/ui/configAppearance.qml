/*
 * 配置页：外观
 *
 * 显示样式、背景不透明度、卡片不透明度。都是纯显示选项，和节假日数据无关，
 * 所以单独一页，避免和「学期周数」页抢同一个配置键。
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

KCMUtils.SimpleKCM {
    id: page

    // KCM 框架的约定：配置页自己声明并发出此信号，宿主据此启用「应用」按钮。
    signal configurationChanged()

    property alias cfg_viewStyle: styleHolder.text
    property alias cfg_backgroundOpacity: opacitySlider.value
    property alias cfg_cardOpacity: cardOpacitySlider.value

    // 不展示，仅作为 cfg_ 的载体
    QQC2.TextField { id: styleHolder; visible: false; width: 0; height: 0 }

    // 每种样式配一句说明，选的时候就知道长什么样
    readonly property var styles: [
        { value: "month", name: i18n("整月网格"),
          hint: i18n("一个月一张网格：格子里上面是公历日号，下面是农历或节气，"
                     + "右上角标「休 / 班」。要一眼看全一个月时用它。") },
        { value: "today", name: i18n("今日"),
          hint: i18n("大字号只讲今天：日期、星期、农历、学期周次、今天放不放假，"
                     + "下面一条本周七天。桌面上一瞥就够。") },
        { value: "week", name: i18n("本周"),
          hint: i18n("只画本周七天，每格是星期、日号、农历，今天整格高亮。"
                     + "占地最小，适合缩到很扁的尺寸。") },
        { value: "mini", name: i18n("迷你月历 + 今日"),
          hint: i18n("左边一个小月历（只有日号，节假日那天一个色点），"
                     + "右边是今天的农历与节气。面积约为整月网格的一半。") },
        { value: "upcoming", name: i18n("假期倒计时"),
          hint: i18n("接下来几个法定节假日排成一列，带「3 天后」这样的倒计时。"
                     + "回答「最近的假是哪天」。调休上班日不算假期。") },
        { value: "almanac", name: i18n("农历详情"),
          hint: i18n("把今天讲透：干支纪年与生肖（丙午年 · 马）、农历月日、"
                     + "下个节气还有几天、下一个农历节日、本月有哪两个节气。") },
        { value: "countdown", name: i18n("倒计时"),
          hint: i18n("自己定的目标卡片：「距离考研 88 天」，或从某天起正向数「开学第 22 天」。"
                     + "目标在「倒计时」页里增删，第一条是大卡，其余排成小行。") }
    ]

    readonly property int styleIndex: {
        for (var i = 0; i < styles.length; i++) {
            if (styles[i].value === styleHolder.text) {
                return i;
            }
        }
        return 0;
    }

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: styleCombo

            Kirigami.FormData.label: i18n("显示样式：")
            textRole: "name"
            model: page.styles
            currentIndex: page.styleIndex
            onActivated: function (index) {
                styleHolder.text = page.styles[index].value;
                page.configurationChanged();
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 34
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: page.styles[page.styleIndex] ? page.styles[page.styleIndex].hint : ""
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 34
            wrapMode: Text.WordWrap
            opacity: 0.6
            font.pointSize: Math.max(6, Kirigami.Theme.smallFont.pointSize)
            text: i18n("放桌面上用完整样式；拖到面板（任务栏）里时自动换成一行紧凑视图"
                       + "（「22 八月十二」），不受这里影响 —— 面板上位置太窄，"
                       + "点击展开完整视图。")
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("背景与卡片")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("背景不透明度：")

            QQC2.Slider {
                id: opacitySlider
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                from: 0
                to: 100
                stepSize: 5
                snapMode: QQC2.Slider.SnapAlways
                onMoved: page.configurationChanged()
            }
            QQC2.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                text: Math.round(opacitySlider.value) + "%"
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 34
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: i18n("组件底板的透明度。调到 0 就只剩内容浮在桌面上，完全没有背景板。")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("卡片不透明度：")

            QQC2.Slider {
                id: cardOpacitySlider
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                from: 0
                to: 100
                stepSize: 5
                snapMode: QQC2.Slider.SnapAlways
                onMoved: page.configurationChanged()
            }
            QQC2.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                text: Math.round(cardOpacitySlider.value) + "%"
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 34
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: i18n("卡片底色的透明度。调到 0 就只剩文字和细描边，卡片本身看不见了。\n"
                       + "文字与「休 / 班」徽章始终不透明 —— 跟着一起淡的话会糊在壁纸上读不清。")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 34
            wrapMode: Text.WordWrap
            opacity: 0.6
            font.pointSize: Math.max(6, Kirigami.Theme.smallFont.pointSize)
            text: i18n("两者相互独立：可以把底板留实、卡片调透，也可以反过来。\n"
                       + "整月网格不受卡片不透明度影响 —— 那里的格子是日历本身，没有卡片。\n"
                       + "背景由组件自己绘制，所以这里的不透明度是准的；"
                       + "组件右键菜单里 Plasma 那个「背景」开关不再起作用。")
        }
    }
}
