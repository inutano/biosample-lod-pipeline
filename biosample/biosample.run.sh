#!/bin/bash
set -u

#
# Variables
#
VERSION="0.1a"

BASEDIR=$(cd $(dirname ${0}) && pwd -P)
JOB_SCRIPT="${BASEDIR}/biosample.job.sh"

BIOSAMPLE_XML_REMOTE_PATH="ftp://ftp.ncbi.nlm.nih.gov/biosample/biosample_set.xml.gz"

#
# Get BioSample XML
#

get_xml() {
  local xml_path="${OUTDIR}/$(basename ${BIOSAMPLE_XML_REMOTE_PATH} ".gz")"
  if [[ ! -e ${xml_path} ]]; then
    lftp -c "open $(dirname ${BIOSAMPLE_XML_REMOTE_PATH}) && pget -n 8 ${xml_path}.gz"
    gunzip "${xml_path}.gz"
  fi
  echo "${xml_path}"
}

create_jobconf() {
  local xml_path=${1}
  if [[ ! -e "${OUTDIR}/bs.00" ]]; then
    grep -n '</BioSample>' "${xml_path}" |\
      awk -F':' 'BEGIN{ start=3 } NR%10000==0 { print start "," $1 "p"; start=$1+1 }' |\
      split -l 5000 -d - "${OUTDIR}/bs."
  fi
}

run_array_job() {
  source "/home/geadmin/UGED/uged/common/settings.sh"

  local xml_path=${1}
  local mode=${2}
  local logdir="${OUTDIR}/log" && mkdir -p ${logdir}

  find ${OUTDIR} -maxdepth 1 -type f -name "bs.*" | while read jobconf; do
    jobname=$(basename ${jobconf})

    case ${mode} in
      test)
        local max=10
        ;;
      *)
        local max=$(wc -l "${jobconf}" | awk '$0=$1')
        ;;
    esac

    qsub \
      -N "${jobname}" \
      -o  "${logdir}/${jobname}.log" \
      -pe def_slot 1 \
      -l s_vmem=4G \
      -l mem_req=4G \
      -t 1-${max}:1 \
      "${JOB_SCRIPT}" \
      "${xml_path}" \
      "${jobconf}"
  done
}

wait_uge() {
  while :; do
    sleep 30
    running_jobs=$(qstat | grep "bs.")
    if [[ -z ${running_jobs} ]]; then
      printf "All jobs finished.\n"
      break
    fi
  done
}

#
# Operations
#
enable_debug_mode() {
  N=$(date +%s%N)
  PS4='+[$((($(date +%s%N)-${N})/1000000))ms][${BASH_SOURCE}:${LINENO}]: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  set -x
}

run() {
  local xml_path=$(get_xml)
  create_jobconf ${xml_path}
  run_array_job ${xml_path} "run"
  wait_uge
}

test_run() {
  local xml_path=$(get_xml)
  create_jobconf ${xml_path}
  run_array_job ${xml_path} "test"
  wait_uge
}

print_version() {
  echo "BioSample RDF generator version: ${VERSION}"
}

print_help() {
  print_version
  cat <<EOS

*Require UGE and Docker for running biosample xml2ttl*

Usage:
  biosample.run.sh <option> <output directory>

Option:
  --version         Show version of the script and exit
  --help            Show this help message and exit
  --run             Run biosample xml2ttl
  --test-run        Test --run function
EOS
}

main() {
  # Default command
  CMD="run"

  # argparse and run
  while [[ $# -gt 0 ]]; do
    key=${1}
    case ${key} in
      -v|--version)
        print_version
        exit 0
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      "--run")
        CMD="run"
        ;;
      "--test-run")
        CMD="test_run"
        ;;
      *)
        OUTDIR=$(cd $(dirname ${1}) && pwd -P)
        TTL_DIR="${OUTDIR}/ttl"
        mkdir -p ${TTL_DIR}
        ;;
    esac
    shift
  done

  case ${CMD} in
    "run")
      run
      ;;
    "test_run")
      test_run
      ;;
  esac
}

#
# Run
#
if [[ $# -eq 0 ]]; then
  print_help
  exit 0
else
  main ${@}
fi
