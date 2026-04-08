#!/bin/bash

# source lib/pyenv.sh
source "$PROJECT_ROOT/lib/pyenv.sh"
export GITHUB_REPO


ensure_pipeline_tables() {
    sqlite3 "$DB_FILE" <<EOF

-- =====================================================
-- 1️⃣ Repository Runs (Experiment-Level)
-- =====================================================
CREATE TABLE IF NOT EXISTS repository_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    repository_id INTEGER NOT NULL,
    url TEXT,

    run_status TEXT NOT NULL,
    error_message TEXT,

    started_at TEXT,
    finished_at TEXT,
    duration_seconds FLOAT,

    created_at TEXT DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (repository_id) REFERENCES repositories(id)
);


-- =====================================================
-- 2️⃣ Notebook Executions (Raw Execution Results)
-- =====================================================
CREATE TABLE IF NOT EXISTS notebook_executions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    repository_run_id INTEGER NOT NULL,
    repository_id INTEGER NOT NULL,
    notebook_id INTEGER NOT NULL,

    notebook_name TEXT,
    url TEXT,

    execution_status TEXT,
    execution_duration FLOAT,

    total_code_cells INTEGER,
    executed_cells INTEGER,

    error_type TEXT,
    error_category TEXT,
    error_message TEXT,
    error_cell_index INTEGER,
    error_count INTEGER,

    created_at TEXT DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(repository_run_id, notebook_id),

    FOREIGN KEY (repository_run_id) REFERENCES repository_runs(id),
    FOREIGN KEY (repository_id) REFERENCES repositories(id),
    FOREIGN KEY (notebook_id) REFERENCES notebooks(id)
);


-- =====================================================
-- 3️⃣ Notebook Reproducibility Metrics (Comparison Layer)
-- =====================================================
CREATE TABLE IF NOT EXISTS notebook_reproducibility_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    repository_run_id INTEGER NOT NULL,
    notebook_execution_id INTEGER NOT NULL,

    repository_id INTEGER NOT NULL,
    notebook_id INTEGER NOT NULL,

    total_code_cells INTEGER,

    identical_cells_count INTEGER,
    different_cells_count INTEGER,
    nondeterministic_cells_count INTEGER,

    identical_cells TEXT,
    different_cells TEXT,
    nondeterministic_cells TEXT,

    reproducibility_score REAL,

    created_at TEXT DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(repository_run_id, notebook_id),

    FOREIGN KEY (repository_run_id) REFERENCES repository_runs(id),
    FOREIGN KEY (notebook_execution_id) REFERENCES notebook_executions(id),
    FOREIGN KEY (repository_id) REFERENCES repositories(id),
    FOREIGN KEY (notebook_id) REFERENCES notebooks(id)
);

EOF
}

create_repository_run() {
    local repo_id="$1"
    local repo_url="$2"

    RUN_ID=$(sqlite3 "$DB_FILE" <<EOF
INSERT INTO repository_runs (
    repository_id,
    url,
    run_status,
    started_at
) VALUES (
    $repo_id,
    '$repo_url',
    'RUNNING',
    datetime('now')
);
SELECT last_insert_rowid();
EOF
)

    export RUN_ID
}

finalize_repository_run() {
    log 'Updating repository_runs database table'
    local run_id="$1"
    local status="$2"
    local message="$3"
    local duration="$4"

    log "Run id: $run_id, Status : $status, Message: $message, Duration: $duration"

    sqlite3 "$DB_FILE" <<EOF
UPDATE repository_runs
SET
    run_status = '$status',
    error_message = '$message',
    finished_at = datetime('now'),
    duration_seconds = $duration
WHERE id = $run_id;
EOF
}

get_notebook_language_stats() {
    local repo_id="$1"

    sqlite3 "$DB_FILE" <<EOF
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN LOWER(language) = 'python' THEN 1 ELSE 0 END) AS python_count
FROM notebooks
WHERE repository_id = $repo_id;
EOF
}

# Move repository to repositories folder
move_repo() {
    if [ -d "$REPO_NAME" ]; then
        log "[REPO] Moving repository '$REPO_NAME' to 'repositories' folder"
        rm -rf "$REPOS_DIR/$REPO_NAME"
        mv "$REPO_NAME" "$REPOS_DIR/"
    else
        log "[ERROR] Repository '$REPO_NAME' does not exist. Cannot move."
    fi
}

# Process the given repository
process_repo() {
    REPO_START_TIME=$(now_sec)

    GITHUB_REPO="$1"
    NOTEBOOK_PATHS="$2"
    SETUP_PATHS="$3"
    REQUIREMENT_PATHS="$4"

    REPO_NAME=$(basename "$GITHUB_REPO" .git)

    log "[REPO] Repository: $REPO_NAME"

    LOG_FILE="${LOG_DIR}/${REPO_NAME}.log"
    > "$LOG_FILE"
    export LOG_FILE

    create_repository_run "$REPO_ID" "$GITHUB_REPO"

    if ! validate_repo "$GITHUB_REPO"; then
        log "[REPO] Skipping $GITHUB_REPO due to invalid repository URL"
        REPO_TOTAL_TIME=$(elapsed_sec "$REPO_START_TIME")
        finalize_repository_run "$RUN_ID" "INVALID_REPOSITORY_URL" "git ls-remote failed" "$REPO_TOTAL_TIME"
        return 0
    fi

    stats=$(get_notebook_language_stats "$REPO_ID")
    total_notebooks=$(echo "$stats" | cut -d'|' -f1)
    python_notebooks=$(echo "$stats" | cut -d'|' -f2)

    log "[CHECK] Notebook stats for repo $GITHUB_REPO (id: $REPO_ID): total notebooks=$total_notebooks, python notebooks=$python_notebooks"

    if [ "$total_notebooks" -eq 0 ]; then
        log "[ERROR] Skipping $GITHUB_REPO: no notebooks found"
        REPO_TOTAL_TIME=$(elapsed_sec "$REPO_START_TIME")
        finalize_repository_run "$RUN_ID" "NO_NOTEBOOKS" "Repository contains no notebooks" "$REPO_TOTAL_TIME"
        return 0
    fi

    if [ "$python_notebooks" -eq 0 ]; then
        log "[ERROR] Skipping $GITHUB_REPO: no Python notebooks found"
        REPO_TOTAL_TIME=$(elapsed_sec "$REPO_START_TIME")
        finalize_repository_run "$RUN_ID" "NO_PYTHON_NOTEBOOKS" "Repository contains only non-Python notebooks" "$REPO_TOTAL_TIME"
        return 0
    fi

    # Clone / pull
    if [ -d "$REPO_NAME" ]; then
        cd "$REPO_NAME" && git pull && cd ..
    else
        git clone --depth 1 "$GITHUB_REPO" >> "$LOG_FILE" 2>&1
    fi

    if [ ! -d "$REPO_NAME" ]; then
        log "[ERROR] Repository directory not found after clone: $REPO_NAME"
        REPO_TOTAL_TIME=$(elapsed_sec "$REPO_START_TIME")
        finalize_repository_run "$RUN_ID" "REPO_DIR_MISSING" "Repository directory not found after clone" "$REPO_TOTAL_TIME"
        return 0
    fi

    # Build requirements.txt for this repo
    process_requirements

    # ---- pyenv: set up isolated Python environment -------------------------
    REQUIREMENTS_FILE="$REPO_NAME/requirements.txt"

    if ! setup_pyenv_env "$REPO_NAME" "$REQUIREMENTS_FILE" "$SETUP_PATHS"; then
        REPO_TOTAL_TIME=$(elapsed_sec "$REPO_START_TIME")
        finalize_repository_run "$RUN_ID" "$ENV_ERROR_TYPE" "$ENV_ERROR_MESSAGE" "$REPO_TOTAL_TIME"
        log "[ERROR] Skipping $REPO_NAME due to environment setup failure: $ENV_ERROR_MESSAGE"
        cleanup_pyenv_env
        return 0
    fi

    # ---- pyenv: execute notebooks ------------------------------------------
    if ! run_in_pyenv_env "$REPO_NAME"; then
        analyze_env_error "$LOG_FILE"
        REPO_TOTAL_TIME=$(elapsed_sec "$REPO_START_TIME")
        finalize_repository_run "$RUN_ID" "$ENV_ERROR_TYPE" "$ENV_ERROR_MESSAGE" "$REPO_TOTAL_TIME"
        cleanup_pyenv_env
        return 0
    fi
    # ------------------------------------------------------------------------

    REPO_TOTAL_TIME=$(elapsed_sec "$REPO_START_TIME")
    NOTEBOOKS_COUNT=$(echo "$NOTEBOOK_PATHS" | awk -F';' '{print NF}')
    export REPO_TOTAL_TIME
    export NOTEBOOKS_COUNT

    # Comparison (unchanged)
    compare_notebook_outputs

    # Clean up venv now that comparison is done
    cleanup_pyenv_env

    move_repo
    REPO_TOTAL_TIME=$(elapsed_sec "$REPO_START_TIME")

    finalize_repository_run "$RUN_ID" "SUCCESS" "Repository executed successfully" "$REPO_TOTAL_TIME"

    log "[REPO] Total repository execution time: ${REPO_TOTAL_TIME}s."
    isExecutedSuccessfully="true"
    export NOTEBOOKS_COUNT
    export RUN_ID
}

# Process all the repositories from the database
process_sqlite_flow() {
    processed_repo_ids=()

    local TARGET_COUNT=10
    local processed_count=0

    log "[INFO]: Processing next $TARGET_COUNT unexecuted repositories."
    while [ $processed_count -lt $TARGET_COUNT ]; do
        if [ ${#processed_repo_ids[@]} -gt 0 ]; then
             not_in_clause="AND r.id NOT IN ($(IFS=,; echo "${processed_repo_ids[*]}"))"
        fi

        repo_data=$(sqlite3 "$DB_FILE" <<EOF
.mode csv
.headers off
SELECT
    r.id,
    r.repository,
    r.notebooks,
    r.setups,
    r.requirements
FROM repositories r
WHERE
    r.notebooks IS NOT NULL
    AND TRIM(r.notebooks) != ''
    AND r.notebooks_count != 0
    AND r.id NOT IN (
        SELECT DISTINCT repository_id FROM repository_runs
    ) $not_in_clause
ORDER BY r.id
LIMIT 1;
EOF
        )

        log "[INFO] REPO_DATA: $repo_data"
        if [ -z "$repo_data" ]; then
            log "[INFO] No more repositories to process"
            break
        fi

        IFS=',' read -r REPO_ID REPO_PATH NOTEBOOK_PATHS SETUP_PATHS REQUIREMENT_PATHS <<< "$repo_data"
        GITHUB_REPO="https://github.com/${REPO_PATH}"
        NOTEBOOK_PATHS=$(echo "$NOTEBOOK_PATHS" | tr -d '\r\n"')
        REQUIREMENT_PATHS=$(echo "$REQUIREMENT_PATHS" | tr -d '\r\n"')
        SETUP_PATHS=$(echo "$SETUP_PATHS" | tr -d '\r\n"')

        log "[DEBUG]: REPO_ID='$REPO_ID'"
        log "[DEBUG]: GITHUB_REPO='$GITHUB_REPO'"
        log "[DEBUG]: REPO_PATH='$REPO_PATH'"
        log "[DEBUG]: NOTEBOOK_PATHS='$NOTEBOOK_PATHS'"

        processed_repo_ids+=($REPO_ID)

        isExecutedSuccessfully="false"
        if ! process_repo "$GITHUB_REPO" "$NOTEBOOK_PATHS" "$SETUP_PATHS" "$REQUIREMENT_PATHS"; then
            log "[ERROR] Skipping $REPO_PATH due to failure"
            REPO_NAME=$(basename "$REPO_PATH")
            log "[DEBUG]: REPO_NAME='$REPO_NAME'"
            if [ -d "$REPO_NAME" ]; then
                rm -rf "$REPO_NAME"
                log "[ERROR] Removed failed repository folder: $REPO_NAME"
                processed_count=$((processed_count + 1))
            fi
            continue
        fi

        if [[ "$isExecutedSuccessfully" == "true" ]]; then
            processed_count=$((processed_count + 1))
        fi
    done
}
