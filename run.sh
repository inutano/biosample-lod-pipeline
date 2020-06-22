#!/bin/bash

### Env Vars
WORKDIR_BASE="${HOME}/work"

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
  printf "$STARTCOLOR%b$ENDCOLOR" "[$(date +'%Y/%m/%d %H:%M:%S')] $1";
}

#
# Setup working directory and log file
#
setup() {
  WORKDIR="${WORKDIR_BASE}/biosample-lod/$(date +%Y%m%d-%H%M)"
  mkdir -p ${WORKDIR}

  LOGFILE="${WORKDIR}/biosample-lod.log"
  touch ${LOGFILE}

  cd ${WORKDIR}
  message "Setup working directory: ${WORKDIR}\n"
  message "Setup log file: ${LOGFILE}\n"
}

#
# Test ttl generator
#
test_ttl_generator() {
  local item_name=${1}
  local wdir=${2}

  num_ttl_files=$(ls ${wdir}/*ttl | wc -l | awk '$0=$1')
  num_lines=$(wc -l ${wdir}/*ttl | sort -n | head)

  if [[ -z ${num_ttl_files} ]]; then
    message "generate_${item_name}: FAILED\n" "danger" | tee -a ${LOGFILE}
    message "  number of files: ${num_ttl_files}\n" | tee -a ${LOGFILE}
    message "  number of lines (smallest 10 files):\n${num_lines}\n" | tee -a ${LOGFILE}
    FAILED+=(${item_name})
  else
    message "generate_${item_name}: SUCCESS\n" "info" | tee -a ${LOGFILE}
    message "  number of files: ${num_ttl_files}\n" | tee -a ${LOGFILE}
    message "  number of lines (smallest 10 files):\n${num_lines}\n" | tee -a ${LOGFILE}
  fi
}

#
# Craete BioSample RDF: Run bs2ld via biosample.run.sh with GridEngine
#
generate_biosample() {
  local wdir=${WORKDIR}/biosample
  git clone 'git://github.com/inutano/biosample_jsonld' -b 'v1.9' --depth 1 ${wdir}
  cd ${wdir}
  run_biosample=$(bash ./sh/biosample.run.sh ${wdir})
  echo "${wdir}/ttl"
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
  git clone 'git://github.com/inutano/insdc-accessions' -b 'v1.1' --depth 1 ${wdir}
  cd ${wdir}
  run_accessions=$(bash ./bin/accessions-ttl-generator-split ${wdir})
  echo "${wdir}/ttl"
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
  git clone 'git://github.com/inutano/ld-sra' -b 'v1.2' --depth 1 ${wdir}
  cd ${wdir}
  run_experiment=$(bash ./sh/exp.run.sh ${wdir})
  echo "${wdir}/ttl"
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
  git clone 'git://github.com/inutano/ttl2virtuosodb' -b 'v0.5.0' --depth 1 ${wdir}
  cd ${wdir}

  mkdir -p "${wdir}/data"
  find ${WORKDIR} -name 'ttl' -type d | while read ttl_dir; do
    find "${ttl_dir}" -name '*ttl' -type f | xargs mv -t "${wdir}/data"
  done

  turtle_load=$(./ttl2virtuosodb load)

  echo ${wdir}/db/virtuoso.db
}

test_load_to_virtuoso() {
  local db_path=$(load_to_virtuoso)
  local db_size=$(ls -l ${db_path} | awk '{ print $5 }')
  if [[ ${db_size} -lt 70000000 ]]; then
    message "load_to_virtuoso: FAILED\n" "danger" | tee -a ${LOGFILE}
    message "  db size: ${db_size}\n" | tee -a ${LOGFILE}
    FAILED+=(load_to_virtuoso)
  else
    message "load_to_virtuoso: SUCCESS\n" "info" | tee -a ${LOGFILE}
    message "  db size: ${db_size}\n" | tee -a ${LOGFILE}
  fi
}

#
# Publish virtuoso.db data file on the http-reachable storage
#
publish_virtuoso_db() {
  local db_file="${WORKDIR}/virtuoso/virtuoso.db"
  local dest_path="${WORKDIR}/dest"
  echo "https://dbcls.rois.ac.jp"
}

test_publish_virtuoso_db() {
  local dest_path=$(publish_virtuoso_db)
  local dest_http_status=$(curl -s -o /dev/null -LI ${dest_path} -w '%{http_code}\n')
  local dest_file_size=$(curl -s -o /dev/null -LI ${dest_path} -w '%{size_download}\n')
  if [[ ${dest_http_status} != 200 ]]; then
    message "publish_virtuoso_db: FAILED\n" "danger" | tee -a ${LOGFILE}
    message "  http status:      ${dest_http_status}\n" | tee -a ${LOGFILE}
    message "  remote file size: ${dest_file_size}\n" | tee -a ${LOGFILE}
    FAILED+=(publish_virtuoso_db)
  else
    message "mirror_virtuoso_db: SUCCESS\n" "info" | tee -a ${LOGFILE}
    message "  remote file size: ${dest_file_size}\n" | tee -a ${LOGFILE}
  fi
}

#
# Generalfunction
#
test() {
  setup
  test_generate_biosample
  test_generate_accessions
  test_generate_experiment
  test_load_to_virtuoso
  test_publish_virtuoso_db

  if [[ ${#FAILED[@]} -ne 0 ]]; then
    for i in "${FAILED[@]}"; do
      message "Test ${i} failed.\n" "danger" | tee -a ${LOGFILE}
    done
    exit 1
  else
    message "Passed all test.\n" "info" | tee -a ${LOGFILE}
  fi
}

main() {
  setup
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