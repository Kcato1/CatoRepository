# GCP Data Science Guide

Running Python + SQL data work on Google Cloud: a Compute Engine VM you control, a managed Vertex AI Workbench notebook, Python examples for BigQuery / Cloud Storage / Cloud SQL, and a plan for moving your local setup over.

## Contents

1. [One-time GCP setup](#1-one-time-gcp-setup)
2. [Option A: Compute Engine VM](#2-option-a-compute-engine-vm)
3. [Option B: Vertex AI Workbench](#3-option-b-vertex-ai-workbench)
4. [Python examples](#4-python-examples)
5. [Migrating from local to GCP](#5-migrating-from-local-to-gcp)
6. [Keeping costs down](#6-keeping-costs-down)

---

## 1. One-time GCP setup

Install the gcloud CLI on your Windows PC (or use [Cloud Shell](https://shell.cloud.google.com), which has everything preinstalled):

```powershell
winget install Google.CloudSDK
```

Then, in a new terminal:

```bash
gcloud auth login                         # your Google account
gcloud auth application-default login     # credentials for Python libraries on your PC
gcloud projects create my-datasci-proj    # or use an existing project
gcloud config set project my-datasci-proj
```

Link a billing account in the console (Billing → Link a billing account) and set a **budget alert** before you create anything (Billing → Budgets & alerts).

---

## 2. Option A: Compute Engine VM

Full control, same workflow as a local Linux box. Two scripts:

| Script | Where to run | What it does |
|---|---|---|
| `gcp/create-vm.sh` | Your PC (Git Bash) or Cloud Shell | Enables APIs, adds an IAP-only SSH firewall rule, creates an Ubuntu 24.04 VM, copies the setup files over |
| `gcp/setup-gcp-datasci.sh` | On the VM | Installs Python venv, Jupyter, pandas/sklearn/etc., GCP client libraries, dbt-bigquery, optional TensorFlow/PyTorch |

### Create and set up

```bash
# From the repo root
bash gcp/create-vm.sh my-datasci-proj                                  # defaults: datasci-vm, us-central1-a, e2-standard-4
bash gcp/create-vm.sh my-datasci-proj datasci-vm us-central1-a e2-standard-8

# SSH in and run setup (~10 min, or ~5 min with --skip-ml)
gcloud compute ssh datasci-vm --zone us-central1-a --tunnel-through-iap
bash ~/gcp-setup/setup-gcp-datasci.sh
```

### Use Jupyter

Jupyter listens on the VM's localhost only. You reach it through an SSH tunnel, so no port is opened to the internet.

```bash
# On the VM
~/start-jupyter.sh

# On your PC, in a second terminal
gcloud compute ssh datasci-vm --zone us-central1-a --tunnel-through-iap -- -L 8888:localhost:8888
```

Open the `http://localhost:8888/?token=...` URL that Jupyter printed.

**VS Code alternative:** install the *Remote - SSH* extension, run `gcloud compute config-ssh` once, then connect to `datasci-vm.us-central1-a.my-datasci-proj`.

### Credentials on the VM

The VM uses its attached service account automatically, so `bigquery.Client()` and `storage.Client()` work without any login. The default compute service account has broad Editor rights; for anything beyond personal use, create a dedicated service account with only the roles you need (`roles/bigquery.user`, `roles/storage.objectAdmin`, `roles/cloudsql.client`, `roles/secretmanager.secretAccessor`) and pass `--service-account` to `gcloud compute instances create`.

---

## 3. Option B: Vertex AI Workbench

A managed JupyterLab VM with Python, pandas, BigQuery, and Cloud Storage integration preinstalled. No setup script needed.

### Create an instance

```bash
gcloud services enable notebooks.googleapis.com aiplatform.googleapis.com

gcloud workbench instances create datasci-notebook \
    --location=us-central1-a \
    --machine-type=e2-standard-4 \
    --metadata=idle-timeout-seconds=10800      # auto-shutdown after 3 idle hours
```

Or use the console: **Vertex AI → Workbench → Instances → Create new**.

### Open it

Console → **Vertex AI → Workbench → Instances → Open JupyterLab**. Access goes through your Google login, with no tunnel or token needed.

### Useful features

- **BigQuery in notebooks:** `%%bigquery df` cell magic runs SQL and returns a DataFrame:
  ```python
  %load_ext google.cloud.bigquery
  ```
  ```sql
  %%bigquery df
  SELECT name, SUM(number) AS total
  FROM `bigquery-public-data.usa_names.usa_1910_current`
  GROUP BY name ORDER BY total DESC LIMIT 10
  ```
- **Git:** the left sidebar has a Git panel. Clone this repo directly.
- **Extra packages:** `pip install --user <package>` in a notebook terminal.
- **GPU:** add `--accelerator-type=NVIDIA_TESLA_T4 --accelerator-core-count=1` at creation (needs GPU quota in the region).

### Manage

```bash
gcloud workbench instances stop  datasci-notebook --location=us-central1-a
gcloud workbench instances start datasci-notebook --location=us-central1-a
gcloud workbench instances list  --location=us-central1-a
```

### VM or Workbench?

| | Compute Engine VM | Vertex AI Workbench |
|---|---|---|
| Setup | Scripts in this folder | None |
| Jupyter access | SSH tunnel | Browser with Google login |
| Idle shutdown | Manual (or a cron job) | Built in |
| Customization | Anything | Mostly pip/conda packages |
| Good for | dbt, scheduled scripts, services, VS Code Remote | Interactive analysis and ML |

Many people use both: Workbench for exploration, a small VM (or Cloud Run jobs) for scheduled pipelines.

---

## 4. Python examples

All in `gcp/examples/`. They take settings as arguments and read secrets from Secret Manager or env vars, never from code. The VM setup copies them to `~/DataScience/scripts/gcp-examples/`.

| File | Shows |
|---|---|
| `bigquery_example.py` | Parameterized query to a DataFrame, writing a DataFrame back to a table |
| `bigquery_ml_example.py` | Train, evaluate, and predict with BigQuery ML in SQL |
| `storage_example.py` | Upload, download, and list objects; read `gs://` CSV/Parquet straight into pandas |
| `cloudsql_example.py` | Connect to Cloud SQL Postgres via the Cloud SQL connector, password from Secret Manager |

```bash
python bigquery_example.py --project my-datasci-proj
python bigquery_example.py --project my-datasci-proj --dataset sandbox --write
python bigquery_ml_example.py --project my-datasci-proj

gcloud storage buckets create gs://my-datasci-proj-data --location=us-central1
python storage_example.py --bucket my-datasci-proj-data upload sales.csv raw/sales.csv
python storage_example.py --bucket my-datasci-proj-data read raw/sales.csv

python cloudsql_example.py --instance my-datasci-proj:us-central1:datasci-db --db analytics \
    --password-secret projects/my-datasci-proj/secrets/db-password/versions/latest
```

### Quick patterns

```python
# BigQuery -> pandas in one line (pandas-gbq)
import pandas_gbq
df = pandas_gbq.read_gbq("SELECT * FROM `my-datasci-proj.sandbox.top_names`", project_id="my-datasci-proj")

# pandas -> BigQuery
pandas_gbq.to_gbq(df, "sandbox.my_table", project_id="my-datasci-proj", if_exists="replace")

# Cloud Storage paths work anywhere pandas takes a path (gcsfs)
df = pd.read_parquet("gs://my-datasci-proj-data/curated/sales.parquet")
df.to_csv("gs://my-datasci-proj-data/exports/sales.csv", index=False)
```

### dbt with BigQuery

`dbt-bigquery` is installed on the VM. A minimal `~/.dbt/profiles.yml` using the VM's credentials:

```yaml
my_project:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: my-datasci-proj
      dataset: dbt_dev
      location: US
      threads: 4
```

---

## 5. Migrating from local to GCP

How the Windows setup in this repo maps to GCP:

| Local (setup-data-science.ps1) | GCP equivalent |
|---|---|
| Anaconda + Jupyter Lab | Vertex AI Workbench, or the VM + `setup-gcp-datasci.sh` |
| PostgreSQL (local) | Cloud SQL for PostgreSQL, or BigQuery for analytics |
| MongoDB (local) | Firestore, or MongoDB Atlas on GCP |
| `datasets/` folder | Cloud Storage bucket |
| PySpark (local) | Dataproc Serverless, or BigQuery SQL |
| Apache Airflow | Cloud Composer (managed Airflow), or Cloud Scheduler + Cloud Run jobs for simple schedules |
| Power BI Desktop | Looker Studio (free); Power BI also connects to BigQuery |
| Azure CLI / AWS CLI | gcloud, bq, gsutil |
| Docker Desktop | Artifact Registry + Cloud Run |

### Step 1: Move files to Cloud Storage

```bash
gcloud storage buckets create gs://my-datasci-proj-data --location=us-central1
gcloud storage cp -r "C:/Users/<you>/DataScience/datasets" gs://my-datasci-proj-data/datasets
gcloud storage rsync -r "C:/Users/<you>/DataScience/datasets" gs://my-datasci-proj-data/datasets   # later syncs
```

### Step 2: Load analytic data into BigQuery

```bash
bq mk --location=US analytics
bq load --autodetect --source_format=CSV analytics.sales gs://my-datasci-proj-data/datasets/sales.csv
bq load --source_format=PARQUET analytics.events "gs://my-datasci-proj-data/datasets/events/*.parquet"
```

### Step 3: Move PostgreSQL to Cloud SQL (if you need a transactional database)

```bash
# Create the instance
gcloud sql instances create datasci-db \
    --database-version=POSTGRES_16 --edition=ENTERPRISE \
    --tier=db-g1-small --region=us-central1
gcloud sql databases create analytics --instance=datasci-db

# Store the password in Secret Manager and set it on the instance
read -rs DB_PASSWORD
printf '%s' "$DB_PASSWORD" | gcloud secrets create db-password --data-file=-
gcloud sql users set-password postgres --instance=datasci-db --password="$DB_PASSWORD"

# Dump locally, upload, import
pg_dump -U postgres -d mydata --no-owner --no-acl -f mydata.sql
gcloud storage cp mydata.sql gs://my-datasci-proj-data/sql/mydata.sql
SA=$(gcloud sql instances describe datasci-db --format='value(serviceAccountEmailAddress)')
gcloud storage buckets add-iam-policy-binding gs://my-datasci-proj-data \
    --member="serviceAccount:$SA" --role=roles/storage.objectViewer
gcloud sql import sql datasci-db gs://my-datasci-proj-data/sql/mydata.sql --database=analytics
```

For large or live databases, use **Database Migration Service** (console → Database Migration) for continuous replication with minimal downtime.

### Step 4: Update your code

| Before | After |
|---|---|
| `pd.read_csv("C:/.../datasets/sales.csv")` | `pd.read_csv("gs://my-datasci-proj-data/datasets/sales.csv")` |
| `psycopg2.connect(host="localhost", ...)` | Cloud SQL connector (`cloudsql_example.py`) |
| Heavy pandas groupbys on big files | Push the work into BigQuery SQL, pull back the result |
| Passwords in scripts / `.env` | Secret Manager |

### Step 5: Move notebooks

Commit notebooks to Git and clone in Workbench or on the VM, or copy them:

```bash
gcloud storage cp -r "C:/Users/<you>/DataScience/notebooks" gs://my-datasci-proj-data/notebooks
# On the VM / Workbench terminal:
gcloud storage cp -r gs://my-datasci-proj-data/notebooks ~/DataScience/
```

### Step 6: Scheduled jobs

- Simple Python script on a schedule: package it as a **Cloud Run job** and trigger it with **Cloud Scheduler**.
- SQL-only transforms: **BigQuery scheduled queries** or dbt.
- Multi-step DAGs you already have in Airflow: **Cloud Composer**.

### Migration checklist

- [ ] Project created, billing linked, budget alert set
- [ ] gcloud installed and authenticated on your PC
- [ ] Workbench instance or VM created
- [ ] Datasets copied to Cloud Storage
- [ ] Analytic tables loaded into BigQuery
- [ ] PostgreSQL migrated to Cloud SQL (if needed)
- [ ] Code updated to `gs://` paths, connector, Secret Manager
- [ ] Notebooks moved
- [ ] Scheduled jobs recreated
- [ ] Local copies kept until everything is verified in GCP

---

## 6. Keeping costs down

- **Stop VMs and Workbench instances when idle.** You only pay for disk while they're stopped. Workbench's `idle-timeout-seconds` does this automatically.
- **Use Spot VMs** for interruptible batch work: add `--provisioning-model=SPOT` to `gcloud compute instances create`.
- **Check BigQuery bytes before running a query:** `bq query --dry_run --use_legacy_sql=false '...'`. Select only the columns you need, and partition big tables by date.
- **Cloud SQL bills while running.** Stop it when unused: `gcloud sql instances patch datasci-db --activation-policy=NEVER`.
- **Set lifecycle rules** on buckets to move old data to cheaper storage classes.
- Estimate first with the [GCP Pricing Calculator](https://cloud.google.com/products/calculator).
