#!/bin/bash

# Values configurable via script parameters
ZK_HOST=""
BROKERS=""

# Update these two values as appropriate for your system
KAFKA_BIN="/usr/lib/kafka/bin/"
TMP="/tmp/kafka"

# Temporary files
TOPICS="${TMP}/topics.json"
PARTITIONS="${TMP}/partitions.json"
PARTITIONS_BACKUP="${TMP}/partitions_backup.json"
ROLLBACK="${TMP}/rollback.json"

usage() {
  cat <<EOF
  $0 (-g | -v | -e | -r | -l) -b broker_list -z zookeeper_host

  Reassign topic partitions to the given broker list.

  -g  Generate partition reassignment json file for all topics and given brokers
  -v  Verify partition reassignment json file
  -e  Execute partition reassignment. This will save a rollback configuration in ${ROLLBACK}
  -r  Prepare for rollback. This will backup the current partitions configuration and then
      copy the rollback configuration to it. To execute the rollback continue as if you are
      applying a new partition configuration
  -l  Run a preferred leader election. This is required after the new partition configuration
      has finished being applied
  -b  Provide the brokers to reassign partitions to as a comma delimited list. This is required
      only if you also provide the -g parameter
  -z  Provide the ZK host. This should include the port number. This option is not required
      for the rollback mode (-r)
  -h  This help page

   Reassigning topic partitions is a multi-step process. The intermediate parts of this procedure
   save files under ${TMP} which the subsequent steps use. The procedure is as follows:

   1. Generate the partition reassignment file
      $0 -g -b "1,2,3,4" -z zk1.acme.org:2181

   2. Verify the partition reassignment file has no errors
      $0 -v -z zk1.acme.org:2181
      This will warn you that the actual partition assignment differ from what the file specifies.
      That is fine since we have not applied those changes yet

   3. Execute the partition reassignment
      $0 -e -z zk1.acme.org:2181

   4. Use the verification functionality to monitor progress
      $0 -v -z zk1.acme.org:2181

   5. Once the reassignment is completed, trigger a partition preferred leader election to ensure
      preferred leaders are evenly distributed across the cluster in a way that is consistent
      with the new partition allocations
      $0 -l -z zk1.acme.org:2181

   If you need to rollback to the previous partition allocation after the new one has been written
   (step 3) then you need to run the prepare rollback step by doing
   $0 -r
   and then continue from step 3 and onwards of the normal procedure.
EOF
}

function create_topics {
    TOPICS_LIST=$(${KAFKA_BIN}kafka-topics.sh \
        --list \
        --zookeeper ${ZK_HOST})

    first=true

    echo -en "{\"topics\": [" > ${TOPICS}

    for line in ${TOPICS_LIST}
    do
        if [ "false" = "$first" ]; then
            echo -e "," >> ${TOPICS}
    else
            echo -e "" >> ${TOPICS}
            first=false
        fi
        echo -ne "\t{\"topic\": \"$line\"}" >> ${TOPICS}
    done

    echo -e "" >> ${TOPICS}
    echo -e "]," >> ${TOPICS}
    echo -e "\t\"version\":1" >> ${TOPICS}
    echo -e "}" >> ${TOPICS}
}

function generate_partitions {
    ${KAFKA_BIN}kafka-reassign-partitions.sh \
        --zookeeper ${ZK_HOST} \
        --topics-to-move-json-file ${TOPICS} \
        --broker-list ${BROKERS} --generate \
        | sed '1,/Proposed partition/d' \
        | tail -n +2 \
        > ${PARTITIONS}
}

function verify_partitions {
    ${KAFKA_BIN}kafka-reassign-partitions.sh \
        --zookeeper ${ZK_HOST} \
        --reassignment-json-file ${PARTITIONS} \
        --verify
}

function execute_partition_reassignment {
    ${KAFKA_BIN}kafka-reassign-partitions.sh \
        --zookeeper ${ZK_HOST} \
        --reassignment-json-file ${PARTITIONS} \
        --execute \
        | grep -v "Current partition replica assignment" \
        | grep -v "Save this to use as the --reassignment-json-file option during rollback" \
        | grep -v "Successfully started reassignment of partitions" \
        | grep -v '^$' \
        > ${ROLLBACK}
}

function prepare_rollback {
    if [ ! -e "${ROLLBACK}" ]; then
        echo "ERROR - No rollback configuration found in ${ROLLBACK}. Terminating..."
        exit 1
    fi

    mv "${PARTITIONS}" "${PARTITIONS_BACKUP}"
    cp "${ROLLBACK}" "${PARTITIONS}"
}

function leader_election {
    ${KAFKA_BIN}kafka-preferred-replica-election.sh \
        --zookeeper ${ZK_HOST}
}

MODE=""

function check_no_duplicate_mode_params {
    if [ ! -z "${MODE}" ]; then
        usage
        exit 1
    fi
}

while getopts ":z:gverlb:h" opt; do
  case ${opt} in
    z)
        ZK_HOST=${OPTARG}
        echo "ZK host set to ${ZK_HOST}"
        ;;
    g)
        check_no_duplicate_mode_params
        MODE="generate"
        ;;
    v)
        check_no_duplicate_mode_params
        MODE="verify"
        ;;
    e)
        check_no_duplicate_mode_params
        MODE="execute"
        ;;
    r)
        check_no_duplicate_mode_params
        MODE="rollback"
        ;;
    l)
        check_no_duplicate_mode_params
        MODE="leader_election"
        ;;
    b)
        BROKERS="${OPTARG}"
        ;;
    h)
        usage
        exit 0;
        ;;
    \?)
      echo "Invalid option: -${OPTARG}" >&2
      usage
      exit 1
      ;;
    :)
      echo "Option -${OPTARG} requires an argument." >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "${MODE}" ]; then
    usage
    exit 1
fi

if [ "generate" = "${MODE}" ] && [ -z ${BROKERS} ]; then
    usage
    exit 1
fi

echo -e "Selected mode: ${MODE}..."
echo -e "Running...\n"

# Generate the temporary directory to place the files this script will generate
mkdir -p ${TMP}

case ${MODE} in
    generate)
        create_topics
        generate_partitions
        ;;
    verify)
        verify_partitions
        ;;
    execute)
        execute_partition_reassignment
        ;;
    rollback)
        prepare_rollback
        ;;
    leader_election)
        leader_election
        ;;
esac

echo -e "Done..."

