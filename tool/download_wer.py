"""Download the English Weekly Epidemiological Report (WER) PDFs.

Reads the WER listing page on epid.gov.lk, keeps the entries whose date range
falls in --years, and saves each PDF into tool/wer_pdfs/ (skipping files that
are already there).

Links come from the listing page only; no URL is ever guessed.

If www.epid.gov.lk cannot be reached (it returns "509 Bandwidth Limit
Exceeded" when its quota is used up) the script falls back to the Internet
Archive's copy of the same URL. A PDF that is in neither place is logged and
left out. Every PDF is listed in tool/wer_manifest.csv with the original
epid.gov.lk URL, where it was actually fetched from, and the result.

Run from the project root:
    py tool/download_wer.py
"""

import argparse
import csv
import re
import sys
import time
from pathlib import Path

import requests
from bs4 import BeautifulSoup

LISTING_URL = (
    "https://www.epid.gov.lk/epid/public/index.php/"
    "weekly-epidemiological-report/weekly-epidemiological-report"
)
WAYBACK = "http://web.archive.org/web/{ts}id_/{url}"
# A plain client name: the site refuses requests with no User-Agent.
HEADERS = {"User-Agent": "CleanSpotDataTool/1.0 (student project)"}

ROOT = Path(__file__).resolve().parent
PDF_DIR = ROOT / "wer_pdfs"
MANIFEST = ROOT / "wer_manifest.csv"


def get(url, **kw):
    return requests.get(url, headers=HEADERS, timeout=120, **kw)


def fetch_listing(listing_file):
    """Return (html, where_it_came_from)."""
    if listing_file:
        return Path(listing_file).read_text(encoding="utf-8", errors="replace"), (
            f"file:{listing_file}"
        )
    try:
        r = get(LISTING_URL)
        if r.status_code == 200 and "product" in r.text:
            return r.text, LISTING_URL
        print(f"Live listing not usable (HTTP {r.status_code}); trying the Internet Archive.")
    except requests.RequestException as e:
        print(f"Live listing failed ({e}); trying the Internet Archive.")
    r = get(WAYBACK.format(ts="20991231", url=LISTING_URL))
    r.raise_for_status()
    # The final URL carries the snapshot timestamp.
    snap = re.search(r"/web/(\d{14})", r.url)
    return r.text, f"archive snapshot {snap.group(1) if snap else '?'} of {LISTING_URL}"


def parse_listing(html, years):
    soup = BeautifulSoup(html, "html.parser")
    entries = []
    for li in soup.select("li.product"):
        a = li.find("a", class_="btn")
        if not a or not a.get("href"):
            continue
        text = " ".join(p.get_text(" ", strip=True) for p in li.select("div.product-name p"))
        m = re.search(r"Week\s+(\d+)\s+(\d{4})\.(\d\d)\.(\d\d)\s*-\s*(\d{4})\.(\d\d)\.(\d\d)", text)
        if not m:
            continue
        end_year = int(m.group(5))
        if end_year not in years:
            continue
        url = a["href"]
        # Skip anything that is clearly not the English edition.
        if not url.lower().endswith(".pdf") or "english" not in url.lower():
            continue
        entries.append(
            {
                "listing_week": int(m.group(1)),
                "listing_range": f"{m.group(2)}.{m.group(3)}.{m.group(4)} - "
                f"{m.group(5)}.{m.group(6)}.{m.group(7)}",
                "url": url,
                "file": url.rsplit("/", 1)[-1],
            }
        )
    return entries


def variants(url):
    """The same file as the listing links it, with and without /epid/public."""
    out = [url]
    alt = (
        url.replace("/epid/public/storage/", "/storage/")
        if "/epid/public/storage/" in url
        else url.replace("/storage/", "/epid/public/storage/")
    )
    if alt != url:
        out.append(alt)
    return out


LIVE_DOWN = False  # set once the live site has failed, so we stop asking it


def get_pdf(url, tries=4):
    """GET a PDF with retries on dropped connections. Returns the response or None."""
    last = None
    for attempt in range(tries):
        try:
            r = get(url)
            if r.status_code == 200 and r.content[:5] == b"%PDF-":
                return r, "ok"
            last = f"HTTP {r.status_code}"
            if r.status_code in (404, 403, 500, 509):
                return None, last  # a real answer, retrying will not help
        except requests.RequestException as e:
            last = type(e).__name__
        time.sleep(3 * (attempt + 1))
    return None, last


def download(entry):
    """Try the live site, then the archive. Returns (bytes|None, source, note)."""
    global LIVE_DOWN
    notes = []
    if not LIVE_DOWN:
        for u in variants(entry["url"]):
            r, why = get_pdf(u, tries=1)
            if r is not None:
                return r.content, u, "live site"
            notes.append(f"live {why}")
        if all("509" in n or "500" in n for n in notes):
            LIVE_DOWN = True
            print("Live site is over its quota; using the archive for the rest.")
    for u in variants(entry["url"]):
        r, why = get_pdf(WAYBACK.format(ts="20991231", url=u))
        if r is not None:
            snap = re.search(r"/web/(\d{14})", r.url)
            return r.content, r.url, f"archive snapshot {snap.group(1) if snap else '?'}"
        notes.append(f"archive {why}")
        time.sleep(0.5)
    return None, "", "; ".join(notes)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--years", default="2024,2025,2026")
    ap.add_argument("--listing-file", help="saved listing HTML instead of fetching it")
    ap.add_argument("--delay", type=float, default=1.5, help="seconds between downloads")
    args = ap.parse_args()
    years = {int(y) for y in args.years.split(",")}

    html, listing_src = fetch_listing(args.listing_file)
    entries = parse_listing(html, years)
    print(f"Listing from: {listing_src}")
    print(f"English WER PDFs listed for {sorted(years)}: {len(entries)}")

    PDF_DIR.mkdir(parents=True, exist_ok=True)
    previous = {}
    if MANIFEST.exists():
        with MANIFEST.open(newline="", encoding="utf-8") as f:
            previous = {r["file"]: r for r in csv.DictReader(f)}
    rows = []
    for i, e in enumerate(entries, 1):
        dest = PDF_DIR / e["file"]
        if dest.exists() and dest.stat().st_size > 1000:
            old = previous.get(e["file"], {})
            status = "already there"
            src, note = old.get("fetched_from", ""), old.get("note", "")
        else:
            data, src, note = download(e)
            if data is None:
                status = "NOT AVAILABLE"
            else:
                dest.write_bytes(data)
                status = "downloaded"
                time.sleep(args.delay)
        print(f"[{i}/{len(entries)}] {e['file']}: {status} {note}")
        rows.append({**e, "status": status, "fetched_from": src, "note": note})

    with MANIFEST.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(
            f,
            fieldnames=["file", "listing_week", "listing_range", "url", "status", "fetched_from", "note"],
        )
        w.writeheader()
        for r in rows:
            w.writerow({k: r[k] for k in w.fieldnames})
    print(f"Manifest written to {MANIFEST}")
    missing = [r for r in rows if r["status"] == "NOT AVAILABLE"]
    print(f"Not available: {len(missing)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
