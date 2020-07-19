#!/bin/bash
set -u

#
# Variables
#
VERSION="0.1a"

BASEDIR=$(cd $(dirname ${0}) && pwd -P)
JOB_SCRIPT="${BASEDIR}/biosampleplus.job.sh"

BIOSAMPLE_XML_REMOTE_PATH="ftp://ftp.ncbi.nlm.nih.gov/biosample/biosample_set.xml.gz"

#
# Get xml.gz and decompress, and then parse XML to dump JSON-line (yet not valid JSON)
#
xml2jsonline() {
  get_xml | awk_xml2jsonline
}

test_xml2jsonline() {
  test_get_xml | awk_xml2jsonline
}

get_xml(){
  local xml_local_path="${OUTDIR}/$(basename ${BIOSAMPLE_XML_REMOTE_PATH})"
  wget -o ${xml_local_path} ${BIOSAMPLE_XML_REMOTE_PATH}
  gunzip -c ${xml_local_path}
}

test_get_xml() {
  curl ${BIOSAMPLE_XML_REMOTE_PATH} | gunzip -c
}

awk_xml2jsonline() {
  awk '
    $0 ~ /<BioSample / {
      match($0, /submission_date="[^"]+"/)
      date = substr($0, RSTART, RLENGTH)
      sub(/submission_date=/,"",date)

      match($0, /accession="[^"]+"/)
      acc = substr($0, RSTART, RLENGTH)
      sub(/accession=/,"",acc)

      printf "{\"accession\":%s,\"submission_date\":%s", acc, date
    }

    $0 ~ /<Organism / {
      match($0, /taxonomy_id="[^"]+"/)
      taxid = substr($0, RSTART, RLENGTH)
      sub(/taxonomy_id=/,"",taxid)
      printf ",\"taxonomy_id\":%s", taxid
    }

    $0 ~ /<Attributes/ {
      printf ",\"characteristics\":{"
    }

    $0 ~ /<Attribute / {
      match($0, /attribute_name="[^"]+"/)
      key = substr($0, RSTART, RLENGTH)
      sub(/attribute_name=/,"",key)

      match($0, /[^>]+<\/Attribute>/)
      value = substr($0, RSTART, RLENGTH)
      sub(/<\/Attribute>/,"",value)
      gsub(/["\\]/, "\\\\&", value)

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
jsonline2json() {
  remove_invalid_jsonline | filter_jsonline_by_taxid "9606" | filter_jsonline_by_year "2019" | group_jsonline 5000 | split_to_json
}

test_jsonline2json() {
  remove_invalid_jsonline | filter_jsonline_by_taxid "9606" | filter_jsonline_by_year "2019" | head -99 | group_jsonline 20 | split_to_json
}

remove_invalid_jsonline() {
  awk '$0 !~ /"characteristics":\{\}/' | sed -e 's:,}}:}}:'
}

filter_jsonline_by_taxid() {
  local taxid=${1}
  awk '/"taxonomy_id":"'"${taxid}"'"/'
}

filter_jsonline_by_year() {
  local year=${1}
  awk '/"submission_date":"'"${year}"'/'
}

group_jsonline() {
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

split_to_json() {
  split -l 1 -d - "bsp.json."
}

#
# Get XML, create JSON-line, filter and dump to JSON files
#
xml2json() {
  cd ${OUTDIR}
  xml2jsonline | jsonline2json
}

test_xml2json() {
  cd ${OUTDIR}
  test_xml2jsonline | test_jsonline2json
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
make_json() {
  xml2json
}

test_make_json() {
  set -x
  test_xml2json
}

run() {
  make_json
  run_metasra
}

test_run() {
  set -x
  test_make_json
  run_metasra
}

print_version() {
  echo "biosampleplus running script ${VERSION}"
  exit 0
}

print_help() {
  cat <<EOS
ttl2virtuosodb version: ${VERSION}

*Require UGE and Docker for running metasra*

Usage:
  biosampleplus.run.sh <option> <output directory>

Option:
  --version         Show version of the script and exit
  --help            Show this help message and exit
  --make-json       Make JSON files for MetaSRA input
  --test-make-json  Test --make-json function
  --run             Make JSON files and run MetaSRA pipeline
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
      "--make-json")
        CMD="make_json"
        ;;
      "--test-make-json")
        CMD="test_make_json"
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
    "make_json")
      make_json
      ;;
    "test_make_json")
      test_make_json
      ;;
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
