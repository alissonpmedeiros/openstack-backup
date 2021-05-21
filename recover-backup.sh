###  TESTING BACKUP ###


# restore backup
KEY_NAME="alisson-cds-key"
SIZE=60
FLAVOR=xenakis-heavy
NET_ID=f015bb03-7ebc-4d6d-a5f0-ddee7245115a # admin

NEW_IMAGE_NAME="imported_image"
BACKUP_INSTANCE_NAME=desktop-imported
SNAPSHOT_FILE=desktop-snapshot.qcow2

# create an instance from the backup file
glance image-create --name $NEW_IMAGE_NAME --file /var/lib/backup/backup2/$SNAPSHOT_FILE --disk-format qcow2 --container-format bare

# boot a new instance from the imported image in the previous step
nova boot --poll --key-name $KEY_NAME --flavor $FLAVOR --image $NEW_IMAGE_NAME --nic net-id=$NET_ID $BACKUP_INSTANCE_NAME




