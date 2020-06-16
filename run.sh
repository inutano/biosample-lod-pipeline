#!/bin/bash

### Env Vars

# working directory
WORKDIR="/data1/inutano/work/biosample-lod/$(date +%Y%m%d-%H%M)"
mkdir -p ${WORKDIR}
cd ${WORKDIR}

# log file
LOGFILE="${WORKDIR}/biosample-lod.log"
touch ${LOGFILE}

### Functions

message() {
  case $2 in
    green|success)
      COLOR="92m";
      ;;
    yellow|warning)
      COLOR="93m";
      ;;
    red|danger)
      COLOR="91m";
      ;;
    blue|info)
      COLOR="96m";
      ;;
    *)
      COLOR="0m"
      ;;
  esac
  STARTCOLOR="\e[$COLOR";
  ENDCOLOR="\e[0m";
  printf "$STARTCOLOR%b$ENDCOLOR" "$1";
}

#
# Test ttl generator
#
test_ttl_generator() {
  local item_name=${1}
  local wdir=${2}

  ttl_files=$(ls ${wdir}/*ttl)
  num_lines=$(wc -l ${wdir}/*ttl)

  if [[ -z ${ttl_files} ]]; then
    message "generate_${item_name}: FAILED\n" "danger"
    message "  files: ${ttl_files}\n"
    message "  number of lines: ${num_lines}\n"
    FAILED+=(${item_name})
  else
    message "generate_${item_name}: SUCCESS\n" "info"
  fi
}

#
# Craete BioSample RDF: Run bs2ld via biosample.run.sh with GridEngine
#
generate_biosample() {
  local wdir=${WORKDIR}/biosample
  mkdir -p ${wdir}
  #touch ${wdir}/biosample.ttl
  echo ${wdir}
}

test_generate_biosample() {
  local wdir=$(generate_biosample)
  test_ttl_generator "biosample" ${wdir}
}

#
# Create SRA accessions RDF: Run accessions-ttl-generator-split
#
generate_accessions() {
  local wdir=${WORKDIR}/accessions
  mkdir -p ${wdir}
  #touch ${wdir}/accessions.ttl
  echo ${wdir}
}

test_generate_accessions() {
  local wdir=$(generate_accessions)
  test_ttl_generator "accessions" ${wdir}
}

#
# Create SRA Experiment RDF: Run xml2ttl via exp.run.sh with GridEngine
#
generate_experiment() {
  local wdir=${WORKDIR}/experiment
  mkdir -p ${wdir}
  #touch ${wdir}/experiment.ttl
  echo ${wdir}
}

test_generate_experiment() {
  local wdir=$(generate_experiment)
  test_ttl_generator "experiment" ${wdir}
}

#
# Load to Virtuoso to create virtuoso.db
#
load_to_virtuoso() {
  local wdir=${WORKDIR}/virtuoso
  mkdir -p ${wdir}
  virtuoso_db_path=${wdir}/virtuoso.db
  #touch ${virtuoso_db_path}
  echo ${virtuoso_db_path}
}

test_load_to_virtuoso() {
  local db_path=$(load_to_virtuoso)
  local db_size=$(ls -l ${db_path} | awk '{ print $5 }')
  if [[ ${db_size} -lt 70000000 ]]; then
    message "load_to_virtuoso: FAILED\n" "danger"
    message "  db size: ${db_size}\n"
    FAILED+=(load_to_virtuoso)
  else
    message "load_to_virtuoso: SUCCESS\n" "info"
    message "  db size: ${db_size}\n"
  fi
}

#
# Publish virtuoso.db data file on the http-reachable storage
#
publish_virtuoso_db() {
  local db_file="${WORKDIR}/virtuoso/virtuoso.db"
  local dest_path="${WORKDIR}/dest"
  # scp ${db_file} ${dest_path}
  echo ${dest_path}
}

test_publish_virtuoso_db() {
  local dest_path=$(publish_virtuoso_db)
  local dest_http_status=$(curl -s -o /dev/null -LI ${dest_path} -w '%{http_code}\n')
  local dest_file_size=$(curl -s -o /dev/null -LI ${dest_path} -w '%{size_download}\n')
  if [[ ${dest_http_status} != 200 ]]; then
    message "publish_virtuoso_db: FAILED\n" "danger"
    message "  http status:      ${dest_http_status}\n"
    message "  remote file size: ${dest_file_size}\n"
    FAILED+=(publish_virtuoso_db)
  else
    message "mirror_virtuoso_db: SUCCESS\n" "info"
    message "  remote file size: ${dest_file_size}\n"
  fi
}

#
# Generalfunction
#
test() {
  test_generate_biosample
  test_generate_accessions
  test_generate_experiment
  test_load_to_virtuoso
  test_publish_virtuoso_db

  if [[ ${#FAILED[@]} -ne 0 ]]; then
    for i in "${FAILED[@]}"; do
      message "Test ${i} failed.\n" "danger"
    done
    exit 1
  else
    message "Passed all test.\n" "info"
  fi
}

main() {
  generate_biosample
  generate_accessions
  generate_experiment
  load_to_virtuoso
  publish_virtuoso_db
}

### Exec
case ${1} in
  test)
    test
    ;;
  *)
    main
    ;;
esac