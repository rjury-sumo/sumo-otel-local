#!/bin/bash

set -euo pipefail

# Helper Functions
function help {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help      Display this help message."
    echo "  -i, --install   Install the dependencies and setup the Sumo Operator."
    echo "  -n, --init      Install dependencies without setting up the Sumo Operator."
    echo "  -m, --helm      Install Sumo Operator onto existing cluster."
    echo "  -o, --output    Output the rendered Kubernetes manifest YAML file."
    echo "  -p, --purge     Uninstall the Cluster and Podman Machine."
    echo "  -u, --uninstall Uninstall the Cluster only."
    echo "  -v, --version   Display the version of the script."
}


# Check Architecture
ARCH=$(uname -m)

# Check Dependencies
function install_dependencies {

    if command -v brew &> /dev/null; then
        echo "Installing Dependencies with Homebrew..."
        brew install --quiet jq kubectl helm kind podman
    elif ! command -v brew &> /dev/null; then
        read -p "Homebrew is not installed. Would you like to install it? [y/n]" yn
        if [[ $yn =~ ^[Yy]$ ]]; then
            curl -fsSL -o install_homebrew.sh https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
            chmod 700 install_homebrew.sh
            ./install_homebrew.sh
            rm install_homebrew.sh
            install_dependencies
        else
            echo "Installing Dependencies Directly..."
            if ! command -v jq &> /dev/null; then
                echo "Installing jq..."
                curl -Lo /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-${ARCH} 
                chmod +x /usr/local/bin/jq
            fi

            if ! command -v kubectl &> /dev/null; then
                echo "Installing Kubectl..."
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/${ARCH}/kubectl"
                chmod +x ./kubectl
                sudo mv ./kubectl /usr/local/bin/kubectl
                sudo chown root: /usr/local/bin/kubectl
                kubectl version --client
            fi

            if ! command -v helm &> /dev/null; then
                echo "Installing Helm..."
                curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
                chmod 700 get_helm.sh
                ./get_helm.sh
            fi

            if ! command -v docker &> /dev/null && ! command -v podman &> /dev/null; then
                echo "Installing Podman..."
                RELEASE=$(curl -L -s https://api.github.com/repos/containers/podman/releases/latest | jq -r .tag_name)
                curl -Lo ./podman-remote-release-darwin_${ARCH}.zip https://github.com/containers/podman/releases/download/${RELEASE}/podman-remote-release-darwin_${ARCH}.zip
                unzip podman-remote-release-darwin_${ARCH}.zip
                chmod +x ./podman-${RELEASE}/usr/bin/podman
                sudo mv ./podman-${RELEASE}/usr/bin/podman /usr/local/bin/podman
                chmod +x ./podman-${RELEASE}/usr/bin/podman-mac-helper
                sudo mv ./podman-${RELEASE}/usr/bin/podman-mac-helper /usr/local/bin/podman-mac-helper
            fi    

            if ! command -v kind &> /dev/null; then
                echo "Installing Kind..."
                RELEASE=$(curl -L -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r .tag_name)
                curl -Lo ./kind https://kind.sigs.k8s.io/dl/${RELEASE}/kind-linux-amd64
                chmod +x ./kind
                mv ./kind /usr/local/bin/kind
            fi
        fi
    fi
}

function init_cluster {
    # Initialise and Start Podman
    if command -v podman &> /dev/null; then
        echo "Podman is installed..."
        use_existing_podman
    else
        read -p "Podman is not installed. Are you using Docker Desktop? [y/n]" yn
        if [[ $yn =~ ^[Yy]$ ]]; then
            echo "Using Docker Desktop..."
        else
            echo "Please install Podman or Docker Desktop to continue."
            exit 1
        fi
    fi

    # Create a cluster
    DEFAULT_CLUSTER_NAME="sumo"
    read -p "Name of the cluster [default=${DEFAULT_CLUSTER_NAME}]: " CLUSTER_NAME
    : ${CLUSTER_NAME:=${DEFAULT_CLUSTER_NAME}}
    kind create cluster --name ${CLUSTER_NAME} --config kind-config.yaml
}

function install_sumo {    

    # Install Sumo Logic Operator

    ACCESS_ID=""
    ACCESS_ID_VAR="Enter your SumoLogic Access ID: "            # to take password character wise
    while IFS= read -p "$ACCESS_ID_VAR" -r -s -n 1 letter
    do
        if [[ $letter == $'\0' ]]                               #  if enter is pressed, exit the loop
        then
            break
        fi
        
        ACCESS_ID+="$letter"                                    # store the letter in ACCESS_ID, use pass+="$letter" for more concise and readable.
        ACCESS_ID_VAR="*"                                       # in place of password the asterisk (*) will be printed
    done
    echo ""

    ACCESS_KEY=""
    ACCESS_KEY_VAR="Enter your SumoLogic Access Key: "           # to take password character wise
    while IFS= read -p "$ACCESS_KEY_VAR" -r -s -n 1 letter
    do
        if [[ $letter == $'\0' ]]                               #  if enter is pressed, exit the loop
        then
            break
        fi
        
        ACCESS_KEY+="$letter"                                   # store the letter in ACCESS_KEY, use VAR+="$letter" for more concise and readable.
        ACCESS_KEY_VAR="*"                                      # in place of password the asterisk (*) will be printed
    done
    echo ""

    DEFAULT_HELM_VALUES="values.yaml"
    echo "Additional example values can be found in the examples folder. When prompted, please provide the path to the values.yaml file. e.g. examples/values.yaml"
    read -p "Name and Location of the Helm Values file. [default=values.yaml]: " HELM_VALUES
    : ${HELM_VALUES:=${DEFAULT_HELM_VALUES}}

    DEFAULT_CLUSTER_NAME="sumo"
    read -p "Name of the cluster [default=${DEFAULT_CLUSTER_NAME}]: " CLUSTER_NAME
    : ${CLUSTER_NAME:=${DEFAULT_CLUSTER_NAME}}

    helm upgrade \
    --install \
    sumologic sumologic/sumologic \
    --namespace=sumologic \
    --create-namespace \
    --values ${HELM_VALUES} \
    --set-string sumologic.accessId=${ACCESS_ID} \
    --set-string sumologic.accessKey=${ACCESS_KEY} \
    --set-string sumologic.clusterName=${CLUSTER_NAME} \
    --set-string fullnameOverride=sumo \
    --set sumologic.falco.enabled=false \
    --set sumologic.logs.systemd.enabled=false
}

function output {
    DEFAULT_HELM_VALUES="values.yaml"
    DEFAULT_K8S_YAML="sumologic-rendered.yaml"

    read -p "Name and Location of the Helm Values file. [default=values.yaml]: " HELM_VALUES
    : ${HELM_VALUES:=${DEFAULT_HELM_VALUES}}
    read -p "Name and Location of the rendered Kuberenetes Manifest YAML file. [default=sumologic-rendered.yaml]: " K8S_YAML
    : ${K8S_YAML:=${DEFAULT_K8S_YAML}}   
 
    helm template \
    --namespace=sumologic \
    --create-namespace \
    -f ${HELM_VALUES} \
    sumologic sumologic/sumologic | tee ${K8S_YAML}
}

function uninstall {
    echo "Caution: This will delete the cluster"
    read -p "Are you sure you want to continue? [y/n]" yn
    if [[ $yn =~ ^[Yy]$ ]]; then
        DEFAULT_CLUSTER_NAME="sumo"
        read -p "Type the name of the cluster (Default: sumo) to continue. Type [exit] to cancel: " CLUSTER_NAME
        : ${CLUSTER_NAME:=${DEFAULT_CLUSTER_NAME}}
        if [[ $CLUSTER_NAME == "exit" ]]; then
            echo "Cancelling and exiting script..."
            exit 0
        else
            echo "Deleting Cluster: ${CLUSTER_NAME}"
            kind delete cluster --name ${CLUSTER_NAME}
            echo "Leaving Podman Machine intact"
        fi
    else
        echo "Cancelling and exiting script..."
        exit 0
    fi    
}

function purge {
    echo "Caution: This will delete the cluster and remove the Podman machine!"
    read -p "Are you sure you want to continue? [y/n]" yn
    if [[ $yn =~ ^[Yy]$ ]]; then
        DEFAULT_CLUSTER_NAME="sumo"
        read -p "Type the name of the cluster (Default: sumo) to continue. Type [exit] to cancel: " CLUSTER_NAME
        : ${CLUSTER_NAME:=${DEFAULT_CLUSTER_NAME}}
        if [[ $CLUSTER_NAME == "exit" ]]; then
            echo "Cancelling and exiting script..."
            exit 0
        else
            echo "Deleting Cluster: ${CLUSTER_NAME}"
            kind delete cluster --name ${CLUSTER_NAME}
            echo "Stopping and Removing Podman Machine..."
            podman machine stop
            podman machine rm
        fi
    else
        echo "Cancelling and exiting script..."
        exit 0
    fi
}

function version {
    RELEASE=$(curl -L -s https://api.github.com/repos/bradtho/sumo-otel-local/releases/latest | jq -r .tag_name)
    echo "sumo-otel-local ${RELEASE}"
}

## Helper Functions
function new_podman {
    echo "Creating a new Podman machine..."   
    DEFAULT_NAME="sumo"
    DEFAULT_MEMORY=18432
    read -p "Allocate memory for Podman machine (in MiB) [default=${DEFAULT_MEMORY}]: " MEMORY
    read -p "Name of the Podman machine [default=${DEFAULT_NAME}]: " NAME
    : ${MEMORY:=${DEFAULT_MEMORY}}
    : ${NAME:=${DEFAULT_NAME}}

    echo "Initializing Podman machine '$NAME' with ${MEMORY}MiB RAM..."
    podman machine init --memory ${MEMORY} ${NAME}

    running_machine=$(podman machine list --format json | jq -r '.[] | select(.Running == true) | .Name')
    if [[ -n "$running_machine" ]]; then
        echo "Podman machine '$running_machine' is currently running."
        echo "Only one Podman machine can run at a time"
        read -p "Would you like to stop it before starting the new one? [y/N]: " stop_choice
        if [[ "$stop_choice" =~ ^[Yy]$ ]]; then
            echo "Stopping '$running_machine'..."
            podman machine stop "$running_machine"
        else
            echo "Cannot start new machine while another is running. Exiting."
            exit 0
        fi
    fi    
    
    podman machine start ${NAME}
}

function use_existing_podman {
    # Minimum requirements
    MIN_MEM_MB=18432  # in MB
    MIN_CPU=4

    # Get list of all machines with their specs
    machines_json=$(podman machine list --format json)

    # Arrays to hold valid machines
    declare -a valid_names valid_memories valid_cpus

    index=0
    echo "Checking Podman machines for minimum requirements (Memory ≥ ${MIN_MEM_MB}MB, CPUs ≥ ${MIN_CPU})..."

    # Loop over machines using `jq` length and index
    machine_count=$(echo "$machines_json" | jq 'length')

    for ((i=0; i<machine_count; i++)); do
        name=$(echo "$machines_json" | jq -r ".[$i].Name")
        mem_bytes=$(echo "$machines_json" | jq -r ".[$i].Memory")
        cpu=$(echo "$machines_json" | jq -r ".[$i].CPUs")
        status=$(echo "$machines_json" | jq -r ".[$i].Running")
        
        #Convert memory from bytes to MB
        mem_mb=$(awk "BEGIN { printf \"%d\", $mem_bytes / 1024 / 1024 }")

        if [[ "$mem_mb" -ge "$MIN_MEM_MB" && "$cpu" -ge "$MIN_CPU" ]]; then
            valid_names[$index]="$name"
            valid_memories[$index]="$mem_mb"
            valid_cpus[$index]="$cpu"
            valid_statuses[$index]="$status"
            echo "$((index + 1)). $name - Memory: ${mem_mb}MB, CPUs: $cpu"
            ((index++))
        fi
    done

    # Check if any valid machine was found
    if [[ ${#valid_names[@]} -eq 0 ]]; then
        echo "No Podman machines meet the minimum requirements (≥ ${MIN_MEM_MB}MB RAM, ≥ ${MIN_CPU} CPUs)."
        read -p "Would you like to create a new Podman machine with the correct specs? [y/N]: " create_choice

        if [[ "$create_choice" =~ ^[Yy]$ ]]; then
            # Check if any Podman machine is currently running
            running_machine=$(echo "$machines_json" | jq -r '.[] | select(.Running == true) | .Name')

            if [[ -n "$running_machine" ]]; then
                echo "⚠️  Podman machine '$running_machine' is currently running."
                read -p "Would you like to stop it before creating a new one? [y/N]: " stop_choice

                if [[ "$stop_choice" =~ ^[Yy]$ ]]; then
                    echo "Stopping '$running_machine'..."
                    podman machine stop "$running_machine"
                else
                    echo "Cannot proceed while another machine is running. Exiting."
                    exit 1
                fi
            fi

            new_podman
            
            exit 0
        else
            echo "No machine selected and creation declined. Exiting."
            exit 0
        fi
    fi

    # Prompt in a loop until valid input
    while true; do
        echo
        echo "Select a Podman machine to use:"
        for i in "${!valid_names[@]}"; do
            display_number=$((i + 1))
            echo "$display_number. ${valid_names[$i]} - Memory: ${valid_memories[$i]}MB, CPUs: ${valid_cpus[$i]}"
        done

        create_option=$(( ${#valid_names[@]} + 1 ))
        exit_option=$(( ${#valid_names[@]} + 2 ))

        echo "$create_option. Create a new Podman machine"
        echo "$exit_option. None (exit)"

        read -p "Enter your choice [1-$exit_option]: " selection

        # Check input is numeric
        if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
            echo "Invalid input: please enter a number between 1 and $exit_option."
            continue
        fi

        # Handle "Create a new machine"
        if [[ "$selection" -eq "$create_option" ]]; then
            new_podman
            exit 0
        fi

        # Handle "None"
        if [[ "$selection" -eq "$exit_option" ]]; then
            echo "Exiting without selecting a Podman machine."
            exit 0
        fi

        # Convert to 0-based index and validate
        selection_index=$((selection - 1))
        if [[ "$selection_index" -lt 0 || "$selection_index" -ge ${#valid_names[@]} ]]; then
            echo "Invalid selection: please enter a number from 1 and $exit_option."
            continue
        fi

        # Valid selection
        chosen_machine="${valid_names[$selection_index]}"
        machine_running="${valid_statuses[$selection_index]}"

        echo "You selected: $chosen_machine"

        if [[ "$machine_running" != "true" ]]; then
            echo "Machine '$chosen_machine' is not running."
            read -p "Would you like to start it now? [y/N]: " start_choice
            if [[ "$start_choice" =~ ^[Yy]$ ]]; then
                echo "Starting Podman machine '$chosen_machine'..."
                podman machine start "$chosen_machine"
            else
                echo "Exiting without starting machine."
                exit 0
            fi
        fi
        # Optional: Activate it
        # podman machine use "$chosen_machine"
        break
    done
}

function cleanup {
    echo "Exiting Keyboard Interrupt or Error..."
    uninstall
}
trap cleanup ERR

# Parse Arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            help
            exit 0
            ;;
        -i|--install)
            install_dependencies
            init_cluster
            install_sumo
            exit 0
            ;;
        -n|--init)
            install_dependencies
            init_cluster
            exit 0
            ;;
        -m|--helm)
            install_sumo
            exit 0
            ;;
        -o|--output)
            output
            exit 0
            ;;
        -p|--purge)
            purge
            exit 0
            ;;
        -u|--uninstall)
            uninstall
            exit 0
            ;;
        -v|--version)
            version
            exit 0
            ;;
        *)
            echo "Invalid Option: $1"
            help
            ;;
    esac
    shift
done