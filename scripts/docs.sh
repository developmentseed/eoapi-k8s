#!/usr/bin/env bash

# eoAPI Scripts - Documentation Management
# Generates and serves project documentation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"

readonly DOCS_DIR="${PROJECT_ROOT}/docs"
readonly MKDOCS_CONFIG="${PROJECT_ROOT}/mkdocs.yml"
readonly DEFAULT_PORT="8000"
readonly DEFAULT_HOST="127.0.0.1"

show_help() {
    cat <<EOF
Documentation Management for eoAPI

USAGE:
    $(basename "$0") [OPTIONS] <COMMAND> [ARGS]

COMMANDS:
    generate        Generate documentation as static HTML
    serve           Serve documentation locally for development
    check           Check documentation for errors
    clean           Clean built documentation

OPTIONS:
    -h, --help      Show this help message
    -d, --debug     Enable debug mode
    -n, --namespace Set Kubernetes namespace
    --port PORT     Port for development server (default: ${DEFAULT_PORT})
    --host HOST     Host for development server (default: ${DEFAULT_HOST})

EXAMPLES:
    # Generate documentation
    $(basename "$0") generate

    # Serve documentation locally
    $(basename "$0") serve

    # Serve on a different port
    $(basename "$0") serve --port 8080

    # Check for documentation issues
    $(basename "$0") check
EOF
}

build_docs() {
    log_info "Building documentation..."

    cd "$PROJECT_ROOT"

    if [[ -n "${MKDOCS_CMD:-}" ]]; then
        $MKDOCS_CMD build
        log_success "Documentation built successfully in site/"
    else
        log_error "MkDocs not available"
        return 1
    fi
}

serve_docs() {
    local port="${1:-$DEFAULT_PORT}"
    local host="${2:-$DEFAULT_HOST}"

    log_info "Serving documentation at http://${host}:${port}"
    log_info "Press Ctrl+C to stop the server"

    cd "$PROJECT_ROOT"

    if [[ -n "${MKDOCS_CMD:-}" ]]; then
        $MKDOCS_CMD serve --dev-addr "${host}:${port}"
    else
        log_error "MkDocs not available"
        return 1
    fi
}

check_docs() {
    log_info "Checking documentation for errors..."

    cd "$PROJECT_ROOT"

    # Check if mkdocs.yml exists
    if [[ ! -f "$MKDOCS_CONFIG" ]]; then
        log_error "MkDocs configuration not found: $MKDOCS_CONFIG"
        return 1
    fi

    if [[ ! -d "$DOCS_DIR" ]]; then
        log_error "Documentation directory not found: $DOCS_DIR"
        return 1
    fi

    # Try to build with strict mode to catch errors
    if [[ -n "${MKDOCS_CMD:-}" ]]; then
        if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
            $MKDOCS_CMD build --site-dir /tmp/eoapi-docs-test || {
                log_error "MkDocs build failed"
                rm -rf /tmp/eoapi-docs-test
                return 1
            }
        else
            $MKDOCS_CMD build --site-dir /tmp/eoapi-docs-test >/dev/null 2>&1 || {
                log_error "MkDocs build failed"
                rm -rf /tmp/eoapi-docs-test
                return 1
            }
        fi
        rm -rf /tmp/eoapi-docs-test
    else
        log_error "MkDocs not available"
        return 1
    fi

    # Check frontmatter
    log_info "Checking frontmatter..."
    while IFS= read -r file; do
        head -1 "$file" | grep -q "^---$" || log_warn "Missing frontmatter: $file"
    done < <(find docs -name "*.md" -not -path "docs/_includes/*")

    # Check internal links
    log_info "Checking internal links..."
    while IFS= read -r file; do
        if grep -q "](\./" "$file" 2>/dev/null; then
            while IFS=: read -r line link; do
                path=$(echo "$link" | sed -n 's/.*](\.\///; s/).*//p')
                if [[ "$path" == images/* ]]; then
                    full="docs/$path"
                else
                    full="docs/$path"
                fi
                [[ -e "$full" ]] || log_warn "$file:$line -> $path (broken link)"
            done < <(grep -n "](\./" "$file")
        fi
    done < <(find docs -name "*.md")

    # Check external links - auto-install markdown-link-check if needed
    if ! command_exists markdown-link-check; then
        log_info "Installing markdown-link-check..."
        npm install -g markdown-link-check >/dev/null 2>&1 || {
            log_warn "Could not install markdown-link-check, skipping external link checks"
        }
    fi

    if command_exists markdown-link-check; then
        log_info "Checking external links..."
        echo '{"timeout":"10s","retryCount":2,"aliveStatusCodes":[200,301,302,403,999]}' > /tmp/mlc.json
        find docs -name "*.md" -exec timeout 30 markdown-link-check {} --config /tmp/mlc.json \; 2>/dev/null || true
        rm -f /tmp/mlc.json
    fi

    log_success "Documentation check completed"
    return 0
}

clean_docs() {
    log_info "Cleaning built documentation..."

    cd "$PROJECT_ROOT"

    if [[ -d "site" ]]; then
        rm -rf site
        log_success "Documentation cleaned"
    else
        log_info "No built documentation to clean"
    fi
}

check_docs_requirements() {
    log_info "Checking documentation requirements..."

    if command_exists mkdocs; then
        log_debug "Found mkdocs command"
        export MKDOCS_CMD="mkdocs"
        log_success "All documentation requirements met"
        return 0
    fi

    if command_exists python3; then
        if python3 -c "import mkdocs" 2>/dev/null; then
            log_debug "Found mkdocs Python module"
            export MKDOCS_CMD="python3 -m mkdocs"
            log_success "All documentation requirements met"
            return 0
        fi

        log_info "Installing MkDocs..."
        python3 -m pip install --user mkdocs mkdocs-material >/dev/null 2>&1 || {
            log_error "Failed to install MkDocs"
            return 1
        }
        log_success "MkDocs installed"
        export MKDOCS_CMD="python3 -m mkdocs"
        log_success "All documentation requirements met"
        return 0
    fi

    log_error "Python 3 is required for MkDocs"
    return 1
}

main() {
    local port="$DEFAULT_PORT"
    local host="$DEFAULT_HOST"
    local command=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--debug)
                export DEBUG_MODE=true
                shift
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --host)
                host="$2"
                shift 2
                ;;
            generate|serve|check|clean)
                command="$1"
                shift
                break
                ;;
            *)
                log_error "Unknown option or command: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -z "$command" ]]; then
        log_error "No command specified"
        show_help
        exit 1
    fi

    if [[ "$command" != "clean" ]]; then
        check_docs_requirements || exit 1
    fi

    case "$command" in
        generate)
            build_docs
            ;;
        serve)
            serve_docs "$port" "$host"
            ;;
        check)
            check_docs
            ;;
        clean)
            clean_docs
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
