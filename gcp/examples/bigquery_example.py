"""Query BigQuery into pandas and write a DataFrame back to a table.

python bigquery_example.py --project my-project
python bigquery_example.py --project my-project --dataset analytics --write
"""

import argparse

import pandas as pd
from google.cloud import bigquery


def top_names(client: bigquery.Client, state: str, limit: int = 10) -> pd.DataFrame:
    query = """
        SELECT name, SUM(number) AS total
        FROM `bigquery-public-data.usa_names.usa_1910_current`
        WHERE state = @state
        GROUP BY name
        ORDER BY total DESC
        LIMIT @limit
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("state", "STRING", state),
            bigquery.ScalarQueryParameter("limit", "INT64", limit),
        ]
    )
    job = client.query(query, job_config=job_config)
    df = job.to_dataframe()
    print(f"Scanned {job.total_bytes_processed / 1e6:.1f} MB")
    return df


def write_dataframe(client: bigquery.Client, df: pd.DataFrame, table_id: str) -> None:
    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_TRUNCATE")
    client.load_table_from_dataframe(df, table_id, job_config=job_config).result()
    print(f"Wrote {len(df)} rows to {table_id}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--state", default="TX")
    parser.add_argument("--dataset", default="sandbox")
    parser.add_argument("--location", default="US")
    parser.add_argument("--write", action="store_true", help="Also write results to <dataset>.top_names")
    args = parser.parse_args()

    client = bigquery.Client(project=args.project)
    df = top_names(client, args.state)
    print(df)

    if args.write:
        dataset = bigquery.Dataset(f"{args.project}.{args.dataset}")
        dataset.location = args.location
        client.create_dataset(dataset, exists_ok=True)
        write_dataframe(client, df, f"{args.project}.{args.dataset}.top_names")


if __name__ == "__main__":
    main()
