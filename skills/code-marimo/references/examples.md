# Marimo Extended Examples

## Contents

- [Interactive Data Filter](#interactive-data-filter)
- [Data Explorer](#data-explorer)
- [SQL Analysis (SQL-First Pattern)](#sql-analysis-sql-first-pattern)

## Interactive Data Filter

```python
@app.cell
def imports():
    import marimo as mo
    import polars as pl
    import altair as alt
    return mo, pl, alt

@app.cell
def constants():
    IRIS_URL = "hf://datasets/scikit-learn/iris/Iris.csv"
    return (IRIS_URL,)

@app.cell
def defaults():
    DEFAULT_SPECIES = "All"
    return (DEFAULT_SPECIES,)

@app.cell
def load_data(mo, IRIS_URL):
    iris = mo.sql(f"""
        SELECT * FROM '{IRIS_URL}'
    """)
    return (iris,)

@app.cell
def species_dropdown(mo, iris, DEFAULT_SPECIES):
    species = mo.ui.dropdown(
        options=["All"] + iris["Species"].unique().sort().to_list(),
        value=DEFAULT_SPECIES,
        label="Species"
    )
    species
    return (species,)

@app.cell
def scatter_plot(pl, alt, iris, species):
    filtered = iris if species.value == "All" else iris.filter(pl.col("Species") == species.value)
    alt.Chart(filtered).mark_circle().encode(
        x="SepalLengthCm",
        y="SepalWidthCm",
        color="Species"
    )
    return (filtered,)
```

## Data Explorer

```python
@app.cell
def imports():
    import marimo as mo
    import polars as pl
    from vega_datasets import data
    return mo, pl, data

@app.cell
def explore_cars(mo, pl, data):
    cars = pl.DataFrame(data.cars())
    mo.ui.data_explorer(cars)
    return (cars,)
```

## SQL Analysis (SQL-First Pattern)

```python
@app.cell
def imports():
    import marimo as mo
    import altair as alt
    return mo, alt

@app.cell
def constants():
    WEATHER_URL = "https://raw.githubusercontent.com/vega/vega-datasets/refs/heads/main/data/weather.csv"
    LOCATION = "Seattle"
    return WEATHER_URL, LOCATION

@app.cell
def load_weather(mo, WEATHER_URL, LOCATION):
    seattle = mo.sql(f"""
        SELECT * FROM '{WEATHER_URL}'
        WHERE location = '{LOCATION}'
        ORDER BY date
    """)
    return (seattle,)

@app.cell
def aggregate_monthly(mo, seattle):
    monthly_avg = mo.sql(f"""
        SELECT date_trunc('month', date) as month,
               avg(temp_max) as avg_high,
               avg(temp_min) as avg_low
        FROM seattle
        GROUP BY 1
        ORDER BY 1
    """)
    return (monthly_avg,)

@app.cell
def visualize(alt, monthly_avg):
    alt.Chart(monthly_avg).mark_line().encode(x="month", y="avg_high")
    return
```
