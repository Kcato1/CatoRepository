# Data Science Quick Reference Guide

## Daily Workflow Commands

### Environment Management
```powershell
# Activate data science environment
conda activate datasci

# Deactivate environment
conda deactivate

# List all environments
conda env list

# List installed packages
conda list
```

### Jupyter Lab
```powershell
# Start Jupyter Lab
jupyter lab

# Start on specific port
jupyter lab --port 8889

# Start without browser
jupyter lab --no-browser
```

## Common Data Operations

### Loading Data

```python
import pandas as pd
import numpy as np

# CSV
df = pd.read_csv('data.csv')
df = pd.read_csv('data.csv', encoding='utf-8', sep=';')

# Excel
df = pd.read_excel('data.xlsx', sheet_name='Sheet1')

# JSON
df = pd.read_json('data.json')

# SQL
import sqlalchemy as sa
engine = sa.create_engine('postgresql://user:pass@localhost/db')
df = pd.read_sql('SELECT * FROM table', engine)

# Parquet (efficient for large data)
df = pd.read_parquet('data.parquet')
```

### Quick Data Inspection

```python
# Basic info
df.head()              # First 5 rows
df.tail()              # Last 5 rows
df.shape               # (rows, columns)
df.columns             # Column names
df.dtypes              # Data types
df.info()              # Overview
df.describe()          # Summary statistics

# Missing data
df.isnull().sum()      # Count nulls per column
df.isna().sum()        # Same as above
```

### Data Cleaning

```python
# Remove duplicates
df = df.drop_duplicates()

# Handle missing values
df = df.dropna()                    # Remove rows with any NaN
df = df.fillna(0)                   # Fill NaN with 0
df = df.fillna(method='ffill')      # Forward fill
df = df.fillna(df.mean())           # Fill with mean

# Rename columns
df = df.rename(columns={'old': 'new'})

# Change data types
df['col'] = df['col'].astype('int')
df['date'] = pd.to_datetime(df['date'])

# Remove columns
df = df.drop(['col1', 'col2'], axis=1)
```

### Filtering & Selection

```python
# Select columns
df['column']                     # Single column
df[['col1', 'col2']]            # Multiple columns

# Filter rows
df[df['age'] > 30]              # Simple condition
df[(df['age'] > 30) & (df['city'] == 'NYC')]  # Multiple conditions
df[df['name'].isin(['Alice', 'Bob'])]          # Multiple values

# Loc and iloc
df.loc[0]                       # Row by label
df.iloc[0]                      # Row by position
df.loc[0:5, ['name', 'age']]   # Rows and columns by label
df.iloc[0:5, 0:2]              # Rows and columns by position
```

### Grouping & Aggregation

```python
# Group by single column
df.groupby('category').sum()
df.groupby('category').mean()
df.groupby('category').count()

# Group by multiple columns
df.groupby(['category', 'region']).sum()

# Multiple aggregations
df.groupby('category').agg({
    'sales': ['sum', 'mean'],
    'quantity': 'count'
})

# Custom aggregation
df.groupby('category').agg({
    'sales': lambda x: x.sum(),
    'quantity': 'count'
})
```

### Merging & Joining

```python
# Merge (similar to SQL JOIN)
pd.merge(df1, df2, on='key')                    # Inner join
pd.merge(df1, df2, on='key', how='left')        # Left join
pd.merge(df1, df2, on='key', how='right')       # Right join
pd.merge(df1, df2, on='key', how='outer')       # Outer join

# Concatenate
pd.concat([df1, df2])                           # Stack vertically
pd.concat([df1, df2], axis=1)                   # Stack horizontally

# Join on index
df1.join(df2, how='inner')
```

## Visualization Quick Reference

### Matplotlib Basics

```python
import matplotlib.pyplot as plt

# Line plot
plt.plot(x, y)
plt.xlabel('X Label')
plt.ylabel('Y Label')
plt.title('Title')
plt.show()

# Scatter plot
plt.scatter(x, y)
plt.show()

# Bar plot
plt.bar(categories, values)
plt.show()

# Histogram
plt.hist(data, bins=20)
plt.show()

# Subplots
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4))
ax1.plot(x, y1)
ax2.plot(x, y2)
plt.show()
```

### Seaborn Plots

```python
import seaborn as sns

# Set style
sns.set_style('whitegrid')

# Distribution plot
sns.histplot(df['column'])
sns.kdeplot(df['column'])

# Box plot
sns.boxplot(x='category', y='value', data=df)

# Violin plot
sns.violinplot(x='category', y='value', data=df)

# Scatter with regression
sns.regplot(x='x', y='y', data=df)

# Correlation heatmap
sns.heatmap(df.corr(), annot=True, cmap='coolwarm')

# Pair plot
sns.pairplot(df)
```

### Pandas Plotting

```python
# Quick plots from DataFrame
df['column'].plot()                    # Line plot
df['column'].plot.hist()               # Histogram
df['column'].plot.box()                # Box plot
df.plot.scatter(x='col1', y='col2')   # Scatter plot
df.plot.bar(x='category', y='value')  # Bar plot
```

## Machine Learning Quick Reference

### Train-Test Split

```python
from sklearn.model_selection import train_test_split

X = df[['feature1', 'feature2', 'feature3']]
y = df['target']

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)
```

### Preprocessing

```python
from sklearn.preprocessing import StandardScaler, MinMaxScaler

# Standardization (mean=0, std=1)
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# Normalization (min-max scaling)
scaler = MinMaxScaler()
X_scaled = scaler.fit_transform(X_train)

# One-hot encoding
X_encoded = pd.get_dummies(X, columns=['category_col'])
```

### Classification Models

```python
from sklearn.linear_model import LogisticRegression
from sklearn.tree import DecisionTreeClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.svm import SVC

# Logistic Regression
model = LogisticRegression()
model.fit(X_train, y_train)
predictions = model.predict(X_test)

# Random Forest
model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X_train, y_train)
predictions = model.predict(X_test)

# Evaluate
from sklearn.metrics import accuracy_score, classification_report
print(f"Accuracy: {accuracy_score(y_test, predictions)}")
print(classification_report(y_test, predictions))
```

### Regression Models

```python
from sklearn.linear_model import LinearRegression
from sklearn.ensemble import RandomForestRegressor

# Linear Regression
model = LinearRegression()
model.fit(X_train, y_train)
predictions = model.predict(X_test)

# Evaluate
from sklearn.metrics import mean_squared_error, r2_score
print(f"RMSE: {np.sqrt(mean_squared_error(y_test, predictions))}")
print(f"R²: {r2_score(y_test, predictions)}")
```

### Cross-Validation

```python
from sklearn.model_selection import cross_val_score

scores = cross_val_score(model, X, y, cv=5)
print(f"CV Scores: {scores}")
print(f"Mean: {scores.mean()}, Std: {scores.std()}")
```

## SQL Quick Reference

### PostgreSQL Connection

```python
import psycopg2
import pandas as pd

# Connect
conn = psycopg2.connect(
    host="localhost",
    database="mydb",
    user="postgres",
    password="password"
)

# Query to DataFrame
df = pd.read_sql("SELECT * FROM table", conn)

# Execute query
cursor = conn.cursor()
cursor.execute("INSERT INTO table VALUES (%s, %s)", (val1, val2))
conn.commit()

# Close
conn.close()
```

### Common SQL Queries

```sql
-- Select
SELECT * FROM table;
SELECT col1, col2 FROM table WHERE condition;

-- Aggregate
SELECT category, COUNT(*), AVG(value)
FROM table
GROUP BY category
HAVING COUNT(*) > 10;

-- Join
SELECT a.*, b.column
FROM table_a a
JOIN table_b b ON a.id = b.id;

-- Window functions
SELECT 
    category,
    value,
    ROW_NUMBER() OVER (PARTITION BY category ORDER BY value DESC) as rank
FROM table;
```

## PySpark Quick Reference

### Create Spark Session

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("MyApp") \
    .config("spark.driver.memory", "4g") \
    .getOrCreate()
```

### Load Data

```python
# CSV
df = spark.read.csv("data.csv", header=True, inferSchema=True)

# Parquet
df = spark.read.parquet("data.parquet")

# JSON
df = spark.read.json("data.json")
```

### Basic Operations

```python
# Show data
df.show(5)
df.printSchema()

# Select
df.select("col1", "col2").show()

# Filter
df.filter(df["age"] > 30).show()
df.where((df["age"] > 30) & (df["city"] == "NYC")).show()

# Group by
df.groupBy("category").count().show()
df.groupBy("category").agg({"sales": "sum", "quantity": "avg"}).show()

# Sort
df.orderBy("value", ascending=False).show()

# Convert to Pandas (for small datasets)
pandas_df = df.toPandas()
```

## Git Commands for Data Science

```bash
# Initialize repository
git init

# Add files (excluding large data)
git add .

# Commit
git commit -m "Initial analysis"

# Create .gitignore
echo "data/raw/*" >> .gitignore
echo "*.csv" >> .gitignore
echo "*.parquet" >> .gitignore
echo "*.h5" >> .gitignore
echo ".ipynb_checkpoints" >> .gitignore
echo "__pycache__" >> .gitignore

# Create branch
git checkout -b feature/new-analysis

# Push to remote
git remote add origin <url>
git push -u origin main
```

## Conda Package Management

```bash
# Install package
conda install pandas numpy scipy

# Install specific version
conda install pandas=1.5.0

# Install from pip
pip install streamlit

# Update package
conda update pandas

# Remove package
conda remove pandas

# List packages
conda list

# Search package
conda search scikit-learn

# Export environment
conda env export > environment.yml

# Create from file
conda env create -f environment.yml

# Update environment
conda env update -f environment.yml
```

## Performance Tips

### Use Appropriate Tools

```python
# Small data (< 1GB): Pandas
import pandas as pd
df = pd.read_csv('small.csv')

# Medium data (1-10GB): Polars or Dask
import polars as pl
df = pl.read_csv('medium.csv')

import dask.dataframe as dd
df = dd.read_csv('medium.csv')

# Large data (> 10GB): PySpark
from pyspark.sql import SparkSession
spark = SparkSession.builder.getOrCreate()
df = spark.read.csv('large.csv')
```

### Optimize Pandas

```python
# Use efficient data types
df['int_col'] = df['int_col'].astype('int32')
df['category_col'] = df['category_col'].astype('category')

# Read only needed columns
df = pd.read_csv('data.csv', usecols=['col1', 'col2'])

# Read in chunks
for chunk in pd.read_csv('large.csv', chunksize=10000):
    process(chunk)

# Use vectorization
# Bad
result = [x * 2 for x in df['col']]
# Good
result = df['col'] * 2
```

## Jupyter Shortcuts

### Command Mode (press Esc)
- `A` - Insert cell above
- `B` - Insert cell below
- `DD` - Delete cell
- `M` - Change to Markdown
- `Y` - Change to Code
- `Shift + Enter` - Run cell and select below
- `Ctrl + Enter` - Run cell

### Edit Mode (press Enter)
- `Tab` - Code completion
- `Shift + Tab` - Tooltip
- `Ctrl + ]` - Indent
- `Ctrl + [` - Dedent
- `Ctrl + /` - Comment

## Debugging Tips

```python
# Print intermediate values
print(f"Shape: {df.shape}")
print(f"Dtypes:\n{df.dtypes}")

# Use assertions
assert df['age'].min() >= 0, "Age cannot be negative"
assert len(df) > 0, "DataFrame is empty"

# Use breakpoint
import pdb; pdb.set_trace()  # Debugger starts here

# Profile code
%%timeit
# Your code here

# Memory usage
df.memory_usage(deep=True)

# Warning control
import warnings
warnings.filterwarnings('ignore')
```

## Common Error Solutions

### "Memory Error"
- Use chunking: `pd.read_csv('file.csv', chunksize=10000)`
- Use Dask or Polars
- Optimize data types
- Use sampling for exploration

### "KeyError"
- Check column names: `df.columns`
- Use `.get()` for safe access

### "ValueError: could not convert"
- Check data types: `df.dtypes`
- Handle missing values first
- Use `pd.to_numeric(df['col'], errors='coerce')`

### "SettingWithCopyWarning"
- Use `.copy()`: `df_new = df[df['age'] > 30].copy()`
- Use `.loc[]` for assignment

---

**Keep this guide handy for quick reference during your data science work!**
