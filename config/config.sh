#!/bin/bash
###############################################################################
# config.sh — Central configuration for the CPRPMC pipeline
###############################################################################

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DATA_INPUT_DIR="$PROJECT_ROOT/data/input"
DATA_OUTPUT_DIR="$PROJECT_ROOT/data/output"
REPOS_DIR="$DATA_OUTPUT_DIR/cloned_repos"
COMP_DIR="$DATA_OUTPUT_DIR/comparisons"
LOG_DIR="$DATA_OUTPUT_DIR/logs"
DB_DIR="$DATA_OUTPUT_DIR/db"
DB_FILE="${DB_FILE:-$DB_DIR/db.sqlite}"
TARGET_COUNT="${TARGET_COUNT:-10}"

initialize_directories() {
    mkdir -p "$REPOS_DIR" "$COMP_DIR" "$LOG_DIR" "$DB_DIR" "$DATA_INPUT_DIR"
    log "[INIT] Initialized directory structure under $DATA_OUTPUT_DIR"
}

export PROJECT_ROOT DATA_INPUT_DIR DATA_OUTPUT_DIR REPOS_DIR COMP_DIR LOG_DIR DB_DIR DB_FILE TARGET_COUNT
