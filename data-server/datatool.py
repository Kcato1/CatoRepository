"""Tools for the kevin-Mini data server: convert CSV to Parquet, validate files, build a catalog.

    py -m pip install pyarrow
    py data-server\\datatool.py convert C:\\Downloads\\sales.csv --out-dir C:\\DataServer\\public\\data
    py data-server\\datatool.py validate
    py data-server\\datatool.py catalog

Commands default to the data server's folder (C:\\DataServer\\public\\data); pass --data-dir for
another one. Exit code 0 means success, 1 means errors were found or a command failed.
"""

from __future__ import annotations

import argparse
import codecs
import html
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import quote

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.csv as pacsv
import pyarrow.parquet as pq

DEFAULT_DATA_DIR = Path(r"C:\DataServer\public\data")
ROW_GROUP_ROWS = 1_048_576  # upper bound (pyarrow's default)
ROW_GROUP_BYTES = 64 << 20  # in-memory size per row group; caps memory on wide files
BLOCK_SIZE = 4 << 20  # CSV bytes read per batch; also the window pyarrow infers column types from
# Values pyarrow would turn into numbers and change. Any match keeps the whole column as text.
CODE_PATTERNS = {
    "leading zeros": r"^[+-]?0[0-9]",
    "hex values": r"^[+-]?0[xX][0-9a-fA-F]+$",
    "leading +": r"^\+[0-9]",
    "16+ digit numbers": r"^[+-]?[0-9]{16,}(\.[0-9]*)?$",
}
SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")
HIDDEN_NAMES = {"desktop.ini", "thumbs.db"}
SERVED_TYPES = {".csv", ".json", ".ndjson", ".jsonl", ".parquet"}
OTHER_TEXT = {".txt", ".md", ".html", ".htm"}
SPREADSHEETS = {".xlsx", ".xls", ".xlsm", ".ods"}
CATALOG_FILES = ("catalog.json", "catalog.html")
MAX_JSON_PARSE_BYTES = 200 << 20
KIB = 1024


class ToolError(Exception):
    """A problem worth reporting to the user without a traceback."""


@dataclass
class CsvOptions:
    encoding: str = "utf8"
    delimiter: str = ","
    string_columns: set[str] = field(default_factory=set)


@dataclass
class CsvScan:
    names: list[str]
    rows: int
    text_columns: dict[str, str]  # column -> why it must stay text


# ---------------------------------------------------------------- shared helpers


def is_hidden(path: Path) -> bool:
    return path.name.startswith(".") or path.name.lower() in HIDDEN_NAMES


def replace_file(tmp: Path, dest: Path) -> None:
    try:
        os.replace(tmp, dest)
    except PermissionError as exc:
        tmp.unlink(missing_ok=True)
        raise ToolError(f"{dest.name} is in use (probably being downloaded); try again in a moment") from exc


def write_text_atomic(dest: Path, text: str) -> bool:
    """Write text via a hidden temp file; return False if the file already had this content."""
    if dest.exists() and dest.read_text(encoding="utf-8") == text:
        return False
    tmp = dest.with_name(f".{dest.name}.tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    replace_file(tmp, dest)
    return True


def read_options(opts: CsvOptions) -> pacsv.ReadOptions:
    return pacsv.ReadOptions(encoding=opts.encoding, block_size=BLOCK_SIZE)


def parse_options(opts: CsvOptions) -> pacsv.ParseOptions:
    # Quoted cells may contain line breaks; without this, one crossing a block boundary fails.
    return pacsv.ParseOptions(delimiter=opts.delimiter, newlines_in_values=True)


def read_header(path: Path, opts: CsvOptions) -> list[str]:
    try:
        reader = pacsv.open_csv(path, read_options=read_options(opts), parse_options=parse_options(opts))
    except pa.ArrowInvalid as exc:
        raise ToolError(f"{path.name}: {friendly_csv_error(exc, opts)}") from exc
    names = reader.schema.names
    reader.close()
    if len(names) == 1 and opts.delimiter == ",":
        other = next((d for d in (";", "\t", "|") if d in names[0]), None)
        if other:
            flag = "tab" if other == "\t" else repr(other)
            raise ToolError(f"{path.name}: the header looks {flag}-separated; add --delimiter {flag}")
    problems = []
    if any(not n.strip() for n in names):
        problems.append("a column has an empty name")
    dupes = sorted({n for n in names if names.count(n) > 1})
    if dupes:
        problems.append(f"duplicate column names: {', '.join(dupes)}")
    if problems:
        raise ToolError(f"{path.name}: fix the header row first ({'; '.join(problems)})")
    return names


def friendly_csv_error(exc: pa.ArrowInvalid, opts: CsvOptions) -> str:
    text = str(exc)
    if "Empty CSV file" in text:
        return "the file is empty"
    if "invalid UTF8" in text or "UTF8" in text:
        hint = " Try --encoding cp1252 (typical for Excel exports on Windows)." if opts.encoding == "utf8" else ""
        return f"text isn't valid {opts.encoding}.{hint}"
    if "Expected" in text and "columns" in text:
        hint = " If it uses semicolons, add --delimiter ';'." if opts.delimiter == "," else ""
        return f"rows have different numbers of fields ({text.split(':', 1)[-1].strip()[:120]}).{hint}"
    return text[:300]


def scan_csv(path: Path, opts: CsvOptions) -> CsvScan:
    """Read every value as text: counts rows, checks encoding and shape, finds code-like columns."""
    names = read_header(path, opts)
    convert = pacsv.ConvertOptions(column_types={n: pa.string() for n in names}, check_utf8=True)
    rows = 0
    reasons: dict[str, str] = {}
    try:
        reader = pacsv.open_csv(path, read_options=read_options(opts), parse_options=parse_options(opts),
                                convert_options=convert)
        for batch in reader:
            rows += batch.num_rows
            for name, column in zip(names, batch.columns, strict=True):
                if name not in reasons:
                    reason = code_like(column)
                    if reason:
                        reasons[name] = reason
    except pa.ArrowInvalid as exc:
        raise ToolError(f"{path.name}: {friendly_csv_error(exc, opts)}") from exc
    return CsvScan(names, rows, {n: reasons[n] for n in names if n in reasons})


def code_like(column: pa.Array) -> str | None:
    for reason, pattern in CODE_PATTERNS.items():
        if pc.any(pc.match_substring_regex(column, pattern)).as_py():
            return reason
    return None


def describe_text_columns(text_columns: dict[str, str]) -> str:
    return ", ".join(f"{name} ({why})" for name, why in text_columns.items())


# ---------------------------------------------------------------- convert


def output_path(src: Path, out_dir: Path | None) -> Path:
    return (out_dir or src.parent) / f"{src.stem}.parquet"


def column_name_from_error(text: str, names: list[str]) -> str | None:
    m = re.search(r"CSV column #(\d+)", text)
    if m and int(m.group(1)) < len(names):
        return names[int(m.group(1))]
    return None


def write_parquet(src: Path, tmp: Path, scan: CsvScan, opts: CsvOptions) -> None:
    as_text = set(scan.text_columns) | opts.string_columns
    convert = pacsv.ConvertOptions(column_types={n: pa.string() for n in as_text}, check_utf8=True)
    writer = None
    pending: list[pa.RecordBatch] = []
    group_rows = ROW_GROUP_ROWS
    try:
        reader = pacsv.open_csv(src, read_options=read_options(opts), parse_options=parse_options(opts),
                                convert_options=convert)
        writer = pq.ParquetWriter(tmp, reader.schema, compression="zstd", write_statistics=True)
        wrote_any = False
        for batch in reader:
            if batch.num_rows == 0:  # nothing to write, and group_rows must never be sized from it
                continue
            batch = blanks_to_null(batch)
            group_rows = min(group_rows, rows_per_group(batch))  # shrinks if later rows are wider
            pending.append(batch)
            if sum(b.num_rows for b in pending) >= group_rows:
                pending = write_full_groups(writer, pa.Table.from_batches(pending), group_rows)
                wrote_any = True
        rest = pa.Table.from_batches(pending, schema=reader.schema)
        if rest.num_rows or not wrote_any:  # an empty write still records the schema (header-only CSV)
            writer.write_table(rest, row_group_size=group_rows)
    except pa.ArrowInvalid as exc:
        column = column_name_from_error(str(exc), scan.names)
        if column:
            raise ToolError(
                f"{src.name}: column '{column}' looked numeric in the first rows but has text later "
                f"({str(exc).split(':')[-1].strip()[:80]}). Re-run with --string-columns {column}") from exc
        raise ToolError(f"{src.name}: {friendly_csv_error(exc, opts)}") from exc
    finally:
        if writer is not None:
            writer.close()


def rows_per_group(batch: pa.RecordBatch) -> int:
    """Rows per row group: ROW_GROUP_BYTES of data, at most ROW_GROUP_ROWS (0 until rows arrive)."""
    if batch.num_rows == 0:
        return 0
    bytes_per_row = max(batch.nbytes / batch.num_rows, 1)
    return max(1, min(ROW_GROUP_ROWS, int(ROW_GROUP_BYTES / bytes_per_row)))


def blanks_to_null(batch: pa.RecordBatch) -> pa.RecordBatch:
    """Blank text cells become missing values, matching how numeric columns treat blanks."""
    columns = [
        pc.if_else(pc.equal(col, ""), pa.scalar(None, pa.string()), col) if pa.types.is_string(col.type) else col
        for col in batch.columns
    ]
    return pa.RecordBatch.from_arrays(columns, schema=batch.schema)


def write_full_groups(writer: pq.ParquetWriter, table: pa.Table, group_rows: int) -> list[pa.RecordBatch]:
    """Write row groups of exactly group_rows rows; return what's left over for the next write."""
    while table.num_rows >= group_rows:
        writer.write_table(table.slice(0, group_rows), row_group_size=group_rows)
        table = table.slice(group_rows)
    return table.to_batches()


def verify_parquet(tmp: Path, scan: CsvScan) -> pq.FileMetaData:
    meta = pq.ParquetFile(tmp).metadata
    names = meta.schema.to_arrow_schema().names
    if meta.num_rows != scan.rows or names != scan.names:
        raise ToolError(f"check failed: wrote {meta.num_rows} rows / {len(names)} columns, "
                        f"expected {scan.rows} rows / {len(scan.names)} columns")
    return meta


def convert_one(src: Path, out_dir: Path | None, opts: CsvOptions, force: bool) -> Path:
    if src.suffix.lower() != ".csv":
        raise ToolError(f"{src.name}: only .csv files can be converted")
    if not src.is_file():
        raise ToolError(f"{src}: file not found")
    dest = output_path(src, out_dir)
    if dest.exists() and not force:
        raise ToolError(f"{dest.name} already exists; add --force to replace it")
    scan = scan_csv(src, opts)
    missing = opts.string_columns - set(scan.names)
    if missing:
        raise ToolError(f"{src.name}: --string-columns names not in the file: {', '.join(sorted(missing))}")
    tmp = dest.with_name(f".{dest.name}.tmp")
    try:
        write_parquet(src, tmp, scan, opts)
        meta = verify_parquet(tmp, scan)
        replace_file(tmp, dest)
    finally:
        tmp.unlink(missing_ok=True)
    kept = f"; kept as text: {describe_text_columns(scan.text_columns)}" if scan.text_columns else ""
    print(f"OK    {src.name} -> {dest}  ({meta.num_rows:,} rows, {meta.num_columns} columns, "
          f"{dest.stat().st_size / src.stat().st_size:.0%} of CSV size{kept})")
    return dest


def cmd_convert(args: argparse.Namespace) -> int:
    opts = CsvOptions(args.encoding, args.delimiter,
                      {c.strip() for c in args.string_columns.split(",") if c.strip()} if args.string_columns else set())
    if args.out_dir:
        args.out_dir.mkdir(parents=True, exist_ok=True)
    failures = 0
    for src in args.files:
        try:
            convert_one(src, args.out_dir, opts, args.force)
        except (ToolError, OSError) as exc:  # one locked or unreadable file shouldn't stop the rest
            failures += 1
            print(f"ERROR {exc}", file=sys.stderr)
    return 1 if failures else 0


# ---------------------------------------------------------------- validate


@dataclass
class Finding:
    level: str  # ERROR, WARN, NOTE
    path: str
    message: str


def check_name(rel: str, path: Path) -> list[Finding]:
    if SAFE_NAME.match(path.name):
        return []
    return [Finding("WARN", rel, "name has spaces or special characters; rename to letters, digits, - _ . "
                                 "so URLs and code snippets work")]


def check_parquet(rel: str, path: Path) -> list[Finding]:
    try:
        meta = pq.ParquetFile(path).metadata
    except (pa.ArrowInvalid, OSError) as exc:
        return [Finding("ERROR", rel, f"not a readable Parquet file ({str(exc)[:120]})")]
    return [Finding("NOTE", rel, f"{meta.num_rows:,} rows, {meta.num_columns} columns, {meta.num_row_groups} row groups")]


def check_csv(rel: str, path: Path) -> list[Finding]:
    try:
        scan = scan_csv(path, CsvOptions())
    except ToolError as exc:
        return [Finding("ERROR", rel, str(exc).split(": ", 1)[-1])]
    found = [Finding("NOTE", rel, f"{scan.rows:,} rows, {len(scan.names)} columns")]
    if scan.text_columns:
        found.append(Finding("NOTE", rel, "code-like values in " + describe_text_columns(scan.text_columns) +
                             "; convert keeps these as text, but pandas/DuckDB may read the CSV as numbers"))
    if path.stat().st_size > 50 << 20:
        found.append(Finding("NOTE", rel, "large CSV; converting to Parquet makes it smaller and faster to query"))
    return found


def reject_constant(name: str) -> None:
    raise ValueError(f"{name} isn't valid JSON (browsers' JSON.parse rejects it)")


def check_json(rel: str, path: Path) -> list[Finding]:
    if path.stat().st_size > MAX_JSON_PARSE_BYTES:
        return [Finding("NOTE", rel, "too large to check here; consider NDJSON or Parquet")]
    try:
        with path.open(encoding="utf-8-sig") as fh:  # Notepad/PowerShell 5 add a BOM
            json.load(fh, parse_constant=reject_constant)
    except ValueError as exc:  # also covers UnicodeDecodeError and JSONDecodeError
        return [Finding("ERROR", rel, f"not valid UTF-8 JSON ({exc})"[:200])]
    return []


def check_ndjson(rel: str, path: Path) -> list[Finding]:
    try:
        with path.open(encoding="utf-8-sig") as fh:  # Notepad/PowerShell 5 add a BOM
            for number, line in enumerate(fh, 1):
                if not line.strip():
                    continue
                try:
                    json.loads(line, parse_constant=reject_constant)
                except json.JSONDecodeError as exc:
                    return [Finding("ERROR", rel, f"invalid JSON on line {number} ({exc.msg})")]
                except ValueError as exc:
                    return [Finding("ERROR", rel, f"invalid JSON on line {number} ({exc})")]
    except UnicodeDecodeError:
        return [Finding("ERROR", rel, "not valid UTF-8")]
    return []


CHECKS = {".parquet": check_parquet, ".csv": check_csv, ".json": check_json,
          ".ndjson": check_ndjson, ".jsonl": check_ndjson}


def validate_file(data_dir: Path, path: Path) -> list[Finding]:
    rel = path.relative_to(data_dir).as_posix()
    if path.name.endswith(".tmp") and path.name.startswith("."):
        return [Finding("WARN", rel, "leftover temp file from an interrupted run; safe to delete")]
    if is_hidden(path):
        return [Finding("NOTE", rel, "hidden file; the server won't serve it")]
    ext = path.suffix.lower()
    found = check_name(rel, path)
    if ext in SPREADSHEETS:
        found.append(Finding("WARN", rel, "spreadsheet files can't be queried over HTTP; export to CSV or Parquet"))
    elif ext in CHECKS:
        try:
            found.extend(CHECKS[ext](rel, path))
        except OSError as exc:  # locked by another program, or no permission
            found.append(Finding("ERROR", rel, f"can't read the file ({exc.strerror or exc})"))
    elif ext not in OTHER_TEXT:
        found.append(Finding("NOTE", rel, "served as a plain download"))
    return found


def iter_files(data_dir: Path):
    for path in sorted(data_dir.rglob("*")):
        if path.is_file() and not any(is_hidden(p) for p in path.relative_to(data_dir).parents if p.name):
            yield path


def cmd_validate(args: argparse.Namespace) -> int:
    findings = [f for path in iter_files(args.data_dir) for f in validate_file(args.data_dir, path)]
    for f in findings:
        print(f"{f.level:<5} {f.path}: {f.message}")
    errors = sum(f.level == "ERROR" for f in findings)
    warnings = sum(f.level == "WARN" for f in findings)
    print(f"\n{errors} error(s), {warnings} warning(s) in {args.data_dir}")
    return 1 if errors else 0


# ---------------------------------------------------------------- catalog


def basic_entry(data_dir: Path, path: Path) -> dict:
    rel = path.relative_to(data_dir).as_posix()
    return {"path": rel, "url": "/data/" + quote(rel), "format": path.suffix.lower().lstrip("."),
            "bytes": path.stat().st_size}


def describe(data_dir: Path, path: Path, scan_csvs: bool) -> dict:
    entry = basic_entry(data_dir, path)
    if entry["format"] == "parquet":
        meta = pq.ParquetFile(path).metadata
        entry["rows"] = meta.num_rows
        entry["columns"] = [{"name": f.name, "type": str(f.type)} for f in meta.schema.to_arrow_schema()]
    elif entry["format"] == "csv":
        if scan_csvs:
            scan = scan_csv(path, CsvOptions())
            entry["rows"] = scan.rows
            entry["columns"] = [{"name": n} for n in scan.names]
        else:
            entry["columns"] = [{"name": n} for n in read_header(path, CsvOptions())]
    return entry


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < KIB or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= KIB
    return f"{n} B"


def render_html(entries: list[dict]) -> str:
    rows = []
    for e in entries:
        cols = e.get("columns", [])
        col_list = "".join(f"<li><code>{html.escape(c['name'])}</code>"
                           f"{' ' + html.escape(c['type']) if 'type' in c else ''}</li>" for c in cols)
        details = f"<details><summary>{len(cols)} columns</summary><ul>{col_list}</ul></details>" if cols else ""
        if "error" in e:
            details += f'<div class="err">Can\'t read: {html.escape(e["error"])}</div>'
        row_count = f"{e['rows']:,}" if "rows" in e else "&ndash;"
        rows.append(
            f"<tr><td><a href=\"{html.escape(e['url'])}\">{html.escape(e['path'])}</a>{details}</td>"
            f"<td>{html.escape(e['format'])}</td><td class=\"n\">{human_size(e['bytes'])}</td>"
            f"<td class=\"n\">{row_count}</td></tr>")
    body = "\n".join(rows) or '<tr><td colspan="4">No datasets yet.</td></tr>'
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>kevin-Mini dataset catalog</title>
<style>
  :root {{ --fg: #1d2330; --muted: #5b6475; --bg: #f7f7f5; --card: #fff; --line: #e3e3de; --accent: #2457c5; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --fg: #e6e8ee; --muted: #9aa3b5; --bg: #15171c; --card: #1d2027; --line: #2c303a; --accent: #7aa2ff; }}
  }}
  body {{ margin: 0; font: 15px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; color: var(--fg); background: var(--bg); }}
  main {{ max-width: 900px; margin: 0 auto; padding: 40px 20px 60px; }}
  h1 {{ font-size: 24px; margin: 0 0 4px; }}
  p {{ color: var(--muted); margin: 0 0 20px; }}
  a {{ color: var(--accent); }}
  .wrap {{ overflow-x: auto; background: var(--card); border: 1px solid var(--line); border-radius: 10px; }}
  table {{ border-collapse: collapse; width: 100%; }}
  th, td {{ text-align: left; padding: 9px 12px; border-bottom: 1px solid var(--line); vertical-align: top; }}
  th {{ font-weight: 600; color: var(--muted); font-size: 13px; }}
  .n {{ text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }}
  details {{ margin-top: 4px; color: var(--muted); font-size: 13px; }}
  .err {{ margin-top: 4px; color: #b3261e; font-size: 13px; }}
  ul {{ margin: 4px 0 0; padding-left: 18px; }}
  code {{ font-family: ui-monospace, "Cascadia Code", Consolas, monospace; }}
</style>
</head>
<body>
<main>
  <h1>Dataset catalog</h1>
  <p><a href="/">&larr; Data server home</a> &middot; also available as <a href="/catalog.json">catalog.json</a></p>
  <div class="wrap"><table>
    <thead><tr><th>Dataset</th><th>Format</th><th class="n">Size</th><th class="n">Rows</th></tr></thead>
    <tbody>
{body}
    </tbody>
  </table></div>
</main>
</body>
</html>
"""


def cmd_catalog(args: argparse.Namespace) -> int:
    out_dir = args.out_dir or args.data_dir.parent
    entries, failures = [], 0
    for path in iter_files(args.data_dir):
        if is_hidden(path) or path.suffix.lower() not in SERVED_TYPES or path.name in CATALOG_FILES:
            continue
        try:
            entries.append(describe(args.data_dir, path, args.scan_csv))
        except (ToolError, pa.ArrowInvalid, OSError) as exc:
            failures += 1
            message = str(exc).removeprefix(f"{path.name}: ")
            print(f"ERROR {path.name}: {message}", file=sys.stderr)
            # Still listed: the server serves it either way. Run validate for details.
            entries.append(basic_entry(args.data_dir, path) | {"error": message})
    doc = json.dumps({"datasets": entries}, indent=2, ensure_ascii=False) + "\n"
    for name, text in (("catalog.json", doc), ("catalog.html", render_html(entries))):
        changed = write_text_atomic(out_dir / name, text)
        print(f"{'Wrote' if changed else 'Unchanged'}: {out_dir / name}")
    print(f"{len(entries)} dataset(s)")
    return 1 if failures else 0


# ---------------------------------------------------------------- CLI


def delimiter_arg(value: str) -> str:
    value = {"tab": "\t", "\\t": "\t"}.get(value.lower(), value)
    if len(value) != 1:
        raise argparse.ArgumentTypeError("use a single character, or 'tab'")
    return value


def encoding_arg(value: str) -> str:
    try:
        codecs.lookup(value)
    except LookupError as exc:
        raise argparse.ArgumentTypeError(f"unknown encoding '{value}' (try cp1252 or utf8)") from exc
    return value


def existing_dir(value: str) -> Path:
    path = Path(value)
    if not path.is_dir():
        raise argparse.ArgumentTypeError(f"folder not found: {value}")
    return path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Tools for the kevin-Mini data server.")
    sub = parser.add_subparsers(dest="command", required=True)

    def add_data_dir(p: argparse.ArgumentParser) -> None:
        p.add_argument("--data-dir", type=existing_dir,
                       default=DEFAULT_DATA_DIR if DEFAULT_DATA_DIR.is_dir() else None,
                       required=not DEFAULT_DATA_DIR.is_dir(),
                       help=f"folder the server publishes (default {DEFAULT_DATA_DIR})")

    conv = sub.add_parser("convert", help="convert CSV files to Parquet")
    conv.add_argument("files", nargs="+", type=Path, help="CSV files to convert")
    conv.add_argument("--out-dir", type=Path, help="where to write the .parquet files (default: next to each CSV)")
    conv.add_argument("--force", action="store_true", help="replace existing .parquet files")
    conv.add_argument("--encoding", default="utf8", type=encoding_arg,
                      help="text encoding of the CSV, e.g. cp1252 (default utf8)")
    conv.add_argument("--delimiter", default=",", type=delimiter_arg, help="field separator: one character or 'tab' (default ,)")
    conv.add_argument("--string-columns", help="comma-separated columns to keep as text")
    conv.set_defaults(func=cmd_convert)

    val = sub.add_parser("validate", help="check files before publishing them")
    add_data_dir(val)
    val.set_defaults(func=cmd_validate)

    cat = sub.add_parser("catalog", help="write catalog.json and catalog.html for the data folder")
    add_data_dir(cat)
    cat.add_argument("--out-dir", type=existing_dir, help="where to write the catalog (default: the data folder's parent)")
    cat.add_argument("--scan-csv", action="store_true", help="also count CSV rows (reads every CSV in full)")
    cat.set_defaults(func=cmd_catalog)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except ToolError as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
