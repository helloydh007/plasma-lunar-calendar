/*
 * 节假日数据的「运行时联网更新」支持
 *
 * 职责划分（重要）：
 *   holidays.js  —— 内置数据表，由 tools/update-from-web.py 生成，请勿手工编辑
 *   本文件        —— 联网拉取、校验、缓存、查询合并的逻辑（纯 JS，可离线单测）
 *
 * 缓存只保存「内置数据里没有的年份」，因此不会随年份累积而膨胀。
 * 缓存在组件配置里（Plasmoid.configuration.holidayCache），格式：
 *     {"2027": {"off": {"2027-01-01": "元旦", ...}, "work": {"2027-01-10": "元旦"}}}
 *
 * 安全性：无论是刚拉取到的数据还是已存缓存，进入使用前都要过一遍 validate 系列
 * 函数。宁可什么都不显示，也不显示错误的节假日——它会实际影响行程安排。
 */

.pragma library

// 注意：.pragma library 脚本里不能写 `import "x.js" as Y`（QML 语法，JS 库不合法）。
// 因此本文件不依赖 holidays.js，需要内置数据的函数一律由调用方显式传入
// （见 builtinYears / statusFromCache 的签名）。这比模块级注入更清晰，
// 也不受 QML 引擎作用域与初始化顺序影响。

// 数据源（按顺序尝试）。两个都指向同一份社区数据集，第二个是 CDN 镜像，
// 在直连 GitHub 受限的网络环境下通常仍可用。
var URL_TEMPLATES = [
    "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/%1.json",
    "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/%1.json"
];

// 自动检查的间隔（天）。放假安排每年 11 月前后发布，按月检查足以在发布后
// 一个月内取到，且不会产生可观的流量。
var AUTO_CHECK_INTERVAL_DAYS = 30;

// 节假日名称 → 放假天数合理区间。
// 含「·」「、」的合并节日（如 2025 年的「国庆节、中秋节」连休 8 天）不适用
// 单节日区间，因此只对精确匹配的名称做天数检查。
var COUNT_RANGES = {
    "元旦":   [1, 3],
    "春节":   [7, 10],
    "清明节": [1, 4],
    "劳动节": [3, 6],
    "端午节": [1, 4],
    "中秋节": [1, 4],
    "国庆节": [5, 8]
};

// 节日的天文/政策窗口（月份均为 1 起算）。日期写错时几乎必然被其中一条抓住。
var INCLUDE_DATES = {
    "元旦":   [[1, 1]],
    "劳动节": [[5, 1]],
    "国庆节": [[10, 1]]
};
var WINDOWS = {
    "春节":   [1, 21, 2, 21],
    "清明节": [4, 4, 4, 6],
    "端午节": [5, 25, 6, 30],
    "中秋节": [9, 5, 10, 10]
};

function urlsFor(year) {
    var out = [];
    for (var i = 0; i < URL_TEMPLATES.length; i++) {
        out.push(URL_TEMPLATES[i].replace("%1", String(year)));
    }
    return out;
}

function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

function dayIndex(y, m, d) {
    return Math.round(Date.UTC(y, m - 1, d) / 86400000);
}

function weekdayOf(y, m, d) {
    return new Date(y, m - 1, d).getDay();   // 0=周日 … 6=周六
}

/* ------------------------------------------------------------------ *
 * 校验
 * ------------------------------------------------------------------ */

// 对「已提取的 off/work 映射」做自检，返回问题描述数组（空数组 = 通过）。
function sanityProblems(off, work, year) {
    var problems = [];
    var k;

    for (k in off) {
        if (work.hasOwnProperty(k)) {
            problems.push("同一天既是放假又是补班：" + k);
        }
    }
    for (k in work) {
        var p = k.split("-");
        var dow = weekdayOf(Number(p[0]), Number(p[1]), Number(p[2]));
        if (dow !== 0 && dow !== 6) {
            problems.push("补班日 " + k + " 不在周末");
        }
    }

    // 每个节日的放假必须是一整段连续日期，且天数在合理区间
    var byName = {};
    for (k in off) {
        var n = off[k];
        if (!byName.hasOwnProperty(n)) {
            byName[n] = [];
        }
        byName[n].push(k);
    }
    for (var name in byName) {
        var ds = byName[name].slice().sort();
        for (var i = 1; i < ds.length; i++) {
            var a = ds[i - 1].split("-"), b = ds[i].split("-");
            if (dayIndex(Number(b[0]), Number(b[1]), Number(b[2]))
                    - dayIndex(Number(a[0]), Number(a[1]), Number(a[2])) !== 1) {
                problems.push(name + " 的放假区间不连续（" + ds[i - 1] + " → " + ds[i] + " 之间有断档）");
                break;
            }
        }
        var r = COUNT_RANGES[name];
        if (r && (ds.length < r[0] || ds.length > r[1])) {
            problems.push(name + " 放假 " + ds.length + " 天，超出合理区间 " + r[0] + "–" + r[1]);
        }
    }

    // 天文/政策窗口
    for (var wname in WINDOWS) {
        var hits = [];
        for (k in off) {
            if (off[k].indexOf(wname) >= 0) {
                var q = k.split("-");
                hits.push(dayIndex(Number(q[0]), Number(q[1]), Number(q[2])));
            }
        }
        if (!hits.length) {
            problems.push("缺少 " + wname + " 的数据");
            continue;
        }
        var w = WINDOWS[wname];
        var lo = dayIndex(year, w[0], w[1]);
        var hi = dayIndex(year, w[2], w[3]);
        var inside = false;
        for (var h = 0; h < hits.length; h++) {
            if (hits[h] >= lo && hits[h] <= hi) {
                inside = true;
            }
        }
        if (!inside) {
            problems.push(wname + " 不落在天文窗口内");
        }
    }
    for (var iname in INCLUDE_DATES) {
        var list = INCLUDE_DATES[iname];
        for (var j = 0; j < list.length; j++) {
            var key = year + "-" + pad2(list[j][0]) + "-" + pad2(list[j][1]);
            var found = false;
            for (k in off) {
                if (k === key && off[k].indexOf(iname) >= 0) {
                    found = true;
                }
            }
            // 只有该节日存在时才要求包含法定日（避免对数据缺失的年份误报）
            var hasHoliday = false;
            for (k in off) {
                if (off[k].indexOf(iname) >= 0) {
                    hasHoliday = true;
                }
            }
            if (hasHoliday && !found) {
                problems.push(iname + " 未包含 " + list[j][0] + " 月 " + list[j][1] + " 日");
            }
        }
    }

    var total = 0;
    for (k in off) {
        total++;
    }
    if (total < 20 || total > 40) {
        problems.push("全年放假 " + total + " 天，不在合理区间 20–40 天");
    }
    return problems;
}

// 校验一份数据源 payload。
// 返回 { ok: bool, error: string, off: {}, work: {}, papers: [] }
function validatePayload(payload, year) {
    var fail = function (msg) {
        return { ok: false, error: msg, off: {}, work: {}, papers: [] };
    };

    if (!payload || typeof payload !== "object") {
        return fail("返回内容不是 JSON 对象");
    }
    if (Number(payload.year) !== Number(year)) {
        return fail("请求 " + year + " 年，返回的却是 " + payload.year);
    }
    var days = payload.days;
    if (!days || !days.length) {
        return fail("数据源里 " + year + ".json 的 days 为空（该年份可能尚未发布）");
    }

    var off = {}, work = {}, papers = [];
    for (var i = 0; i < days.length; i++) {
        var d = days[i];
        if (!d || d.name === undefined || d.date === undefined || d.isOffDay === undefined) {
            return fail("第 " + (i + 1) + " 条记录缺少字段（需要 name/date/isOffDay）");
        }
        var ds = String(d.date);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(ds)) {
            return fail("日期格式异常：" + ds);
        }
        if (ds.substring(0, 4) !== String(year)) {
            continue;                       // 跨年的补班记录先忽略
        }
        if (d.isOffDay) {
            off[ds] = String(d.name);
        } else {
            work[ds] = String(d.name);
        }
    }
    if (payload.papers && payload.papers.length) {
        papers = payload.papers;
    }

    var problems = sanityProblems(off, work, Number(year));
    if (problems.length) {
        return fail("数据未通过自检：" + problems.join("；"));
    }
    // 数据源应标注政府网通知原文；没标注不算错，但要让调用方能看到
    var hasPaper = false;
    for (var p = 0; p < papers.length; p++) {
        if (String(papers[p]).indexOf("gov.cn") >= 0) {
            hasPaper = true;
        }
    }
    return { ok: true, error: "", off: off, work: work, papers: papers, hasOfficialSource: hasPaper };
}

/* ------------------------------------------------------------------ *
 * 缓存（存放于组件配置的字符串）
 * ------------------------------------------------------------------ */

// 解析缓存串；结构不合法则返回空缓存（静默降级，不抛异常）
function parseCache(str) {
    var empty = { years: {}, checkedAt: "" };
    if (!str) {
        return empty;
    }
    var obj;
    try {
        obj = JSON.parse(str);
    } catch (e) {
        return empty;
    }
    if (!obj || typeof obj !== "object" || !obj.years || typeof obj.years !== "object") {
        return empty;
    }
    // 逐个年份做结构校验，坏数据直接丢弃
    var clean = {};
    for (var y in obj.years) {
        var e = obj.years[y];
        if (/^\d{4}$/.test(y) && e && typeof e.off === "object" && typeof e.work === "object") {
            clean[y] = { off: e.off, work: e.work };
        }
    }
    return { years: clean, checkedAt: typeof obj.checkedAt === "string" ? obj.checkedAt : "" };
}

function serializeCache(cache) {
    return JSON.stringify({ years: cache.years || {}, checkedAt: cache.checkedAt || "" });
}

// 把某个年份的数据并入缓存，返回新的缓存对象
function mergeYear(cache, year, off, work) {
    var years = {};
    for (var y in (cache.years || {})) {
        years[y] = cache.years[y];
    }
    years[String(year)] = { off: off, work: work };
    return { years: years, checkedAt: cache.checkedAt || "" };
}

// 内置数据已覆盖的年份 + 缓存已覆盖的年份 = 无需再拉取的年份。
// builtinYears 由调用方传入（holidays.js 的 COVERED_YEARS）。
function coveredYears(cache, builtinYears) {
    var out = {};
    var list = builtinYears || [];
    for (var i = 0; i < list.length; i++) {
        out[String(list[i])] = true;
    }
    for (var y in (cache.years || {})) {
        out[y] = true;
    }
    return out;
}

// 需要联网获取的年份：当年与次年之中，尚未覆盖的
function yearsToFetch(cache, now, builtinYears) {
    var covered = coveredYears(cache, builtinYears);
    var out = [];
    var candidates = [now.getFullYear(), now.getFullYear() + 1];
    for (var i = 0; i < candidates.length; i++) {
        var y = candidates[i];
        if (!covered.hasOwnProperty(String(y))) {
            out.push(y);
        }
    }
    return out;
}

// 距上次检查是否已超过间隔
function shouldAutoCheck(cache, now) {
    if (!cache.checkedAt) {
        return true;
    }
    var last = new Date(cache.checkedAt);
    if (isNaN(last.getTime())) {
        return true;
    }
    var days = (now.getTime() - last.getTime()) / 86400000;
    return days >= AUTO_CHECK_INTERVAL_DAYS;
}

/* ------------------------------------------------------------------ *
 * 联网拉取
 * ------------------------------------------------------------------ */

function hostOf(url) {
    var m = /^https?:\/\/([^\/]+)/.exec(url);
    return m ? m[1] : url;
}

function countKeys(obj) {
    var n = 0;
    for (var k in obj) {
        n++;
    }
    return n;
}

// 单次 HTTP GET，回调 (status, parsedJsonOrNull)。
// XMLHttpRequest 在 .pragma library 脚本里同样可用（已实测）。
function fetchJson(url, onDone) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) {
            return;
        }
        var parsed = null;
        try {
            parsed = JSON.parse(xhr.responseText);
        } catch (e) {
            parsed = null;
        }
        onDone(xhr.status, parsed);
    };
    xhr.open("GET", url, true);
    xhr.timeout = 15000;
    xhr.ontimeout = function () {
        onDone(0, null);            // 0 = 超时/传输失败
    };
    xhr.onerror = function () {
        onDone(0, null);
    };
    xhr.send();
}

// 拉取并校验需要更新的年份。
//   onProgress(text) —— 过程反馈（可为 null）
//   onDone(result)   —— 结束时调用一次：
//        { cache, fetched:[年份], failed:[年份], messages:[每步结果] }
// 任一源返回的、通过校验的数据才会被采用；未通过的会记录原因并尝试下一个源。
function runUpdate(cache, now, builtinYears, onProgress, onDone) {
    var progress = onProgress || function () {};
    var result = { cache: cache, fetched: [], failed: [], messages: [] };
    var years = yearsToFetch(cache, now, builtinYears);

    if (!years.length) {
        result.messages.push("内置数据与缓存已覆盖 " + now.getFullYear() + " 年及次年，无需联网更新");
        onDone(result);
        return;
    }

    var yi = 0;

    function nextYear() {
        if (yi >= years.length) {
            result.cache = { years: result.cache.years, checkedAt: now.toISOString() };
            onDone(result);
            return;
        }
        var year = years[yi];
        var urls = urlsFor(year);
        var ui = 0;

        function tryUrl() {
            if (ui >= urls.length) {
                result.failed.push(year);
                result.messages.push(year + " 年：所有数据源都未取到可用数据");
                yi += 1;
                nextYear();
                return;
            }
            var url = urls[ui];
            progress("正在获取 " + year + " 年数据…（源 " + (ui + 1) + "/" + urls.length + "）");
            fetchJson(url, function (status, payload) {
                if (status !== 200) {
                    result.messages.push(year + " 年：HTTP " + status + "（" + hostOf(url) + "）");
                    ui += 1;
                    tryUrl();
                    return;
                }
                var v = validatePayload(payload, year);
                if (!v.ok) {
                    result.messages.push(year + " 年：" + v.error + "（" + hostOf(url) + "）");
                    ui += 1;
                    tryUrl();
                    return;
                }
                result.cache = mergeYear(result.cache, year, v.off, v.work);
                result.fetched.push(year);
                result.messages.push(year + " 年：已更新（放假 " + countKeys(v.off)
                    + " 天、补班 " + countKeys(v.work) + " 天）"
                    + (v.hasOfficialSource ? "，数据源自带政府网通知链接" : "，⚠ 数据源未标注政府网原文，请自行核实"));
                yi += 1;
                nextYear();
            });
        }
        tryUrl();
    }
    nextYear();
}

/* ------------------------------------------------------------------ *
 * 查询：缓存优先，其次内置数据
 * ------------------------------------------------------------------ */

// 只查「联网获取的缓存」，命中返回 { type, name, source: "cache" }，否则 null。
// 内置数据的兜底由调用方负责（qml 里写 `HolidaysNet.statusFromCache(...) || Holidays.statusFor(...)`），
// 这样本文件与 holidays.js 完全解耦。
function statusFromCache(y, m, d, cache) {
    var key = y + "-" + pad2(m) + "-" + pad2(d);
    var c = cache && cache.years ? cache.years[String(y)] : null;
    if (!c) {
        return null;
    }
    if (c.off && c.off.hasOwnProperty(key)) {
        return { type: "off", name: c.off[key], source: "cache" };
    }
    if (c.work && c.work.hasOwnProperty(key)) {
        return { type: "work", name: c.work[key], source: "cache" };
    }
    return null;
}
