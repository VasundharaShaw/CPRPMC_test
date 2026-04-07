# -----------------------------------------------------------------------------
# PATCH for lib/repo.sh — process_repo() function
#
# Changes from original:
#   - Source pyenv.sh instead of docker.sh
#   - Replace create_entrypoint / create_dockerfile / create_dockerignore /
#     cleanup_container / build_docker_image / run_docker_container
#     with setup_pyenv_env / run_in_pyenv_env / cleanup_pyenv_env
#   - DOCKER_ERROR_TYPE / DOCKER_ERROR_MESSAGE -> ENV_ERROR_TYPE / ENV_ERROR_MESSAGE
#   - Docker name sanitization block removed (no longer needed)
# Everything else (DB calls, compare_notebook_outputs, move_repo) is unchanged.
# -----------------------------------------------------------------------------

# At the top of repo.sh, replace:
#   source lib/docker.sh
# with:
#   source lib/pyenv.sh

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

    log "[CHECK] Notebook stats for $GITHUB_REPO: total=$total_notebooks, python=$python_notebooks"

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

    # Compare outputs (unchanged)
    compare_notebook_outputs

    # Clean up venv now that comparison is done
    cleanup_pyenv_env

    move_repo
    REPO_TOTAL_TIME=$(elapsed_sec "$REPO_START_TIME")

    finalize_repository_run "$RUN_ID" "SUCCESS" "Repository executed successfully" "$REPO_TOTAL_TIME"

    log "[REPO] Total execution time: ${REPO_TOTAL_TIME}s."
    isExecutedSuccessfully="true"
    export NOTEBOOKS_COUNT
    export RUN_ID
}
