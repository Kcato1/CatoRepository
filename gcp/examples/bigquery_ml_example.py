"""Train and evaluate a model inside BigQuery with SQL (BigQuery ML) — no data leaves BigQuery.

Uses the public penguins dataset; creates <dataset>.penguin_classifier in your project.

python bigquery_ml_example.py --project my-project
"""

import argparse

from google.cloud import bigquery

SOURCE = "`bigquery-public-data.ml_datasets.penguins`"
FEATURES = "island, culmen_length_mm, culmen_depth_mm, flipper_length_mm, body_mass_g, sex"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--dataset", default="sandbox")
    parser.add_argument("--location", default="US")
    args = parser.parse_args()

    client = bigquery.Client(project=args.project)
    dataset = bigquery.Dataset(f"{args.project}.{args.dataset}")
    dataset.location = args.location
    client.create_dataset(dataset, exists_ok=True)
    model = f"`{args.project}.{args.dataset}.penguin_classifier`"

    print("Training (takes a minute or two)...")
    client.query(f"""
        CREATE OR REPLACE MODEL {model}
        OPTIONS (model_type = 'logistic_reg', input_label_cols = ['species'],
                 data_split_method = 'AUTO_SPLIT')
        AS SELECT species, {FEATURES}
        FROM {SOURCE}
        WHERE body_mass_g IS NOT NULL
    """).result()

    print("\nEvaluation:")
    print(client.query(f"SELECT * FROM ML.EVALUATE(MODEL {model})").to_dataframe().T)

    print("\nSample predictions:")
    preds = client.query(f"""
        SELECT species, predicted_species
        FROM ML.PREDICT(MODEL {model},
             (SELECT species, {FEATURES} FROM {SOURCE} WHERE body_mass_g IS NOT NULL LIMIT 10))
    """).to_dataframe()
    print(preds)


if __name__ == "__main__":
    main()
