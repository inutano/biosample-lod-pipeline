#!/bin/bash
set -eux

#
# Variables
#
INPUT_JSON=${1}
INPUT_DIR=$(cd $(dirname ${INPUT_JSON}) && pwd -P)

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
    "-o" \
    "/work/$(basename ${INPUT_JSON}).ttl"
}

main() {
  run_metasra
}

#
# Exec
#
main
