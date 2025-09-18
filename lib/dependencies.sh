#!/bin/bash
# lib/dependencies.sh
# Funzioni per il controllo dei prerequisiti e il download dei binari di HashiCorp.

check_and_install_prerequisites() {
    log_info "CHECKING PREREQUISITES"
    local missing_pkgs=()
    declare -A pkg_map
    pkg_map["curl"]="curl"; pkg_map["jq"]="jq"; pkg_map["unzip"]="unzip"; pkg_map["lsof"]="lsof"

    for cmd_name in "${!pkg_map[@]}"; do
        if ! command -v "${pkg_map[$cmd_name]}" &> /dev/null; then
            missing_pkgs+=("${pkg_map[$cmd_name]}")
        fi
    done

    if [ ${#missing_pkgs[@]} -eq 0 ]; then
        log_info "All necessary prerequisites are already installed. 👍"
        return 0
    fi

    log_warn "The following prerequisite packages are missing: ${missing_pkgs[*]}"
    local install_cmd=""
    case "$(uname -s)" in
        Linux*)
            if command -v apt-get &> /dev/null; then install_cmd="sudo apt-get update && sudo apt-get install -y"
            elif command -v yum &> /dev/null; then install_cmd="sudo yum install -y"
            elif command -v dnf &> /dev/null; then install_cmd="sudo dnf install -y"
            elif command -v pacman &> /dev/null; then install_cmd="sudo pacman -Sy --noconfirm"
            fi
            ;;
        Darwin*)
            if command -v brew &> /dev/null; then install_cmd="brew install"
            else log_error "Homebrew is not installed. Please install it to proceed."
            fi
            ;;
        *)
            log_warn "Unsupported OS. Please install missing packages manually: ${missing_pkgs[*]}"
            read -p "Do you want to proceed anyway? (y/N): " choice
            [[ "$choice" =~ ^[Yy]$ ]] || log_error "Exiting."
            return 0
            ;;
    esac

    read -p "Do you want to install them now? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        if ! eval "$install_cmd ${missing_pkgs[*]}"; then
            log_error "Failed to install prerequisites. Please install them manually."
        fi
    else
        log_error "Installation skipped. Exiting."
    fi
}

_download_hashicorp_binary() {
    local product="$1" bin_dir="$2"           # es: vault, consul
    local requested_version="${3:-latest}"    # terzo arg facoltativo
    local platform="linux_amd64"

    case "$(uname -s)" in
        Darwin*)  platform="darwin_amd64" ;;
        *MINGW*)  platform="windows_amd64" ;;
    esac

    local product_exe
    product_exe=$(get_exe "$product")
    local temp_dir
    temp_dir=$(mktemp -d) || log_error "Cannot create temp dir"
    trap 'rm -rf "$temp_dir"' EXIT INT TERM

    log_info "${product^^} binary management: check and download"

    # Se non specificato, determina la versione più recente
    local target_version="$requested_version"
    if [ "$requested_version" = "latest" ]; then
        local releases_json
        releases_json=$(curl -s "https://releases.hashicorp.com/${product}/index.json") \
            || log_error "Failed to fetch ${product} releases. Check internet connection."

        target_version=$(echo "$releases_json" \
            | jq -r '.versions | keys[]' \
            | grep -Ev 'ent|rc|beta|preview' \
            | sort -V | tail -n 1)

        [ -z "$target_version" ] && log_error "Could not determine the latest ${product} version."
        log_info "Latest available ${product} version: $target_version"
    else
        log_info "Requested ${product} version: $target_version"
    fi

    # Se il binario esiste già ed è alla versione giusta, esci
    if [ -x "$product_exe" ]; then
        local current_version
        current_version=$("$product_exe" --version | head -n1 | awk '{print $2}' | sed 's/^v//')
        if [ "$current_version" = "$target_version" ]; then
            log_info "Current ${product} binary (v$current_version) is up to date."
            trap - EXIT INT TERM; rm -rf "$temp_dir"
            return 0
        fi
        log_info "Updating ${product} from v$current_version to v$target_version..."
    fi

    local url="https://releases.hashicorp.com/${product}/${target_version}/${product}_${target_version}_${platform}.zip"
    log_info "Downloading ${product} v$target_version from $url"
    curl -fsSL -o "$temp_dir/${product}.zip" "$url" || log_error "Download failed."

    unzip -o "$temp_dir/${product}.zip" -d "$bin_dir" >/dev/null || log_error "Extraction failed."
    chmod +x "$product_exe"

    log_info "${product^} v$target_version downloaded and configured successfully."
    trap - EXIT INT TERM; rm -rf "$temp_dir"
}

download_latest_vault_binary() {
    _download_hashicorp_binary "vault" "$BIN_DIR" "${VAULT_VERSION:-latest}"
}

download_latest_consul_binary() {
    _download_hashicorp_binary "consul" "$BIN_DIR" "${CONSUL_VERSION:-latest}"
}