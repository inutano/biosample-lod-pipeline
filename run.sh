#!/bin/bash

### Env Vars
WORKDIR_BASE="${HOME}/work"

### Functions
message() {
  case ${2} in
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
  STARTCOLOR="\e[${COLOR}"
  ENDCOLOR="\e[0m"
  printf "${STARTCOLOR}%b${ENDCOLOR}" "[$(date +'%Y/%m/%d %H:%M:%S')] ${1}" | tee -a ${LOGFILE}
}

#
# Setup working directory and log file
#
setup() {
  PIPELINE_RUN_ID="bsp-$(date +%Y%m%d-%H%M)"
  WORKDIR="${WORKDIR_BASE}/biosampleplus-pipeline/${PIPELINE_RUN_ID}"
  mkdir -p ${WORKDIR}

  git clone 'git://github.com/inutano/biosampleplus-pipeline' --depth 1 "${WORKDIR}/pipeline"

  LOGFILE="${WORKDIR}/biosampleplus-pipeline.${PIPELINE_RUN_ID}.log"
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
    message "generate_${item_name}: FAILED\n" "danger"
    message "  number of files: ${num_ttl_files}\n"
    message "  number of lines (smallest 10 files):\n${num_lines}\n"
    FAILED+=(${item_name})
  else
    message "generate_${item_name}: SUCCESS\n" "info"
    message "  number of files: ${num_ttl_files}\n"
    message "  number of lines (smallest 10 files):\n${num_lines}\n"
  fi
}

#
# Create BioSample RDF: Run bs2ld via biosample.run.sh with GridEngine
#
generate_biosample() {
  local wdir=${WORKDIR}/biosample
  mkdir -p ${wdir}

  cd "${WORKDIR}/pipeline"

  if [[ $# -gt 0 ]]; then
    run_biosample=$(bash ./biosample/biosample.run.sh --test-run ${wdir})
  else
    run_biosample=$(bash ./biosample/biosample.run.sh --run ${wdir})
  fi

  echo "${wdir}/ttl"
}

test_generate_biosample() {
  local outdir=$(generate_biosample "--test-run")
  test_ttl_generator "biosample" ${outdir}
  echo ${outdir}
}

#
# Create BioSamplePlus RDF: Run MetaSRA pipeline to map BioSample arrtibutes to ontologies
#
generate_biosampleplus() {
  local wdir=${WORKDIR}/bsp
  mkdir -p ${wdir}

  cd "${WORKDIR}/pipeline"

  if [[ $# -gt 0 ]]; then
    run_biosampleplus=$(bash ./biosampleplus/biosampleplus.run.sh --test-run ${wdir})
  else
    run_biosampleplus=$(bash ./biosampleplus/biosampleplus.run.sh --run ${wdir})
  fi

  echo "${wdir}/ttl"
}

test_generate_biosampleplus() {
  local outdir=$(generate_biosampleplus "--test-run")
  test_ttl_generator "biosampleplus" ${outdir}
  echo ${outdir}
}

#
# Create SRA accessions RDF: Run accessions-ttl-generator-split
#
generate_accessions() {
  local wdir=${WORKDIR}/accessions
  git clone 'git://github.com/inutano/insdc-accessions' -b 'v1.3' --depth 1 ${wdir}
  cd ${wdir}
  run_accessions=$(bash ./bin/accessions-ttl-generator-split ${wdir})
  echo "${wdir}/ttl"
}

test_generate_accessions() {
  local outdir=$(generate_accessions)
  test_ttl_generator "accessions" ${outdir}
  echo ${outdir}
}

#
# Create SRA Experiment RDF: Run xml2ttl via exp.run.sh with GridEngine
#
generate_experiment() {
  local wdir=${WORKDIR}/experiment
  git clone 'git://github.com/inutano/ld-sra' -b 'v1.4' --depth 1 ${wdir}
  cd ${wdir}
  run_experiment=$(bash ./sh/exp.run.sh ${wdir})
  echo "${wdir}/ttl"
}

test_generate_experiment() {
  local outdir=$(generate_experiment)
  test_ttl_generator "experiment" ${outdir}
  echo ${outdir}
}

#
# Load to Virtuoso to create virtuoso.db
#
load_to_virtuoso() {
  local wdir=${WORKDIR}/virtuoso
  git clone 'git://github.com/inutano/ttl2virtuosodb' -b 'v0.5.0' --depth 1 ${wdir}
  cd ${wdir}

  rm -fr "${wdir}/data"
  mkdir -p "${wdir}/data"

  for ttl_dir in "${@}"; do
    find "${ttl_dir}" -name '*ttl' -type f | xargs mv -t "${wdir}/data"
  done

  turtle_load=$(./ttl2virtuosodb load)
  virtuoso_down=$(./ttl2virtuosodb down)

  echo ${wdir}/db/virtuoso.db
}

test_load_to_virtuoso() {
  local db_path=$(load_to_virtuoso ${@})
  local db_size=$(ls -l ${db_path} | awk '{ print $5 }')
  if [[ ${db_size} -lt 70000000 ]]; then
    message "load_to_virtuoso: FAILED\n" "danger"
    message "  db size: ${db_size}\n"
    FAILED+=(load_to_virtuoso)
  else
    message "load_to_virtuoso: SUCCESS\n" "info"
    message "  db size: ${db_size}\n"
  fi
}

#
# Publish virtuoso.db data file on the http-reachable storage
#
export_outputs() {
  local db_file="${WORKDIR}/virtuoso/virtuoso.db"
  local ttl_dir_org="${WORKDIR}/virtuoso/data"
  local ttl_dir="${WORKDIR}/biosampleplus-${PIPELINE_RUN_ID}"
  mv ${ttl_dir_org} ${ttl_dir}

  local dest_path="/gpfs1/dpl1/ddbj-scfs/rdf/biosample"
  local dest_vdb="/gpfs1/dpl1/ddbj-scfs/rdf/biosample/virtuosodb/biosampleplus.${PIPELINE_RUN_ID}.virtuoso.db"
  local dest_ttl="/gpfs1/dpl1/ddbj-scfs/rdf/biosample/ttl/biosampleplus.${PIPELINE_RUN_ID}.ttl.tgz"

  mkdir -p $(dirname ${dest_vdb}) && cp ${db_file} ${dest_vdb}
  mkdir -p $(dirname ${dest_ttl}) && tar -zcf ${dest_ttl} ${ttl_dir}

  echo "ftp://ftp.ddbj.nig.ac.jp/rdf/biosample/$(basename ${dest_vdb})"
}

test_export_outputs() {
  local dest_path=$(export_outputs)
  local dest_http_status=$(curl -s -o /dev/null -LI ${dest_path} -w '%{http_code}\n')
  local dest_file_size=$(curl -s -o /dev/null -LI ${dest_path} -w '%{size_download}\n')
  if [[ ${dest_http_status} != 350 ]]; then
    message "export_outputs: FAILED\n" "danger" | tee -a ${LOGFILE}
    message "  http status:      ${dest_http_status}\n" | tee -a ${LOGFILE}
    message "  remote file size: ${dest_file_size}\n" | tee -a ${LOGFILE}
    FAILED+=(export_outputs)
  else
    message "export_outputs: SUCCESS\n" "info" | tee -a ${LOGFILE}
    message "  remote file size: ${dest_file_size}\n" | tee -a ${LOGFILE}
  fi
}

#
# Generalfunction
#
test() {
  setup
  bs_ttl=$(test_generate_biosample)
  bsp_ttl=$(test_generate_biosampleplus)
  acc_ttl=$(test_generate_accessions)
  # test_generate_experiment
  test_load_to_virtuoso ${bs_ttl} ${bsp_ttl} ${acc_ttl}
  test_export_outputs

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
  bs_ttl=$(generate_biosample)
  bsp_ttl=$(generate_biosampleplus)
  acc_ttl=$(generate_accessions)
  # generate_experiment # Under construction
  load_to_virtuoso ${bs_ttl} ${bsp_ttl} ${acc_ttl}
  export_outputs
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
