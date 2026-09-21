/*
 * 配置页
 *
 * 五项：法定节假日标记开关、数据更新方式与「立即更新」、学期周数开关与起始日。
 *
 * 学期周数的起始日只需落在第 1 周内的任意一天即可——计算时会自动折到该周的
 * 首日，所以「开学日 9 月 1 日（周二）」和「8 月 31 日（周一）」结果相同。
 *
 * 联网更新由本页的按钮主动触发（点击后立即拉取并校验），或在组件里设为自动
 * 模式后由组件按节律检查。拉取到的数据只有当通过校验才会被采用。
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

import "termweek.js" as TermWeek
import "holidays.js" as Holidays
import "holidays-update.js" as HolidaysNet

KCMUtils.SimpleKCM {
    id: page

    // KCM 框架的约定：配置页自己声明并发出此信号，宿主据此启用「应用」按钮。
    // SimpleKCM / AbstractKCM 本身并未定义它（已核对上游源码）。
    signal configurationChanged()

    property alias cfg_showTermWeeks: showSwitch.checked
    property alias cfg_termStart: termStartField.text
    property alias cfg_showHolidays: showHolidaysSwitch.checked
    property alias cfg_holidayUpdateMode: modeHolder.text
    property alias cfg_holidayCache: cacheHolder.text

    property bool updating: false
    property string updateStatus: ""

    // 不展示，仅作为 cfg_ 的载体（SimpleKCM 通过 cfg_ 前缀属性读写配置）
    QQC2.TextField { id: modeHolder; visible: false; width: 0; height: 0 }
    QQC2.TextField { id: cacheHolder; visible: false; width: 0; height: 0 }

    // 当前数据覆盖情况：内置年份 + 联网获取到的年份
    readonly property string coverageText: {
        const builtin = Holidays.COVERED_YEARS;
        const cached = Object.keys(HolidaysNet.parseCache(cacheHolder.text).years).sort();
        let t = i18n("内置数据：%1", builtin.length ? builtin[0] + "–" + builtin[builtin.length - 1] : i18n("无"));
        t += cached.length ? i18n("；联网获取：%1", cached.join("、")) : i18n("；联网获取：无");
        return t;
    }

    function startUpdate() {
        page.updating = true;
        page.updateStatus = i18n("正在检查…");
        const cache = HolidaysNet.parseCache(cacheHolder.text);
        HolidaysNet.runUpdate(cache, new Date(), Holidays.COVERED_YEARS,
            function (msg) {
                page.updateStatus = msg;
            },
            function (result) {
                page.updating = false;
                let txt = result.messages.join("\n");
                if (result.fetched.length > 0) {
                    cacheHolder.text = HolidaysNet.serializeCache(result.cache);
                    page.configurationChanged();
                    txt += "\n" + i18n("✓ 已获取 %1 年数据，请点「应用」保存后生效。",
                                        result.fetched.join("、"));
                }
                page.updateStatus = txt;
            });
    }

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
            id: showHolidaysSwitch

            Kirigami.FormData.label: i18n("法定节假日：")
            text: i18n("在日期上标记「休 / 班」")
            onToggled: page.configurationChanged()
        }

        QQC2.ComboBox {
            id: modeCombo

            Kirigami.FormData.label: i18n("数据更新方式：")
            textRole: "text"
            model: [
                { text: i18n("手动（默认）"), value: "manual" },
                { text: i18n("自动（每 30 天检查一次）"), value: "auto" }
            ]
            currentIndex: Math.max(0, model.findIndex(function (x) {
                return x.value === modeHolder.text;
            }))
            onActivated: function (index) {
                modeHolder.text = model[index].value;
                page.configurationChanged();
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("节假日数据：")

            QQC2.Button {
                id: updateButton
                text: page.updating ? i18n("更新中…") : i18n("立即更新")
                enabled: !page.updating
                onClicked: page.startUpdate()
            }

            QQC2.BusyIndicator {
                running: page.updating
                visible: running
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: page.coverageText + "\n"
                + i18n("放假安排由国务院逐年发文规定（含调休），无法由历法推算，故使用数据表。")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            visible: page.updateStatus !== ""
            text: page.updateStatus
            color: text.indexOf("✓") >= 0 ? Kirigami.Theme.positiveTextColor
                 : (text.indexOf("✗") >= 0 || text.indexOf("HTTP") >= 0
                    ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor)
        }

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
