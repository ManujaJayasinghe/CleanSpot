"""Extract weekly Dengue Fever cases per RDHS from the WER PDFs.

For every PDF in tool/wer_pdfs/ this finds Table 1 (the table of notifiable
diseases reported by Medical Officers of Health), reads the year and week from
the TABLE TITLE (never from the file name or volume number), and takes the
Dengue Fever column A (cases in that week; column B is the cumulative total
for the year and is ignored) for the 26 RDHS rows. The SRI LANKA total row is
read too, but only to check the sum of the 26 rows.

Nothing is guessed. A PDF whose table cannot be read with every check passing
is skipped and the reason is logged; a (year, week) found in two PDFs with
different numbers is left out and reported.

The table is printed sideways in the PDFs, so the characters are rotated back
using their position on the page and then assigned to columns by x position.

Outputs:
    assets/data/dengue_stats.csv   district,year,week,cases
    tool/dengue_sources.csv        year,week,pdf_url
and a validation report printed to the console.

Run from the project root:
    py tool/extract_dengue.py
"""

import argparse
import collections
import csv
import random
import re
import sys
from pathlib import Path

import pdfplumber

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent
PDF_DIR = ROOT / "wer_pdfs"
MANIFEST = ROOT / "wer_manifest.csv"
OUT_CSV = PROJECT / "assets" / "data" / "dengue_stats.csv"
SOURCES_CSV = ROOT / "dengue_sources.csv"

# The 26 RDHS rows, in the order of the request. Kalmunai is its own RDHS.
DISTRICTS = [
    "Colombo", "Gampaha", "Kalutara", "Kandy", "Matale", "Nuwara Eliya",
    "Galle", "Hambantota", "Matara", "Jaffna", "Kilinochchi", "Mannar",
    "Vavuniya", "Mullaitivu", "Batticaloa", "Ampara", "Trincomalee",
    "Kalmunai", "Kurunegala", "Puttalam", "Anuradhapura", "Polonnaruwa",
    "Badulla", "Moneragala", "Ratnapura", "Kegalle",
]
# Row label as printed (spaces removed, lower case) -> canonical name. The
# reports print "Monaragala"; the app uses the standard spelling "Moneragala".
ROW_KEYS = {d.replace(" ", "").lower(): d for d in DISTRICTS}
ROW_KEYS["monaragala"] = "Moneragala"
# The first reports of 2024 print these two row labels cut short.
ROW_KEYS["anuradhapur"] = "Anuradhapura"
ROW_KEYS["kalmune"] = "Kalmunai"
TOTAL_KEY = "srilanka"

TITLE_RE = re.compile(
    r"Table1[:.].*?MedicalOfficersofHealth(?P<dates>.*?)\((?P<week>\d{1,2})"
    r"(?:st|nd|rd|th)Week\)",
    re.IGNORECASE,
)


class Skip(Exception):
    """This PDF cannot be read reliably; the message says why."""


# ---------------------------------------------------------------- geometry

def orientation(ch):
    m = tuple(round(v) for v in ch["matrix"][:4])
    return m if m in {(1, 0, 0, 1), (0, 1, -1, 0), (0, -1, 1, 0)} else None


def logical_groups(page):
    """Characters of the page, rotated back to reading order, per orientation.

    Returns {orientation: [(lx, ly, text), ...]} where lx runs along the
    reading direction and ly runs down the (logical) page.
    """
    groups = collections.defaultdict(list)
    for ch in page.chars:
        o = orientation(ch)
        if o is None or not ch["text"].strip():
            continue
        cx = (ch["x0"] + ch["x1"]) / 2
        cy = (ch["top"] + ch["bottom"]) / 2
        if o == (1, 0, 0, 1):
            lx, ly = cx, cy
        elif o == (0, 1, -1, 0):  # text reads bottom to top
            lx, ly = page.height - cy, cx
        else:  # (0, -1, 1, 0): text reads top to bottom
            lx, ly = cy, page.width - cx
        groups[o].append((lx, ly, ch["text"]))
    return groups


def to_lines(chars, gap=5.0):
    """Cluster characters into lines by ly; each line sorted along lx."""
    lines, current, last = [], [], None
    for c in sorted(chars, key=lambda c: c[1]):
        if last is not None and c[1] - last > gap:
            lines.append(sorted(current))
            current = []
        current.append(c)
        last = c[1]
    if current:
        lines.append(sorted(current))
    return lines


def squash(line):
    return "".join(c[2] for c in line)


# ------------------------------------------------------------------- title

def parse_title(groups):
    """(year, week, title_text) from the Table 1 title, or raise Skip."""
    for chars in groups.values():
        for line in to_lines(chars):
            text = squash(line)
            m = TITLE_RE.search(text)
            if not m:
                continue
            week = int(m.group("week"))
            years = [int(y) for y in re.findall(r"(20\d\d)", m.group("dates"))]
            if not years:
                raise Skip(f"no year in table title: {text!r}")
            if len(set(years)) == 1:
                year = years[0]
            elif week >= 50:
                year = min(years)  # range straddles New Year, still last week
            elif week <= 3:
                year = max(years)
            else:
                raise Skip(f"ambiguous year in table title: {text!r}")
            if not 1 <= week <= 53:
                raise Skip(f"week out of range in title: {text!r}")
            return year, week, text
    raise Skip("Table 1 title not found")


# ------------------------------------------------------------------- table

def table_lines(groups):
    """Lines of the orientation group that holds the table (most digits)."""
    best = max(groups.values(), key=lambda cs: sum(c[2].isdigit() for c in cs))
    return to_lines(best)


def check_first_disease_is_dengue(lines):
    """The header row reads 'RDHS' then 'Dengue ...'."""
    for line in lines:
        text = squash(line)
        if text.startswith("RDHS") or "RDHSDengue" in text:
            if "RDHSDengue" in text:
                return
            raise Skip(f"first disease column is not Dengue: {text[:40]!r}")
    raise Skip("table header row (RDHS ... Dengue) not found")


def digit_pitch(lines):
    """Distance between neighbouring digits of one number (about 4.4 pt).

    The most common small gap between digits; a few stray digits in a smaller
    font (footnotes) must not decide it.
    """
    gaps = collections.Counter()
    for line in lines:
        d = [c[0] for c in line if c[2].isdigit()]
        for a, b in zip(d, d[1:]):
            if 2.0 < b - a < 8.0:
                gaps[round(b - a, 1)] += 1
    if not gaps:
        raise Skip("no numbers in table")
    return gaps.most_common(1)[0][0]


def numbers_in_row(line, pitch):
    """Numbers of a row in order, left to right: [int, ...].

    Digits closer than 1.2 x the digit pitch belong to one number. Every cell
    of the table holds a number (zeros are printed), so the order of the
    numbers is the order of the columns.
    """
    nums, current, last = [], "", None
    for lx, _, t in line:
        if not t.isdigit():
            continue
        if last is not None and lx - last > pitch * 1.2:
            nums.append(int(current))
            current = ""
        current += t
        last = lx
    if current:
        nums.append(int(current))
    return nums


def row_label(line):
    """Letters before the first digit of a row, lower case, no spaces."""
    out = []
    for _, _, t in line:
        if t.isdigit():
            break
        out.append(t)
    return re.sub(r"[^a-z]", "", "".join(out).lower())


def extract_pdf(path):
    with pdfplumber.open(path) as pdf:
        found = None
        for page in pdf.pages:
            groups = logical_groups(page)
            try:
                year, week, _ = parse_title(groups)
            except Skip:
                continue
            found = (year, week, groups)
            break
        if found is None:
            raise Skip("Table 1 title not found in any page")
        year, week, groups = found
        lines = table_lines(groups)
        check_first_disease_is_dengue(lines)
        pitch = digit_pitch(lines)

        values, total = {}, None
        for line in lines:
            label = row_label(line)
            if label == TOTAL_KEY:
                nums = numbers_in_row(line, pitch)
                total = nums[0] if len(nums) >= 2 and nums[0] <= nums[1] else None
            elif label in ROW_KEYS:
                nums = numbers_in_row(line, pitch)
                name = ROW_KEYS[label]
                if name in values:
                    raise Skip(f"row {name} appears twice on the table page")
                if len(nums) < 2 or nums[0] > nums[1]:
                    raise Skip(f"{name}: Dengue A/B not readable ({nums[:2]})")
                values[name] = nums[0]
        missing = [d for d in DISTRICTS if d not in values]
        if missing:
            raise Skip(f"rows not found: {', '.join(missing)}")
        return year, week, values, total


# -------------------------------------------------------------------- main

def load_manifest():
    if not MANIFEST.exists():
        return {}
    with MANIFEST.open(newline="", encoding="utf-8") as f:
        return {r["file"]: r for r in csv.DictReader(f)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--years", default="2024,2025,2026", help="years to keep")
    ap.add_argument("--seed", type=int, default=None, help="seed for the 5 random spot checks")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    keep_years = {int(y) for y in args.years.split(",")}
    manifest = load_manifest()
    listed = len(manifest)
    not_available = [f for f, r in manifest.items() if r["status"] == "NOT AVAILABLE"]
    pdfs = sorted(PDF_DIR.glob("*.pdf"))

    parsed = {}  # (year, week) -> list of (file, values, total)
    skipped = []
    for p in pdfs:
        try:
            year, week, values, total = extract_pdf(p)
        except Skip as e:
            skipped.append((p.name, str(e)))
            continue
        except Exception as e:  # a broken PDF must not stop the run
            skipped.append((p.name, f"{type(e).__name__}: {e}"))
            continue
        parsed.setdefault((year, week), []).append((p.name, values, total))

    # A report can hold a week of a neighbouring year (the first report of
    # 2024 is week 52 of 2023); only the requested years are kept.
    outside = sorted(k for k in parsed if k[0] not in keep_years)
    parsed = {k: v for k, v in parsed.items() if k[0] in keep_years}

    # One result per (year, week). Identical repeats are fine; conflicting
    # repeats are left out entirely and reported.
    final, conflicts = {}, []
    for key, items in sorted(parsed.items()):
        first = items[0]
        if all(it[1] == first[1] for it in items):
            final[key] = first
        else:
            conflicts.append((key, [it[0] for it in items]))

    # ---- outputs
    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    rows = sorted(
        (d, y, w, v[d]) for (y, w), (_, v, _) in final.items() for d in DISTRICTS
    )
    with OUT_CSV.open("w", newline="", encoding="utf-8") as f:
        f.write("district,year,week,cases\n")
        for d, y, w, c in rows:
            f.write(f"{d},{y},{w},{c}\n")
    with SOURCES_CSV.open("w", newline="", encoding="utf-8") as f:
        f.write("year,week,pdf_url\n")
        for (y, w), (name, _, _) in sorted(final.items()):
            url = manifest.get(name, {}).get("url", "")
            f.write(f"{y},{w},{url}\n")

    # ---- report
    print("=" * 78)
    print("VALIDATION")
    print("=" * 78)
    print(f"{'PDFs listed (2024-2026, English)':<44}{listed:>6}")
    print(f"{'PDFs not available (not on the live site/archive)':<44}{len(not_available):>6}")
    print(f"{'PDFs downloaded (present in tool/wer_pdfs)':<44}{len(pdfs):>6}")
    print(f"{'PDFs parsed':<44}{sum(len(v) for v in parsed.values()):>6}")
    print(f"{'PDFs skipped':<44}{len(skipped):>6}")
    print(f"{'Distinct (year, week) in the CSV':<44}{len(final):>6}")
    print(f"{'CSV rows':<44}{len(rows):>6}")

    if outside:
        print("\nPARSED BUT OUTSIDE THE REQUESTED YEARS (not in the CSV)")
        for y, w in outside:
            print(f"  year {y}, week {w}")
    if skipped:
        print("\nSKIPPED PDFs")
        for name, why in skipped:
            print(f"  {name}: {why}")
    if conflicts:
        print("\nLEFT OUT: same week in several PDFs with different numbers")
        for key, names in conflicts:
            print(f"  {key}: {names}")
    if not_available:
        print("\nLISTED BUT NOT DOWNLOADABLE")
        for f in not_available:
            r = manifest[f]
            print(f"  {f}  (listing: week {r['listing_week']}, {r['listing_range']})")

    no_url = [
        (y, w, name)
        for (y, w), (name, _, _) in sorted(final.items())
        if not manifest.get(name, {}).get("url")
    ]
    if no_url:
        print("\nNO SOURCE URL IN tool/wer_manifest.csv (pdf_url left empty)")
        print("  Run py tool/download_wer.py to fill it from the listing page.")
        for y, w, name in no_url:
            print(f"  {y} week {w}: {name}")

    print("\nWEEKS COVERED PER YEAR")
    years = sorted({y for y, _ in final} | {y for y, _ in parsed})
    latest = max(years) if years else None
    for y in years:
        have = sorted(w for (yy, w) in final if yy == y)
        top = max(52, max(have)) if y != latest else max(have)
        miss = [w for w in range(1, top + 1) if w not in have]
        print(f"  {y}: {len(have)} weeks ({have[0]}..{have[-1]})")
        print(f"      missing within 1..{top}: {miss if miss else 'none'}")

    print("\nCHECK: sum of the 26 districts vs the SRI LANKA total")
    print(f"  {'year':<6}{'week':<6}{'sum':>8}{'total':>8}  result")
    bad = 0
    for (y, w), (_, v, total) in sorted(final.items()):
        s = sum(v[d] for d in DISTRICTS)
        if total is None:
            res = "NO TOTAL ROW"
            bad += 1
        elif s != total:
            res = f"MISMATCH ({s - total:+d})"
            if str(s).startswith(str(total)):
                # The printed total is the start of our sum with its last
                # digit(s) missing: the report itself prints a cut-short total.
                res += " printed total is the start of the sum"
            bad += 1
        else:
            res = "ok"
        print(f"  {y:<6}{w:<6}{s:>8}{(total if total is not None else '-'):>8}  {res}")
    print(f"  weeks flagged: {bad} of {len(final)}")

    print("\n5 RANDOM VALUES TO CHECK BY EYE")
    seed = args.seed if args.seed is not None else random.randrange(1, 10**6)
    rng = random.Random(seed)
    print(f"  (seed {seed}; re-run with --seed {seed} for the same picks)")
    picks = rng.sample(sorted(final), min(5, len(final)))
    for (y, w) in picks:
        name, v, _ = final[(y, w)]
        d = rng.choice(DISTRICTS)
        url = manifest.get(name, {}).get("url", "")
        src = manifest.get(name, {}).get("fetched_from", "")
        print(f"  {d}, {y}, week {w}: {v[d]} cases")
        print(f"      report: {url}")
        if src and src != url:
            print(f"      fetched from: {src}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
