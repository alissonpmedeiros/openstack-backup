#!/bin/bash
# Script to create snapshot of openstack Instance
# Place the computerc file in: /root/.openstack_snapshotrc

# Debian/Ubuntu install
# apt-get install python3-pip
# pip3 install python-openstackclient

# If you have any error while launchging openstack command :
#Êopenstack --debug --help
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
EMAIL_FROM="openstack.cnds.unibe.ch@inf.unibe.ch"
EMAIL_TO="alissonp.medeiros@inf.unibe.ch"

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
SNAPSHOT_DIRECTORY="/var/lib/glance/snapshots/"
BACKUP1_DIRECTORY="/var/lib/backup/backup1/"
BACKUP2_DIRECTORY="/var/lib/backup/backup2/"

check_backup(){
  echo -e "\nINFO: Checking backup"
  #count number of lines
  FILE_LINES=$(grep "" -c $FILE_DIRECTORY$FILENAME)
  for (( i=1; i<=$FILE_LINES-$BACKUPS; i++ ))
  do
    DESTROY_BACKUP=$(head -1 $FILE_DIRECTORY$FILENAME)
    echo "INFO: The following backup will be destroyed: $DESTROY_BACKUP"
    #remove first line of the file
    echo "$(tail -n +2 $FILE_DIRECTORY$FILENAME)" > ${FILE_DIRECTORY}${FILENAME}
    
    echo -e "INFO: Removing backup $DESTROY_BACKUP in storage server CDS-STORAGE1:"
    ssh -p 2711 root@130.92.70.135 'rm -rf '${BACKUP2_DIRECTORY}${DESTROY_BACKUP}

    echo -e "INFO: Removing backup $DESTROY_BACKUP in storage server CDS-STORAGE2:"
    #rm -rf ${BACKUP1_DIRECTORY}${DESTROY_BACKUP}
    ssh -p 2711 root@130.92.70.135 'rsync -avh '$BACKUP2_DIRECTORY $BACKUP1_DIRECTORY ' --delete'

  done

}

add_backup(){
  #add in the end of the file
  echo -e "\n\nINFO: updating file ${FILENAME}"
  echo "INFO: The following backup will be included:"
  echo "$BACKUP_NAME"  | tee -a ${FILE_DIRECTORY}${FILENAME}
}

saving_backup() {
  echo -e "\nINFO: Creating backup directory $BACKUP_NAME in storage server CDS-STORAGE1:"
  #echo "mkdir ${BACKUP2_DIRECTORY}${BACKUP_NAME}"
  ssh -p 2711 root@130.92.70.135 'mkdir '${BACKUP2_DIRECTORY}${BACKUP_NAME}

  echo -e "INFO: sending snapshot to CDS-STORAGE1"
  scp -P 2711 "${SNAPSHOT_DIRECTORY}${1}".qcow2 root@130.92.70.135:"$BACKUP2_DIRECTORY""${BACKUP_NAME}"

  echo -e "INFO: synchronizing backup directory $BACKUP_NAME in storage server CDS-STORAGE2:"
  #echo "mkdir ${BACKUP1_DIRECTORY}${BACKUP_NAME}"
  #mkdir ${BACKUP1_DIRECTORY}${BACKUP_NAME}
  ssh -p 2711 root@130.92.70.135 'rsync -r ' $BACKUP2_DIRECTORY $BACKUP1_DIRECTORY
}


launch_instances_backups () {
  if output=$(openstack server list | awk -F'|' '/\|/ && !/ID/{system("echo "$2"__"$3"")}'); then
    set -- "$output"
    IFS=$'\n'; declare -a arrOutput=($*)
    
    add_backup
    

    for instance in "${arrOutput[@]}"; do
      set -- "$instance"
      IFS=__; declare arrInstance=($*)

      # instance UUID
      INSTANCE_UUID="${arrInstance[0]:0:${#arrInstance[0]}-1}"

      # instance name
      INSTANCE_NAME="${arrInstance[2]:1:${#arrInstance[2]}-1}"

      # snapshot names will sort by date, instance_name and UUID.
      SNAPSHOT_NAME="snapshot-$(date "+%Y%m%d%H%M")-${BACKUP_TYPE}-${INSTANCE_NAME}"
      

      echo -e "\nINFO: Start OpenStack snapshot creation : ${INSTANCE_NAME}"

      #echo -e "INFO: command -> openstack server image create "${INSTANCE_UUID}" --name "${SNAPSHOT_NAME}" --wait"
      openstack server image create "${INSTANCE_UUID}" --name "${SNAPSHOT_NAME}" --wait
      sleep 3
      aux=$(openstack --os-image-api-version 2 image show ${SNAPSHOT_NAME} | sed -n 's/|\s*id\s*|\s*\(.*[^\s]\)\s*|/\1/p')
      SNAPSHOT_ID=$(echo "$aux" | sed 's/[[:space:]]//g')
      echo -e "\nINFO: downloading image ${SNAPSHOT_ID}"
      glance image-download "${SNAPSHOT_ID}" --file "${SNAPSHOT_DIRECTORY}""${SNAPSHOT_NAME}".qcow2
      echo -e "\nINFO: Removing image ${SNAPSHOT_NAME} from openstack"
      openstack image delete ${SNAPSHOT_NAME}

      saving_backup $SNAPSHOT_NAME

      echo -e "\nINFO: deleting "${SNAPSHOT_NAME}".qcow2"
      rm -rf "${SNAPSHOT_DIRECTORY}""${SNAPSHOT_NAME}".qcow2

      if [[ "$?" != 0 ]]; then
        cat tmp_error.log >> openstack_errors.log
      else
        echo -e "\nSUCCESS: Backup image created and uploaded."
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
  else
    echo "The backup has been created successfully" | mail -s "Openstack Backup" $EMAIL_TO
  fi
}

if [ -f openstack_errors.log ]; then
  rm openstack_errors.log
fi
launch_instances_backups
#send_errors_if_there_are
#bash "$SCRIPTPATH/count_volume_snapshots.sh" "$ROTATION"
