#!/bin/bash
# Project: StreamSage Intelligent Transaction Processing Platform
# Purpose: Promote configuration between environments via Git merge

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VALID_ENVS=("dev" "test" "qa" "staging" "perf" "prod" "ep" "eem" "dr")
PROMOTION_PATH="dev→test→qa→staging→perf→prod"

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error()   { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }
print_header()  { echo ""; echo "=========================================="; echo "$1"; echo "=========================================="; echo ""; }

validate_env() {
    local env=$1
    for v in "${VALID_ENVS[@]}"; do
        [ "$env" == "$v" ] && return 0
    done
    return 1
}

validate_promotion_path() {
    case "$1" in
        "dev")     [[ "$2" == "test"    ]] && return 0 ;;
        "test")    [[ "$2" == "qa"      ]] && return 0 ;;
        "qa")      [[ "$2" == "staging" ]] && return 0 ;;
        "staging") [[ "$2" == "perf" || "$2" == "prod" ]] && return 0 ;;
        "perf")    [[ "$2" == "prod"    ]] && return 0 ;;
    esac
    return 1
}

check_git_status() {
    print_info "Checking Git repository status..."
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a Git repository"
        exit 1
    fi
    if [ -n "$(git status --porcelain)" ]; then
        print_error "Working directory is not clean. Please commit or stash changes."
        git status --short
        exit 1
    fi
    print_success "Git repository is clean"
}

perform_promotion() {
    local source=$1
    local target=$2
    local dry_run=$3

    print_header "Promoting from $source to $target"
    print_info "Checking out $target branch..."
    git checkout "$target"
    git pull origin "$target"

    if [ "$dry_run" == "true" ]; then
        print_warning "DRY RUN: Would merge $source into $target"
        git merge --no-commit --no-ff "origin/$source" || true
        git merge --abort 2>/dev/null || true
        return 0
    fi

    print_info "Merging $source into $target..."
    if git merge --no-ff "origin/$source" -m "Promote from $source to $target"; then
        print_success "Merge successful"
    else
        print_error "Merge failed. Please resolve conflicts manually."
        exit 1
    fi

    print_warning "Ready to push changes to $target branch. Press Enter to push or Ctrl+C to abort..."
    read -r
    git push origin "$target"
    print_success "Changes pushed to $target"
}

trigger_argocd_sync() {
    local env=$1
    local dry_run=$2
    print_header "Triggering ArgoCD sync for $env"

    if ! command -v argocd &> /dev/null; then
        print_warning "argocd CLI not found. Sync via ArgoCD UI or: argocd app sync <app-name>"
        return 0
    fi

    [ "$dry_run" == "true" ] && { print_warning "DRY RUN: Would sync ArgoCD apps for $env"; return 0; }

    local apps
    apps=$(argocd app list -o name | grep "^${env}-" || true)
    if [ -z "$apps" ]; then
        print_warning "No ArgoCD applications found for $env"
        return 0
    fi

    print_info "Found applications:"; echo "$apps"; echo ""
    print_warning "Sync these applications? Press Enter to sync or Ctrl+C to skip..."
    read -r

    while IFS= read -r app; do
        print_info "Syncing $app..."
        argocd app sync "$app" --prune && print_success "Synced $app" || print_error "Failed to sync $app"
    done <<< "$apps"
}

main() {
    local source_env=$1
    local target_env=$2
    local dry_run=false

    [ "$3" == "--dry-run" ] && { dry_run=true; print_warning "DRY RUN mode — no changes will be made"; }

    if [ -z "$source_env" ] || [ -z "$target_env" ]; then
        print_error "Usage: $0 <source-env> <target-env> [--dry-run]"
        echo "Valid environments: ${VALID_ENVS[*]}"
        echo "Standard promotion path: $PROMOTION_PATH"
        exit 1
    fi

    validate_env "$source_env" || { print_error "Invalid source: $source_env"; exit 1; }
    validate_env "$target_env" || { print_error "Invalid target: $target_env"; exit 1; }

    if ! validate_promotion_path "$source_env" "$target_env"; then
        print_warning "Non-standard promotion path: $source_env → $target_env. Proceed? (yes/no)"
        read -r confirmation
        [ "$confirmation" != "yes" ] && { print_info "Promotion cancelled"; exit 0; }
    fi

    print_header "Environment Promotion: $source_env → $target_env"
    check_git_status
    git fetch origin
    perform_promotion "$source_env" "$target_env" "$dry_run"

    if [ "$dry_run" != "true" ]; then
        trigger_argocd_sync "$target_env" "$dry_run"
        print_header "Promotion Summary"
        echo "Source: $source_env → Target: $target_env"
        echo "Date:   $(date)"
        echo "By:     $(git config user.name) <$(git config user.email)>"
        print_success "Promotion completed!"
    else
        print_warning "DRY RUN completed — no changes were made"
    fi
}

main "$@"
