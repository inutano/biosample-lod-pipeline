#!/bin/bash
# set -eux
# For DDBJ supercomputer system

#
# Load UGE configuration
#
source "/home/geadmin/UGED/uged/common/settings.sh"

#
# Constants
#
FASTQ_DIR="/usr/local/resources/dra/fastq"
JOB_SCRIPT_PATH="$(cd $(dirname "${0}") && pwd -P)/exp.job.sh"
WORKDIR="$(cd "${1}" && pwd -P)"
JOBCONF_DIR="${WORKDIR}/jobconf"
TTL_DIR="${WORKDIR}/ttl"
UGE_LOG_DIR="${WORKDIR}/log"

#
# Functions
#
setup_dirs() {
  mkdir -p "${JOBCONF_DIR}"
  mkdir -p "${TTL_DIR}"
  mkdir -p "${UGE_LOG_DIR}"
}

find_experiment_xml() {
  if [[ -z $(find ${JOBCONF_DIR} -name 'exp.*') ]]; then
    cd ${JOBCONF_DIR}
    find ${FASTQ_DIR} -type f -name '*.experiment.xml' | split -l 50000 -d - "exp."
  fi
}

submit_uge() {
  find ${JOBCONF_DIR} -name "exp.*" | sort | while read jobconf; do
    qsub -N "$(basename ${jobconf})" \
      -j y \
      -o "${UGE_LOG_DIR}/$(basename ${jobconf}).log" \
      -pe def_slot 1 -l s_vmem=4G -l mem_req=4G \
      ${JOB_SCRIPT_PATH} ${jobconf} ${TTL_DIR}
  done
}

wait_uge_jobs() {
  while :; do
    sleep 30
    running_jobs=$(qstat | grep "exp.")
    if [[ -z ${running_jobs} ]]; then
      printf "All jobs finished.\n"
      break
    fi
  done
}

run() {
  setup_dirs
  find_experiment_xml
  submit_uge
  wait_uge_jobs
}

#
# Exec
#
run
