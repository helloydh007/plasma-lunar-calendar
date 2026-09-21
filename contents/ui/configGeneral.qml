/*
 * 学期周数配置页
 *
 * 两个配置项：
 *   · showTermWeeks —— 是否在月历左侧显示自定义周数列
 *   · termStart     —— 第 1 周的起始日（ISO yyyy-MM-dd）
 *
 * 起始日只需落在第 1 周内的任意一天即可——计算时会自动折到该周的首日，
 * 所以「开学日 9 月 1 日（周二）」和「8 月 31 日（周一）」结果相同。
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

import "termweek.js" as TermWeek

KCMUtils.SimpleKCM {
    id: page

    property alias cfg_showTermWeeks: showSwitch.checked
    property alias cfg_termStart: termStartField.text

    readonly property var parsedStart: TermWeek.parseIsoDate(termStartField.text)

    // 0 = 未填写，1 = 格式无效，2 = 有效
    readonly property int inputState: termStartField.text.length === 0 ? 0 : (parsedStart ? 2 : 1)

    readonly property int todayWeek: parsedStart
        ? TermWeek.termWeekOf(new Date(), parsedStart, Qt.locale().firstDayOfWeek)
        : 0

    function setStart(d) {
        termStartField.text = Qt.formatDate(d, "yyyy-MM-dd");
        page.configurationChanged();
    }

    Kirigami.FormLayout {
        QQC2.Switch {
            id: showSwitch

            Kirigami.FormData.label: i18n("学期周数：")
            text: i18n("在月历左侧显示周数")
            onToggled: page.configurationChanged()
        }

        QQC2.TextField {
            id: termStartField

            Kirigami.FormData.label: i18n("第 1 周起始日：")
            placeholderText: "yyyy-MM-dd"
            inputMethodHints: Qt.ImhDate | Qt.ImhPreferNumbers
            onTextEdited: page.configurationChanged()
        }

        RowLayout {
            Kirigami.FormData.label: i18n("快捷设置：")

            QQC2.Button {
                text: i18n("今天")
                onClicked: page.setStart(new Date())
            }

            QQC2.Button {
                text: i18n("本周首日")
                onClicked: {
                    const d = new Date();
                    const back = (d.getDay() - Qt.locale().firstDayOfWeek + 7) % 7;
                    page.setStart(new Date(d.getFullYear(), d.getMonth(), d.getDate() - back));
                }
            }

            QQC2.Button {
                text: i18n("本月 1 日")
                onClicked: {
                    const d = new Date();
                    page.setStart(new Date(d.getFullYear(), d.getMonth(), 1));
                }
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            color: page.inputState === 1
                ? Kirigami.Theme.negativeTextColor
                : Kirigami.Theme.textColor
            opacity: page.inputState === 1 ? 1 : 0.75
            text: {
                switch (page.inputState) {
                case 0:
                    return i18n("尚未设置起始日，周数列不会显示。");
                case 1:
                    return i18n("日期格式无效，请使用 yyyy-MM-dd，例如 2026-09-01。");
                default:
                    return page.todayWeek >= 1
                        ? i18n("预览：今天属于第 %1 周。", page.todayWeek)
                        : i18n("预览：今天早于第 1 周（尚有 %1 周开学）。", 1 - page.todayWeek);
                }
            }
        }
    }
}
