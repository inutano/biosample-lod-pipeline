#!/bin/sh
#$ -S /bin/sh -j y
# set -x
# For DDBJ supercomputer system
#  ./exp.job.sh <path to job configuration> <output dir>

#
# Load Docker configuration
#
module load docker

#
# Constants
#
FASTQ_DIR="/usr/local/resources/dra/fastq"
SCTIPT_REMOTE_PATH="https://github.com/inutano/ld-sra/raw/master/python/script/expxml2ttl.py"
SCRIPT_LOCAL_PATH="/tmp/bsp/expxml2ttl.py"
DOCKER_IMAGE_TAG="python:3.9.0-buster"

JOBCONF_PATH="${1}"
OUTDIR="${2}"
OUT_TTL_PATH="${OUTDIR}/$(basename ${1}).ttl"

#
# Functions
#
download_script() {
  if [[ ! -e "${SCRIPT_LOCAL_PATH}" ]]; then
    mkdir -p $(dirname ${SCRIPT_LOCAL_PATH})
    curl -s "${SCTIPT_REMOTE_PATH}" > "${SCRIPT_LOCAL_PATH}"
  fi
}

xml2ttl() {
  local script_path_inside="/script.py"
  local jobconf_path_inside="/job.conf"
  docker run --security-opt seccomp=unconfined --rm -i \
    -v ${SCRIPT_LOCAL_PATH}:${script_path_inside} \
    -v ${JOBCONF_PATH}:${jobconf_path_inside} \
    -v ${FASTQ_DIR}:${FASTQ_DIR} \
    ${DOCKER_IMAGE_TAG} \
    python \
    ${script_path_inside} \
    -l \
    ${jobconf_path_inside} \
    > "${OUT_TTL_PATH}"
}

validate_ttl() {
  local validation_output="${OUT_TTL_PATH}.validation"
  local valid_value='Validator finished with 0 warnings and 0 errors.'

  docker run --security-opt seccomp=unconfined --rm -i \
    -v $(dirname "${OUT_TTL_PATH}"):/work \
    "quay.io/inutano/turtle-validator:v1.0" \
    ttl \
    /work/$(basename "${OUT_TTL_PATH}") \
    > "${validation_output}"

  if [[ $(cat "${validation_output}") == "${valid_value}" ]]; then
    rm -f "${validation_output}"
  fi
}

run() {
  xml2ttl
  validate_ttl
}

#
# Exec
#
run
