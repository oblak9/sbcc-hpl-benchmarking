#!/bin/bash

LOG_FILE=$(pwd)/log-hpl-build.txt                               # Local logs
touch "$LOG_FILE" 

# Load two plaintext KEY=VALUE configs and expand ${VARS} after overrides.
# - Configs must use ${VAR} (not bare $VAR) for references.
# - No external deps, no eval.

load_cfg() {
  local base_cfg="$1" platform_cfg="$2"

  # Read KEY=VALUE lines from both files into an associative array (platform overrides base).
  declare -A CFG=()
  _read_cfg() {
    local f="$1" line key val
    [ -f "$f" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"                                   # strip comments
      line="${line#"${line%%[![:space:]]*}"}"              # ltrim
      line="${line%"${line##*[![:space:]]}"}"              # rtrim
      [ -z "$line" ] && continue
      [[ "$line" != *"="* ]] && continue
      key=${line%%=*}; val=${line#*=}
      key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
      val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
      CFG["$key"]="$val"
    done < "$f"
  }

  _read_cfg "$base_cfg"
  _read_cfg "$platform_cfg"

  # Export RAW values first so variables can reference each other (and env like SCRIPTS_DIR/HOME).
  local k
  for k in "${!CFG[@]}"; do export "$k=${CFG[$k]}"; done

  # Late-expand ${VAR} and $VAR safely (no command eval). Two passes for chained refs.
  local v name repl pass
  for pass in 1 2; do
    for k in "${!CFG[@]}"; do
      v=${!k}
      while [[ $v =~ (\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)) ]]; do
        name="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
        repl="${!name-}"
        v="${v//\$\{$name\}/${repl}}"
        v="${v//\$$name/${repl}}"
      done
      printf -v "$k" '%s' "$v"
      export "$k"
    done
  done
}

# Load configs if a config file is passed
if [ $# -eq 1 ]; then
  config_file="$1"
  base_config="${SCRIPTS_DIR}/config-files/base-config.txt"
  load_cfg "$base_config" "$config_file"
fi

# Variable declarations and exports (group all constants here)
hostname=$(hostname)
NUM_OF_BUILDS=$(grep -v '^\s*$' "$BUILD_INFO" | wc -l)  # Added for consistency

echo "DEBUG: NUM_OF_BUILDS: $NUM_OF_BUILDS" >> "$LOG_FILE"

# Function to create an array of devices
create_devices_array() {
  DEVICES=()
  master_node_number="${MASTER_DEVICE//[!0-9]}"
  for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
    host_number=$(printf "%02d" "$i")
    DEVICES+=("${MASTER_DEVICE//[0-9]}"$host_number)
  done

  echo -e "Device array created:\n'${DEVICES[*]}'. \n"  >> "$LOG_FILE"
}

# Function to determine node numbers (added for consistency)
determine_node_numbers() {
  # Validate DEVICES array
  if [[ ${#DEVICES[@]} -eq 0 ]]; then
    echo "ERROR: DEVICES array is empty. Ensure it is set in the parent script (e.g., executor.sh)."
    exit 1
  fi

  # Find the current node's ordinal number in the DEVICES array
  current_node_ord_number=""
  for i in "${!DEVICES[@]}"; do
    if [[ "${DEVICES[$i]}" == "$hostname" ]]; then
      current_node_ord_number=$i
      break
    fi
  done

  # Validate that the current hostname was found
  if [[ -z "$current_node_ord_number" ]]; then
    echo "ERROR: Current hostname ($hostname) not found in DEVICES array: ${DEVICES[*]}"
    exit 1
  fi

  # Total number of nodes is the length of the DEVICES array
  total_nodes=${#DEVICES[@]}
}

# Function to process each build
process_build() {
  local build_line=$1
  local build_name=$(echo "$build_line" | cut -d "|" -f 3)
  local build_opt_flags=$(echo "$build_line" | cut -d "|" -f 5)
  local build_flags=$(echo "$build_line" | cut -d "|" -f 6)

  # Check if the node has the specific ATLAS build
  if [[ ! -f "${ATLAS_STORAGE}/${build_name}/lib/libcblas.a" || ! -f "${ATLAS_STORAGE}/${build_name}/lib/libatlas.a" ]]; then
    echo "Error: Required libraries (${ATLAS_STORAGE}/${build_name}/lib/libcblas.a and ${ATLAS_STORAGE}/${build_name}/lib/libatlas.a) not built for $build_name, skipping." >> "$LOG_FILE"
    return
  fi

  cd "$HPL_DIR" || { echo "Failed to change directory to $HPL_DIR"; exit 1; }

  # Remove the existing Makefile if it exists
  rm -f "Make.$build_name"

  # Copy the generic makefile and make the necessary changes
  cp "$HPL_GENERIC_MAKEFILE" "Make.$build_name"
  sed -i "s/buildname/$build_name/g" "Make.$build_name"
  sed -i "s/gccflags/$build_opt_flags $build_flags/g" "Make.$build_name"

  # Update the CC line to use the MPICH directory from the config file
  sed -i "s|^CC *=.*|CC = $MPICH_DIR/bin/mpicc|g" "Make.$build_name"

  # Update the TOPdir line to use the HPL directory from the config file
  sed -i "s|^TOPdir *=.*|TOPdir = $HPL_DIR|g" "Make.$build_name"

  # Build the project
  echo "${hostname} is building HPL for $build_name build" >> "$LOG_FILE"
  make arch="$build_name" -B
}

# Function to create and send the "done" file
create_and_send_done_file() {
  local done_file="$HOME/hpl-build-${hostname}-done.txt"
  touch "$done_file" || { echo "Error: Failed to create done file."; exit 1; }
  local scp_cmd="scp \"$done_file\" \"$USER@$MASTER_DEVICE:$WAIT_DIR/hpl-build-${hostname}-done.txt\""
  echo -e "SCP line to send done files: \n${scp_cmd} \n" >> "$LOG_FILE"
  eval "$scp_cmd" || { echo "Error: Failed to send done file."; exit 1; }
  rm "$done_file" || { echo "Error: Failed to remove done file."; exit 1; }
}

create_devices_array
determine_node_numbers  # Added for consistency

for ((i=current_node_ord_number+1; i<=NUM_OF_BUILDS; i+=total_nodes)); do
  build_line=$(sed -n "${i}p" "$BUILD_INFO")
  [ -z "$build_line" ] && continue
  echo "${hostname} is building line ${i} of HPL build: $build_line" >> "$LOG_FILE"
  process_build "$build_line" || echo "WARNING: Failed to process build: $build_line" >> "$LOG_FILE"

  # Derive the build's name
  build_name="$(echo "$build_line" | cut -d '|' -f 3)"
  BUILD_DIR="${HPL_DIR}/bin/${build_name}"
  if [ -d "$BUILD_DIR" ]; then
    echo "BUILD_DIR exists: $BUILD_DIR" >> "$LOG_FILE"
    ls -la "$BUILD_DIR" >> "$LOG_FILE"  # Log contents for verification
  else
    echo "WARNING: expected $BUILD_DIR not found" >> "$LOG_FILE"
    continue
  fi
done

create_and_send_done_file
