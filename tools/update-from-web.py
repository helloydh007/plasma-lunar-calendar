#!/usr/bin/env python3
"""
从公开数据源获取节假日数据，生成／更新 contents/ui/holidays.js。

用法：
    python3 tools/update-from-web.py 2027              # 只预览，不写文件
    python3 tools/update-from-web.py 2027 --write      # 写入
    python3 tools/update-from-web.py 2026              # 也可用来审计已有年份
    python3 tools/update-from-web.py 2026 --file /path/to/holidays.js --write

为什么是「更新时联网」而不是「运行时联网」：
    本组件刻意不在运行时请求网络。理由：
      · 断网／代理异常时组件仍要能显示（内置数据是永远可用的兜底）
      · 桌面日历不该在后台定时向外发请求
      · 万一接口返回错误数据，节假日是会实际影响行程的信息，代价太高
      · 社区接口的可用性无法保证（例如 timor.tech 现已被 Cloudflare 拦截）
    所以把联网放在「你主动更新数据」的那一刻：本工具拉取数据、校验、
    生成数据表，之后组件照旧离线运行。

数据源：
    holiday-cn（社区维护，按年发布 JSON，并标注对应的国务院办公厅通知原文）
        https://github.com/NateScarlet/holiday-cn
    实际来源可能是政府网原文，本工具会把 papers 字段记录的来源 URL 写进文件头。

退出码：0 = 成功；1 = 失败（含「该年份尚未发布」）。
"""

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

SOURCES = [
    "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/{year}.json",
    "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/{year}.json",
]

REPO = Path(__file__).resolve().parent.parent
DEFAULT_JS = REPO / "contents" / "ui" / "holidays.js"

WEEKDAY_CN = "一二三四五六日"


class NotPublished(Exception):
    """该年份的放假安排尚未发布（数据源里只有占位文件）。"""

# 与 verify-holidays.py 保持一致的天文/政策窗口
WINDOWS = {
    "元旦":   {"include": [(1, 1)], "count": (1, 3)},
    "春节":   {"window": (1, 21, 2, 21), "count": (7, 10)},
    "清明节": {"window": (4, 4, 4, 6), "count": (1, 4)},
    "劳动节": {"include": [(5, 1)], "count": (3, 6)},
    "端午节": {"window": (5, 25, 6, 30), "count": (1, 4)},
    "中秋节": {"window": (9, 5, 10, 10), "count": (1, 4)},
    "国庆节": {"include": [(10, 1)], "count": (5, 8)},
}


def fetch(year):
    """依次尝试各数据源，返回 (数据, 使用的 URL)。"""
    last = None
    for tpl in SOURCES:
        url = tpl.format(year=year)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "plasma-lunar-calendar-updater"})
            with urllib.request.urlopen(req, timeout=25) as r:
                return json.loads(r.read().decode("utf-8")), url
        except urllib.error.HTTPError as e:
            last = f"{url} → HTTP {e.code}"
        except Exception as e:                       # 网络不可达、超时、JSON 解析失败等
            last = f"{url} → {type(e).__name__}: {e}"
    raise RuntimeError(f"所有数据源都取不到 {year} 年的数据。最后错误：{last}\n"
                       f"提示：该年份可能尚未发布（通常在上一年 11 月上旬发布）。")


def validate(payload, year):
    """结构校验。返回 (off 映射, work 映射, papers)。"""
    if not isinstance(payload, dict):
        raise ValueError("返回内容不是 JSON 对象")
    if payload.get("year") != year:
        raise ValueError(f"请求 {year} 年，返回的却是 {payload.get('year')}")
    days = payload.get("days")
    if not days:
        # 数据源对未发布的年份会保留一个 days 为空的占位文件，
        # 这里给出明确结论，而不是让调用方看到一堆结构错误。
        raise NotPublished(f"数据源里 {year}.json 的 days 为空"
                           f"（papers: {payload.get('papers') or '无'}）")

    off, work = {}, {}
    for x in days:
        for key in ("name", "date", "isOffDay"):
            if key not in x:
                raise ValueError(f"记录缺少字段 {key}：{x}")
        ds = x["date"]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", ds):
            raise ValueError(f"日期格式异常：{ds}")
        if not ds.startswith(str(year)):
            continue                                  # 跨年的补班记录（少见）先跳过
        (off if x["isOffDay"] else work)[ds] = x["name"]

    papers = payload.get("papers") or []
    if not any("gov.cn" in p for p in papers):
        print("  ⚠ 数据源未标注 gov.cn 通知原文，请人工确认其可靠性")
    return off, work, papers


def sanity(off, work, year):
    """对拉取到的数据做与 verify-holidays.py 同源的自检。"""
    problems = []
    if set(off) & set(work):
        problems.append(f"放假与补班重叠：{sorted(set(off) & set(work))}")

    bad = [k for k in work if date.fromisoformat(k).weekday() < 5]
    if bad:
        problems.append(f"补班日落在工作日：{bad}")

    by_name = {}
    for k, n in off.items():
        by_name.setdefault(n, []).append(date.fromisoformat(k))
    for name, ds in by_name.items():
        ds.sort()
        gaps = [i for i in range(1, len(ds)) if (ds[i] - ds[i - 1]).days != 1]
        if gaps:
            problems.append(f"{name} 的放假区间不连续（{len(gaps)} 处断档）")

    for name, rule in WINDOWS.items():
        hits = [date.fromisoformat(k) for k, n in off.items() if name in n]
        if not hits:
            problems.append(f"缺少 {name} 的数据")
            continue
        if "include" in rule:
            for mo, da in rule["include"]:
                if date(year, mo, da) not in hits:
                    problems.append(f"{name} 未包含 {mo} 月 {da} 日")
        if "window" in rule:
            m1, d1, m2, d2 = rule["window"]
            lo, hi = date(year, m1, d1), date(year, m2, d2)
            if not any(lo <= x <= hi for x in hits):
                problems.append(f"{name} 落在天文窗口 {lo}–{hi} 之外")
        if "count" in rule:
            # 天数检查只对「单一节日名」生效：合并节日（如「国庆节、中秋节」
            # 连休 8 天）不能拿单个节日的天数区间去套，否则必然误报。
            # 注意要用精确匹配——窗口检查用的是子串匹配，两者不能混用。
            single = [k for k, n in off.items() if n == name]
            if single:
                lo, hi = rule["count"]
                if not lo <= len(single) <= hi:
                    problems.append(
                        f"{name} 放假 {len(single)} 天，超出合理区间 {lo}–{hi}")
    return problems


def fmt(date_str):
    d = date.fromisoformat(date_str)
    return f"{d.month:2d}/{d.day:2d}(周{WEEKDAY_CN[d.weekday()]})"


def print_table(year, off, work):
    print(f"\n【{year} 年】请与通知原文逐条核对：")
    by_name = {}
    for k, n in sorted(off.items()):
        by_name.setdefault(n, []).append(k)
    for name, ks in by_name.items():
        print(f"  放假  {name:16s} {fmt(ks[0])} – {fmt(ks[-1])}   共 {len(ks)} 天")
    if work:
        print("  补班  " + "、".join(fmt(k) for k in sorted(work)))
    else:
        print("  补班  （无）")


def read_existing(path):
    """读取现有 holidays.js 中的 OFF / WORK / COVERED_YEARS。"""
    if not path.exists():
        return {}, {}, []
    text = path.read_text(encoding="utf-8")
    off_src, _, work_src = text.partition("var WORK")

    def entries(src):
        return {m.group(1): m.group(2)
                for m in re.finditer(r'"(\d{4}-\d{2}-\d{2})"\s*:\s*"([^"]+)"', src)}

    m = re.search(r"COVERED_YEARS\s*=\s*\[([^\]]*)\]", text)
    years = [int(y) for y in re.findall(r"\d{4}", m.group(1))] if m else []

    # 文件头里记录的「YYYY: 通知URL」，用于在多次写入之间累积溯源信息
    sources = {int(y): u for y, u in
               re.findall(r"\*\s+(\d{4}):\s+(https?://\S+)", text)}
    return entries(off_src), entries(work_src), years, sources


def render(off, work, years, sources):
    """按固定模板生成 holidays.js。文件由本工具生成，请勿手工编辑条目。"""
    src = "\n".join(f" *   {y}: {u}" for y, u in sorted(sources.items())) \
        or " *   （来源未标注）"

    def block(mapping):
        """按「年 → 节日」分组，每个节日一行。行尾必须带逗号（跨行拼接成对象字面量）。"""
        lines = []
        by_year = {}
        for k, v in sorted(mapping.items()):
            by_year.setdefault(k[:4], []).append((k, v))
        for y in sorted(by_year):
            lines.append(f"    // ── {y} ──")
            by_name = {}
            for k, v in by_year[y]:
                by_name.setdefault(v, []).append(k)
            for name, ks in by_name.items():
                items = ", ".join(f'"{k}": "{name}"' for k in ks)
                lines.append("    " + items + ",")
        return "\n".join(lines)

    def block2(mapping):
        """补班日按年一行。同样行尾带逗号。"""
        out = []
        by_year = {}
        for k, v in sorted(mapping.items()):
            by_year.setdefault(k[:4], []).append((k, v))
        for y in sorted(by_year):
            out.append(f"    // ── {y} ──")
            items = ", ".join(f'"{k}": "{v}"' for k, v in by_year[y])
            out.append("    " + items + ",")
        return "\n".join(out)

    return f'''/*
 * 中国法定节假日与调休数据表
 *
 * ⚠ 本文件由 tools/update-from-web.py 生成，请勿手工编辑条目；
 *   需要更新时运行该工具（见 README「下一年怎么更新」）。
 *
 * ── 为什么必须内置数据表 ──
 *   节日的「日期」可以算（春节＝正月初一、清明＝清明节气、中秋＝八月十五……），
 *   但「放假安排」不能算：哪几天连休、哪个周末要补班，是国务院办公厅每年单独发文
 *   规定的行政安排，逐年不同（例如同样是春节，2025 与 2026 的调休日完全不同）。
 *   所以这里内置官方数据，不做推算。
 *
 * ── 数据来源（国务院办公厅通知原文）──
{src}
 *
 *   更新后请运行 tools/verify-holidays.py 复核。
 *
 * 未覆盖的年份不会有任何标记（不会显示错误数据）。
 */

.pragma library

// 放假日期 → 节日名
var OFF = {{
{block(off)}
}};

// 调休上班（周末补班）日期 → 所属节日
var WORK = {{
{block2(work)}
}};

// 数据覆盖的年份（未覆盖的年份不显示任何标记，避免展示错误信息）
var COVERED_YEARS = [{", ".join(str(y) for y in sorted(years))}];

function pad2(n) {{
    return (n < 10 ? "0" : "") + n;
}}

function key(y, m, d) {{
    return y + "-" + pad2(m) + "-" + pad2(d);
}}

function isYearCovered(y) {{
    for (var i = 0; i < COVERED_YEARS.length; i++) {{
        if (COVERED_YEARS[i] === y) {{
            return true;
        }}
    }}
    return false;
}}

// 返回 null（普通日）或 {{ type: "off" | "work", name: 节日名 }}
function statusFor(y, m, d) {{
    var k = key(y, m, d);
    if (OFF.hasOwnProperty(k)) {{
        return {{ type: "off", name: OFF[k] }};
    }}
    if (WORK.hasOwnProperty(k)) {{
        return {{ type: "work", name: WORK[k] }};
    }}
    return null;
}}
'''


def main():
    ap = argparse.ArgumentParser(description="从公开数据源更新节假日数据表")
    ap.add_argument("year", type=int, help="要获取的年份，例如 2027")
    ap.add_argument("--write", action="store_true", help="写入 holidays.js（默认只预览）")
    ap.add_argument("--file", type=Path, default=DEFAULT_JS, help="目标 holidays.js 路径")
    args = ap.parse_args()

    print(f"=== 获取 {args.year} 年数据 ===")
    try:
        payload, used = fetch(args.year)
    except RuntimeError as e:
        print(f"  ✗ {e}")
        return 1
    print(f"  来源: {used}")

    try:
        off, work, papers = validate(payload, args.year)
    except NotPublished as e:
        print(f"  ─ {args.year} 年的放假安排尚未发布")
        print(f"    {e}")
        print(f"    国务院办公厅通常在上一年 11 月上旬发布，届时再运行本工具即可。")
        return 1
    except ValueError as e:
        print(f"  ✗ 数据源返回的内容不符合预期：{e}")
        print(f"    来源: {used}")
        return 1

    print(f"  取得 {len(off)} 个放假日、{len(work)} 个补班日")
    for p in papers:
        print(f"  通知原文: {p}")

    problems = sanity(off, work, args.year)
    if problems:
        print("\n  ✗ 拉取到的数据未通过自检，拒绝使用：")
        for p in problems:
            print(f"      {p}")
        return 1
    print("  ✓ 通过结构与自检")

    print_table(args.year, off, work)

    old_off, old_work, old_years, sources = read_existing(args.file)
    for p in papers:
        if "gov.cn" in p:
            sources[args.year] = p
            break
    same_year_off = {k: v for k, v in old_off.items() if k.startswith(str(args.year))}
    if same_year_off or {k for k in old_work if k.startswith(str(args.year))}:
        old_w = {k for k in old_work if k.startswith(str(args.year))}
        new_w = set(work)
        if same_year_off == off and old_w == new_w:
            print(f"\n  ✓ 与 {args.file.name} 中已有的 {args.year} 年数据完全一致")
        else:
            print(f"\n  ⚠ 与已有 {args.year} 年数据存在差异：")
            for k in sorted(set(same_year_off) - set(off)):
                print(f"      仅本地有: {k} {same_year_off[k]}")
            for k in sorted(set(off) - set(same_year_off)):
                print(f"      仅线上有: {k} {off[k]}")
            for k in sorted(old_w - new_w):
                print(f"      仅本地有(补班): {k}")
            for k in sorted(new_w - old_w):
                print(f"      仅线上有(补班): {k}")

    merged_off = {k: v for k, v in old_off.items() if not k.startswith(str(args.year))}
    merged_off.update(off)
    merged_work = {k: v for k, v in old_work.items() if not k.startswith(str(args.year))}
    merged_work.update(work)
    years = sorted(set(old_years) | {args.year} | {int(k[:4]) for k in list(merged_off) + list(merged_work)})

    if not args.write:
        print(f"\n（预览模式，未写入。确认无误后加 --write 写入 {args.file}）")
        print(f"  更新后覆盖年份将是: {years}")
        return 0

    args.file.write_text(render(merged_off, merged_work, years, sources), encoding="utf-8")
    print(f"\n  ✓ 已写入 {args.file}（覆盖年份 {years}）")

    print("\n=== 复核（tools/verify-holidays.py）===")
    r = subprocess.run([sys.executable, str(REPO / "tools" / "verify-holidays.py"), str(args.file)],
                       capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if line.strip().startswith(("[", "✗", "⚠", "全部检查通过")):
            print("  " + line.strip())
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
