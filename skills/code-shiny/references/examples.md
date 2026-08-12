# Shiny for Python Examples

## Contents

- [Reactive Filter with Extended Task](#reactive-filter-with-extended-task)
- [Module Pattern (Core Mode)](#module-pattern-core-mode)
- [Polling External Data](#polling-external-data)

## Reactive Filter with Extended Task

```python
import asyncio

import pandas as pd
from shiny import App, reactive, render, req, ui

app_ui = ui.page_fluid(
    ui.input_numeric("threshold", "Min value:", value=0),
    ui.input_action_button("run", "Run analysis"),
    ui.output_text("status"),
    ui.output_data_frame("results"),
)


def server(input, output, session):
    @reactive.extended_task
    async def load_data(threshold: float) -> pd.DataFrame:
        await asyncio.sleep(2)
        return pd.DataFrame({"value": range(20)})[lambda df: df["value"] > threshold]

    @reactive.effect
    @reactive.event(input.run)
    def trigger():
        load_data(input.threshold())

    @render.text
    def status():
        if load_data.status() == "running":
            return "Loading..."
        return "Ready"

    @render.data_frame
    def results():
        req(load_data.result())
        return load_data.result()


app = App(app_ui, server)
```

## Module Pattern (Core Mode)

```python
import pandas as pd
from shiny import App, module, reactive, render, req, ui


@module.ui
def filter_ui():
    return ui.TagList(
        ui.input_select("species", "Species:", choices=[]),
        ui.output_text("count"),
    )


@module.server
def filter_server(input, output, session, *, data: reactive.Value):
    @reactive.effect
    def sync_choices():
        req(data())
        ui.update_select("species", choices=data()["species"].unique().tolist())

    @render.text
    def count():
        req(data(), input.species())
        filtered = data()[data()["species"] == input.species()]
        return f"{len(filtered)} records"


app_ui = ui.page_fluid(filter_ui("filter1"))


def server(input, output, session):
    df = reactive.value(pd.read_csv("iris.csv"))
    filter_server("filter1", data=df)


app = App(app_ui, server)
```

## Polling External Data

```python
import sqlite3

import pandas as pd
from shiny import App, reactive, render, ui

app_ui = ui.page_fluid(ui.output_data_frame("latest"))


def server(input, output, session):
    conn = sqlite3.connect("data.db")
    session.on_ended(lambda: conn.close())

    def check_timestamp():
        return conn.execute("SELECT max(updated_at) FROM events").fetchone()[0]

    @reactive.poll(check_timestamp, interval_secs=5)
    def events():
        return pd.read_sql("SELECT * FROM events ORDER BY updated_at DESC LIMIT 50", conn)

    @render.data_frame
    def latest():
        return events()


app = App(app_ui, server)
```
