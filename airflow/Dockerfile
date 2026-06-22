# Astro Runtime 3.2-5 == Apache Airflow 3.x. The Airflow environment stays lean;
# dbt and dlt each live in their own isolated virtualenv (see below) so their
# dependencies never clash with Airflow's. This is Astronomer's recommended
# pattern for running dbt via Cosmos, and it is recorded in DECISIONS.md ADR-017.
FROM astrocrpublic.azurecr.io/runtime:3.2-5

# --- dbt in an isolated virtualenv -------------------------------------------
# dbt-core's pins (jinja2, protobuf, etc.) conflict with Airflow's. Cosmos invokes
# this dbt binary as a subprocess via ExecutionConfig(dbt_executable_path=...);
# dbt is never imported into the Airflow Python process.
# Lands at /usr/local/airflow/dbt_venv (WORKDIR is /usr/local/airflow).
RUN python -m venv dbt_venv && \
    dbt_venv/bin/pip install --no-cache-dir dbt-snowflake==1.11.5

# --- dlt in its own isolated virtualenv --------------------------------------
# pandas 3.0 / pyarrow are heavy and version-sensitive; keep them out of Airflow.
# The dlt_load_olist task runs load_olist.py with this interpreter.
# Lands at /usr/local/airflow/dlt_venv.
RUN python -m venv dlt_venv && \
    dlt_venv/bin/pip install --no-cache-dir \
        "dlt[snowflake,parquet]==1.28.0" pandas==3.0.3 requests==2.34.2
