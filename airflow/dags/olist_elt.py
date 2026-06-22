"""Olist ELT — the one DAG that orchestrates the whole pipeline (Phase 7, L5).

Flow:  dlt_load_olist  ->  dbt_transform (Cosmos)  ->  dbt_docs_generate
                                   \\------------------------/  ->  notify_failure (on any failure)

Design notes (see DECISIONS.md ADR-017):
  * dlt stays the loader; Airflow only orchestrates (ADR-003). The load task runs the
    EXISTING dlt/load_olist.py unchanged, via the isolated dlt_venv interpreter.
  * dbt runs through astronomer-cosmos, which expands the dbt project into one Airflow
    task per model/test/seed (model-level lineage in the Airflow UI), executed by the
    isolated dbt_venv dbt binary.
  * Snowflake credentials come from two Airflow Connections (least privilege, ADR-012):
    loader writes RAW, transformer cannot. No creds are hardcoded in the DAG.
  * schedule=None: the Olist source is a static historical dump, so the DAG is
    trigger-on-demand. It demonstrates orchestration, not response to arriving data.
"""
from __future__ import annotations

from datetime import timedelta

import pendulum
from airflow.sdk import DAG
from airflow.providers.standard.operators.python import PythonOperator

from cosmos import (
    DbtTaskGroup,
    ProjectConfig,
    ProfileConfig,
    ExecutionConfig,
    RenderConfig,
)
from cosmos.constants import LoadMode
from cosmos.profiles import SnowflakePrivateKeyPemProfileMapping
from cosmos.operators.local import DbtDocsLocalOperator

# --- In-container paths (provided by docker-compose.override.yml mounts + Dockerfile venvs) ---
DBT_PROJECT_DIR = "/usr/local/airflow/dbt"
DBT_MANIFEST = "/usr/local/airflow/dbt/target/manifest.json"
DBT_EXECUTABLE = "/usr/local/airflow/dbt_venv/bin/dbt"
DLT_PYTHON = "/usr/local/airflow/dlt_venv/bin/python"
DLT_DIR = "/usr/local/airflow/dlt"

LOADER_CONN_ID = "snowflake_olist_loader"
TRANSFORMER_CONN_ID = "snowflake_olist_transformer"


# ---------------------------------------------------------------------------
# dlt load task — runs load_olist.py in the dlt_venv with credentials taken
# from the loader Airflow Connection (mapped onto dlt's env-var config keys).
# Both seed passes run (pass 1 = reference tables + pre-2018 history + FX,
# pass 2 = the 2018 batch) so a trigger reproduces the full RAW load idempotently.
# ---------------------------------------------------------------------------
def _run_dlt_load() -> None:
    import os
    import subprocess

    try:
        from airflow.sdk import BaseHook  # Airflow 3
    except ImportError:  # pragma: no cover
        from airflow.hooks.base import BaseHook

    conn = BaseHook.get_connection(LOADER_CONN_ID)
    extra = conn.extra_dejson

    env = dict(os.environ)
    env.update(
        {
            "DESTINATION__SNOWFLAKE__CREDENTIALS__HOST": extra["account"],
            "DESTINATION__SNOWFLAKE__CREDENTIALS__DATABASE": extra["database"],
            "DESTINATION__SNOWFLAKE__CREDENTIALS__USERNAME": conn.login,
            "DESTINATION__SNOWFLAKE__CREDENTIALS__WAREHOUSE": extra["warehouse"],
            "DESTINATION__SNOWFLAKE__CREDENTIALS__ROLE": extra["role"],
            "DESTINATION__SNOWFLAKE__CREDENTIALS__PRIVATE_KEY_PATH": extra["private_key_file"],
        }
    )

    for pass_num in ("1", "2"):
        print(f"--- dlt load pass {pass_num} ---", flush=True)
        subprocess.run(
            [DLT_PYTHON, "load_olist.py", pass_num],
            cwd=DLT_DIR,
            env=env,
            check=True,
        )


def _notify_failure(**context) -> None:
    """Failure branch: fires (trigger_rule=one_failed) if any upstream task fails.
    A real deployment would page Slack/email here; locally we log a loud, clear line."""
    print(
        "ALERT: Olist ELT pipeline FAILED — "
        f"dag={context.get('dag').dag_id if context.get('dag') else 'olist_elt'} "
        f"run_id={context.get('run_id')}. Check the failed task's logs.",
        flush=True,
    )


# ---------------------------------------------------------------------------
# Cosmos config — render the dbt project from the manifest (fast parse, no
# Snowflake access at DAG-parse time) and execute with the dbt_venv binary.
# Credentials come from the transformer Connection via the PEM profile mapping.
# profile_name MUST equal dbt_project.yml's `profile:` (olist_dbt).
# ---------------------------------------------------------------------------
profile_config = ProfileConfig(
    profile_name="olist_dbt",
    target_name="dev",
    profile_mapping=SnowflakePrivateKeyPemProfileMapping(
        conn_id=TRANSFORMER_CONN_ID,
        profile_args={
            "database": "OLIST",
            "schema": "STAGING",
            "warehouse": "OLIST_WH",
            "role": "OLIST_TRANSFORMER",
            "threads": 4,
        },
    ),
)

project_config = ProjectConfig(
    dbt_project_path=DBT_PROJECT_DIR,
    manifest_path=DBT_MANIFEST,
)

execution_config = ExecutionConfig(dbt_executable_path=DBT_EXECUTABLE)

render_config = RenderConfig(load_method=LoadMode.DBT_MANIFEST)


with DAG(
    dag_id="olist_elt",
    description="Olist ELT: dlt load -> dbt (Cosmos) transform/test -> docs.",
    schedule=None,                       # static dump -> trigger on demand
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=5)},
    tags=["olist", "elt", "dlt", "dbt", "cosmos"],
) as dag:

    dlt_load_olist = PythonOperator(
        task_id="dlt_load_olist",
        python_callable=_run_dlt_load,
    )

    dbt_transform = DbtTaskGroup(
        group_id="dbt_transform",
        project_config=project_config,
        profile_config=profile_config,
        execution_config=execution_config,
        render_config=render_config,
        operator_args={"install_deps": False},  # dbt_packages already present in the mount
    )

    dbt_docs_generate = DbtDocsLocalOperator(
        task_id="dbt_docs_generate",
        project_dir=DBT_PROJECT_DIR,
        profile_config=profile_config,
        dbt_executable_path=DBT_EXECUTABLE,
        install_deps=False,
    )

    notify_failure = PythonOperator(
        task_id="notify_failure",
        python_callable=_notify_failure,
        trigger_rule="one_failed",
    )

    dlt_load_olist >> dbt_transform >> dbt_docs_generate
    [dlt_load_olist, dbt_transform, dbt_docs_generate] >> notify_failure
