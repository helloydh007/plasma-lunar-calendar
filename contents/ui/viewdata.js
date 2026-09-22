/*
 * 各显示样式共用的派生数据。
 *
 * 只有纯计算，没有 import —— .pragma library 里不允许 import 别的 JS 脚本
 * （QML 语法，不是 JS 语法），所以需要节假日表的地方一律由调用方传进来
 * （见 upcomingOffDays 的 statusFn）。
 */

.pragma library

// 把日期折成「第几天」，用来做跨月/跨年的天数差。
// termweek.js 里有一个同名函数，两个库不能互相 import，这里保持一份副本。
function dayIndex(d) {
    return Math.floor(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
}

function daysBetween(from, to) {
    return dayIndex(to) - dayIndex(from);
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear()
        && a.getMonth() === b.getMonth()
        && a.getDate() === b.getDate();
}

// 42 个格子里今天所在的下标；不在范围内返回 -1
function indexOfToday(cells, today) {
    for (var i = 0; i < cells.length; ++i) {
        var c = cells[i];
        if (c && c.year === today.getFullYear()
                && c.month === today.getMonth() + 1
                && c.day === today.getDate()) {
            return i;
        }
    }
    return -1;
}

// 取 index 所在的那一整行（7 格）。月历网格固定 7 列，行首就是周首日。
// 数据没就绪时返回能取到的部分，调用方自己判空。
function weekRowOf(cells, index) {
    if (index < 0) {
        return [];
    }
    var start = Math.floor(index / 7) * 7;
    var out = [];
    for (var k = 0; k < 7; ++k) {
        out.push(cells[start + k] || null);
    }
    return out;
}

// 从今天起往后的「放假的连续段」。
//   · 连续的同名放假日算一段（春节 7 天是一段，不是 7 条）
//   · daysAway 是从今天起第几天（0 = 今天）
//   · 只收 type === "off"；调休上班（"work"）不算假期
// statusFn(date) → null | { type, name }
function upcomingOffDays(today, maxDays, count, statusFn) {
    var out = [];
    var run = null;
    for (var offset = 0; offset < maxDays; ++offset) {
        var d = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset);
        var st = statusFn(d);
        if (st && st.type === "off") {
            if (run && run.name === st.name && offset === run.lastOffset + 1) {
                run.lastOffset = offset;
                run.length += 1;
            } else {
                if (out.length >= count) {
                    break;
                }
                run = {
                    name: st.name,
                    date: d,
                    length: 1,
                    lastOffset: offset,
                    daysAway: offset
                };
                out.push(run);
            }
        }
    }
    return out;
}

// ── 「农历详情」样式要用的几样 ──

// 农历节日。key 是 alternatecalendar 完整写法里的「月+日」片段，
// 例如八月十五那天 subLabel = 「丙午八月十五」，用 indexOf 就能认出来。
// 注意写法：农历日用「初一…初十、十一…十九、二十、廿一…廿九、三十」这套。
var LUNAR_FESTIVALS = [
    { key: "正月初一", name: "春节" },
    { key: "正月十五", name: "元宵节" },
    { key: "二月初二", name: "龙抬头" },
    { key: "五月初五", name: "端午节" },
    { key: "七月初七", name: "七夕" },
    { key: "八月十五", name: "中秋节" },
    { key: "九月初九", name: "重阳节" },
    { key: "腊月初八", name: "腊八" },
    { key: "腊月廿三", name: "小年" }
];

// 从「丙午八月十二」里取出农历月日（去掉开头的干支两字与后面的节气括号）
function lunarDateText(full) {
    if (!full || full.length <= 2) {
        return "";
    }
    var t = full.substring(2);
    var p = t.indexOf("(");
    if (p < 0) {
        p = t.indexOf("（");
    }
    if (p >= 0) {
        t = t.substring(0, p);
    }
    return t.trim();
}

// 干支纪年 + 生肖。alternatecalendar 的完整写法以「丙午」这样的干支开头，
// 取前两字并校验确实是「天干 + 地支」，避免格式变了之后显示垃圾。
function ganzhiOf(full) {
    var STEMS = "甲乙丙丁戊己庚辛壬癸";
    var BRANCHES = "子丑寅卯辰巳午未申酉戌亥";
    var ZODIAC = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"];
    if (!full || full.length < 2) {
        return null;
    }
    var a = full.charAt(0);
    var b = full.charAt(1);
    var si = STEMS.indexOf(a);
    var bi = BRANCHES.indexOf(b);
    if (si < 0 || bi < 0) {
        return null;
    }
    return { name: a + b, zodiac: ZODIAC[bi] };
}

// 窗口内今天（含）之后的第一个节气。节气那天 subDayLabel 就是节气名。
function nextSolarTerm(cells, today) {
    for (var i = 0; i < cells.length; ++i) {
        var c = cells[i];
        if (!c || !c.isTerm || !c.lunar) {
            continue;
        }
        var d = new Date(c.year, c.month - 1, c.day);
        var away = daysBetween(today, d);
        if (away >= 0) {
            return { name: c.lunar, date: d, daysAway: away };
        }
    }
    return null;
}

// 窗口内今天（含）之后的第一个农历节日。cells 是按日期递增的，所以第一个
// 命中的就是最近的。
function nextLunarFestival(cells, today, festivals) {
    for (var i = 0; i < cells.length; ++i) {
        var c = cells[i];
        if (!c || !c.full) {
            continue;
        }
        for (var j = 0; j < festivals.length; ++j) {
            if (c.full.indexOf(festivals[j].key) >= 0) {
                var d = new Date(c.year, c.month - 1, c.day);
                var away = daysBetween(today, d);
                if (away >= 0) {
                    return { name: festivals[j].name, date: d, daysAway: away };
                }
            }
        }
    }
    return null;
}

// 某个月份里有哪些节气（用于「本月节气」那一行）
function termsInMonth(cells, year, month) {
    var out = [];
    for (var i = 0; i < cells.length; ++i) {
        var c = cells[i];
        if (c && c.isTerm && c.lunar && c.year === year && c.month === month) {
            out.push({ name: c.lunar, date: new Date(c.year, c.month - 1, c.day) });
        }
    }
    return out;
}
