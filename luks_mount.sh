#!/bin/bash

# Treat unset variables as errors and exit
set -u

# Return an error code if any command on a pipeline fails
set -o pipefail

# Load config file and set variables
source /etc/luks_mount.conf
CURL_CMD="curl -s -H X-Vault-Token:$VAULT_TOKEN"

# Get a list of all luks devices on the system
ALL_DEVICES=$(lsblk --noheadings --nodeps | awk '{print $1}')
LUKS_DEVICES=""
for DEV in $ALL_DEVICES; do
    if cryptsetup isLuks /dev/${DEV}; then
        LUKS_DEVICES="$LUKS_DEVICES $DEV"
    fi
done
echo "Luks devices are: $LUKS_DEVICES"

# open and mount all luks devices
for DEV in $LUKS_DEVICES; do

    # Get luks key
    LUKS_KEY=$($CURL_CMD -X GET ${VAULT_ADDR}/v1/secret/$HOSTNAME/luks_${DEV} | jq -r .data.value)
    if [[ $? -eq 0 ]]; then
        echo "Succesfully retrieved keys for $DEV"
    else
        echo "Failed to retrieve key for $DEV. Exiting..."
        exit 1
    fi

    # Open luks volume
    echo $LUKS_KEY | cryptsetup -v --batch-mode luksOpen /dev/${DEV} luks_${DEV}
    if [[ $? -eq 0 ]]; then
        echo "Succesfully decrypted volume $DEV"
    else
        echo "Failed to decrypt volume $DEV. Exiting..."
        exit 1
    fi

    # Mount decrypted volume.
    # Assume mounting point will be availabe on /etc/fstab
    mount /dev/mapper/luks_${DEV}

done
