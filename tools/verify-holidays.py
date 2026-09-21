#!/usr/bin/env python3
"""
校验节假日数据表（contents/ui/holidays.js）。

用法：
    python3 tools/verify-holidays.py [holidays.js 路径]

为什么需要它：
    放假安排只能从国务院办公厅通知里人工录入，录入就可能出错。本脚本把
    「人工核对星期几」这件事自动化，并检查一组天文/政策上必然成立的约束
    ——日期写错时几乎必然会被其中一条抓住。

检查项：
    1. 同一天不能同时出现在「放假」和「补班」里
    2. 补班日必须落在周末（调休补班在实践中都是周末）
    3. 每个节日的放假区间必须落在其天文窗口内：
         元旦   含 1 月 1 日
         春节   与 [1/21, 2/21] 相交（农历正月初一的最早/最晚）
         清明节 与 [4/4, 4/6] 相交（清明节气日期极稳定）
         劳动节 含 5 月 1 日
         端午节 与 [5/25, 6/30] 相交
         中秋节 与 [9/5, 10/10] 相交
         国庆节 含 10 月 1 日
    4. 每年放假总天数在 20–40 天的合理区间
    5. 数据覆盖年份与 COVERED_YEARS 一致

同时打印一张对照表，便于与通知原文逐条核对。

退出码：0 = 全部通过；1 = 有检查未通过。
"""

import datetime
import re
import sys
from pathlib import Path

WEEKDAY_CN = "一二三四五六日"

# 每个节日的天文/政策窗口（用于抓录入错误）
# include: 必须包含的日期（月, 日）
# window:  放假区间必须与之相交 (起始月, 起始日, 结束月, 结束日)
# count:   放假天数合理区间（仅用于单一节日名；含「·」的合并节日跳过）
CHECKS = {
    "元旦":   {"include": [(1, 1)], "count": (1, 3)},
    "春节":   {"window": (1, 21, 2, 21), "count": (7, 10)},
    "清明节": {"window": (4, 4, 4, 6), "count": (1, 4)},
    "劳动节": {"include": [(5, 1)], "count": (3, 6)},
    "端午节": {"window": (5, 25, 6, 30), "count": (1, 4)},
    "中秋节": {"window": (9, 5, 10, 10), "count": (1, 4)},
    "国庆节": {"include": [(10, 1)], "count": (5, 8)},
}


def load(path):
    """从 holidays.js 里抽出 OFF / WORK 两个映射，保持所在区段。"""
    text = Path(path).read_text(encoding="utf-8")
    off_src, _, work_src = text.partition("var WORK")

    def entries(src):
        return {m.group(1): m.group(2)
                for m in re.finditer(r'"(\d{4}-\d{2}-\d{2})"\s*:\s*"([^"]+)"', src)}

    covered = re.search(r"COVERED_YEARS\s*=\s*\[([^\]]*)\]", text)
    years = [int(y) for y in re.findall(r"\d{4}", covered.group(1))] if covered else []
    return entries(off_src), entries(work_src), years


def d(s):
    return datetime.date.fromisoformat(s)


def blocks(dates):
    """把连续日期聚成区间，返回 [(start, end), ...]。"""
    out = []
    for x in sorted(dates):
        if out and (x - out[-1][1]).days == 1:
            out[-1][1] = x
        else:
            out.append([x, x])
    return [(a, b) for a, b in out]


def fmt_range(a, b):
    def w(x):
        return "周" + WEEKDAY_CN[x.weekday()]

    if a == b:
        return f"{a.month:2d}/{a.day:2d}({w(a)})"
    return f"{a.month:2d}/{a.day:2d}({w(a)})–{b.month:2d}/{b.day:2d}({w(b)})"


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else (
        Path(__file__).resolve().parent.parent / "contents" / "ui" / "holidays.js")
    if not Path(path).exists():
        print(f"找不到数据文件：{path}", file=sys.stderr)
        return 1

    OFF, WORK, COVERED = load(path)
    problems = []

    print("=" * 78)
    print("节假日数据对照表（请与国务院办公厅通知原文逐条核对）")
    print("=" * 78)

    for year in sorted({int(k[:4]) for k in list(OFF) + list(WORK)}):
        print(f"\n【{year} 年】")

        # 按节日名分组，便于逐条对照通知
        by_name = {}
        for k, name in OFF.items():
            if int(k[:4]) == year:
                by_name.setdefault(name, []).append(d(k))
        for name in sorted(by_name):
            span = "、".join(fmt_range(a, b) for a, b in blocks(by_name[name]))
            print(f"  放假  {name:12s} {span}   共 {len(by_name[name])} 天")

        work = sorted(d(k) for k, _ in WORK.items() if int(k[:4]) == year)
        if work:
            print(f"  补班  {'':12s} " + "、".join(fmt_range(x, x) for x in work))
        else:
            print(f"  补班  {'':12s} （无）")

    print("\n" + "=" * 78)
    print("自动检查")
    print("=" * 78)

    # 1. 放假 / 补班 不得重叠
    dup = set(OFF) & set(WORK)
    if dup:
        problems.append(f"同一天既是放假又是补班：{sorted(dup)}")
    print(f"  [{'✗' if dup else '✓'}] 放假与补班无重叠")

    # 2. 补班日应为周末
    bad_work = [(k, n) for k, n in WORK.items() if d(k).weekday() < 5]
    if bad_work:
        problems.append(f"补班日落在工作日（调休补班通常都是周末，请核对）：{bad_work}")
    print(f"  [{'✗' if bad_work else '✓'}] 补班日全部落在周末"
          + (f"（{len(WORK)} 天）" if not bad_work else ""))

    # 3. 节日的天文窗口
    ok = True
    for year in sorted({int(k[:4]) for k in OFF}):
        for name, rule in CHECKS.items():
            hits = [d(k) for k, n in OFF.items() if int(k[:4]) == year and name in n]
            if not hits:
                problems.append(f"{year} 年缺少 {name} 的数据")
                ok = False
                continue
            if "include" in rule:
                for mo, da in rule["include"]:
                    if datetime.date(year, mo, da) not in hits:
                        problems.append(
                            f"{year} 年 {name} 放假区间未包含 {mo} 月 {da} 日 → 日期可能有误")
                        ok = False
            if "window" in rule:
                m1, d1, m2, d2 = rule["window"]
                lo, hi = datetime.date(year, m1, d1), datetime.date(year, m2, d2)
                if not any(lo <= x <= hi for x in hits):
                    problems.append(
                        f"{year} 年 {name} 放假区间 {min(hits)}–{max(hits)} "
                        f"不在天文窗口 {lo}–{hi} 内 → 日期可能有误")
                    ok = False
    print(f"  [{'✓' if ok else '✗'}] 各节日均落在其天文/政策窗口内")

    # 3. 每个节日的放假区间必须是「一整段连续日期」
    #    通知里每个节日的放假都是一段连续区间；录入时把某天写错月/写错日，
    #    几乎必然把这一段拆成两段（或漏出缺口），这条能抓住。
    ok = True
    for year in sorted({int(k[:4]) for k in OFF}):
        names = {}
        for k, n in OFF.items():
            if int(k[:4]) == year:
                names.setdefault(n, []).append(d(k))
        for name, ds in names.items():
            if len(blocks(ds)) != 1:
                problems.append(
                    f"{year} 年 {name} 的放假不是一整段连续日期："
                    + "、".join(fmt_range(a, b) for a, b in blocks(ds)))
                ok = False
    print(f"  [{'✓' if ok else '✗'}] 各节日的放假区间连续（无断档）")

    # 3b. 每个节日的放假天数在合理区间
    ok = True
    for year in sorted({int(k[:4]) for k in OFF}):
        for name, rule in CHECKS.items():
            if "count" not in rule:
                continue
            hits = [k for k, n in OFF.items()
                    if int(k[:4]) == year and n == name]      # 只用单一节日名
            if not hits:
                continue
            lo, hi = rule["count"]
            if not lo <= len(hits) <= hi:
                problems.append(
                    f"{year} 年 {name} 放假 {len(hits)} 天，超出合理区间 {lo}–{hi} 天")
                ok = False
    print(f"  [{'✓' if ok else '✗'}] 各节日放假天数在合理区间")

    # 4. 年度放假天数
    ok = True
    for year in sorted({int(k[:4]) for k in OFF}):
        n = sum(1 for k in OFF if int(k[:4]) == year)
        if not 20 <= n <= 40:
            problems.append(f"{year} 年放假天数 {n} 不在合理区间 20–40 天")
            ok = False
    print(f"  [{'✓' if ok else '✗'}] 年度放假总天数在合理区间")

    # 5. COVERED_YEARS 与实际数据一致
    actual = sorted({int(k[:4]) for k in list(OFF) + list(WORK)})
    if actual != sorted(COVERED):
        problems.append(f"COVERED_YEARS={sorted(COVERED)} 与实际数据年份 {actual} 不一致")
    print(f"  [{'✓' if actual == sorted(COVERED) else '✗'}] "
          f"COVERED_YEARS 与实际数据一致（{actual}）")

    print()
    if problems:
        print("发现问题：")
        for p in problems:
            print(f"  ✗ {p}")
        return 1

    print("全部检查通过。")
    print()
    print("⚠ 请注意本工具的边界：它能抓住「月份/日期写错、区间断档、补班写成工作日、")
    print("  放假与补班重叠、漏掉法定日、天数明显异常」这些常见录入错误，但**无法**")
    print("  判断某段区间是否恰好与通知一致（例如国庆多录一天不会被发现）。")
    print("  请务必用上面的对照表与国务院办公厅通知原文逐条核对。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
