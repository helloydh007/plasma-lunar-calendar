/*
 * 配置页：倒计时
 *
 * 倒计时目标就是「一个名字 + 一个日期 + 一种数法」，在这里增删改：
 *   · 倒计时（down）：距离那天还有几天。过了那天显示「已过 N 天」
 *   · 正向（up）：那天算第 1 天，往后「第 N 天」地数
 *
 * 数据整体存成一个 JSON 数组（main.xml 里的 countdowns）。本页持有编辑副本，
 * 任何改动立即序列化回 cfg_countdowns 并启用「应用」；名字或日期没填完的行
 * 不写入。日期逐个校验（拒绝 2026-02-30 这类），无效的标红并给出预览位置提示。
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

import "termweek.js" as TermWeek
import "viewdata.js" as ViewData

KCMUtils.SimpleKCM {
    id: page

    // KCM 框架的约定：配置页自己声明并发出此信号，宿主据此启用「应用」按钮。
    signal configurationChanged()

    property alias cfg_countdowns: holder.text

    // 不展示，仅作为 cfg_ 的载体
    QQC2.TextField { id: holder; visible: false; width: 0; height: 0 }

    // 编辑副本。字段补齐成固定形状，委托里的绑定才不会因为缺键而告警。
    //
    // 用绑定（而不是只在 onCompleted 里解析一次）读入配置：KCM 宿主把 cfg_
    // 值推进来的时机不保证早于 onCompleted，绑定能保证「值一到就解析」。
    // 首次编辑（addOne / edit / removeAt 给 entries 赋值）会自然断开这个
    // 绑定 —— 之后条目由编辑器接管，commit() 显式写回 holder.text，
    // 不会被重新解析冲掉。
    property var entries: parseList(holder.text)

    function parseList(raw) {
        let list = [];
        try {
            const parsed = JSON.parse(raw);
            if (Array.isArray(parsed)) {
                list = parsed;
            }
        } catch (e) {
            list = [];
        }
        const out = [];
        for (let i = 0; i < list.length; ++i) {
            const e = list[i] || {};
            out.push({
                name: String(e.name || ""),
                date: String(e.date || ""),
                mode: e.mode === "up" ? "up" : "down"
            });
        }
        return out;
    }

    function commit() {
        const out = [];
        for (let i = 0; i < page.entries.length; ++i) {
            const e = page.entries[i];
            if (e.name === "" || e.date === "") {
                continue;               // 没填完的行不入库
            }
            out.push({ name: e.name, date: e.date, mode: e.mode });
        }
        holder.text = JSON.stringify(out);
        page.configurationChanged();
    }

    function edit(i, key, val) {
        const a = page.entries.slice();
        const e = a[i];
        a[i] = { name: e.name, date: e.date, mode: e.mode };
        a[i][key] = val;
        page.entries = a;
        page.commit();
    }

    function removeAt(i) {
        const a = page.entries.slice();
        a.splice(i, 1);
        page.entries = a;
        page.commit();
    }

    function addOne() {
        page.entries = page.entries.concat([{ name: "", date: "", mode: "down" }]);
    }

    // ── 单行校验与预览 ──
    function dateValid(s) {
        return s !== "" && TermWeek.parseIsoDate(s) !== null;
    }

    function previewText(e) {
        if (e.name === "" && e.date === "") {
            return i18n("新行");
        }
        const d = TermWeek.parseIsoDate(e.date);
        if (!d) {
            return e.date === "" ? i18n("日期还没填") : i18n("日期无效");
        }
        const diff = ViewData.daysBetween(new Date(), d);
        if (e.mode === "up") {
            if (diff > 0) {
                return i18n("尚未开始");
            }
            return diff === 0 ? i18n("今天第 1 天") : i18n("预览：第 %1 天", 1 - diff);
        }
        if (diff > 0) {
            return i18n("预览：还有 %1 天", diff);
        }
        return diff === 0 ? i18n("预览：就是今天") : i18n("预览：已过 %1 天", -diff);
    }

    function previewValid(e) {
        return dateValid(e.date);
    }

    bottomPadding: Kirigami.Units.largeSpacing

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 30
            Layout.leftMargin: Kirigami.Units.largeSpacing
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: i18n("倒计时目标是自定义的重要日期：考试、纪念日、项目截止……"
                       + "每条可以选「倒计时」（距离那天还有几天）或"
                       + "「正向」（那天算第 1 天，往后数第 N 天）。"
                       + "在组件上选「倒计时」显示样式即可看到这些卡片。")
        }

        // ── 每条目标一个编辑行 ──
        Repeater {
            model: page.entries.length

            delegate: RowLayout {
                id: entryRow

                required property int index

                readonly property var e: page.entries[index]

                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                Layout.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: nameField

                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                    placeholderText: i18n("名称（如：考研）")
                    text: entryRow.e.name
                    onTextEdited: page.edit(entryRow.index, "name", text)
                }

                QQC2.TextField {
                    id: dateField

                    Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                    placeholderText: "yyyy-MM-dd"
                    inputMethodHints: Qt.ImhDate | Qt.ImhPreferNumbers
                    text: entryRow.e.date
                    color: page.dateValid(text) || text === ""
                        ? palette.text : Kirigami.Theme.negativeTextColor
                    onTextEdited: page.edit(entryRow.index, "date", text)
                }

                QQC2.ComboBox {
                    id: modeCombo

                    textRole: "text"
                    model: [
                        { text: i18n("倒计时"), value: "down" },
                        { text: i18n("正向（第 N 天）"), value: "up" }
                    ]
                    currentIndex: entryRow.e.mode === "up" ? 1 : 0
                    onActivated: function (index) {
                        page.edit(entryRow.index, "mode", model[index].value);
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    opacity: 0.75
                    text: page.previewText(entryRow.e)
                    color: page.previewValid(entryRow.e)
                        ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                }

                QQC2.ToolButton {
                    icon.name: "list-remove"
                    QQC2.ToolTip.text: i18n("删除这一条")
                    QQC2.ToolTip.visible: hovered
                    onClicked: page.removeAt(entryRow.index)
                }
            }
        }

        QQC2.Button {
            Layout.leftMargin: Kirigami.Units.largeSpacing
            icon.name: "list-add"
            text: i18n("添加一条")
            onClicked: page.addOne()
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 30
            Layout.leftMargin: Kirigami.Units.largeSpacing
            wrapMode: Text.WordWrap
            opacity: 0.6
            font.pointSize: Math.max(6, Kirigami.Theme.smallFont.pointSize)
            text: i18n("日期格式 yyyy-MM-dd。没填完的行不会保存；删除组件样式里"
                       + "看不到的条目也在这里。显示样式在「外观」页里选「倒计时」。")
        }
    }
}
