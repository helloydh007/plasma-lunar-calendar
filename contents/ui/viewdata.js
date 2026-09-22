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
