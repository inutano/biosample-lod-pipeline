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
JOBCONF_PATH="${1}"
OUTDIR="${2}"
OUT_TTL_PATH="${OUTDIR}/$(basename ${1}).ttl"
SCRIPT_PATH="/tmp/ld-sra/python/script/expxml2ttl.py"
DOCKER_IMAGE_TAG="python:3.9.0-buster"

#
# Functions
#
download_script() {
  if [[ ! -e "${SCRIPT_PATH}" ]]; then
    git clone --depth=1 "https://github.com/inutano/ld-sra" "/tmp/ld-sra"
  fi
}

xml2ttl() {
  docker run --security-opt seccomp=unconfined --rm -i \
    -v ${SCRIPT_PATH}:/$(basename ${SCRIPT_PATH}) \
    -v ${JOBCONF_PATH}:/$(basename ${JOBCONF_PATH}) \
    -v /usr/local/resources/dra/fastq:/usr/local/resources/dra/fastq \
    ${DOCKER_IMAGE_TAG} \
    python \
    "/$(basename ${SCRIPT_PATH})" \
    -l "/$(basename ${JOBCONF_PATH})" \
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
