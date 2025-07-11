#!/bin/bash
CONFIG_FILE=$1
if [ -z "$2" ]; then
    HPL_DAT_EXTRA_COLUMN=""
else
    HPL_DAT_EXTRA_COLUMN="-$2"
fi
source $CONFIG_FILE
#Reduce throttle for the small cores so the HPL run with the big cores remains stable (done in executor.sh)
export PATH="$PATH:$HOME/mpich-install/bin/"

(( NUM_PROCESSES=$NUM_OF_NODES*$CORES_PER_NODE ))

# Get HPL params from a config file
IFS=' ' read -ra RUNs <<< "$RUNs"
IFS=' ' read -ra Ns <<< "$Ns"
IFS=' ' read -ra NBs <<< "$NBs"
IFS=' ' read -ra Ps <<< "$Ps"

# Build or parameter runs
i=0
BUILDS=()
if [ "$BUILD_RUN" = "yes" ]; then
    # Create an array of builds
    while read line; do
        BUILDS[$i]=$(echo $line | cut -d "|" -f 3)
        i=$(expr $i + 1)
    done < "$BUILD_INFO"
else
    # Use only one top performing build
    BUILDS=("$TOP_BUILDs")
fi

# Single node considerations (HOSTFILE empty means single node)
if [ "$NUM_OF_NODES" -eq 1 ]; then
    HOSTFILEINFO=""
else
    HOSTFILEINFO="-hostfile $HOSTFILE"
fi

# This part is necessary if the results file already contains some results and we want to continue
# Step 1: Read and store combinations
declare -A existingMeasurements
while read line; do
    read -r element1 _ element3 element4 element5 _ <<<"$line"
    existingMeasurements["$element1,$element3,$element4,$element5"]=1
done < "$RESULTSFILE"


for BUILD_NAME in "${BUILDS[@]}"; do
    # ATLAS/OpenBLAS considerations
    if [ "$BLAS_IMPL" = "OpenBLAS" ]; then
        # Use the OpenBLAS directory
        HPL_PATH="$HPL_DIR_OPENBLAS/bin/linux_OpenBLAS"
    else
        # Use the default HPL directory
        HPL_PATH="$HPL_DIR/bin/$BUILD_NAME"
    fi

    mkdir -p "$RESULTSDIR/$BUILD_NAME"
    for RUN in "${RUNs[@]}"; do
        printf "%s %s " "$BUILD_NAME" "${RUN}${HPL_DAT_EXTRA_COLUMN}" >> "$RESULTSFILE" #not using echo, because avoiding newline
        for N in "${Ns[@]}"; do
            for NB in "${NBs[@]}"; do
                NRound=$(python -c "print(int(round($N / $NB)* $NB))")
                echo "RUN=$RUN N=$N NB=$NB NRound=$NRound"
                for P in "${Ps[@]}"; do
                    # Step 2: Check if combination exists
                    if [[ ${existingMeasurements["$RUN,$NRound,$NB,$P"]} ]]; then
                        echo "Skipping existing combination RUN=$RUN, NRound=$NRound, NB=$NB, P=$P"
                        continue
                    fi
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
$(expr $NUM_PROCESSES / $P) Qs
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

EXTRAE_CONFIG=$(cat <<- EOF
<?xml version='1.0'?>
 
<trace enabled="yes"
  home="/opt/extrae"
  initial-mode="detail"
  type="paraver"
>
 
<mpi enabled="yes">
  <counters enabled="yes" />
  <comm-calls enabled="yes" />
</mpi>
  
<storage enabled="yes">
  <final-directory enabled="yes">$HOME/traces/$BUILD_NAME/HPL_N$N-NB$NB-P$P-$RUN</final-directory>
</storage>

</trace>
EOF
)
		    echo "$EXTRAE_CONFIG" > "$HPL_PATH/extrae.xml"
	 	    rsync -avP "$HPL_PATH/extrae.xml" "odroid11:$HPL_PATH/extrae.xml"
		    rsync -avP "$HPL_PATH/extrae.xml" "odroid12:$HPL_PATH/extrae.xml"
		    rsync -avP "$HPL_PATH/extrae.xml" "odroid13:$HPL_PATH/extrae.xml"
                    cd $HPL_PATH

                    #sleep 0.01

                    # Record throttling info before
                    THROTTLING_INFO=$($SCRIPTS_DIR/throttling/get_throttling.sh $CONFIG_FILE)
                    IFS=' ' read -r -a THROTTLING_INFO_BEFORE <<< "$THROTTLING_INFO"

                    # Construct the command
		    TRACE_SCRIPT_PATH="/home/zdravak/run_extrae.sh"
                    COMMAND="mpiexec -n $NUM_PROCESSES $HOSTFILEINFO $SPECIAL_FLAGS $TRACE_SCRIPT_PATH $HPL_PATH/xhpl"

                    # do a warmup run if necessary
                    if [ "$WARMUP" = "yes" ]; then
                        eval "${COMMAND}"
                        WARMUP="no"
                    fi
                    # Running an instance of HPL
                    #echo ${COMMAND}
                    eval "${COMMAND}"
                    RESULT_LINE=$(cat $RESULTSDIR/$BUILD_NAME/$OUTFILE | grep "WR")
                    
                    # Throttling info after running an instance of HPL
                    THROTTLING_INFO=$($SCRIPTS_DIR/throttling/get_throttling.sh $CONFIG_FILE)
                    IFS=' ' read -r -a THROTTLING_INFO_AFTER <<< "$THROTTLING_INFO"

                    # Check if both throttling arrays have the same length
                    if [ ${#THROTTLING_INFO_BEFORE[@]} -ne ${#THROTTLING_INFO_AFTER[@]} ]; then
                        echo "Error: Throttling values arrays do not have the same length."
                        exit 1
                    fi

                    # Initialize an empty array to store the results
                    THROTTLING_INFO_ARRAY=()

                    # Calculate the difference in throttling parameters
                    for (( i=0; i<${#THROTTLING_INFO_BEFORE[@]}; i++ )); do
                        THROTTLING_INFO_ARRAY[i]=$((${THROTTLING_INFO_AFTER[i]} - ${THROTTLING_INFO_BEFORE[i]}))
                    done

                    # Convert the result array back to a string
                    THROTTLING_INFO=$(IFS=" "; echo "${THROTTLING_INFO_ARRAY[*]}")


                    echo "$RUN $RESULT_LINE $(date +%F' '%T) $THROTTLING_INFO" >> "$RESULTSFILE"
                done
            done
        done
    done
done
#Delay the end if another node is running a job spearately, and for the next job we need both
#sleep 1h
