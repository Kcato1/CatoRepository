"""Tests for datatool.py. Run: python -m pytest data-server/tests"""

import json
import sys
from pathlib import Path

import pyarrow.parquet as pq
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import datatool  # noqa: E402


def write(path: Path, text: str, encoding: str = "utf-8") -> Path:
    path.write_bytes(text.encode(encoding))
    return path


def run(*argv: str) -> int:
    return datatool.main(list(argv))


# ---------------------------------------------------------------- convert


def test_convert_round_trip(tmp_path):
    src = write(tmp_path / "sales.csv", "id,region,amount\n1,north,10.5\n2,south,3.25\n")
    assert run("convert", str(src)) == 0
    table = pq.read_table(tmp_path / "sales.parquet")
    assert table.num_rows == 2
    assert table.column_names == ["id", "region", "amount"]
    assert table.column("amount").to_pylist() == [10.5, 3.25]
    assert src.exists(), "source CSV must be left in place"
    assert not list(tmp_path.glob(".*.tmp")), "no temp files left behind"


def test_leading_zeros_kept_as_text(tmp_path):
    src = write(tmp_path / "zips.csv", "zip,count\n00123,1\n02134,2\n90210,3\n")
    assert run("convert", str(src)) == 0
    table = pq.read_table(tmp_path / "zips.parquet")
    assert table.schema.field("zip").type == "string"
    assert table.column("zip").to_pylist() == ["00123", "02134", "90210"]
    assert table.schema.field("count").type == "int64"


def test_late_text_in_numeric_column_names_column(tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(datatool, "BLOCK_SIZE", 1 << 16)  # types are inferred from the first block only
    rows = "".join(f"{i},{i}\n" for i in range(300_000))
    src = write(tmp_path / "late.csv", "id,val\n" + rows + "300000,abc\n")
    assert run("convert", str(src)) == 1
    err = capsys.readouterr().err
    assert "'val'" in err and "--string-columns val" in err
    assert not (tmp_path / "late.parquet").exists()
    assert not list(tmp_path.glob(".*.tmp"))
    assert run("convert", str(src), "--string-columns", "val") == 0
    assert pq.read_table(tmp_path / "late.parquet").column("val")[-1].as_py() == "abc"


def test_cp1252_detected_and_converted_with_flag(tmp_path, capsys):
    src = write(tmp_path / "excel.csv", "name,city\nJosé,Zürich\n", encoding="cp1252")
    assert run("convert", str(src)) == 1
    assert "--encoding cp1252" in capsys.readouterr().err
    assert run("convert", str(src), "--encoding", "cp1252") == 0
    assert pq.read_table(tmp_path / "excel.parquet").column("city").to_pylist() == ["Zürich"]


def test_bom_stripped_from_header(tmp_path):
    src = write(tmp_path / "bom.csv", "﻿name,x\na,1\n")
    assert run("convert", str(src)) == 0
    assert pq.read_table(tmp_path / "bom.parquet").column_names == ["name", "x"]


def test_semicolon_hint_and_delimiter(tmp_path, capsys):
    src = write(tmp_path / "semi.csv", "a;b\n1;2\n3;4\n")
    assert run("convert", str(src)) == 1, "must not silently produce one column named 'a;b'"
    assert "--delimiter ';'" in capsys.readouterr().err
    assert not (tmp_path / "semi.parquet").exists()
    ok = write(tmp_path / "semi_ok.csv", "a;b\n1;2\n3;4\n")
    assert run("convert", str(ok), "--delimiter", ";") == 0
    assert pq.read_table(tmp_path / "semi_ok.parquet").column_names == ["a", "b"]


def test_refuses_to_overwrite_without_force(tmp_path, capsys):
    src = write(tmp_path / "d.csv", "a\n1\n")
    assert run("convert", str(src)) == 0
    before = (tmp_path / "d.parquet").stat().st_mtime_ns
    assert run("convert", str(src)) == 1
    assert "--force" in capsys.readouterr().err
    assert (tmp_path / "d.parquet").stat().st_mtime_ns == before
    assert run("convert", str(src), "--force") == 0


def test_bad_headers_rejected(tmp_path, capsys):
    dup = write(tmp_path / "dup.csv", "a,a\n1,2\n")
    empty_name = write(tmp_path / "blank.csv", "a,\n1,2\n")
    assert run("convert", str(dup), str(empty_name)) == 1
    err = capsys.readouterr().err
    assert "duplicate column names: a" in err and "empty name" in err


def test_empty_and_header_only(tmp_path, capsys):
    empty = write(tmp_path / "empty.csv", "")
    assert run("convert", str(empty)) == 1
    assert "empty" in capsys.readouterr().err
    header = write(tmp_path / "header.csv", "a,b\n")
    assert run("convert", str(header)) == 0
    meta = pq.ParquetFile(tmp_path / "header.parquet").metadata
    assert meta.num_rows == 0 and meta.num_columns == 2


def test_row_groups_are_batched(tmp_path, monkeypatch):
    monkeypatch.setattr(datatool, "ROW_GROUP_ROWS", 50_000)
    monkeypatch.setattr(datatool, "BLOCK_SIZE", 1 << 14)  # many small batches
    src = write(tmp_path / "big.csv", "a,b\n" + "".join(f"{i},{i * 2}\n" for i in range(120_000)))
    assert run("convert", str(src)) == 0
    meta = pq.ParquetFile(tmp_path / "big.parquet").metadata
    assert meta.num_rows == 120_000
    sizes = [meta.row_group(i).num_rows for i in range(meta.num_row_groups)]
    assert sizes == [50_000, 50_000, 20_000], f"small batches must be grouped into full row groups, got {sizes}"
    assert meta.row_group(0).column(0).compression == "ZSTD"
    assert meta.row_group(0).column(0).statistics is not None


def test_ragged_rows_rejected(tmp_path, capsys):
    src = write(tmp_path / "ragged.csv", "a,b\n1,2\n3,4,5\n")
    assert run("convert", str(src)) == 1
    assert "different numbers of fields" in capsys.readouterr().err


def test_unknown_string_column_rejected(tmp_path, capsys):
    src = write(tmp_path / "s.csv", "a\n1\n")
    assert run("convert", str(src), "--string-columns", "nope") == 1
    assert "nope" in capsys.readouterr().err


# ---------------------------------------------------------------- validate


def make_data_dir(tmp_path: Path) -> Path:
    data = tmp_path / "public" / "data"
    data.mkdir(parents=True)
    write(data / "good.csv", "zip,v\n00501,1\n")
    write(data / "ragged.csv", "a,b\n1,2\n3\n")
    write(data / "bad.json", "{not json")
    write(data / "events.ndjson", '{"a": 1}\n{"a": 2\n')
    write(data / "my file.csv", "a\n1\n")
    write(data / ".secret", "x")
    write(data / ".half.parquet.tmp", "x")
    write(data / "report.xlsx", "x")
    write(data / "broken.parquet", "not parquet")
    return data


def test_validate_reports_each_problem(tmp_path, capsys):
    data = make_data_dir(tmp_path)
    assert run("validate", "--data-dir", str(data)) == 1
    out = capsys.readouterr().out
    expectations = {
        "ragged.csv": "different numbers of fields",
        "bad.json": "not valid UTF-8 JSON",
        "events.ndjson": "line 2",
        "my file.csv": "spaces or special characters",
        ".secret": "won't serve",
        ".half.parquet.tmp": "leftover temp file",
        "report.xlsx": "export to CSV or Parquet",
        "broken.parquet": "not a readable Parquet file",
        "good.csv": "leading zeros in zip",
    }
    for name, text in expectations.items():
        line = next((ln for ln in out.splitlines() if f" {name}:" in ln and text in ln), None)
        assert line, f"expected '{text}' for {name} in:\n{out}"
    assert "4 error(s)" in out


def test_validate_clean_folder_passes(tmp_path):
    data = tmp_path / "data"
    data.mkdir()
    write(data / "ok.csv", "a,b\n1,2\n")
    assert run("validate", "--data-dir", str(data)) == 0


# ---------------------------------------------------------------- catalog


def test_catalog_contents_escaping_and_stability(tmp_path, capsys):
    data = tmp_path / "public" / "data"
    (data / "sub").mkdir(parents=True)
    write(data / "sales.csv", "id,amount\n1,2\n")
    assert run("convert", str(data / "sales.csv")) == 0
    write(data / "sub" / "a&b <x>.csv", "q\n1\n")
    write(data / ".hidden.csv", "a\n1\n")
    write(data / "notes.txt", "hi")
    assert run("catalog", "--data-dir", str(data)) == 0

    doc = json.loads((tmp_path / "public" / "catalog.json").read_text(encoding="utf-8"))
    paths = [d["path"] for d in doc["datasets"]]
    assert paths == ["sales.csv", "sales.parquet", "sub/a&b <x>.csv"]
    parquet = next(d for d in doc["datasets"] if d["format"] == "parquet")
    assert parquet["rows"] == 1 and parquet["columns"][0] == {"name": "id", "type": "int64"}
    assert "rows" not in next(d for d in doc["datasets"] if d["path"] == "sales.csv")
    odd = next(d for d in doc["datasets"] if d["path"].startswith("sub/"))
    assert odd["url"] == "/data/sub/a%26b%20%3Cx%3E.csv"

    page = (tmp_path / "public" / "catalog.html").read_text(encoding="utf-8")
    assert "a&amp;b &lt;x&gt;.csv" in page and "<x>" not in page

    capsys.readouterr()
    assert run("catalog", "--data-dir", str(data)) == 0
    assert capsys.readouterr().out.count("Unchanged") == 2, "re-run with no changes must not rewrite files"


def test_catalog_scan_csv_counts_rows(tmp_path):
    data = tmp_path / "public" / "data"
    data.mkdir(parents=True)
    write(data / "t.csv", "a\n1\n2\n3\n")
    assert run("catalog", "--data-dir", str(data), "--scan-csv") == 0
    doc = json.loads((tmp_path / "public" / "catalog.json").read_text(encoding="utf-8"))
    assert doc["datasets"][0]["rows"] == 3


@pytest.mark.parametrize("command", ["validate", "catalog"])
def test_missing_data_dir_is_a_usage_error(tmp_path, command):
    with pytest.raises(SystemExit) as exc:
        run(command, "--data-dir", str(tmp_path / "nope"))
    assert exc.value.code == 2
