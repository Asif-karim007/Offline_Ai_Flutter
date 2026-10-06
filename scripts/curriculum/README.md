# NCTB curriculum packs

`nctb_pipeline.py` downloads the textbooks NCTB publishes at nctb.gov.bd, reads their text
(with OCR — most NCTB PDFs contain no real text, only drawn letters), splits it into chunks,
computes search embeddings, and uploads the result to Hugging Face as one small SQLite file per
class and version. The phone app later downloads only the pack a student needs.

```
nctb.gov.bd ─► scrape ─► download ─► extract (OCR) ─► build (embeddings) ─► upload to Hugging Face
               catalog     PDFs        text per page     data/packs/*.db
```

This folder is self-contained: copy `scripts/curriculum/` to any Windows, macOS or Linux
computer and run it there.

## What the computer needs

| | |
|---|---|
| Disk | **~6 GB free** in the default space-saving mode (each PDF is deleted once its text is read). ~20 GB if you keep the PDFs. |
| Time | Many hours — mostly OCR of ~40,000 pages. More CPU cores = faster. Leave it running overnight and keep the computer from sleeping. |
| Internet | ~10–15 GB of downloads in total. |
| Python | 3.11 or newer (3.12 recommended) |
| Tesseract OCR | With **Bengali** language data — install below |

## 1. One-time setup

**Windows**
1. Install Python from https://www.python.org/downloads/ — tick **"Add python.exe to PATH"**.
2. Install Tesseract from https://github.com/UB-Mannheim/tesseract/wiki. In the installer, open
   **"Additional language data (download)"** and tick **Bengali**.

**macOS**
```sh
brew install python@3.12 tesseract tesseract-lang
```

**Ubuntu / Debian Linux**
```sh
sudo apt install python3 python3-venv tesseract-ocr tesseract-ocr-ben
```

## 2. Run

Open a terminal (Windows: Command Prompt) in this folder.

**First, a quick test with one pack** (class 3, Bangla version — 9 books, about 30–60 min):

```
Windows:        run.bat --packs general_class-3_bn --no-upload
macOS / Linux:  ./run.sh --packs general_class-3_bn --no-upload
```

The first run installs the Python packages (~1 GB including PyTorch). Then look at the result:
open `data/extract_report.csv` (every book should have pages under `ocr` and few `unusable`).

**Then everything:**

```
Windows:        run.bat
macOS / Linux:  ./run.sh
```

It asks for your Hugging Face token once at the start (paste the **Write** token from
huggingface.co/settings/tokens — the terminal hides it as you paste, that is normal), then runs
to the end and uploads to **huggingface.co/datasets/Asifkarim/nctb-curriculum-packs** as a
*private* dataset.

**If it stops** — the computer slept, the internet dropped, Google Drive said "too many
downloads" — just run the same command again. Finished books are never repeated.

## Options

Add these after `run.bat` / `./run.sh`:

| Option | Effect |
|---|---|
| `--packs general_class-9-10_bn,general_class-9-10_en` | Only these packs (names are listed by the first stage) |
| `--streams general,hsc,madrasa,technical` | Also include madrasa (ইবতেদায়ি/দাখিল) and technical (কারিগরি) books. Delete `data/catalog.json` first so the book list is rebuilt. |
| `--no-upload` | Stop after building; upload later with `run.bat upload` / `./run.sh upload` |
| `--public` | Create the Hugging Face dataset public (default is private) |
| `--workers 4` | OCR processes in parallel (default: CPU cores − 1). Lower it if the computer is too slow to use meanwhile. |
| `--no-embeddings` | Skip PyTorch / embeddings; the app then falls back to keyword search only |

The run scripts always add `--delete-pdfs`. To keep the PDFs, run the Python script directly:
`python nctb_pipeline.py all` (inside the `.venv` environment).

## Output (`data/`)

| Path | What |
|---|---|
| `catalog.json` | Every book found: pack, class, version, title, download links |
| `text/` | Extracted text per book, page by page |
| `extract_report.csv` | Per book: pages from the text layer, pages OCR'd, pages unusable. Opens in Excel. |
| `packs/` | **What gets uploaded**: `<pack>.db`, `manifest.json`, `README.md` (dataset card) |

Check quality before making the dataset public: open a pack with any SQLite viewer (e.g. DB
Browser for SQLite) and read some rows of the `chunks` table. If the Bangla is garbled there, the
app's answers will be too.

## Pack format

```sql
meta   (key, value)              -- pack_id, class, version, embedding_model, ...
books  (id, title, file_key, page_count, source_url)
chunks (id, book_id, chapter, page_start, page_end, text, embedding)
```

`embedding` is 384 × float32 little-endian, L2-normalised, from `intfloat/multilingual-e5-small`
on `"passage: " + text`. The app must embed questions as `"query: " + question` with the same
model (the catalog's `multilingual-e5-small` GGUF) and normalise them, so cosine similarity is a
plain dot product.

The app finds packs through
`https://huggingface.co/datasets/Asifkarim/nctb-curriculum-packs/resolve/main/manifest.json`
(and each `<pack>.db` at the same path), once the dataset is public.

## Updating for a new academic year

Update `LEVEL_PAGES` and `ACADEMIC_YEAR` at the top of `nctb_pipeline.py` from nctb.gov.bd →
পাঠ্যপুস্তক → "<year> শিক্ষাবর্ষের সকল স্তরের পাঠ্যপুস্তক", then run with a fresh
`--data-dir`.

## Permission

The textbook content belongs to NCTB. Get NCTB's permission before making the dataset public
or shipping packs in an app.
