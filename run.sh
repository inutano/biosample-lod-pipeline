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

#
# Test ttl generator
#
test_ttl_generator() {
  local item_name=${1}
  local wdir=${2}

  ttl_files=$(ls ${wdir}/*ttl)
  num_lines=$(wc -l ${wdir}/*ttl)

  if [[ -z ${ttl_files} ]]; then
    echo "generate_${item_name}: FAILED"
    echo "  files: ${ttl_files}"
    echo "  number of lines: ${num_lines}"
    FAILED+=(${item_name})
  else
    echo "generate_${item_name}: SUCCESS"
  fi
}

#
# Craete BioSample RDF: Run bs2ld via biosample.run.sh with GridEngine
#
generate_biosample() {
  local wdir=${WORKDIR}/biosample
  mkdir -p  ${wdir}
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
  local dir=${WORKDIR}/accessions
  mkdir -p  ${wdir}
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
  mkdir -p  ${wdir}
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
  mkdir -p  ${wdir}
  virtuoso_db_path=${wdir}/virtuoso.db
  #touch ${virtuoso_db_path}
  echo ${virtuoso_db_path}
}

test_load_to_virtuoso() {
  local db_path=$(load_to_virtuoso)
  local db_size=$(ls -l ${db_path} | awk '{ print $5 }')
  if [[ ${db_size} -lt 70000000 ]]; then
    echo "load_to_virtuoso: FAILED"
    echo "  db size: ${db_size}"
    FAILED+=(load_to_virtuoso)
  else
    echo "load_to_virtuoso: SUCCESS"
    echo "  db size: ${db_size}"
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
    echo "publish_virtuoso_db: FAILED"
    echo "  http status:      ${dest_http_status}"
    echo "  remote file size: ${dest_file_size}"
    FAILED+=(publish_virtuoso_db)
  else
    echo "mirror_virtuoso_db: SUCCESS"
    echo "  remote file size: ${dest_file_size}"
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

  if [[ -z ${FAILED} ]]; then
    for i in "${FAILED[@]}"; do
      echo "Test ${i} failed."
    done
    exit 1
  else
    echo "Passed all test."
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
  *)
    main
    ;;
esac