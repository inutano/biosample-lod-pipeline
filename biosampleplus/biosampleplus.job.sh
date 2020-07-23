#!/bin/bash
#$ -S /bin/bash -j y
set -eux

#
# Variables
#
INPUT_DIR=$(cd $(dirname ${1}) && pwd -P)
INPUT_JSON="${INPUT_DIR}/$(basename ${1})"

module load docker
METASRA_DOCKER_IMAGE="shikeda/metasra:1.4"

#
# Run MetaSRA
#
run_metasra() {
  docker run --security-opt seccomp=unconfined --rm \
    -e TZ=Asia/Tokyo \
    --volume ${INPUT_DIR}:/work \
    ${METASRA_DOCKER_IMAGE} \
    python3 \
    "/app/MetaSRA-pipeline/run_pipeline.py" \
    "-f" \
    "/work/$(basename ${INPUT_JSON})" \
    "-n" \
    "8" \
    "-o" \
    "/work/$(basename ${INPUT_JSON}).ttl"
  echo "${INPUT_JSON}.ttl"
}

validate_ttl() {
  local ttl=${1}
  local validation_output="${ttl}.validation"

  docker run --security-opt seccomp=unconfined --rm \
    --user "$(id -u):$(id -g)" \
    -v $(dirname "${ttl}"):/work \
    "quay.io/inutano/turtle-validator:v1.0" \
    ttl \
    /work/$(basename "${ttl}") \
    > "${validation_output}"

  if [[ $(cat "${validation_output}") == 'Validator finished with 0 warnings and 0 errors.' ]]; then
    rm -f "${validation_output}"
  else
    mv "${validation_output}" "${validation_output}.failed"
  fi
}

main() {
  local ttl=$(run_metasra)
  validate_ttl ${ttl}
}

#
# Exec
#
main
