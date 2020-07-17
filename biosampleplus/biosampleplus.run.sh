#!/bin/bash
set -ux

#
# Variables
#
VERSION="0.1a"

BASEDIR=$(cd $(dirname ${0}) && pwd -P)
JOB_SCRIPT="${BASEDIR}/biosampleplus.job.sh"

#
# Get xml.gz and decompress, and then parse XML to dump JSON-line (yet not valid JSON)
#
xml2jsonl() {
  get_xml | gunzip | awk_xml2jsonl
}

get_xml(){
  local xml_path="ftp://ftp.ncbi.nlm.nih.gov/biosample/biosample_set.xml.gz"
  curl -s -o - ${xml_path}
}

awk_xml2jsonl() {
  awk '
    $0 ~ /<BioSample / {
      for(i=1; i<=NF; i++) {
        if($i ~ /^accession/) {
          match($i, /\"SAM.+\"/)
          printf "{\"accession\":%s", substr($i, RSTART, RLENGTH)
        }
      }
    }

    $0 ~ /<Organism/ {
      for(i=1; i<=NF; i++) {
        if($i ~ /^taxonomy_id/) {
          match($i, /\".+\"/)
          printf ",\"taxonomy_id\":%s,\"characteristics\":{", substr($i, RSTART, RLENGTH)
        }
      }
    }

    $0 ~ /<Attribute / {
      match($0, /attribute_name="[^"]+"/)
      key = substr($0, RSTART, RLENGTH)
      sub(/attribute_name=/,"",key)

      match($0, /[^>]+<\/Attribute>/)
      value = substr($0, RSTART, RLENGTH)
      sub(/<\/Attribute>/,"",value)

      printf "%s:[{\"text\":\"%s\"}],", key, value
    }

    $0 ~ /<\/BioSample>/ {
     print "}}"
    }
  '
}

#
# Filter JSON-line, make them valid JSON format, and split into files
#
jsonl2json() {
  filter_jsonl "9606" | group_jsonl 50000 | split_json
}

test_jsonl2json() {
  filter_jsonl "9606" | head -99 | group_jsonl 20 | split_json
}

filter_jsonl() {
  local taxid=${1}
  awk '$0 !~ /"characteristics":\{\}/' | awk '/"taxonomy_id":"'"${taxid}"'"/' | sed -e 's:,}}:}}:'
}

group_jsonl() {
  local size=${1}
  awk '
    NR % '"${size}"' == 1 {
      printf "["
    }
    NR % '"${size}"' != 1 {
      printf ","
    }
    {
      printf "%s", $0
    }
    NR % '"${size}"' == 0 {
      print "]"
    }
    END {
      print "]"
    }
  '
}

split_json() {
  split -l 1 -d - "bsp.json."
}

#
# Get XML, create JSON-line, filter and dump to JSON files
#
xml2json() {
  cd ${OUTDIR}
  xml2jsonl | jsonl2json
}

test_xml2json() {
  cd ${OUTDIR}
  xml2jsonl | test_jsonl2json
}

#
# Run MetaSRA pipeline on UGE for each JSON files
#
run_metasra() {
  submit_job
  wait_qsub
  collect_ttl
}

submit_job() {
  source "/home/geadmin/UGED/uged/common/settings.sh"
  find ${OUTDIR} -type f -name 'bsp.json.*' | while read json; do
    qsub -N $(basename ${json}) -j y -o ${json}.qsub.out -pe def_slot 8 -l s_vmem=64G -l mem_req=64G "${JOB_SCRIPT}" ${json}
  done
}

wait_qsub() {
  while :; do
    sleep 30
    running_jobs=$(qstat | grep "bsp.")
    if [[ -z ${running_jobs} ]]; then
      printf "All jobs finished.\n"
      break
    fi
  done
}

collect_ttl() {
  find ${OUTDIR} -type f -name '*ttl' | while read ttl; do
    if [[ ! -e "${ttl}.validation.failed" ]]; then
      mv ${ttl} ${TTL_DIR}
      rm -f "$(basename ${ttl} .ttl)"
      rm -f "$(basename ${ttl} .ttl).qsub.out"
    fi
  done
}

#
# Operations
#
test() {
  test_xml2json
  run_metasra
}

run() {
  xml2json
  run_metasra
}

print_version() {
  echo "biosampleplus ${VERSION}"
  exit 0
}

print_help() {
  cat <<EOS
ttl2virtuosodb version: ${VERSION}
Usage:
  biosampleplus.run.sh [--test] <output directory>
EOS
}

main() {
  # Default command
  CMD="run"

  # argparse and run
  if [[ $# -eq 0 ]]; then
    print_help
    exit 0
  fi
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
      "test")
        CMD="test"
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
    "test")
      test
      ;;
  esac
}

#
# Run
#
main ${@}
