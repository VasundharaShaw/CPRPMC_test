# #!/bin/bash
# ###############################################################################
# # Automated Repository-Level Containerization Pipeline
# # 
# # Author: Sheeba Samuel <sheeba.samuel@informatik.tu-chemnitz.de>
# # Co-authors: Hemanta Lo
# # Institution: Chemnitz University of Technology
# # 
# # Description: Main pipeline orchestrating repository discovery, dependency
# #              extraction, Docker containerization, and reproducibility assessment
# #
# # License: GPL-3.0 license
# # Repository: https://github.com/Sheeba-Samuel/computational-reproducibility-pmc-docker
# ###############################################################################

# set -e

# # Get script directory
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# # Source configuration
# source "$PROJECT_ROOT/config/config.sh"

# # Source library functions
# source "$PROJECT_ROOT/lib/logging.sh"
# source "$PROJECT_ROOT/lib/checks.sh"
# source "$PROJECT_ROOT/lib/db.sh"
# # source "$PROJECT_ROOT/lib/entrypoint.sh"
# # source "$PROJECT_ROOT/lib/docker.sh"
# source "$PROJECT_ROOT/lib/pyenv.sh"
# source "$PROJECT_ROOT/lib/requirements.sh"
# source "$PROJECT_ROOT/lib/notebooks.sh"
# source "$PROJECT_ROOT/lib/repo.sh"

# export PYTHONPATH="$PROJECT_ROOT:$PYTHONPATH"

# # Initialize directories
# initialize_directories

# log "[MAIN] Starting pipeline..."
# log "[MAIN] Data directory: $DATA_DIR"
# log "[MAIN] Database: $DB_FILE"
# log "[MAIN] PYTHONPATH: $PYTHONPATH"
# log "[MAIN] PROJECT_ROOT: $PROJECT_ROOT"
# log "[MAIN] SCRIPT_DIR: $SCRIPT_DIR"
# log "[MAIN] LOG_DIR: $LOG_DIR"

# # Initialize database
# ensure_pipeline_tables

# # Function to prompt user for custom inputs
# prompt_for_input() {
#     read -p "Enter GitHub repo URL: " GITHUB_REPO
#     read -p "Enter notebook paths (semicolon-separated): " NOTEBOOK_PATHS
#     read -p "Enter setup paths (semicolon-separated, optional): " SETUP_PATHS
#     read -p "Enter requirements paths (semicolon-separated, optional): " REQUIREMENT_PATHS
# }

# # ============================================================
# # ---------------- MAIN EXECUTION ----------------------------
# # ============================================================


# # Ask the user if they want to input a custom repo or use the SQLite flow
# echo "Would you like to input a custom GitHub repo or use the SQLite flow?"
# echo "1. Input custom GitHub repo"
# echo "2. Use SQLite flow"
# read -p "Enter your choice (1 or 2): " choice

# if [ "$choice" -eq 1 ]; then
#     prompt_for_input
#     REPO_ID=$(get_or_create_repo_id "$GITHUB_REPO")
#     export REPO_ID
#     process_repo "$GITHUB_REPO" "$NOTEBOOK_PATHS" "$SETUP_PATHS" "$REQUIREMENT_PATHS"
# else
#     process_sqlite_flow
# fi

#!/bin/bash
###############################################################################
# CPRPMC Reproducibility Pipeline
#
# Author: Sheeba Samuel <sheeba.samuel@informatik.tu-chemnitz.de>
# Co-authors: Vasundhara Shaw
# Institution: Chemnitz University of Technology
#
# Description: Main pipeline orchestrating repository discovery, dependency
#              extraction, pyenv-based environment isolation, notebook
#              execution, and reproducibility assessment.
#
# License: GPL-3.0 license
# Repository: https://github.com/VasundharaShaw/CPRPMC-pyenv-Vasu
#
# Usage:
#   cd scripts && bash main.sh
#
#   Mode 1 — Single repo: enter a GitHub URL and notebook paths interactively
#   Mode 2 — Batch mode: process all repos registered in the SQLite database
###############################################################################

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source configuration
source "$PROJECT_ROOT/config/config.sh"

# Source library functions
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/checks.sh"
source "$PROJECT_ROOT/lib/db.sh"
source "$PROJECT_ROOT/lib/pyenv.sh"
source "$PROJECT_ROOT/lib/requirements.sh"
source "$PROJECT_ROOT/lib/notebooks.sh"
source "$PROJECT_ROOT/lib/repo.sh"

export PYTHONPATH="$PROJECT_ROOT:$PYTHONPATH"

# Initialize directories
initialize_directories

log "[MAIN] Starting pipeline..."
log "[MAIN] Data directory: $DATA_DIR"
log "[MAIN] Database: $DB_FILE"
log "[MAIN] PYTHONPATH: $PYTHONPATH"
log "[MAIN] PROJECT_ROOT: $PROJECT_ROOT"
log "[MAIN] SCRIPT_DIR: $SCRIPT_DIR"
log "[MAIN] LOG_DIR: $LOG_DIR"

# Initialize database
ensure_pipeline_tables

# Function to prompt user for custom inputs
prompt_for_input() {
    read -p "Enter GitHub repo URL: " GITHUB_REPO
    read -p "Enter notebook paths (semicolon-separated): " NOTEBOOK_PATHS
    read -p "Enter setup paths (semicolon-separated, optional): " SETUP_PATHS
    read -p "Enter requirements paths (semicolon-separated, optional): " REQUIREMENT_PATHS
}

# Print a summary of this run's results from the database
print_run_summary() {
    local run_start="$1"
    local run_end
    run_end=$(date +%s)
    local elapsed=$(( run_end - run_start ))

    local total success failed
    total=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM repository_runs;")
    success=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM repository_runs WHERE run_status = 'SUCCESS';")
    failed=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM repository_runs WHERE run_status NOT IN ('SUCCESS');")

    echo ""
    echo "════════════════════════════════════════"
    echo "           PIPELINE RUN SUMMARY         "
    echo "════════════════════════════════════════"
    echo "  Total runs in DB  : $total"
    echo "  Successful        : $success"
    echo "  Failed/Skipped    : $failed"
    echo "  Elapsed time      : ${elapsed}s"
    echo ""
    echo "  Results stored in : $DB_FILE"
    echo "  Logs directory    : $LOG_DIR"
    echo "════════════════════════════════════════"
    echo ""
}

# ============================================================
# ---------------- MAIN EXECUTION ----------------------------
# ============================================================

RUN_START=$(date +%s)

echo "Would you like to input a custom GitHub repo or use the SQLite flow?"
echo "1. Input custom GitHub repo"
echo "2. Use SQLite flow"
read -p "Enter your choice (1 or 2): " choice

if [ "$choice" -eq 1 ]; then
    prompt_for_input
    REPO_ID=$(get_or_create_repo_id "$GITHUB_REPO")
    export REPO_ID
    process_repo "$GITHUB_REPO" "$NOTEBOOK_PATHS" "$SETUP_PATHS" "$REQUIREMENT_PATHS"
else
    process_sqlite_flow
fi

print_run_summary "$RUN_START"
