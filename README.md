# OpenStack automatic instances snapshots to a external storage server mounted at the openstack controller

# git clone this repo into the openstack controller then chmod 755 *.sh scripts
$ chmod 755 *

# create the openstack file credentials
$ nano /root/.openstack_snapshotrc

# source it to apply the credentials 
$ source /root/.openstack_snapshotrc

# Update the crontab to include the backup file
$ crontab -e

    # Weekly snapshot at 3 a.m
    0  3 * * 0 root /bin/bash /root/backup/create_snapshot.sh

