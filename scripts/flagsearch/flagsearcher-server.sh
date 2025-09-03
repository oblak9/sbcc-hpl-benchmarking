#!/bin/bash

# Function to check the number of parameters
check_parameters() {
  if [ "$#" -ne 1 ]; then
    echo "Error: You must provide exactly one parameter."
    echo "Usage: $0 <config-file>"
    exit 1
  fi
}

# Function to check if the config file exists
check_config_file() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file '$CONFIG_FILE' not found."
    exit 1
  fi
}

# Function to initialize variables
initialize_variables() {
  source $CONFIG_FILE
  BUILD_NUM=1
  BUILD_INFO_FLAGS="${BUILD_INFO//.txt/-flags.txt}"
  FLAGSEARCH_RUN="$FLAGSEARCH_DIR/flagsearcher-client.sh $CONFIG_FILE"
  DEVICES=()
  master_node_number="${MASTER_DEVICE//[!0-9]}"
  for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
    host_number=$(printf "%02d" "$i")
    DEVICES+=("${MASTER_DEVICE//[0-9]}"$host_number)
  done
}

# Function to clean previous flagsearched builds info file and wait files
clean_previous_builds() {
  rm $BUILD_INFO_FLAGS
  rm "$WAIT_DIR/fs-*-done.txt"
}

# Function to run flagsearches on client devices
run_flagsearches() {
  for current_host in "${DEVICES[@]:1}"; do
     echo "Running flagsearches on $current_host and sending the results to $MASTER_DEVICE"
     ssh $current_host -- tmux new-session -d -s "flagsearch" -- "$FLAGSEARCH_RUN"
  done
  eval ${FLAGSEARCH_RUN}
}

# Function to wait for clients to finish flagsearching
wait_for_clients() {
  waitcommand="$SCRIPTS_DIR/wait/waitScript.sh"
  for current_host in "${DEVICES[@]:1}"; do
     waitcommand+=" \"$WAIT_DIR/fs-${current_host}-done.txt\""
  done
  eval "$waitcommand"
}

# Function to process build information
process_build_information() {
  while read line; do
    BUILD_NAME=$(echo $line | cut -d "|" -f 3)
    BUILD_FLAGSEARCH_DIR=$HOME/atlas-$BUILD_NAME/tune/blas/gemm
    echo $BUILD_NAME
    for current_host in "${DEVICES[@]:1}"; do
      scp -r $USER@$current_host:$BUILD_FLAGSEARCH_DIR/results/* $BUILD_FLAGSEARCH_DIR/results/
    done
    echo =========================
    extract_mflops_and_flags
    create_new_build_file
    BUILD_NUM=$(expr $BUILD_NUM + 1)
  done < $BUILD_INFO
}

# Function to extract MFLOPS and FLAGS
extract_mflops_and_flags() {
  BEST=0
  BEST_TEMP=0
  BEST_FLAGS=""
  BEST_OPT_FLAGS=""
  for current_host in "${DEVICES[@]}"; do
    for j in {0..4}; do
      BEST_TEMP=$(grep 'BEST FLAGS GIVE MFLOP=' $BUILD_FLAGSEARCH_DIR/results/fs_${current_host}_${j}.txt | sed 's/^.*=//' | cut -d'(' -f1 | sed 's/\.//')
      echo $BUILD_NAME : $BEST_TEMP vs $BEST
      if [ $BEST_TEMP -gt $BEST ]; then
        BEST=$BEST_TEMP
        BEST_FLAGS=$(tail -n 2 $BUILD_FLAGSEARCH_DIR/results/fs_${current_host}_${j}.txt | grep -v == | grep . | sed 's/^ *//g' | sed "s/'//g")
      fi
    done
  done
  get_optimization_option
}

# Function to get the optimization option from the best flags
get_optimization_option() {
  search_string="-O"
  extra_character=""
  found_string=""
  if [[ $BEST_FLAGS == *"$search_string"* ]]; then
    found_string="${BEST_FLAGS#*$search_string}"
    extra_character="${found_string:0:1}"
    BEST_OPT_FLAGS="$search_string$extra_character"
    BEST_FLAGS=${BEST_FLAGS/$BEST_OPT_FLAGS /}
  fi
}

# Function to create a new build file
create_new_build_file() {
  echo "$BUILD_NUM|20|$BUILD_NAME-flags|$ATLAS_CORE_FLAGS $ATLAS_TIDS $ATLAS_EXTRA_FLAGS \"$BEST_OPT_FLAGS $BEST_FLAGS\"|$BEST_OPT_FLAGS|$BEST_FLAGS|$BEST" >> $BUILD_INFO_FLAGS
}

# Function to send the new build file to all clients
send_build_file_to_clients() {
  for device in "${DEVICES[@]}"; do
    scp $OPTIMIZATION_FLAGS_FILE $USER@$device:$FLAGSEARCH_DIR
  done
}

# Function to run executor
run_executor() {
  $SCRIPTS_DIR/wait/executor.sh $SCRIPTS_DIR/builds_info/builds_info_flags.txt
}

# Main function to orchestrate the script execution
main() {
  check_parameters "$@"
  CONFIG_FILE=$1
  check_config_file
  initialize_variables
  clean_previous_builds
  run_flagsearches
  wait_for_clients
  process_build_information
  send_build_file_to_clients
  #run_executor
}

# Execute the main function with all provided arguments
main "$@"



# #!/bin/bash

# # Check the number of parameters
# if [ "$#" -ne 1 ]; then
#   echo "Error: You must provide exactly one parameter."
#   echo "Usage: $0 <config-file>"
#   exit 1
# fi

# # The parameter is given
# CONFIG_FILE=$1

# # Check if the config file exists
# if [ ! -f "$CONFIG_FILE" ]; then
#   echo "Error: Config file '$CONFIG_FILE' not found."
#   exit 1
# fi

# source $CONFIG_FILE

# # Initialize build iterator to 1
# BUILD_NUM=1

# # Create a filename for the oputput builds info flags file according to the original one
# BUILD_INFO_FLAGS="${BUILD_INFO//.txt/-flags.txt}"

# # Create a client run
# FLAGSEARCH_RUN="$FLAGSEARCH_DIR/flagsearcher-client.sh $CONFIG_FILE"

# # Create an array of devices
# DEVICES=()
# master_node_number="${MASTER_DEVICE//[!0-9]}"
# for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
#   host_number=$(printf "%02d" "$i")
#   DEVICES+=("${MASTER_DEVICE//[0-9]}"$host_number)
# done

# # Remove any prevoius flagsearched builds infomration
# rm $BUILD_INFO_FLAGS

# # Clean the flagsearch wait files
# rm "$WAIT_DIR/fs-*-done.txt"

# # Run flagsearches ONLY on client devices (can be done independently)
# for current_host in "${DEVICES[@]:1}"; do
#    echo "Running flagsearches on $current_host and sending the results to $MASTER_DEVICE"
#    ssh $current_host -- tmux new-session -d -s "flagsearch" -- "$FLAGSEARCH_RUN"
#    #ssh $current_host "$FLAGSEARCH_RUN"
# done
# #Do it also on the $MASTER_DEVICE
# eval ${FLAGSEARCH_RUN}

# # Wait for all the clients to finish flagsearching for all builds (master has to finish flagsearching in order to come to this code, so no need to wait for him)
# waitcommand="$SCRIPTS_DIR/wait/waitScript.sh"
# for current_host in "${DEVICES[@]:1}"; do
#    waitcommand+=" \"$WAIT_DIR/fs-${current_host}-done.txt\""
# done
# # Run the constructed waitcommand
# eval "$waitcommand"

# while read line; do
# BUILD_NAME=$(echo $line | cut -d "|" -f 3)
# BUILD_FLAGSEARCH_DIR=$HOME/atlas-$BUILD_NAME/tune/blas/gemm

# echo $BUILD_NAME

# #Collect all the files from clients for a single build (initiated by the server so it does not interfere with the server performance during flagsearching)
# for current_host in "${DEVICES[@]:1}"; do
#   scp -r $USER@$current_host:$BUILD_FLAGSEARCH_DIR/results/* $BUILD_FLAGSEARCH_DIR/results/
# done

# echo =========================
# #Extract MFLOPS and FLAGS
# BEST=0
# BEST_TEMP=0
# BEST_FLAGS=""
# BEST_OPT_FLAGS=""
# #get all the results from all the hosts
# for current_host in "${DEVICES[@]}"; do
#   #For all the fs_d_ files
#   for j in {0..4}; do
#     BEST_TEMP=$(grep 'BEST FLAGS GIVE MFLOP=' $BUILD_FLAGSEARCH_DIR/results/fs_${current_host}_${j}.txt | sed 's/^.*=//' | cut -d'(' -f1 | sed 's/\.//')
#     echo $BUILD_NAME : $BEST_TEMP vs $BEST
#     if [ $BEST_TEMP -gt $BEST ]
#         then
#         BEST=$BEST_TEMP
#         BEST_FLAGS=$(tail -n 2 $BUILD_FLAGSEARCH_DIR/results/fs_${current_host}_${j}.txt | grep -v == | grep . | sed 's/^ *//g' | sed "s/'//g")
#     fi
#   done
# done

# #Get the optimization option from the found best flags
# search_string="-O"
# extra_character=""
# found_string=""

# if [[ $BEST_FLAGS == *"$search_string"* ]]; then
#   # Extract the found string plus an extra character
#   found_string="${BEST_FLAGS#*$search_string}"
#   extra_character="${found_string:0:1}"
#   BEST_OPT_FLAGS="$search_string$extra_character"
#   BEST_FLAGS=${BEST_FLAGS/$BEST_OPT_FLAGS /}
# fi

# #create a new file for the builds information
# echo "$BUILD_NUM|20|$BUILD_NAME-flags|$ATLAS_CORE_FLAGS $ATLAS_TIDS $ATLAS_EXTRA_FLAGS \"$BEST_OPT_FLAGS $BEST_FLAGS\"|$BEST_OPT_FLAGS|$BEST_FLAGS|$BEST" >> $BUILD_INFO_FLAGS

# BUILD_NUM=$(expr $BUILD_NUM + 1)
# done < $BUILD_INFO

# #Send a new build file to all the clients
# for device in "${DEVICES[@]}"
# do
#   scp $OPTIMIZATION_FLAGS_FILE $USER@$device:$FLAGSEARCH_DIR
# done

# #RUN EXECUTOR
# #$SCRIPTS_DIR/wait/executor.sh $SCRIPTS_DIR/builds_info/builds_info_flags.txt
