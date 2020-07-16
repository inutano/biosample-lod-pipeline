#!/bin/bash
set -eux

#
# Variables
#
WORKDIR=${0}
BASEDIR=$(cd $(dirname $0) && pwd -P)
JOB_SCRIPT="${BASEDIR}/biosampleplus.job.sh"

#
# Get xml.gz and decompress, and then parse XML to dump JSON-line (yet not valid JSON)
#
xml2jsonl() {
  get_xml | gunzip | awk_xml2jsonl
}

test_xml2jsonl() {
  xml2jsonl | head -100
}

get_xml(){
  local xml_path="ftp://ftp.ncbi.nlm.nih.gov/biosample/biosample_set.xml.gz"
  curl -s -o - ${xml_path}
}

awk_xml2jsonl() {
  awk '
    $0 ~ /<BioSample / {
      printf "{"
      for(i=1; i<=NF; i++) {
        if($i ~ /^accession/) {
          match($i, /\"SAM.+\"/)
          printf "\"accession\":" substr($i, RSTART, RLENGTH)
        }
      }
    }

    $0 ~ /<Organism/ {
      for(i=1; i<=NF; i++) {
        if($i ~ /^taxonomy_id/) {
          match($i, /\".+\"/)
          printf "," "\"taxonomy_id\":" substr($i, RSTART, RLENGTH) ",\"characteristics\":{"
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

      printf key ":[{\"text\":\"" value "\"}],"
    }

    $0 ~ /<\/BioSample>/ {
     printf "}}\n"
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
  filter_jsonl "408172" | group_jsonl 3 | split_json
}

filter_jsonl() {
  local taxid=${1}
  awk '$0 !~ /"characteristics":{}/' | awk '/"taxonomy_id":"'"${taxid}"'"/' | sed -e 's:,}}:}}:'
}

group_jsonl() {
  local size=${1}
  awk '
    NR % '"${size}"' == 1 {
      printf "[" $0
    } NR % '"${size}"' == 0 {
      print "," $0 "]"
    } NR % '"${size}"' > 1 {
      printf "," $0
    } END {
      print "]"
    }
  '
}

split_json() {
  gsplit -l 1 -d - "bsp.json."
}

#
# Get XML, create JSON-line, filter and dump to JSON files
#
xml2json() {
  cd ${WORKDIR}
  xml2jsonl | jsonl2json
}

test_xml2json() {
  cd ${WORKDIR}
  test_xml2jsonl | test_jsonl2json
}

#
# Run MetaSRA pipeline on UGE for each JSON files
#
run_metasra() {
  submit_job
  wait_qsub
}

submit_job() {
  source "/home/geadmin/UGED/uged/common/settings.sh"
  find ${WORKDIR} -type f -name 'bsp.json.*' | while read json; do
    qsub -N $(basename ${json}) -o /dev/null -pe def_slot 8 -l s_vmem=64G -l mem_req=64G "${JOB_SCRIPT}" ${json}
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

test() {
  test_xml2json
  run_metasra
}

main() {
  xml2json
  run_metasra
}

#
# Exec
#
test
