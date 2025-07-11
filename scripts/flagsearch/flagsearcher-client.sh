#!/bin/bash

# Function to initialize variables
initialize_variables() {
  CONFIG_FILE=$1
  source $CONFIG_FILE
}

# Function to process each build line
process_build_line() {
  BUILD_NAME=$(echo $line | cut -d "|" -f 3)
  BUILD_FLAGS=$(echo $line | cut -d "|" -f 6)
  BUILD_FLAGSEARCH_DIR="$HOME/atlas-$BUILD_NAME/tune/blas/gemm"
  GCCFLAGS=$HOME/atlas-$BUILD_NAME/tune/blas/gemm/gccflags.txt
  GCCFLAGS_FILE=$HOME/atlas-$BUILD_NAME/tune/blas/gemm/gccflags-generated.txt
}

# Function to clean and prepare directory
prepare_directory() {
  cd $BUILD_FLAGSEARCH_DIR
  rm -r results
  mkdir results
}

# Function to generate initial flags
generate_initial_flags() {
  MAKE="make xmmflagsearch -B"
  GENERATE="./xmmflagsearch -f gcc"
  REMOVE_PREVIOUS_GCCFLAGS="rm $GCCFLAGS_FILE"
  eval ${MAKE}
  eval ${GENERATE}
  eval ${REMOVE_PREVIOUS_GCCFLAGS}
}

# Function to edit gccflags.txt
edit_gccflags() {
  echo $BUILD_FLAGS > $GCCFLAGS_FILE

  COMMENT_LINE="Flags to probe"
  first_line=true
  string_Os="Os"
  next_line=false
  number_of_flags=0

  while IFS= read -r gccflagsline; do
    if [ "$first_line" = true ]; then
      first_line=false
      continue
    fi

    if [ "$next_line" = true ]; then
      next_line=false
      number_of_flags=$(expr $gccflagsline + $(wc -l < "$OPTIMIZATION_FLAGS_FILE"))
      echo "$number_of_flags" >> $GCCFLAGS_FILE
      continue
    fi

    if [[ $gccflagsline == *"$string_Os"* ]]; then
      next_line=true
    fi

    if [[ $gccflagsline == *"$COMMENT_LINE"* ]]; then
      cat $OPTIMIZATION_FLAGS_FILE >> $GCCFLAGS_FILE
    fi

    echo "$gccflagsline" >> $GCCFLAGS_FILE
  done < "$GCCFLAGS"
}

# Function to run flagsearch
run_flagsearch() {
  for i in {0..4}; do
    echo $BUILD_NAME $i
    echo $($TASKSET ./xmmflagsearch -p d -f $GCCFLAGS_FILE 2>&1 > $BUILD_FLAGSEARCH_DIR/results/fs_$(hostname)_$i.txt)
  done
}

# Function to signal completion
signal_completion() {
  touch fs-$(hostname)-done.txt
  scp fs-$(hostname)-done.txt $USER@$MASTER_DEVICE:$WAIT_DIR
}

# Main function to orchestrate the script execution
main() {
  initialize_variables "$@"
  while read line; do
    process_build_line
    prepare_directory
    generate_initial_flags
    edit_gccflags
    run_flagsearch
  done < $BUILD_INFO
  signal_completion
}

# Execute the main function with all provided arguments
main "$@"
