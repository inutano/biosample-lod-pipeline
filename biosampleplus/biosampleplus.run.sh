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
  local xml_path=$(get_xml)
  subset_xml_by_year ${xml_path} "2014" | sebset_xml_tags | awk_xml2jsonline
}

get_xml() {
  local xml_path="${OUTDIR}/$(basename ${BIOSAMPLE_XML_REMOTE_PATH} ".gz")"
  if [[ ! -e ${xml_path} ]]; then
    lftp -c "open $(dirname ${BIOSAMPLE_XML_REMOTE_PATH}) && pget -n 8 $(basename ${BIOSAMPLE_XML_REMOTE_PATH}) -o ${xml_path}.gz"
    gunzip "${xml_path}.gz"
  fi
  echo "${xml_path}"
}

subset_xml_by_year() {
  local xml_path=${1}
  local year=${2}
  local prev_of_first_appear=$(grep -n "submission_date=\"${year}" ${xml_path} | head -1 | awk -F ':' '{ print $1 - 1 }')
  sed -e "2,${prev_of_first_appear}d" ${xml_path}
}

sebset_xml_tags() {
  grep -e "<BioSample " -e "<Organism " -e "<Attribute" -e "</BioSample"
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
  remove_invalid_jsonline | filter_jsonline_by_taxid "9606" | group_jsonline 5000 | split_to_json
}

test_jsonline2json() {
  remove_invalid_jsonline | filter_jsonline_by_taxid "9606" | head -99 | group_jsonline 20 | split_to_json
}

remove_invalid_jsonline() {
  awk '$0 !~ /"characteristics":\{\}/' | sed -e 's:,}}:}}:'
}

filter_jsonline_by_taxid() {
  local taxid=${1}
  awk '/"taxonomy_id":"'"${taxid}"'"/'
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
  split --lines 1 --numeric-suffixes - "bsp.json."
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
  xml2jsonline | test_jsonline2json
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
  find ${OUTDIR} -maxdepth 1 -type f -name 'bsp.json.*' | while read json; do
    qsub \
      -N $(basename ${json}) \
      -j y \
      -o ${json}.qsub.out \
      -pe def_slot 8 \
      -l s_vmem=8G \
      -l mem_req=8G \
      "${JOB_SCRIPT}" ${json}
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
  find ${OUTDIR} -maxdepth 1 -type f -name '*ttl' | while read ttl; do
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
enable_debug_mode() {
  N=$(date +%s%N)
  PS4='+[$((($(date +%s%N)-${N})/1000000))ms][${BASH_SOURCE}:${LINENO}]: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  set -x
}

make_json() {
  xml2json
}

test_make_json() {
  enable_debug_mode
  test_xml2json
}

run() {
  make_json
  run_metasra
}

test_run() {
  enable_debug_mode
  test_make_json
  run_metasra
}

print_version() {
  echo "BioSample+ RDF generator version: ${VERSION}"
}

print_help() {
  print_version
  cat <<EOS

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
        OUTDIR=$(cd ${1} && pwd -P)
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
