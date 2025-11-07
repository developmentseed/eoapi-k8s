#!/bin/bash

# eoAPI Scripts - Standardized Argument Parsing Library
# Provides consistent CLI interface across all scripts

set -euo pipefail

# Source common utilities if not already loaded
if ! declare -f log_info >/dev/null 2>&1; then
    ARGS_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
    source "$ARGS_SCRIPT_DIR/common.sh"
fi

# Global argument variables with defaults
# Default values
NAMESPACE="${NAMESPACE:-eoapi}"
RELEASE_NAME="${RELEASE_NAME:-eoapi}"
TIMEOUT="${TIMEOUT:-5m}"
DEBUG_MODE="${DEBUG_MODE:-false}"
DEPS_ONLY="${DEPS_ONLY:-false}"
HELM_SET_VALUES=()
HELM_VALUES_FILES=()
CLUSTER_TYPE="${CLUSTER_TYPE:-minikube}"
CLUSTER_NAME="${CLUSTER_NAME:-eoapi-local}"
HTTP_PORT="${HTTP_PORT:-8080}"
HTTPS_PORT="${HTTPS_PORT:-8443}"

# Parse common arguments used across multiple scripts
parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace|-n)
                if [ -z "${2:-}" ]; then
                    log_error "Namespace value required"
                    return 1
                fi
                NAMESPACE="$2"
                shift 2
                ;;
            --release|-r)
                if [ -z "${2:-}" ]; then
                    log_error "Release name value required"
                    return 1
                fi
                RELEASE_NAME="$2"
                shift 2
                ;;
            --timeout|-t)
                if [ -z "${2:-}" ]; then
                    log_error "Timeout value required"
                    return 1
                fi
                TIMEOUT="$2"
                shift 2
                ;;
            --debug|-d)
                DEBUG_MODE=true
                shift
                ;;
            --deps-only)
                DEPS_ONLY=true
                shift
                ;;
            --set)
                if [ -z "${2:-}" ]; then
                    log_error "Set value required"
                    return 1
                fi
                HELM_SET_VALUES+=("$2")
                shift 2
                ;;
            -f|--values)
                if [ -z "${2:-}" ]; then
                    log_error "Values file required"
                    return 1
                fi
                HELM_VALUES_FILES+=("$2")
                shift 2
                ;;
            --verbose|-v)
                DEBUG_MODE=true
                set -x
                shift
                ;;
            --help|-h)
                return 2  # Special return code to trigger help
                ;;
            --)
                shift
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                return 1
                ;;
            *)
                break
                ;;
        esac
    done

    # Enable debug logging if requested
    if [ "$DEBUG_MODE" = true ]; then
        log_debug "Debug mode enabled"
        log_debug "Parsed arguments:"
        log_debug "  NAMESPACE: $NAMESPACE"
        log_debug "  RELEASE_NAME: $RELEASE_NAME"
        log_debug "  TIMEOUT: $TIMEOUT"
        log_debug "  DEPS_ONLY: $DEPS_ONLY"
        if [ "${#HELM_VALUES_FILES[@]}" -gt 0 ]; then
            log_debug "  HELM_VALUES_FILES: ${HELM_VALUES_FILES[*]}"
        fi
        log_debug "  HELM_SET_VALUES: ${HELM_SET_VALUES[*]}"
    fi

    return 0
}

# Parse cluster-specific arguments
parse_cluster_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                if [ -z "${2:-}" ]; then
                    log_error "Cluster type value required"
                    return 1
                fi
                case "$2" in
                    minikube|k3s)
                        CLUSTER_TYPE="$2"
                        ;;
                    *)
                        log_error "Invalid cluster type: $2 (must be minikube or k3s)"
                        return 1
                        ;;
                esac
                shift 2
                ;;
            --name)
                if [ -z "${2:-}" ]; then
                    log_error "Cluster name value required"
                    return 1
                fi
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --http-port)
                if [ -z "${2:-}" ]; then
                    log_error "HTTP port value required"
                    return 1
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1024 ] || [ "$2" -gt 65535 ]; then
                    log_error "Invalid HTTP port: $2 (must be 1024-65535)"
                    return 1
                fi
                HTTP_PORT="$2"
                shift 2
                ;;
            --https-port)
                if [ -z "${2:-}" ]; then
                    log_error "HTTPS port value required"
                    return 1
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1024 ] || [ "$2" -gt 65535 ]; then
                    log_error "Invalid HTTPS port: $2 (must be 1024-65535)"
                    return 1
                fi
                HTTPS_PORT="$2"
                shift 2
                ;;
            *)
                # Let common args parser handle it
                parse_common_args "$@"
                local result=$?
                if [ $result -eq 2 ]; then
                    return 2  # Help requested
                elif [ $result -ne 0 ]; then
                    return $result
                fi
                break
                ;;
        esac
    done

    if [ "$DEBUG_MODE" = true ]; then
        log_debug "Cluster arguments:"
        log_debug "  CLUSTER_TYPE: $CLUSTER_TYPE"
        log_debug "  CLUSTER_NAME: $CLUSTER_NAME"
        log_debug "  HTTP_PORT: $HTTP_PORT"
        log_debug "  HTTPS_PORT: $HTTPS_PORT"
    fi

    return 0
}

# Parse file-related arguments
parse_file_args() {
    local collections_file=""
    local items_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --collections|-c)
                if [ -z "${2:-}" ]; then
                    log_error "Collections file path required"
                    return 1
                fi
                collections_file="$2"
                shift 2
                ;;
            --items|-i)
                if [ -z "${2:-}" ]; then
                    log_error "Items file path required"
                    return 1
                fi
                items_file="$2"
                shift 2
                ;;
            *)
                # Let common args parser handle it
                parse_common_args "$@"
                local result=$?
                if [ $result -eq 2 ]; then
                    return 2  # Help requested
                elif [ $result -ne 0 ]; then
                    return $result
                fi
                break
                ;;
        esac
    done

    # Set global variables for file arguments
    COLLECTIONS_FILE="${collections_file:-./collections.json}"
    ITEMS_FILE="${items_file:-./items.json}"

    if [ "$DEBUG_MODE" = true ]; then
        log_debug "File arguments:"
        log_debug "  COLLECTIONS_FILE: $COLLECTIONS_FILE"
        log_debug "  ITEMS_FILE: $ITEMS_FILE"
    fi

    return 0
}

# Validate parsed arguments
validate_parsed_args() {
    local validation_type="${1:-basic}"

    case "$validation_type" in
        basic)
            # Basic validation for all scripts
            if [ -z "$NAMESPACE" ]; then
                log_error "Namespace cannot be empty"
                return 1
            fi

            if [ -z "$RELEASE_NAME" ]; then
                log_error "Release name cannot be empty"
                return 1
            fi

            # Validate namespace name format (RFC 1123)
            if ! [[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
                log_error "Invalid namespace format: $NAMESPACE (must follow RFC 1123)"
                return 1
            fi

            # Validate release name format
            if ! [[ "$RELEASE_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
                log_error "Invalid release name format: $RELEASE_NAME (must follow RFC 1123)"
                return 1
            fi
            ;;

        cluster)
            validate_parsed_args basic || return 1

            if [ "$CLUSTER_TYPE" != "minikube" ] && [ "$CLUSTER_TYPE" != "k3s" ]; then
                log_error "Invalid cluster type: $CLUSTER_TYPE"
                return 1
            fi

            if [ -z "$CLUSTER_NAME" ]; then
                log_error "Cluster name cannot be empty"
                return 1
            fi

            # Check for port conflicts
            if [ "$HTTP_PORT" = "$HTTPS_PORT" ]; then
                log_error "HTTP and HTTPS ports cannot be the same"
                return 1
            fi
            ;;

        files)
            validate_parsed_args basic || return 1

            # Files will be validated by validation.sh functions
            ;;

        *)
            log_error "Unknown validation type: $validation_type"
            return 1
            ;;
    esac

    return 0
}

# Generate standard help sections
show_common_options() {
    cat << EOF
COMMON OPTIONS:
    --namespace, -n NAME    Target namespace (default: $NAMESPACE)
    --release, -r NAME      Helm release name (default: $RELEASE_NAME)
    --timeout, -t DURATION  Operation timeout (default: $TIMEOUT)
    -f, --values FILE       Specify values file (can be used multiple times)
    --set KEY=VALUE         Set Helm chart values (can be used multiple times)
    --debug, -d             Enable debug mode
    --deps-only             Setup Helm dependencies only (no cluster required)
    --verbose, -v           Enable verbose output with command tracing
    --help, -h              Show this help message

EOF
}

show_cluster_options() {
    cat << EOF
CLUSTER OPTIONS:
    --type TYPE             Cluster type: minikube or k3s (default: $CLUSTER_TYPE)
    --name NAME             Cluster name (default: $CLUSTER_NAME)
    --http-port PORT        HTTP port for k3s ingress (default: $HTTP_PORT)
    --https-port PORT       HTTPS port for k3s ingress (default: $HTTPS_PORT)

EOF
}

show_file_options() {
    cat << EOF
FILE OPTIONS:
    --collections, -c FILE  Collections JSON file (default: ./collections.json)
    --items, -i FILE        Items JSON file (default: ./items.json)

EOF
}

# Environment variable documentation
show_environment_variables() {
    cat << EOF
ENVIRONMENT VARIABLES:
    NAMESPACE               Target namespace (default: eoapi)
    RELEASE_NAME            Helm release name (default: eoapi)
    TIMEOUT                 Operation timeout (default: 10m)
    DEBUG_MODE              Enable debug mode (default: false)
    CLUSTER_TYPE            Cluster type for local development (default: minikube)
    CLUSTER_NAME            Local cluster name (default: eoapi-local)
    HTTP_PORT               HTTP port for k3s ingress (default: 8080)
    HTTPS_PORT              HTTPS port for k3s ingress (default: 8443)

EOF
}

# Export functions and variables
export -f parse_common_args parse_cluster_args parse_file_args validate_parsed_args
export -f show_common_options show_cluster_options show_file_options show_environment_variables
export NAMESPACE RELEASE_NAME TIMEOUT DEBUG_MODE DEPS_ONLY CLUSTER_TYPE CLUSTER_NAME HTTP_PORT HTTPS_PORT HELM_SET_VALUES HELM_VALUES_FILES
