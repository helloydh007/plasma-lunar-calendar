/*
 * 农历月历 —— 桌面常驻月历，农历数据来自 KDE 官方 alternatecalendar
 * 插件（plasma-calendar-addons），与系统托盘时钟的农历完全同源。
 *
 * ── 三个必须遵守的约束（都踩过坑，改代码前先读）──
 *  1. root 必须是 PlasmoidItem。libPlasmaQuick 有硬性检查
 *     "The root item of %1 must be of type PlasmoidItem"，
 *     用普通 Item 作根会被 plasmashell 拒绝加载并静默移除组件。
 *  2. 驱动「显示哪个月」的是 today（对应内部 backend 的 today），
 *     与数字时钟的用法一致。currentDate 是「被选中的日期」，由组件
 *     内部在用户点击某天时赋值，不是初始化入口；不设 today 会让后端
 *     停在未初始化的 0 年，整月显示成负数日期。
 *  3. 每个月格子要容纳「公历数字 + 农历文字」两层文字，内容区高度
 *     不足约 400px 时两层会叠印在一起。
 *
 * ── 自动刷新（为什么需要）──
 *   today 若在创建时只求值一次，长时间不重启 plasmashell 就会停在过去：
 *   「今天」高亮不再移动，跨月后显示的还是上个月。下面用每分钟检查一次
 *   的 Timer 修正。
 *
 *   日历后端的 today 与 displayedDate 是相互独立的两个属性（见
 *   calendarplugin.qmltypes），因此更新 today 只更新高亮判定，不会移动
 *   用户正在浏览的月份；只有真正跨月时才重建表示层，让日历回到当前月。
 */

pragma ComponentBehavior: Bound

import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.calendar as PlasmaCalendar

PlasmoidItem {
    id: root

    // 当前日期。必须可变：创建时取一次的静态值会随时间变旧。
    property date today: new Date()

    // 表示层重建计数器。跨月时 +1，触发日历重建以显示新的当前月。
    // 之所以要重建：MonthView 没有公开的「跳转到某月」接口
    // （selectedMonth / selectedYear 都是只读别名，resetToToday 是内部
    // 实现），而 displayedDate 不会跟随 today 自动前进。
    property int generation: 0

    // 首次拖到桌面时的默认尺寸。注意桌面容器存下来的几何值会比实际
    // 内容区大约 48px，所以 ItemGeometries 里存 464x464 左右较合适。
    implicitWidth: 420
    implicitHeight: 410

    // 每分钟核对一次日期：跨天则更新「今天」高亮，跨月则额外重建表示层。
    Timer {
        interval: 60000
        running: true
        repeat: true

        onTriggered: {
            const now = new Date();
            const dayChanged = now.getDate() !== root.today.getDate();
            const monthChanged = now.getMonth() !== root.today.getMonth()
                || now.getFullYear() !== root.today.getFullYear();

            if (dayChanged || monthChanged) {
                root.today = now;
            }
            if (monthChanged) {
                root.generation += 1;
            }
        }
    }

    fullRepresentation: Item {
        id: representation

        implicitWidth: 420
        implicitHeight: 410

        Loader {
            id: calendarLoader

            anchors.fill: parent
            sourceComponent: calendarComponent

            // 跨月时重建整棵子树：新的 today 生效，且日历回到当前月。
            Connections {
                target: root

                function onGenerationChanged() {
                    calendarLoader.active = false;
                    calendarLoader.active = true;
                }
            }
        }
    }

    Component {
        id: calendarComponent

        Item {
            PlasmaCalendar.EventPluginsManager {
                id: eventPluginsManager

                // 只加载 alternatecalendar 这一个日历事件插件。它的历法
                // 选择默认跟随系统 locale（zh_CN → 中国农历），与托盘
                // 时钟未写配置时的行为一致。
                enabledPlugins: ["alternatecalendar"]
            }

            PlasmaCalendar.MonthView {
                anchors.fill: parent

                eventPluginsManager: eventPluginsManager

                // 不要改成 currentDate：那是「被选中的日期」，
                // 不是显示月份的驱动入口。
                today: root.today
            }
        }
    }
}
