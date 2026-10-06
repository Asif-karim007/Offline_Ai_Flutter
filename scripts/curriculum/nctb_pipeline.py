#!/usr/bin/env python3
"""Turn NCTB's published textbooks into offline knowledge packs for the app.

Runs on a developer machine, never on the phone. Five stages, each resumable, each reading
the previous stage's output from the data directory:

    scrape    nctb.gov.bd textbook pages      -> data/catalog.json
    download  catalog.json                    -> data/pdfs/<file key>.pdf
    extract   PDFs (+ Tesseract OCR)          -> data/text/<file key>.json
    build     text (+ e5 embeddings)          -> data/packs/<pack id>.db + manifest.json
    upload    data/packs/                     -> Hugging Face dataset repository

`all` runs them in order; re-running it continues where it stopped. See README.md.

One pack is one (stream, class, version) — e.g. `general_class-9-10_bn` is every class 9–10
Bangla-version textbook — so a student downloads only what their own syllabus needs.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import unicodedata
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import requests

NCTB_BASE = "https://nctb.gov.bd"

# The "২০২৬ শিক্ষাবর্ষের সকল স্তরের পাঠ্যপুস্তক" hub links to these two level pages. Each level
# page is one table whose cells link to one page per class per stream. Update these when
# NCTB publishes the next academic year (menu: পাঠ্যপুস্তক → <year> শিক্ষাবর্ষের ...).
LEVEL_PAGES = {
    "primary": "/pages/static-pages/695b9b7cc4774958d7b70a12",
    "secondary": "/pages/static-pages/695b98afc4774958d7b7044c",
}
ACADEMIC_YEAR = 2026

DEFAULT_STREAMS = ("general", "hsc")
ALL_STREAMS = ("general", "hsc", "madrasa", "technical")

EMBEDDING_MODEL = "intfloat/multilingual-e5-small"
EMBEDDING_DIM = 384
PACK_SCHEMA_VERSION = 1

DEFAULT_HF_REPO = "Asifkarim/nctb-curriculum-packs"

USER_AGENT = "Mozilla/5.0 (offline-ai-chat curriculum pipeline)"

# nctb.gov.bd serves an incomplete certificate chain, so strict verification fails on most
# machines. Only the public HTML index pages are fetched from it; the PDFs come from Google
# Drive or the government egovcloud mirror, both verified normally.
NCTB_VERIFY_TLS = False


# ---------------------------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------------------------

BANGLA_DIGITS = str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789")

ORDINAL_WORDS = {
    # Longest first, so "একাদশ"/"দ্বাদশ" are consumed before anything shorter could match.
    "একাদশ": 11, "দ্বাদশ": 12, "প্রথম": 1, "দ্বিতীয়": 2, "তৃতীয়": 3, "চতুর্থ": 4,
    "পঞ্চম": 5, "ষষ্ঠ": 6, "সপ্তম": 7, "অষ্টম": 8, "নবম": 9, "দশম": 10,
}

ENGLISH_VERSION_MARKERS = ("ইংলিশ ভার্সন", "ইংরেজি ভার্সন", "english version")


def log(message: str) -> None:
    print(message, flush=True)


def clean_text(fragment: str) -> str:
    """HTML fragment -> one line of plain NFC text."""
    text = re.sub(r"<[^>]+>", " ", fragment)
    text = html.unescape(text).replace("\xa0", " ")
    return unicodedata.normalize("NFC", re.sub(r"\s+", " ", text)).strip()


def class_numbers(text: str) -> list[int]:
    """Class numbers mentioned in a page title or link label, 1–12 only."""
    text = unicodedata.normalize("NFC", text)
    found: list[int] = []
    for word, number in ORDINAL_WORDS.items():
        if word in text:
            found.append(number)
            text = text.replace(word, " ")
    for digits in re.findall(r"\d+", text.translate(BANGLA_DIGITS)):
        number = int(digits)
        if 1 <= number <= 12:  # drops the academic year and other stray numbers
            found.append(number)
    return sorted(set(found))


def class_key(numbers: list[int]) -> str:
    if not numbers:
        return "class-unknown"
    if len(numbers) == 1:
        return f"class-{numbers[0]}"
    return f"class-{numbers[0]}-{numbers[-1]}"


def is_english_version(title: str) -> bool:
    lowered = title.lower()
    return any(marker in lowered for marker in ENGLISH_VERSION_MARKERS)


def strip_version_marker(title: str) -> str:
    stripped = title
    for marker in ENGLISH_VERSION_MARKERS:
        stripped = re.sub(r"\(?\s*" + re.escape(marker) + r"\s*\)?", "", stripped, flags=re.I)
    return stripped.strip()


def stream_for_title(title: str) -> str | None:
    """Which stream a class page belongs to, or None for pages this pipeline ignores."""
    if any(word in title for word in ("শিক্ষক", "নির্দেশিকা", "ম্যানুয়াল", "নৃ", "প্রাক")):
        return None  # teacher guides, assessment guidelines, indigenous-language books, pre-primary
    if "দাখিল" in title or "ইবতেদায়ি" in title:
        return "madrasa"
    if "কারিগরি" in title:
        return "technical"
    if "উচ্চ মাধ্যমিক" in title:
        return "hsc"
    return "general"


def http_session() -> requests.Session:
    session = requests.Session()
    session.headers["User-Agent"] = USER_AGENT
    return session


def fetch_nctb(session: requests.Session, path: str) -> str:
    if not NCTB_VERIFY_TLS:
        requests.packages.urllib3.disable_warnings()  # type: ignore[attr-defined]
    for attempt in range(4):
        try:
            response = session.get(NCTB_BASE + path, timeout=60, verify=NCTB_VERIFY_TLS)
            response.raise_for_status()
            response.encoding = "utf-8"
            return response.text
        except requests.RequestException as error:
            if attempt == 3:
                raise
            log(f"  retrying {path}: {error}")
            time.sleep(3 * (attempt + 1))
    raise AssertionError("unreachable")


def first_table_rows(page: str) -> list[list[str]]:
    """The raw HTML of each cell of each row of the page's first <table>."""
    start = page.find("<table")
    if start < 0:
        return []
    table = page[start:page.find("</table>", start)]
    return [
        re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)
        for row in re.findall(r"<tr.*?</tr>", table, re.S)
    ]


def hrefs(cell: str) -> list[str]:
    return [html.unescape(h) for h in re.findall(r'href="([^"]+)"', cell)]


# ---------------------------------------------------------------------------------------------
# Stage 1: scrape
# ---------------------------------------------------------------------------------------------

@dataclass
class Book:
    id: str                   # unique per (pack, book)
    pack_id: str              # e.g. general_class-9-10_bn
    stream: str
    class_key: str
    version: str              # "bn" (Bangla version) or "en" (English version)
    title: str
    file_key: str             # identifies the PDF itself; shared books share one download
    urls: list[str] = field(default_factory=list)
    source_page: str = ""


def drive_file_id(url: str) -> str | None:
    match = re.search(r"drive\.google\.com/(?:file/d/|open\?id=|uc\?id=)([\w-]{20,})", url)
    return match.group(1) if match else None


def file_key_for(urls: list[str]) -> str | None:
    for url in urls:
        if drive_id := drive_file_id(url):
            return "gd_" + drive_id
    for url in urls:
        if match := re.search(r"egovcloud\.gov\.bd/index\.php/s/(\w+)", url):
            return "eg_" + match.group(1)
    return None


def parse_class_page(page: str, stream: str, ckey: str, page_path: str) -> list[Book]:
    rows = first_table_rows(page)
    if not rows:
        return []
    header = " ".join(clean_text(cell) for cell in rows[0])
    two_versions = "ইংরেজি ভার্সন" in header or "ইংলিশ ভার্সন" in header

    found: list[tuple[str, str, list[str]]] = []  # (version or "", title, urls)
    for cells in rows[1:]:
        last_name = ""
        link_cell_index = 0
        for cell in cells:
            links = [u for u in hrefs(cell) if "drive.google" in u or "egovcloud" in u]
            text = clean_text(cell)
            if not links:
                if text and not re.fullmatch(r"[\d০-৯.\s]+", text):
                    last_name = text
                continue
            if not last_name:
                continue
            if two_versions:
                version = "bn" if link_cell_index == 0 else "en"
            else:
                version = "en" if is_english_version(last_name) else ""
            found.append((version, last_name, links))
            link_cell_index += 1

    # Single-column pages (HSC, madrasa, technical) mostly list books shared by both versions,
    # with an occasional "(ইংলিশ ভার্সন)" twin. A book with such a twin is Bangla-version only;
    # one without is common to both. Madrasa and technical streams are Bangla-medium only.
    english_twins = {strip_version_marker(t) for v, t, _ in found if v == "en"}
    books: list[Book] = []
    for version, title, links in found:
        if version:
            versions = [version]
        elif stream in ("madrasa", "technical") or strip_version_marker(title) in english_twins:
            versions = ["bn"]
        else:
            versions = ["bn", "en"]
        key = file_key_for(links)
        if key is None:
            log(f"  ! no usable download link for {title!r} on {page_path}")
            continue
        for v in versions:
            pack_id = f"{stream}_{ckey}_{v}"
            books.append(Book(
                id=f"{pack_id}:{key}", pack_id=pack_id, stream=stream, class_key=ckey,
                version=v, title=title, file_key=key, urls=links, source_page=page_path,
            ))
    return books


def scrape(data_dir: Path, streams: tuple[str, ...]) -> None:
    session = http_session()
    seen_pages: set[str] = set()
    books: dict[str, Book] = {}

    for level, level_path in LEVEL_PAGES.items():
        log(f"Level page: {level}")
        level_page = fetch_nctb(session, level_path)
        for cells in first_table_rows(level_page):
            for cell in cells:
                label = clean_text(cell)
                for href in hrefs(cell):
                    if not href.startswith("/pages/static-pages/") or href in seen_pages:
                        continue
                    seen_pages.add(href)
                    page = fetch_nctb(session, href)
                    title_match = re.search(r"<title>(.*?)</title>", page, re.S)
                    title = clean_text(title_match.group(1)).split("|")[0] if title_match else ""
                    stream = stream_for_title(title)
                    if stream is None or stream not in streams:
                        log(f"  skip   {label:<22} {title[:60]}")
                        continue
                    # The title is authoritative (one link cell can hold class 9 *and* 10);
                    # the link label covers pages NCTB left untitled.
                    numbers = class_numbers(title) or class_numbers(label)
                    if not numbers:
                        log(f"  skip   {label:<22} no class number in {title[:50]!r}")
                        continue
                    ckey = class_key(numbers)
                    page_books = parse_class_page(page, stream, ckey, href)
                    for book in page_books:
                        books.setdefault(book.id, book)
                    log(f"  {stream:<9} {ckey:<12} {len(page_books):>3} books  ({title[:50]})")
                    time.sleep(0.5)


    catalog = {
        "academic_year": ACADEMIC_YEAR,
        "scraped_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "books": [asdict(book) for book in books.values()],
    }
    data_dir.mkdir(parents=True, exist_ok=True)
    write_json(data_dir / "catalog.json", catalog, indent=2)
    packs = Counter(book.pack_id for book in books.values())
    files = {book.file_key for book in books.values()}
    log(f"\n{len(books)} book entries, {len(files)} distinct PDFs, {len(packs)} packs:")
    for pack_id, count in sorted(packs.items()):
        log(f"  {pack_id:<32} {count} books")


def write_json(path: Path, value, indent: int | None = None) -> None:
    # Always UTF-8: on Windows the default encoding is a code page that cannot hold Bangla.
    path.write_text(json.dumps(value, ensure_ascii=False, indent=indent), encoding="utf-8")


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def load_catalog(data_dir: Path, packs: list[str] | None = None) -> list[Book]:
    """The scraped catalog, narrowed to [packs] when given."""
    path = data_dir / "catalog.json"
    if not path.exists():
        sys.exit(f"{path} not found — run the 'scrape' stage first.")
    books = [Book(**entry) for entry in read_json(path)["books"]]
    if packs:
        known = {book.pack_id for book in books}
        unknown = sorted(set(packs) - known)
        if unknown:
            sys.exit(f"Unknown pack id(s): {', '.join(unknown)}\nKnown: {', '.join(sorted(known))}")
        books = [book for book in books if book.pack_id in packs]
    return books


def distinct_files(books: list[Book]) -> dict[str, Book]:
    """One representative Book per PDF — a book shared by both versions is one download."""
    by_file: dict[str, Book] = {}
    for book in books:
        by_file.setdefault(book.file_key, book)
    return dict(sorted(by_file.items()))


# ---------------------------------------------------------------------------------------------
# Stage 2: download
# ---------------------------------------------------------------------------------------------

def candidate_download_urls(urls: list[str]) -> list[str]:
    candidates = []
    for url in urls:
        if drive_id := drive_file_id(url):
            candidates.append(
                f"https://drive.usercontent.google.com/download?id={drive_id}&export=download&confirm=t"
            )
        elif match := re.search(r"(https?://drive\.egovcloud\.gov\.bd/index\.php/s/\w+)", url):
            candidates.append(match.group(1) + "/download")
    return list(dict.fromkeys(candidates))  # de-duplicate, keep order


def is_pdf(path: Path) -> bool:
    """A complete PDF: the header at the start *and* the %%EOF trailer at the end.

    Checking the header alone accepts a download that was cut off halfway, which then opens
    as a zero-page document much later in `extract`.
    """
    try:
        with path.open("rb") as handle:
            if handle.read(5) != b"%PDF-":
                return False
            handle.seek(max(0, path.stat().st_size - 2048))
            return b"%%EOF" in handle.read()
    except OSError:
        return False


def download_one(session: requests.Session, url: str, target: Path) -> bool:
    partial = target.with_suffix(".part")
    written = 0
    try:
        with session.get(url, stream=True, timeout=(30, 300)) as response:
            response.raise_for_status()
            expected = int(response.headers.get("Content-Length") or 0)
            with partial.open("wb") as handle:
                for block in response.iter_content(chunk_size=1 << 20):
                    handle.write(block)
                    written += len(block)
    except requests.RequestException as error:
        log(f"    failed: {error}")
        partial.unlink(missing_ok=True)
        return False
    if expected and written != expected:
        log(f"    failed: connection dropped at {written:,} of {expected:,} bytes")
        partial.unlink(missing_ok=True)
        return False
    if not is_pdf(partial):
        # Google answers quota/virus-scan problems with an HTML page and a 200.
        log("    failed: response was not a complete PDF (Drive quota page?)")
        partial.unlink(missing_ok=True)
        return False
    partial.replace(target)
    log(f"    downloaded {written / 1e6:.1f} MB")
    return True


def download(data_dir: Path, books: list[Book], delay: float, after_each=None) -> None:
    """Fetch every PDF in [books] not already downloaded *or already extracted*.

    [after_each], when given, is called with each file key right after its PDF lands — the
    space-saving mode uses it to extract and then delete each PDF before fetching the next,
    so only one book's PDF is ever on disk.
    """
    pdf_dir = data_dir / "pdfs"
    pdf_dir.mkdir(parents=True, exist_ok=True)
    session = http_session()
    files = distinct_files(books)

    failed: list[str] = []
    for index, (key, book) in enumerate(files.items(), start=1):
        target = pdf_dir / f"{key}.pdf"
        if is_pdf(target) or text_path(data_dir, key).exists():
            continue
        log(f"[{index}/{len(files)}] {book.class_key} {book.title}")
        if any(download_one(session, url, target) for url in candidate_download_urls(book.urls)):
            if after_each is not None:
                after_each(key)
        else:
            failed.append(f"{key}  {book.class_key}  {book.title}")
        time.sleep(delay)

    done = sum(1 for key in files if is_pdf(pdf_dir / f"{key}.pdf") or text_path(data_dir, key).exists())
    log(f"\n{done}/{len(files)} books downloaded")
    if failed:
        log(f"{len(failed)} failed — run the same command again later (Google Drive rate-limits bursts):")
        for line in failed:
            log("  " + line)


# ---------------------------------------------------------------------------------------------
# Stage 3: extract
# ---------------------------------------------------------------------------------------------

def text_path(data_dir: Path, key: str) -> Path:
    return data_dir / "text" / f"{key}.json"


def is_bengali(char: str) -> bool:
    return "\u0980" <= char <= "\u09ff"


def page_quality(text: str) -> tuple[str, float]:
    """Classify extracted page text: ("ok" | "empty" | "broken", bengali share of letters).

    Three failure modes occur in NCTB PDFs. Many books draw their text as vector outlines and
    have no text layer at all ("empty"). Pages typeset with legacy Bijoy/SutonnyMJ fonts, or
    with a broken ToUnicode map, extract as Latin gibberish ("evsjv" for "বাংলা") or as
    Bengali with vowel signs in visual order — a word that *starts* with a dependent vowel sign
    like ি or ে cannot occur in correct Unicode ("broken"). Either way the page is OCR'd.
    """
    letters = [c for c in text if c.isalpha() or unicodedata.category(c).startswith("M")]
    if len(letters) < 40:
        return "empty", 0.0
    bengali_share = sum(map(is_bengali, letters)) / len(letters)

    bengali_words = re.findall(r"[\u0980-\u09ff]+", text)
    if bengali_words:
        mark_initial = sum(unicodedata.category(w[0]).startswith("M") for w in bengali_words)
        if mark_initial / len(bengali_words) > 0.08:
            return "broken", bengali_share

    if bengali_share < 0.05:
        # Latin text: either real English (English-version books) or legacy-font gibberish.
        # Real English is mostly common short words; Bijoy-encoded Bangla almost never is.
        words = re.findall(r"[A-Za-z]+", text.lower())
        common = {"the", "of", "and", "to", "a", "in", "is", "that", "for", "it", "with",
                  "as", "are", "on", "be", "this", "by", "an", "we", "or", "from", "you"}
        if words and sum(w in common for w in words) / len(words) < 0.04:
            return "broken", bengali_share
    return "ok", bengali_share


def find_tesseract() -> str | None:
    found = shutil.which("tesseract")
    if found:
        return found
    # The Windows installer does not add itself to PATH by default.
    for candidate in (r"C:\Program Files\Tesseract-OCR\tesseract.exe",
                      r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"):
        if Path(candidate).exists():
            return candidate
    return None


def check_tesseract(ocr: str) -> str | None:
    """Path to a Tesseract that has Bengali and English data, or None (with the reason logged)."""
    if ocr == "never":
        return None
    exe = find_tesseract()
    if exe is None:
        log("! Tesseract OCR is not installed. Most NCTB books have no text layer, so without it\n"
            "  most books will come out EMPTY. Install it (see README.md) and run again.")
        return None
    result = subprocess.run([exe, "--list-langs"], capture_output=True, text=True, check=False)
    langs = set((result.stdout + result.stderr).split())
    missing = [lang for lang in ("ben", "eng") if lang not in langs]
    if missing:
        log(f"! Tesseract is missing language data: {', '.join(missing)} (see README.md).")
        return None
    return exe


def ocr_png(exe: str, png: bytes) -> str:
    result = subprocess.run(
        [exe, "stdin", "stdout", "-l", "ben+eng", "--psm", "3"],
        input=png, capture_output=True, check=False,
        # One thread per Tesseract process: pages already run in parallel, and Tesseract's own
        # OpenMP threading on top of that oversubscribes the CPU and runs slower overall.
        env={**os.environ, "OMP_THREAD_LIMIT": "1"},
    )
    return unicodedata.normalize("NFC", result.stdout.decode("utf-8", errors="replace"))


def extract_one(data_dir: Path, key: str, title: str, tesseract: str | None, ocr: str,
                dpi: int, workers: int) -> bool:
    """PDF -> text/<key>.json, page by page. Returns False if the PDF could not be read."""
    import pymupdf

    pdf = data_dir / "pdfs" / f"{key}.pdf"
    try:
        document = pymupdf.open(pdf)
    except Exception as error:  # corrupt download
        log(f"    cannot open {pdf.name}: {error}")
        return False

    started = time.time()
    results: dict[int, tuple[str, str]] = {}  # page -> (method, text)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        pending = {}
        for number, page in enumerate(document, start=1):
            text = unicodedata.normalize("NFC", page.get_text("text", sort=True))
            quality, _ = page_quality(text)
            if tesseract and (quality != "ok" or ocr == "always"):
                # Rendering stays on this thread (PyMuPDF is not thread-safe); only the
                # Tesseract subprocess runs in the pool.
                png = page.get_pixmap(dpi=dpi).tobytes("png")
                pending[number] = pool.submit(ocr_png, tesseract, png)
                if len(pending) >= workers * 2:  # bound memory held in rendered pages
                    for done_number in list(pending)[:workers]:
                        results[done_number] = ("ocr", pending.pop(done_number).result())
            else:
                results[number] = ("text", text)
        for done_number, future in pending.items():
            results[done_number] = ("ocr", future.result())

    pages = []
    counts = Counter()
    for number in sorted(results):
        method, text = results[number]
        quality, _ = page_quality(text)
        counts[method if quality == "ok" else "unusable"] += 1
        if quality == "ok":
            pages.append({"page": number, "method": method, "text": text})

    log(f"    {document.page_count} pages: {counts['text']} text layer, {counts['ocr']} OCR, "
        f"{counts['unusable']} unusable ({time.time() - started:.0f}s)")
    write_json(text_path(data_dir, key), {
        "file_key": key, "title": title, "page_count": document.page_count,
        "pages_text": counts["text"], "pages_ocr": counts["ocr"],
        "pages_unusable": counts["unusable"], "pages": pages,
    })
    document.close()
    return True


def extract(data_dir: Path, books: list[Book], ocr: str, dpi: int, workers: int,
            delete_pdfs: bool) -> None:
    (data_dir / "text").mkdir(parents=True, exist_ok=True)
    tesseract = check_tesseract(ocr)
    files = distinct_files(books)
    todo = [(k, b) for k, b in files.items()
            if not text_path(data_dir, k).exists() and is_pdf(data_dir / "pdfs" / f"{k}.pdf")]
    for index, (key, book) in enumerate(todo, start=1):
        log(f"[extract {index}/{len(todo)}] {book.class_key} {book.title}")
        if extract_one(data_dir, key, book.title, tesseract, ocr, dpi, workers) and delete_pdfs:
            (data_dir / "pdfs" / f"{key}.pdf").unlink(missing_ok=True)
    write_extract_report(data_dir, books)


def write_extract_report(data_dir: Path, books: list[Book]) -> None:
    rows = ["file_key,class,title,pages,text_layer,ocr,unusable"]
    for key, book in distinct_files(books).items():
        path = text_path(data_dir, key)
        if not path.exists():
            rows.append(f'{key},{book.class_key},"{book.title}",,,,NOT EXTRACTED')
            continue
        info = read_json(path)
        rows.append(f'{key},{book.class_key},"{book.title}",{info["page_count"]},'
                    f'{info["pages_text"]},{info["pages_ocr"]},{info["pages_unusable"]}')
    # utf-8-sig so Excel shows the Bangla titles instead of mojibake.
    (data_dir / "extract_report.csv").write_text("\n".join(rows) + "\n", encoding="utf-8-sig")
    log(f"Per-book quality report: {data_dir / 'extract_report.csv'}")


# ---------------------------------------------------------------------------------------------
# Stage 4: build packs
# ---------------------------------------------------------------------------------------------

CHAPTER_PATTERN = re.compile(
    r"^\s*(?:(?:[০-৯\d]+|প্রথম|দ্বিতীয়|তৃতীয়|চতুর্থ|পঞ্চম|ষষ্ঠ|সপ্তম|অষ্টম|নবম|দশম|একাদশ|দ্বাদশ)"
    r"\s*(?:অধ্যায়|অধ্যায়)|(?:অধ্যায়|অধ্যায়)\s*[:\-–]?\s*[০-৯\d]+|(?:chapter|unit|lesson)\s+[\w০-৯]+)",
    re.I,
)


def strip_boilerplate(pages: list[dict]) -> list[dict]:
    """Drop running headers/footers (lines repeated on many pages) and bare page numbers."""
    def signature(line: str) -> str:
        return re.sub(r"[\d০-৯\s]+", "", line)

    line_counts = Counter()
    for page in pages:
        line_counts.update({signature(l) for l in page["text"].splitlines() if l.strip()})
    threshold = max(4, int(len(pages) * 0.3))
    repeated = {sig for sig, count in line_counts.items() if count >= threshold and len(sig) < 80}

    cleaned = []
    for page in pages:
        lines = [
            line for line in page["text"].splitlines()
            if line.strip()
            and signature(line) not in repeated
            and not re.fullmatch(r"\s*[\d০-৯]{1,4}\s*", line)
        ]
        cleaned.append({**page, "text": "\n".join(lines)})
    return cleaned


def paragraphs_with_pages(pages: list[dict]):
    """Yield (page number, chapter heading or None, paragraph text)."""
    chapter = None
    for page in pages:
        buffer: list[str] = []
        lines = page["text"].splitlines()
        # A table of contents lists every chapter heading on one page. Taking those as
        # headings would label the whole book with the *last* chapter in the list, so a page
        # with several headings — or a heading followed by page numbers ("অধ্যায় ১১ ... ১৩৩ - ১৪৪")
        # — is treated as ordinary text.
        is_contents_page = sum(bool(CHAPTER_PATTERN.match(l.strip())) for l in lines) >= 3
        for line in lines:
            stripped = line.strip()
            looks_like_contents_entry = re.search(r"[\d০-৯]+\s*[-–]\s*[\d০-৯]+\s*$", stripped)
            if (CHAPTER_PATTERN.match(stripped) and len(stripped) < 120
                    and not is_contents_page and not looks_like_contents_entry):
                if buffer:
                    yield page["page"], chapter, " ".join(buffer)
                    buffer = []
                chapter = stripped
                continue
            buffer.append(stripped)
            # A line ending in sentence punctuation (। ? ! .) closes a paragraph.
            if re.search(r"[।?!.]$", stripped) and sum(map(len, buffer)) > 200:
                yield page["page"], chapter, " ".join(buffer)
                buffer = []
        if buffer:
            yield page["page"], chapter, " ".join(buffer)


def chunk_book(pages: list[dict], target_chars: int, overlap_chars: int) -> list[dict]:
    chunks: list[dict] = []
    current: list[tuple[int, str]] = []
    current_chapter = None

    def flush() -> None:
        if not current:
            return
        text = re.sub(r"\s+", " ", " ".join(t for _, t in current)).strip()
        if len(text) >= 80:  # captions, stray labels and the like are not worth retrieving
            chunks.append({
                "chapter": current_chapter,
                "page_start": current[0][0],
                "page_end": current[-1][0],
                "text": text,
            })

    for page_number, chapter, paragraph in paragraphs_with_pages(strip_boilerplate(pages)):
        if chapter != current_chapter and current:
            flush()
            current = []
        current_chapter = chapter
        # Very long paragraphs are cut at sentence boundaries so no chunk overruns the
        # embedding model's 512-token window.
        sentences = re.split(r"(?<=[।?!.])\s+", paragraph) if len(paragraph) > target_chars else [paragraph]
        # OCR output and tables can run on with no sentence punctuation at all; those are cut
        # at whitespace instead.
        pieces = []
        for sentence in sentences:
            while len(sentence) > target_chars:
                cut = sentence.rfind(" ", 0, target_chars)
                cut = cut if cut > target_chars // 2 else target_chars
                pieces.append(sentence[:cut])
                sentence = sentence[cut:].lstrip()
            pieces.append(sentence)
        for piece in pieces:
            if current and sum(len(t) for _, t in current) + len(piece) > target_chars:
                flush()
                tail = current[-1][1][-overlap_chars:] if overlap_chars else ""
                tail = tail.split(" ", 1)[-1] if " " in tail else tail  # start on a word
                current = [(current[-1][0], tail)] if tail else []
            current.append((page_number, piece))
    flush()
    return chunks


def load_embedder(device: str | None):
    from sentence_transformers import SentenceTransformer
    log(f"Loading {EMBEDDING_MODEL} (downloads ~470 MB the first time) ...")
    return SentenceTransformer(EMBEDDING_MODEL, device=device)


def embed_passages(model, texts: list[str], batch_size: int) -> list[bytes]:
    import numpy as np
    # e5 is trained with these prefixes. The app must embed questions as "query: <text>"
    # and normalise them the same way, or cosine scores are meaningless.
    vectors = model.encode(
        [f"passage: {t}" for t in texts], batch_size=batch_size,
        normalize_embeddings=True, show_progress_bar=len(texts) > 200,
    )
    return [np.asarray(v, dtype="<f4").tobytes() for v in vectors]


PACK_SCHEMA = """
CREATE TABLE meta   (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE books  (id TEXT PRIMARY KEY, title TEXT NOT NULL, file_key TEXT NOT NULL,
                     page_count INTEGER, source_url TEXT);
CREATE TABLE chunks (id INTEGER PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
                     chapter TEXT, page_start INTEGER, page_end INTEGER,
                     text TEXT NOT NULL,
                     embedding BLOB);  -- 384 x float32 little-endian, L2-normalised; NULL if built without
CREATE INDEX chunks_book ON chunks(book_id);
"""

STREAM_LABELS = {
    "general": ("সাধারণ", "General"), "hsc": ("উচ্চ মাধ্যমিক", "HSC"),
    "madrasa": ("মাদ্রাসা", "Madrasa"), "technical": ("কারিগরি", "Technical"),
}


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def build(data_dir: Path, books: list[Book], embeddings: bool, target_chars: int,
          overlap_chars: int, batch_size: int, device: str | None) -> None:
    pack_dir = data_dir / "packs"
    pack_dir.mkdir(parents=True, exist_ok=True)
    model = load_embedder(device) if embeddings else None

    packs: dict[str, list[Book]] = {}
    for book in books:
        packs.setdefault(book.pack_id, []).append(book)

    chunk_cache: dict[str, list[dict]] = {}  # shared books are chunked and embedded once
    vector_cache: dict[str, list[bytes]] = {}

    for pack_id, pack_books in sorted(packs.items()):
        sample = pack_books[0]
        path = pack_dir / f"{pack_id}.db"
        path.unlink(missing_ok=True)
        db = sqlite3.connect(path)
        db.executescript(PACK_SCHEMA)
        total_chunks = 0
        included = 0

        for book in pack_books:
            source = text_path(data_dir, book.file_key)
            if not source.exists():
                log(f"  ! {pack_id}: no extracted text for {book.title} — skipped")
                continue
            extracted = read_json(source)
            if book.file_key not in chunk_cache:
                chunk_cache[book.file_key] = chunk_book(extracted["pages"], target_chars, overlap_chars)
                if model is not None and chunk_cache[book.file_key]:
                    vector_cache[book.file_key] = embed_passages(
                        model, [c["text"] for c in chunk_cache[book.file_key]], batch_size)
            chunks = chunk_cache[book.file_key]
            if not chunks:
                log(f"  ! {pack_id}: {book.title} produced no text — check extract_report.csv")
                continue
            vectors = vector_cache.get(book.file_key) or [None] * len(chunks)
            db.execute(
                "INSERT INTO books VALUES (?, ?, ?, ?, ?)",
                (book.file_key, book.title, book.file_key, extracted["page_count"],
                 book.urls[0] if book.urls else None),
            )
            db.executemany(
                "INSERT INTO chunks (book_id, chapter, page_start, page_end, text, embedding)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                [(book.file_key, c["chapter"], c["page_start"], c["page_end"], c["text"], v)
                 for c, v in zip(chunks, vectors)],
            )
            total_chunks += len(chunks)
            included += 1

        meta = {
            "schema_version": PACK_SCHEMA_VERSION,
            "pack_id": pack_id,
            "stream": sample.stream,
            "class": sample.class_key,
            "version": sample.version,
            "academic_year": ACADEMIC_YEAR,
            "embedding_model": EMBEDDING_MODEL if model is not None else "",
            "embedding_dim": EMBEDDING_DIM if model is not None else 0,
            "embedding_query_prefix": "query: ",
            "source": "National Curriculum and Textbook Board (NCTB), Bangladesh — nctb.gov.bd",
            "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        db.executemany("INSERT INTO meta VALUES (?, ?)", [(k, str(v)) for k, v in meta.items()])
        db.commit()
        db.execute("VACUUM")
        db.close()

        if included == 0:
            path.unlink()
            log(f"  {pack_id}: nothing to pack, skipped")
            continue
        log(f"  {pack_id:<32} {included:>2} books {total_chunks:>6} chunks "
            f"{path.stat().st_size / 1e6:7.1f} MB")

    write_manifest(pack_dir)
    log(f"\nPacks and manifest written to {pack_dir}")


def write_manifest(pack_dir: Path) -> None:
    """manifest.json and the dataset card, from every pack on disk.

    Read back from the .db files rather than from this run's work, so building packs in
    several runs (`--packs`) still ends with one manifest that lists all of them.
    """
    entries = []
    embedding_model, embedding_dim = "", 0
    for path in sorted(pack_dir.glob("*.db")):
        db = sqlite3.connect(path)
        meta = dict(db.execute("SELECT key, value FROM meta"))
        books = db.execute("SELECT COUNT(*) FROM books").fetchone()[0]
        chunks = db.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
        db.close()
        embedding_model = embedding_model or meta.get("embedding_model", "")
        embedding_dim = embedding_dim or int(meta.get("embedding_dim", 0))
        stream = meta["stream"]
        bn_stream, en_stream = STREAM_LABELS[stream]
        version_label = "Bangla version" if meta["version"] == "bn" else "English version"
        entries.append({
            "id": meta["pack_id"],
            "file": path.name,
            "title": f"{meta['class'].replace('class-', 'Class ')} · {en_stream} · {version_label}",
            "stream": stream,
            "stream_bn": bn_stream,
            "class": meta["class"],
            "version": meta["version"],
            "has_embeddings": bool(meta.get("embedding_model")),
            "books": books,
            "chunks": chunks,
            "size_bytes": path.stat().st_size,
            "sha256": sha256_of(path),
        })
    manifest = {
        "schema_version": PACK_SCHEMA_VERSION,
        "academic_year": ACADEMIC_YEAR,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "embedding_model": embedding_model,
        "embedding_dim": embedding_dim,
        "packs": entries,
    }
    write_json(pack_dir / "manifest.json", manifest, indent=2)
    write_dataset_card(pack_dir, manifest)


def write_dataset_card(pack_dir: Path, manifest: dict) -> None:
    rows = "\n".join(
        f"| `{p['file']}` | {p['title']} | {p['books']} | {p['chunks']} | {p['size_bytes'] / 1e6:.1f} MB |"
        for p in manifest["packs"]
    )
    (pack_dir / "README.md").write_text(f"""---
language: [bn, en]
pretty_name: NCTB curriculum knowledge packs
tags: [education, bangladesh, rag]
---

# NCTB curriculum knowledge packs ({manifest['academic_year']})

Text extracted from the textbooks published by the National Curriculum and Textbook Board
(NCTB), Bangladesh, at nctb.gov.bd, split into retrieval chunks for an offline on-device study
assistant. One SQLite file per class, stream and version.

The textbook content belongs to NCTB. This repository redistributes it in processed form for
free educational use.

| File | Pack | Books | Chunks | Size |
|---|---|---|---|---|
{rows}

## Format

`meta`, `books`, `chunks` tables. `chunks.embedding` is a {manifest['embedding_dim']}-dim
float32 little-endian L2-normalised vector from `{manifest['embedding_model'] or 'none'}`,
computed on `"passage: " + text`; embed questions as `"query: " + question` and normalise.
`manifest.json` lists every pack with its size and SHA-256.
""", encoding="utf-8")


# ---------------------------------------------------------------------------------------------
# Stage 5: upload
# ---------------------------------------------------------------------------------------------

def hf_user() -> str | None:
    """The logged-in Hugging Face user, or None. The token itself never passes through here."""
    try:
        from huggingface_hub import HfApi
        return HfApi().whoami()["name"]
    except Exception:
        return None


def upload(data_dir: Path, repo: str, public: bool) -> None:
    from huggingface_hub import HfApi

    pack_dir = data_dir / "packs"
    if not (pack_dir / "manifest.json").exists():
        sys.exit(f"No packs in {pack_dir} — run the 'build' stage first.")
    user = hf_user()
    if user is None:
        sys.exit("Not logged in to Hugging Face. Run:  hf auth login")

    api = HfApi()
    api.create_repo(repo, repo_type="dataset", private=not public, exist_ok=True)
    files = sorted(p.name for p in pack_dir.iterdir() if p.is_file())
    total = sum((pack_dir / name).stat().st_size for name in files)
    log(f"Uploading {len(files)} files ({total / 1e6:.0f} MB) to {repo} as {user} ...")
    api.upload_folder(
        folder_path=str(pack_dir), repo_id=repo, repo_type="dataset",
        allow_patterns=["*.db", "manifest.json", "README.md"],
        commit_message=f"NCTB {ACADEMIC_YEAR} curriculum packs",
    )
    log(f"Done: https://huggingface.co/datasets/{repo}")


# ---------------------------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------------------------

def main() -> None:
    # Windows consoles default to a code page that cannot print Bangla book titles.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stage", choices=["scrape", "download", "extract", "build", "upload", "all"])
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).parent / "data")
    parser.add_argument("--streams", default=",".join(DEFAULT_STREAMS),
                        help=f"comma list from {','.join(ALL_STREAMS)} (default: %(default)s)")
    parser.add_argument("--packs", default="",
                        help="only these pack ids, comma list (e.g. general_class-9-10_bn)")
    parser.add_argument("--delete-pdfs", action="store_true",
                        help="save disk: extract each PDF right after download, then delete it")
    parser.add_argument("--delay", type=float, default=2.0, help="seconds between downloads")
    parser.add_argument("--ocr", choices=["auto", "always", "never"], default="auto",
                        help="auto = OCR only pages whose text layer is missing or broken")
    parser.add_argument("--ocr-dpi", type=int, default=300)
    parser.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) - 1),
                        help="parallel OCR processes (default: CPU cores - 1)")
    parser.add_argument("--no-embeddings", action="store_true",
                        help="build text-only packs (no PyTorch needed); the app then uses BM25 only")
    parser.add_argument("--chunk-chars", type=int, default=800)
    parser.add_argument("--overlap-chars", type=int, default=150)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--device", default=None, help="torch device: cuda, mps or cpu (default: auto)")
    parser.add_argument("--repo", default=DEFAULT_HF_REPO, help="Hugging Face dataset repo for 'upload'")
    parser.add_argument("--public", action="store_true",
                        help="create the dataset repo public (default: private)")
    parser.add_argument("--no-upload", action="store_true", help="'all' stops after 'build'")
    args = parser.parse_args()

    streams = tuple(s.strip() for s in args.streams.split(",") if s.strip())
    unknown = set(streams) - set(ALL_STREAMS)
    if unknown:
        parser.error(f"unknown stream(s): {', '.join(sorted(unknown))}")
    packs = [p.strip() for p in args.packs.split(",") if p.strip()] or None

    if args.stage == "all":
        stages = ["scrape", "download", "extract", "build"] + ([] if args.no_upload else ["upload"])
        # Fail in the first second, not after a day of OCR.
        if "upload" in stages and hf_user() is None:
            sys.exit("Not logged in to Hugging Face. Run  hf auth login  first "
                     "(or add --no-upload).")
        if check_tesseract(args.ocr) is None and args.ocr != "never":
            sys.exit("Fix Tesseract first, or pass --ocr never to accept mostly-empty packs.")
    else:
        stages = [args.stage]

    for stage in stages:
        log(f"\n=== {stage} ===")
        if stage == "scrape":
            if args.stage == "all" and (args.data_dir / "catalog.json").exists():
                log("catalog.json exists — reusing it (run 'scrape' on its own to refresh)")
                continue
            scrape(args.data_dir, streams)
        elif stage == "download":
            books = load_catalog(args.data_dir, packs)
            after_each = None
            if args.delete_pdfs:
                tesseract = check_tesseract(args.ocr)
                titles = {key: book.title for key, book in distinct_files(books).items()}
                (args.data_dir / "text").mkdir(parents=True, exist_ok=True)

                def after_each(key: str) -> None:
                    if extract_one(args.data_dir, key, titles[key], tesseract, args.ocr,
                                   args.ocr_dpi, args.workers):
                        (args.data_dir / "pdfs" / f"{key}.pdf").unlink(missing_ok=True)
            download(args.data_dir, books, args.delay, after_each)
        elif stage == "extract":
            extract(args.data_dir, load_catalog(args.data_dir, packs), args.ocr, args.ocr_dpi,
                    args.workers, args.delete_pdfs)
        elif stage == "build":
            build(args.data_dir, load_catalog(args.data_dir, packs), not args.no_embeddings,
                  args.chunk_chars, args.overlap_chars, args.batch_size, args.device)
        elif stage == "upload":
            upload(args.data_dir, args.repo, args.public)


if __name__ == "__main__":
    main()
