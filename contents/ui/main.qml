/*
 * 农历月历 —— 桌面常驻月历，农历数据来自 KDE 官方 alternatecalendar
 * 插件（plasma-calendar-addons），与系统托盘时钟的农历完全同源。
 *
 * ── 五个必须遵守的约束（都踩过坑，改代码前先读）──
 *  1. root 必须是 PlasmoidItem。libPlasmaQuick 有硬性检查
 *     "The root item of %1 must be of type PlasmoidItem"，
 *     用普通 Item 作根会被 plasmashell 拒绝加载并静默移除组件。
 *  2. 整月网格里驱动「显示哪个月」的是 today（对应内部 backend 的 today），
 *     与数字时钟的用法一致。currentDate 是「被选中的日期」，由组件
 *     内部在用户点击某天时赋值，不是初始化入口；不设 today 会让后端
 *     停在未初始化的 0 年，整月显示成负数日期。
 *  3. 每个月格子要容纳「公历数字 + 农历文字」两层文字，内容区高度
 *     不足约 400px 时两层会叠印在一起。
 *  4. 自定义周数列（见 StyleMonth.qml）靠 MonthView 暴露的 cellHeight /
 *     borderWidth / viewHeader / rows 来对齐，勿硬编码像素值。
 *  5. 「切到月/年视图后标记不消失」那个 bug 的根因是：把引用了 MonthView
 *     的属性定义在了另一个文件的作用域里。失败的绑定会让 visible 停在
 *     默认值 true。所以凡是读 MonthView 几何的属性，都必须和 MonthView
 *     待在同一个文件里。
 *
 * ── 五种显示样式 ──
 *   month（整月网格，默认）/ today（今日）/ week（本周）/
 *   mini（迷你月历 + 今日）/ upcoming（假期倒计时），设置里切换。
 *   每种样式在 contents/ui/Style*.qml 里，本文件只负责数据与装配。
 *
 * ── 农历数据从哪来 ──
 *   下面有一个独立的 PlasmaCalendar.Calendar 后端（lunarBackend）。它不
 *   依赖任何视图被实例化，只为算出「当前月网格覆盖的 42 天」的农历文字。
 *   42 个 Delegate 各自把自己的那一格发布到 root.cells，五种样式共用。
 *   （之前是让整月网格从 MonthView 的 daysModel 里读，一旦换成别的样式
 *     就没有日期可读了，而且换月时容易读到陈旧数据。）
 *
 *   插件的数据是异步算出来的（实测几秒内到），所以读取一律走绑定；
 *   在 Component.onCompleted 里快照会永远拿到空字符串。
 *
 * ── 自动刷新 ──
 *   today 若在创建时只求值一次，长时间不重启 plasmashell 就会停在过去：
 *   「今天」高亮不再移动，跨月后显示的还是上个月。下面用每分钟检查一次
 *   的 Timer 修正。日历后端的 today 与 displayedDate 是相互独立的两个属性
 *   （见 calendarplugin.qmltypes），更新 today 只更新高亮判定，不会移动
 *   用户正在浏览的月份；只有真正跨月时才重建表示层，让日历回到当前月。
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg 1.0 as KSvg
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.workspace.calendar as PlasmaCalendar

import "termweek.js" as TermWeek
import "holidays.js" as Holidays
import "holidays-update.js" as HolidaysNet
import "viewdata.js" as ViewData

PlasmoidItem {
    id: root

    /*
     * 背景由组件自己画，所以设成 NoBackground。
     * Plasma 默认那个背景板的不透明度是改不了的，而设置里要给出可调的不透明度，
     * 只能把背景拿过来自己画一层（见 fullRepresentation 里的 bg）。
     * 代价是组件右键菜单里 Plasma 那个「背景」开关不再起作用 —— 配置页里有等效且更细的控制。
     */
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    /*
     * 色组要显式指定成 Window。
     * widgets/background 那个 SVG 是按颜色方案上色的，不指定色组时 applet
     * 默认落在 View 上，背景会解析成别的颜色 —— 而桌面容器的
     * BasicAppletContainer 用的正是 Kirigami.Theme.Window，两边必须一致
     * 才看得出是同一块板。
     */
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window

    // ══════════════════ 配置 ══════════════════

    // 显示样式。认不出来的值一律当整月网格，免得配置被手改坏之后什么都不显示。
    readonly property string viewStyle: {
        const v = Plasmoid.configuration.viewStyle;
        if (v === "today" || v === "week" || v === "mini" || v === "upcoming") {
            return v;
        }
        return "month";
    }

    // 背景 / 卡片不透明度（0..1）。
    // 不能用 `Number(x) || 100`：0 是合法取值，会被 || 吞掉。
    function opacityFrom(value) {
        let v = Number(value);
        if (!isFinite(v)) {
            v = 100;
        }
        return Math.max(0, Math.min(100, Math.round(v))) / 100;
    }

    readonly property real backgroundOpacity:
        root.opacityFrom(Plasmoid.configuration.backgroundOpacity)
    readonly property real cardOpacity:
        root.opacityFrom(Plasmoid.configuration.cardOpacity)

    readonly property var termStartDate: TermWeek.parseIsoDate(Plasmoid.configuration.termStart)
    readonly property bool termWeeksVisible: Plasmoid.configuration.showTermWeeks
        && termStartDate !== null
    readonly property bool holidaysVisible: Plasmoid.configuration.showHolidays

    // 联网获取到的节假日数据（只含内置数据未覆盖的年份）。配置里的 JSON 串
    // 解析失败时静默降级为空缓存，此时仅使用内置数据。
    readonly property var holidayCache: HolidaysNet.parseCache(Plasmoid.configuration.holidayCache)

    // ══════════════════ 时间 ══════════════════

    // 当前日期。必须可变：创建时取一次的静态值会随时间变旧。
    property date today: new Date()

    // 表示层重建计数器。跨月时 +1，触发日历重建以显示新的当前月。
    property int generation: 0

    // 自动更新是否正在进行：防止慢网络下每小时定时器与上一次请求重叠。
    property bool holidayUpdating: false

    // ══════════════════ 农历数据源 ══════════════════

    /*
     * 42 个日期格子的数据，索引 0 是当前月网格的第一格（行首＝周首日）。
     * 每格：{ year, month, day, dayText, lunar, full, isTerm }
     *   dayText 公历日号（「22」）
     *   lunar   农历短标签（「十二」，初一那天是月名「八月」，节气当天是节气名「白露」）
     *   full    农历完整写法（「丙午八月十二」，节气当天带括号「丙午七月廿六 (白露)」）
     */
    property var cells: []

    function publishCell(index, cell) {
        const arr = root.cells.slice();
        arr[index] = cell;
        root.cells = arr;
    }

    PlasmaCalendar.Calendar {
        id: lunarBackend

        days: 7
        weeks: 6
        firstDayOfWeek: Qt.locale().firstDayOfWeek
        today: root.today
        // displayedDate 决定这 42 天从哪天起算。绑到 today 上，
        // 跨月时范围自动跟着走，不用重建后端。
        displayedDate: root.today

        Component.onCompleted: daysModel.setPluginsManager(eventPluginsManager)
    }

    // 只为了读 42 个格子的角色，不参与任何布局。
    // 用 stamp 绑定（而不是创建时读一次）是必须的：农历文字是插件异步给的，
    // 一次性的读取只会拿到空串。
    Item {
        id: cellSource

        visible: false
        width: 0
        height: 0

        Repeater {
            model: lunarBackend.daysModel

            delegate: Item {
                id: cellReader

                required property int index
                required property var model

                readonly property string stamp: model.yearNumber + "/"
                    + model.monthNumber + "/" + model.dayNumber + "|"
                    + model.dayLabel + "|" + model.subDayLabel + "|" + model.subLabel

                visible: false
                width: 0
                height: 0

                function publish() {
                    const full = model.subLabel || "";
                    root.publishCell(index, {
                        year: model.yearNumber,
                        month: model.monthNumber,
                        day: model.dayNumber,
                        dayText: String(model.dayLabel !== undefined && model.dayLabel !== null
                                        ? model.dayLabel : model.dayNumber),
                        lunar: model.subDayLabel || "",
                        full: full,
                        // 节气在完整写法里带括号：丙午七月廿六 (白露)
                        isTerm: full.indexOf("(") >= 0 || full.indexOf("（") >= 0
                    });
                }

                onStampChanged: publish()
                Component.onCompleted: publish()
            }
        }
    }

    // ══════════════════ 派生数据 ══════════════════

    readonly property int todayIndex: ViewData.indexOfToday(root.cells, root.today)
    // 今天在本周那一行里的下标（0 = 周首日）
    readonly property int todayColumn: root.todayIndex >= 0 ? root.todayIndex % 7 : -1
    readonly property var weekCells: ViewData.weekRowOf(root.cells, root.todayIndex)

    readonly property string monthTitle: Qt.locale()
        .standaloneMonthName(root.today.getMonth(), Locale.LongFormat)

    // 学期周次（未设置起始日、或今天早于第 1 周时不显示）
    readonly property int todayTermWeek: root.termStartDate
        ? TermWeek.termWeekOf(root.today, root.termStartDate, Qt.locale().firstDayOfWeek)
        : 0
    readonly property string termWeekLabel: root.todayTermWeek >= 1
        ? i18n("第 %1 周", root.todayTermWeek) : ""

    // 节假日：缓存优先（联网获取到的年份），未命中回落到内置数据表
    function holidayOfCell(cell) {
        if (!cell) {
            return null;
        }
        return HolidaysNet.statusFromCache(cell.year, cell.month, cell.day, root.holidayCache)
            || Holidays.statusFor(cell.year, cell.month, cell.day);
    }

    function holidayOfDate(d) {
        return HolidaysNet.statusFromCache(d.getFullYear(), d.getMonth() + 1, d.getDate(),
                                           root.holidayCache)
            || Holidays.statusFor(d.getFullYear(), d.getMonth() + 1, d.getDate());
    }

    readonly property var cellHolidays: {
        const out = [];
        for (let i = 0; i < root.cells.length; ++i) {
            out.push(root.holidayOfCell(root.cells[i]));
        }
        return out;
    }

    readonly property var weekHolidays: {
        const out = [];
        for (let i = 0; i < root.weekCells.length; ++i) {
            out.push(root.holidayOfCell(root.weekCells[i]));
        }
        return out;
    }

    readonly property var todayHoliday: root.holidayOfDate(root.today)

    // 接下来几个法定节假日（连续的同名放假日算一段）。最远找 400 天。
    readonly property var upcoming: ViewData.upcomingOffDays(root.today, 400, 6,
                                                             root.holidayOfDate)

    // 往后一年内有没有可用数据。缺数据时要说清楚是「没有」还是「没取到」，
    // 免得空列表看着像坏了。
    readonly property bool dataCoversFuture: {
        const y = root.today.getFullYear();
        const years = Object.keys(root.holidayCache.years || {});
        function covered(year) {
            for (let i = 0; i < years.length; ++i) {
                if (Number(years[i]) === year) {
                    return true;
                }
            }
            return Holidays.isYearCovered(year);
        }
        return covered(y) && covered(y + 1);
    }

    // 首次拖到桌面时的默认尺寸。注意桌面容器存下来的几何值会比实际
    // 内容区大约 48px，所以 ItemGeometries 里存 464x464 左右较合适。
    // 高度按样式给：周条只要一条，给太高反而缩不下去。
    readonly property int styleImplicitHeight: {
        switch (root.viewStyle) {
        case "today":
            return 320;
        case "week":
            return 130;
        case "mini":
            return 300;
        case "upcoming":
            return 320;
        }
        return 410;
    }

    implicitWidth: 420
    implicitHeight: root.styleImplicitHeight

    // ══════════════════ 定时器 ══════════════════

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

    // 自动更新：仅当配置为 auto 时才动作。每小时核对一次节律，
    // 真正联网拉取受 AUTO_CHECK_INTERVAL_DAYS（30 天）限制，
    // 且只会去取「内置数据与缓存都没有的年份」。
    Timer {
        interval: 3600000
        running: Plasmoid.configuration.holidayUpdateMode === "auto"
        repeat: true
        triggeredOnStart: true

        onTriggered: {
            if (root.holidayUpdating) {
                return;                 // 上一次还没结束，跳过本轮
            }
            const now = new Date();
            if (!HolidaysNet.shouldAutoCheck(root.holidayCache, now)) {
                return;
            }
            root.holidayUpdating = true;
            HolidaysNet.runUpdate(root.holidayCache, now, Holidays.COVERED_YEARS, null, function (result) {
                root.holidayUpdating = false;
                if (result.fetched.length > 0) {
                    Plasmoid.configuration.holidayCache = HolidaysNet.serializeCache(result.cache);
                    console.log("holidays: 自动更新成功，年份 " + result.fetched.join(", "));
                } else {
                    // 即便没取到也要记录检查时间，避免每小时重复尝试
                    Plasmoid.configuration.holidayCache = HolidaysNet.serializeCache(result.cache);
                    console.log("holidays: 自动检查完成，无新增（" + result.messages.join("；") + "）");
                }
            });
        }
    }

    // ══════════════════ 表示层 ══════════════════

    fullRepresentation: Item {
        implicitWidth: 420
        implicitHeight: root.styleImplicitHeight

        /*
         * 自己画的背景，用桌面主题的 widgets/background 边框 —— 桌面容器画的
         * applet 背景就是它，所以外观和原来一致。
         *
         * 这里用 opacity 是安全的：这个项没有子项，不像 Item.opacity 会把内容一起变淡。
         */
        KSvg.FrameSvgItem {
            id: bg

            anchors.fill: parent
            imagePath: "widgets/background"
            opacity: root.backgroundOpacity
        }

        Loader {
            id: styleLoader

            anchors.fill: parent
            // 内容按主题边框的内边距缩进，和容器画背景时的位置一致。
            // 取不到 margins 就退化成铺满，不影响可用性。
            anchors.margins: bg.margins ? bg.margins.left : 0

            sourceComponent: root.styleComponent

            // 跨月时重建整棵子树：新的 today 生效，且整月网格回到当前月。
            Connections {
                target: root

                function onGenerationChanged() {
                    styleLoader.active = false;
                    styleLoader.active = true;
                }
            }
        }
    }

    readonly property Component styleComponent: {
        switch (root.viewStyle) {
        case "today":
            return styleTodayComponent;
        case "week":
            return styleWeekComponent;
        case "mini":
            return styleMiniComponent;
        case "upcoming":
            return styleUpcomingComponent;
        }
        return styleMonthComponent;
    }

    Component {
        id: styleMonthComponent

        StyleMonth {
            cells: root.cells
            cellHolidays: root.cellHolidays
            termWeeksVisible: root.termWeeksVisible
            termStartDate: root.termStartDate
            holidaysVisible: root.holidaysVisible
            eventPluginsManager: eventPluginsManager
            today: root.today
        }
    }

    Component {
        id: styleTodayComponent

        StyleToday {
            todayCell: root.todayIndex >= 0 ? root.cells[root.todayIndex] : null
            weekCells: root.weekCells
            todayColumn: root.todayColumn
            weekHolidays: root.weekHolidays
            holiday: root.todayHoliday
            termWeekLabel: root.termWeekLabel
            cardOpacity: root.cardOpacity
        }
    }

    Component {
        id: styleWeekComponent

        StyleWeek {
            weekCells: root.weekCells
            todayColumn: root.todayColumn
            weekHolidays: root.weekHolidays
            termWeekLabel: root.termWeekLabel
            monthText: root.monthTitle
            cardOpacity: root.cardOpacity
        }
    }

    Component {
        id: styleMiniComponent

        StyleMini {
            cells: root.cells
            cellHolidays: root.cellHolidays
            todayIndex: root.todayIndex
            todayHoliday: root.todayHoliday
            termWeekLabel: root.termWeekLabel
            cardOpacity: root.cardOpacity
        }
    }

    Component {
        id: styleUpcomingComponent

        StyleUpcoming {
            upcoming: root.upcoming
            todayCell: root.todayIndex >= 0 ? root.cells[root.todayIndex] : null
            termWeekLabel: root.termWeekLabel
            dataCoversFuture: root.dataCoversFuture
            cardOpacity: root.cardOpacity
        }
    }

    PlasmaCalendar.EventPluginsManager {
        id: eventPluginsManager

        // 只加载 alternatecalendar 这一个日历事件插件。它的历法
        // 选择默认跟随系统 locale（zh_CN → 中国农历），与托盘
        // 时钟未写配置时的行为一致。
        enabledPlugins: ["alternatecalendar"]
    }
}
