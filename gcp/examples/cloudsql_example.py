"""Connect to Cloud SQL for PostgreSQL with the Cloud SQL Python Connector.

The password comes from Secret Manager (--password-secret) or the DB_PASSWORD env var,
never from source code.

python cloudsql_example.py --instance my-project:us-central1:datasci-db --db analytics \
    --password-secret projects/my-project/secrets/db-password/versions/latest
"""

import argparse
import os

import pandas as pd
import sqlalchemy
from google.cloud import secretmanager
from google.cloud.sql.connector import Connector


def get_password(secret_name: str | None) -> str:
    if secret_name:
        client = secretmanager.SecretManagerServiceClient()
        return client.access_secret_version(name=secret_name).payload.data.decode()
    password = os.environ.get("DB_PASSWORD")
    if not password:
        raise SystemExit("Set --password-secret or the DB_PASSWORD environment variable")
    return password


def make_engine(instance: str, user: str, password: str, db: str) -> tuple[sqlalchemy.Engine, Connector]:
    connector = Connector()

    def getconn():
        return connector.connect(instance, "pg8000", user=user, password=password, db=db)

    engine = sqlalchemy.create_engine("postgresql+pg8000://", creator=getconn)
    return engine, connector


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--instance", required=True, help="PROJECT:REGION:INSTANCE")
    parser.add_argument("--db", default="postgres")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password-secret", help="Secret Manager version resource name")
    parser.add_argument("--query", default="SELECT table_schema, table_name FROM information_schema.tables "
                                           "WHERE table_schema NOT IN ('pg_catalog', 'information_schema')")
    args = parser.parse_args()

    engine, connector = make_engine(args.instance, args.user, get_password(args.password_secret), args.db)
    try:
        with engine.connect() as conn:
            df = pd.read_sql(sqlalchemy.text(args.query), conn)
        print(df)
    finally:
        connector.close()


if __name__ == "__main__":
    main()
