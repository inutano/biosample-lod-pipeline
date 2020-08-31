#!/bin/bash
#$ -S /bin/bash -j y
# Note: `data "+%s%N"` does not work with BSD/macOS
N=$(date +%s%N)
PS4='+[$((($(date +%s%N)-${N})/1000000))ms][${BASH_SOURCE}:${LINENO}]: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -eux

module load docker
BIOSAMPLE_RDF_DOCKER_IMAGE="quay.io/inutano/biosample_jsonld:v1.13"

#
# Functions
#
setup() {
  XML_PATH=${1}
  JOBCONF=${2}
  WORKDIR="$(cd $(dirname ${XML_PATH}) && pwd -P)"
  OUTDIR="${WORKDIR}/ttl"

  TMPDIR="/data1/tmp/biosample-lod/biosample/ttl"
  mkdir -p "${TMPDIR}"
}

get_job_param() {
  local mode=${1}

  case ${mode} in
    test )
      SGE_TASK_ID=1
      ;;
  esac

  cat ${JOBCONF} | awk -v id=${SGE_TASK_ID} 'NR==id'
}

set_job_name() {
  local job_param=${1}
  echo "biosample.$(echo ${job_param} | sed -e 's:,.*$::')"
}

create_xml() {
  local job_param=${1}
  local tmp_xml="${TMPDIR}/$(set_job_name ${job_param}).xml"

  printf "<BioSampleSet>\n" > ${tmp_xml}
  sed -n "${job_param}" "${XML_PATH}" >> ${tmp_xml}

  echo ${tmp_xml}
}

xml2ttl() {
  local tmp_xml=${1}
  local tmp_ttl="${TMPDIR}/$(basename ${tmp_xml} .xml).ttl"
  docker run \
    --security-opt seccomp=unconfined \
    --rm \
    -e TZ=Asia/Tokyo \
    --volume ${TMPDIR}:/work \
    ${BIOSAMPLE_RDF_DOCKER_IMAGE} \
    bs2ld \
    xml2ttl \
    /work/$(basename ${tmp_xml}) \
    > "${tmp_ttl}"
  rm -f ${tmp_xml}
  echo "${tmp_ttl}"
}

validate_ttl() {
  local ttl=${1}
  local validation_output="${ttl}.validation.failed"

  docker run \
    --security-opt seccomp=unconfined \
    --rm \
    --user "$(id -u):$(id -g)" \
    -v $(dirname "${ttl}"):/work \
    "quay.io/inutano/turtle-validator:v1.0" \
    ttl \
    /work/$(basename "${ttl}") \
    > "${validation_output}"

  if [[ $(cat "${validation_output}") == 'Validator finished with 0 warnings and 0 errors.' ]]; then
    rm -f "${validation_output}"
    echo "${ttl}"
  else
    echo "${validation_output}"
  fi
}

generate_turtle() {
  setup ${1} ${2}
  local job_param=$(get_job_param ${3})
  local job_name=$(set_job_name ${job_param})
  local tmp_xml=$(create_xml ${job_param})
  local tmp_ttl=$(xml2ttl ${tmp_xml})
  local output=$(validate_ttl ${tmp_ttl})
  mv ${output} ${OUTDIR}
}

main() {
  if [[ $# -gt 2 ]]; then
    generate_turtle ${1} ${2} "test"
  else
    generate_turtle ${1} ${2} "productionn"
  fi
}

#
# Exec
#
main ${@}
