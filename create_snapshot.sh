#!/bin/bash
# Script to create snapshot of openstack Instance
# Place the computerc file in: /root/.openstack_snapshotrc

# Debian/Ubuntu install
# apt-get install python3-pip
# pip3 install python-openstackclient

# If you have any error while launchging openstack command :
# openstack --debug --help
# for me the fix was :
# pip3 install six --upgrade

# Get the script path
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

# dry-run
DRY_RUN="${3}"

# First we check if all the commands we need are installed.
command_exists() {
  command -v "$1" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "I require $1 but it's not installed. Aborting."
    exit 1
  fi
}

for COMMAND in "openstack" "dmidecode" "tr"; do
  command_exists "${COMMAND}"
done

# Check if the computerc file exists. If so, assume it has the credentials.
if [[ ! -f "/root/.openstack_snapshotrc" ]]; then
  echo "/root/.openstack_snapshotrc file required."
  exit 1
else
  source "/root/.openstack_snapshotrc"
fi

# Export the emails from & to
EMAIL_FROM="$LOG_EMAIL_FROM"
EMAIL_TO="$LOG_EMAIL_TO"

# backup_type
BACKUP_TYPE="${1}"
if [[ -z "${BACKUP_TYPE}" ]]; then
  BACKUP_TYPE="manual"
fi

# rotation of snapshots
ROTATION="${2}"

FILE_DIRECTORY="/root/backup/"
FILENAME='backupHistory.txt'
#define the number of backups you want to maintain
BACKUPS=3
BACKUP_NAME="backup-$(date "+%Y%m%d%H%M")"
SNAPSHOT_DIRECTORY="/var/lib/glance-external/snapshots/"

check_backup(){
  echo -e "\n\nINFO: checking backup"
  #count number of lines
  FILE_LINES=$(grep "" -c $FILE_DIRECTORY$FILENAME)
  for (( i=1; i<=$FILE_LINES-$BACKUPS; i++ ))
  do
    DESTROY_BACKUP=$(head -1 $FILE_DIRECTORY$FILENAME)
    echo "the following backup will be destroyed: $DESTROY_BACKUP"
    #remove first line of the file
    echo "$(tail -n +2 $FILE_DIRECTORY$FILENAME)" > ${FILE_DIRECTORY}${FILENAME}
    echo "rm -rf ${SNAPSHOT_DIRECTORY}${DESTROY_BACKUP}"
    rm -rf ${SNAPSHOT_DIRECTORY}${DESTROY_BACKUP}
  done

}

add_backup(){
  #add in the end of the file
  echo "INFO: updating file ${FILENAME}"
  echo "the following backup will be included:"
  echo "$BACKUP_NAME"  | tee -a ${FILE_DIRECTORY}${FILENAME}
}


launch_instances_backups () {
  if output=$(openstack server list | awk -F'|' '/\|/ && !/ID/{system("echo "$2"__"$3"")}'); then
    set -- "$output"
    IFS=$'\n'; declare -a arrOutput=($*)
    
    add_backup
    
    echo -e "\n\nINFO: Creating weekly backup directory:"
    echo "mkdir ${SNAPSHOT_DIRECTORY}${BACKUP_NAME}"
    mkdir ${SNAPSHOT_DIRECTORY}${BACKUP_NAME}

    for instance in "${arrOutput[@]}"; do
      set -- "$instance"
      IFS=__; declare arrInstance=($*)

      # instance UUID
      INSTANCE_UUID="${arrInstance[0]:0:${#arrInstance[0]}-1}"

      # instance name
      INSTANCE_NAME="${arrInstance[2]:1:${#arrInstance[2]}-1}"

      # snapshot names will sort by date, instance_name and UUID.
      SNAPSHOT_NAME="snapshot-$(date "+%Y%m%d%H%M")-${BACKUP_TYPE}-${INSTANCE_NAME}"
      

      echo -e "INFO: Start OpenStack snapshot creation : ${INSTANCE_NAME}"

      if [ "$DRY_RUN" = "--dry-run" ] ; then
        #echo "DRY-RUN is enabled. In real a backup of the instance called ${SNAPSHOT_NAME} would've been done like that :
        echo "simulation:
        openstack server backup create ${INSTANCE_UUID} --name ${SNAPSHOT_NAME} --type ${BACKUP_TYPE} --rotate ${ROTATION} --wait
        glance image-download ${SNAPSHOT_NAME} --file ${SNAPSHOT_DIRECTORY}${BACKUP_NAME}/${SNAPSHOT_NAME}.qcow2
        openstack image delete ${SNAPSHOT_NAME}"
        
      else
        echo -e "INFO: command -> openstack server image create "${INSTANCE_UUID}" --name "${SNAPSHOT_NAME}" --wait"
        openstack server image create "${INSTANCE_UUID}" --name "${SNAPSHOT_NAME}" --wait
        sleep 3
        aux=$(openstack --os-image-api-version 2 image show ${SNAPSHOT_NAME} | sed -n 's/|\s*id\s*|\s*\(.*[^\s]\)\s*|/\1/p')
        SNAPSHOT_ID=$(echo "$aux" | sed 's/[[:space:]]//g')
        echo -e "INFO: downloading image with following command:"
        glance image-download "${SNAPSHOT_ID}" --file "${SNAPSHOT_DIRECTORY}""${BACKUP_NAME}"/"${SNAPSHOT_NAME}".qcow2
        echo -e "Removing image ${SNAPSHOT_NAME} from openstack"
        openstack image delete ${SNAPSHOT_NAME}
      fi
      if [[ "$?" != 0 ]]; then
        cat tmp_error.log >> openstack_errors.log
      else
        echo "SUCCESS: Backup image created and uploaded."
      fi
    done

  else
    echo "NO INSTANCE FOUND"
  fi
  check_backup
}


send_errors_if_there_are () {
  if [ -f openstack_errors.log ]; then
    echo -e "ERRORS:\n\n$(cat openstack_errors.log)" | mail -s "Snapshot errors" -aFrom:Backup\<$EMAIL_FROM\> "$EMAIL_TO"
  fi
}

if [ -f openstack_errors.log ]; then
  rm openstack_errors.log
fi
launch_instances_backups
#send_errors_if_there_are
#bash "$SCRIPTPATH/count_volume_snapshots.sh" "$ROTATION"
