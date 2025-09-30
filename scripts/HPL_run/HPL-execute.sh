#!/bin/bash

# Ensure the script is using Unix-style line endings
if grep -q $'\r' "$0"; then
    echo "Error: Script contains Windows-style line endings. Please convert to Unix-style line endings."
    exit 1
fi

# Function to initialize variables
initialize_variables() {
    if [ "$BLAS_IMPL" = "OpenBLAS" ]; then
        HPL_PATH="$HPL_DIR/bin/linux_OpenBLAS"
    else
        HPL_PATH="$HPL_DIR/bin/$BUILD_NAME"
    fi

    (( NUM_PROCESSES = NUM_OF_NODES * CORES_PER_NODE ))
    IFS=' ' read -ra RUNs <<< "$RUNs"
    IFS=' ' read -ra Ns <<< "$Ns"
    IFS=' ' read -ra NBs <<< "$NBs"
    IFS=' ' read -ra Ps <<< "$Ps"

    i=0
    BUILDS=()
    if [ "$BUILD_RUN" = "yes" ]; then
        while read -r line; do
            BUILDS[$i]=$(echo "$line" | cut -d "|" -f 3)
            i=$((i + 1))
        done < "$BUILD_INFO"
    else
        # Changed TOP_BUILDs to TOP_BUILDs, assuming it's a space-separated list in the config
        IFS=' ' read -ra BUILDS <<< "$TOP_BUILDs"
    fi

    if [ "$NUM_OF_NODES" -eq 1 ]; then
        HOSTFILEINFO=""
    else
        HOSTFILEINFO="-hostfile $HOSTFILE"
    fi
}

# Declared globally since it has to be seen outside the function
declare -A existingMeasurements

# Function to read existing measurements
read_existing_measurements() {
    if [ -f "$RESULTSFILE" ]; then
        while read -r line; do
            # Read the elements from the line with an extra column for build_name
            read -r build_name run _ nround nb p _ <<<"$line"

            # Store the elements in the associative array using build_name as part of the key
            existingMeasurements["$build_name,$run,$nround,$nb,$p"]=1¸
        done < "$RESULTSFILE"
    fi
}


# Calculated outside since NRound variable has to be seen outside the function
calculate_nround() {
    local N=$1
    local NB=$2
    python -c "import sys; n=int(sys.argv[1]); nb=int(sys.argv[2]); print(int(round(n / nb) * nb))" "$N" "$NB"
}

# Function to configure HPL
configure_hpl() {
    local BUILD_NAME=$1
    local RUN=$2
    local N=$3
    local NB=$4
    local P=$5

    OUTFILE="HPL_N$N-NB$NB-$RUN.out"

    CONFIG=$(cat <<- EOF
HPLinpack benchmark input file
Faculty of Electrical Engineering, Computer Science and Information Technology Osijek
$RESULTSDIR/$BUILD_NAME/$OUTFILE      output file name (if any)
file            device out (6=stdout,7=stderr,file)
1            # of problems sizes (N)
$NRound          Ns
1            # of NBs
$NB         NBs
0            PMAP process mapping (0=Row-,1=Column-major)
1            # of process grids (P x Q)
$P              Ps
$((NUM_PROCESSES / P)) Qs
16.0         threshold
1            # of panel fact
0 1 2        PFACTs (0=left, 1=Crout, 2=Right)
1            # of recursive stopping criterium
2 4          NBMINs (>= 1)
1            # of panels in recursion
2            NDIVs
1            # of recursive panel fact.
0 1 2        RFACTs (0=left, 1=Crout, 2=Right)
1            # of broadcast
0            BCASTs (0=1rg,1=1rM,2=2rg,3=2rM,4=Lng,5=LnM)
1            # of lookahead depth
0            DEPTHs (>=0)
2            SWAP (0=bin-exch,1=long,2=mix)
64           swapping threshold
0            L1 in (0=transposed,1=no-transposed) form
0            U  in (0=transposed,1=no-transposed) form
1            Equilibration (0=no,1=yes)
8            memory alignment in double (> 0)
EOF
)
    echo "$CONFIG" > "$HPL_PATH/HPL.dat"
}

# Function to run HPL
run_hpl() {
    local HPL_DIR=$1
    local COMMAND="mpiexec $MPIEXEC_BIND_TO -n $NUM_PROCESSES $HOSTFILEINFO $SPECIAL_FLAGS $HPL_PATH/xhpl"

    # Change to the HPL directory
    cd $HPL_DIR

    if [ "$WARMUP" = "yes" ]; then
        eval "$COMMAND"
        WARMUP="no"
    fi

    eval "$COMMAND"
}

# Function to handle throttling information
handle_throttling_info() {
    local before=()
    local after=()

    THROTTLING_INFO=$($SCRIPTS_DIR/throttling/get_throttling.sh "$CONFIG_FILE")
    IFS=' ' read -r -a before <<< "$THROTTLING_INFO"

    run_hpl "$HPL_PATH"

    THROTTLING_INFO=$($SCRIPTS_DIR/throttling/get_throttling.sh "$CONFIG_FILE")
    IFS=' ' read -r -a after <<< "$THROTTLING_INFO"

    if [ "${#before[@]}" -ne "${#after[@]}" ]; then
        echo "Error: Throttling values arrays do not have the same length."
        exit 1
    fi

    local differences=()
    for (( i = 0; i < ${#before[@]}; i++ )); do
        differences[i]=$(( after[i] - before[i] ))
    done

    THROTTLING_INFO=$(IFS=" "; echo "${differences[*]}")

    echo $THROTTLING_INFO
}

# Function to extract and format result line with fixed-width columns
extract_and_format_result_line() {
    local result_line=$1
    local build_name=$2
    local run=$3
    local n=$4
    local nb=$5
    local p=$6
    local q=$7
    local nround=$8
    local throttling_info=$9

    local hpl_param_string=""
    local hpl_execution_time=""
    local num_flops=""

    # Check if result_line is not empty and assign values
    if [ -n "$result_line" ]; then
        hpl_param_string=$(echo "$result_line" | awk '{print $1}')
        hpl_execution_time=$(echo "$result_line" | awk '{print $6}')
        num_flops=$(echo "$result_line" | awk '{print $NF}')
    fi

    # Provide dummy values if any variable is not calculated
    [ -z "$run" ] && run="NA"
    [ -z "$hpl_param_string" ] && hpl_param_string="NA"
    [ -z "$nround" ] && nround="0"
    [ -z "$nb" ] && nb="0"
    [ -z "$p" ] && p="0"
    [ -z "$q" ] && q="0"
    [ -z "$hpl_execution_time" ] && hpl_execution_time="0.0"
    [ -z "$num_flops" ] && num_flops="0.0"
    [ -z "$throttling_info" ] && throttling_info="NA"

    # Updated print format to match the number of variables (added 'build_name' column)
    printf "%-10s %-10s %-10s %-8s %-6s %-4s %-10s %-10s %-15s %-10s %-20s\n" \
        "$build_name" "$run" "$hpl_param_string" "$nround" "$nb" "$p" "$q" "$hpl_execution_time" "$num_flops" "$(date +%F' '%T)" "$throttling_info"
}

# Main function
main() {
    CONFIG_FILE="$1"  # Added: Get config file path from argument
    initialize_variables
    read_existing_measurements

    for BUILD_NAME in "${BUILDS[@]}"; do
        mkdir -p "$RESULTSDIR/$BUILD_NAME"
        for RUN in "${RUNs[@]}"; do
            #printf "%s %s " "$BUILD_NAME" "${RUN}${HPL_DAT_EXTRA_COLUMN}" >> "$RESULTSFILE"
            for N in "${Ns[@]}"; do
                for NB in "${NBs[@]}"; do
                    for P in "${Ps[@]}"; do
                        # Calculate NRound before checking
                        NRound=$(calculate_nround "$N" "$NB")

                        # Updated to check with build_name in the key
                        if [[ ${existingMeasurements["$BUILD_NAME,$RUN,$NRound,$NB,$P"]} ]]; then
                            echo "Skipping existing combination BUILD_NAME=$BUILD_NAME, RUN=$RUN, NRound=$NRound, NB=$NB, P=$P"
                            continue
                        fi

                        echo "$BUILD_NAME" "$RUN" "$N" "$NB" "$P" "$NRound"

                        configure_hpl "$BUILD_NAME" "$RUN" "$N" "$NB" "$P"
                        handle_throttling_info "$CONFIG_FILE"
                        RESULT_LINE=$(grep "WR" "$RESULTSDIR/$BUILD_NAME/HPL_N$N-NB$NB-$RUN.out")

                        formatted_result=$(extract_and_format_result_line "$RESULT_LINE" "$BUILD_NAME" "$RUN" "$N" "$NB" "$P" "$((NUM_PROCESSES / P))" "$NRound" "$THROTTLING_INFO")
                        echo "$formatted_result" >> "$RESULTSFILE"
                    done
                done
            done
        done
    done
}


main "$@"
