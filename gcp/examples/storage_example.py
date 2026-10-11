"""Move files between local disk and Cloud Storage, and read CSV/Parquet straight from gs://.

python storage_example.py --bucket my-bucket upload data/sales.csv raw/sales.csv
python storage_example.py --bucket my-bucket download raw/sales.csv sales.csv
python storage_example.py --bucket my-bucket list --prefix raw/
python storage_example.py --bucket my-bucket read raw/sales.csv
"""

import argparse

import pandas as pd
from google.cloud import storage


def upload(bucket: storage.Bucket, local_path: str, blob_name: str) -> None:
    bucket.blob(blob_name).upload_from_filename(local_path)
    print(f"Uploaded {local_path} -> gs://{bucket.name}/{blob_name}")


def download(bucket: storage.Bucket, blob_name: str, local_path: str) -> None:
    bucket.blob(blob_name).download_to_filename(local_path)
    print(f"Downloaded gs://{bucket.name}/{blob_name} -> {local_path}")


def list_blobs(bucket: storage.Bucket, prefix: str) -> None:
    for blob in bucket.list_blobs(prefix=prefix):
        print(f"{blob.size:>12,}  {blob.name}")


def read(bucket_name: str, blob_name: str) -> pd.DataFrame:
    # pandas reads gs:// paths directly via gcsfs
    path = f"gs://{bucket_name}/{blob_name}"
    if blob_name.endswith(".parquet"):
        return pd.read_parquet(path)
    return pd.read_csv(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--project")
    sub = parser.add_subparsers(dest="command", required=True)

    up = sub.add_parser("upload")
    up.add_argument("local_path")
    up.add_argument("blob_name")

    down = sub.add_parser("download")
    down.add_argument("blob_name")
    down.add_argument("local_path")

    ls = sub.add_parser("list")
    ls.add_argument("--prefix", default="")

    rd = sub.add_parser("read")
    rd.add_argument("blob_name")

    args = parser.parse_args()
    bucket = storage.Client(project=args.project).bucket(args.bucket)

    if args.command == "upload":
        upload(bucket, args.local_path, args.blob_name)
    elif args.command == "download":
        download(bucket, args.blob_name, args.local_path)
    elif args.command == "list":
        list_blobs(bucket, args.prefix)
    elif args.command == "read":
        print(read(args.bucket, args.blob_name).head())


if __name__ == "__main__":
    main()
