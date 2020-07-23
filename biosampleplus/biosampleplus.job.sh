#!/bin/bash
#$ -S /bin/bash -j y
# Note: `data "+%s%N"` does not work with BSD/macOS
N=$(date +%s%N)
PS4='+[$((($(date +%s%N)-${N})/1000000))ms][${BASH_SOURCE}:${LINENO}]: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -eux

module load docker
METASRA_DOCKER_IMAGE="shikeda/metasra:1.4"

#
# Staging
#
stage_json() {
  local input_json=${1}
  local input_json_dir=$(cd $(dirname ${input_json}) && pwd -P)
  local input_json_fname=$(basename ${input_json})

  local workdir="/data1/tmp/biosample-lod/bsp/${input_json_fname}.tmpdir"
  local work_json="${workdir}/${input_json_fname}"

  rm -fr ${workdir}; mkdir -p ${workdir}
  cp "${input_json_dir}/${input_json_fname}" "${work_json}"

  echo "${work_json}"
}

#
# Run MetaSRA
#
run_metasra() {
  local json_path="${1}"
  docker run --security-opt seccomp=unconfined --rm \
    -e TZ=Asia/Tokyo \
    --volume $(dirname ${json_path}):/work \
    ${METASRA_DOCKER_IMAGE} \
    python3 \
    "/app/MetaSRA-pipeline/run_pipeline.py" \
    "-f" \
    "/work/$(basename ${json_path})" \
    "-n" \
    "8" \
    "-o" \
    "/work/$(basename ${json_path}).ttl"
  echo "${json_path}.ttl"
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
    mv "${ttl}" "${INPUT_DIR}"
  else
    mv "${validation_output}" "${INPUT_DIR}/${validation_output}.failed"
  fi
}

main() {
  local json=$(stage_json ${1})
  local ttl=$(run_metasra ${json})
  validate_ttl ${ttl}
}

#
# Exec
#
main ${1}
