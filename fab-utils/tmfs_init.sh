####################################################################
#
#    SCRIPT TO START THE TIERING MANAGEMENT FILE SYSTEM (TMFS)
#                    on a KUBERNETES NODE
#
# Warning: 
#  - Do not run this script with privilege rights otherwise NooBaa, 
#    which is run as user 'noob', won't be able to access the TMFS. 
####################################################################

VERBOSE=0
unset GREP_OPTIONS

# if [[ $UID != 0 ]]; then
#     echo "#[INFO] -- Re-running this script with 'root' privileges --"
#     echo
#     exec sudo --preserve-env bash "$0" "$@"
# fi

echo "#-- Setting the TMFS data directory ----------------------"
export TMFS_DATA_DIR="/noobaa_storage"
if [ ! -d "${TMFS_DATA_DIR}" ]; then
  echo "[WARNING] Directory '${TMFS_DATA_DIR}' does not exist..."
  exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] TMFS data directory is: '${TMFS_DATA_DIR}'"
    echo
fi

echo "#-- Setting the TMFS work directory ----------------------"
export TMFS_WORK_DIR="/tmfs/tmfs_db"
mkdir -p /tmfs/tmfs_db
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to create directory /tmfs/tmfs_db"
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] TMFS_WORK_DIR directory is: '${TMFS_WORK_DIR}'"
    echo
fi

echo "#-- Setting BASEDEV --------------------------------------"
BASEDEV=$(findmnt -n -o SOURCE -M /noobaa_storage) # [TODO-FIXME] ${TMFS_DATA_DIR}
export BASEDEV=$(echo ${BASEDEV} | sed 's/,/\\,/g')
if [ -z "${BASEDEV}" ]; then
    echo "[ERROR] BASEDEV is is empty."
    exit 1;
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] BASEDEV=${BASEDEV}"
    echo 
fi

echo "#-- Setting ADMIN_KEY ------------------------------------"
if [ -z "${CEPH_ADMIN_KEY}" ]; then
    echo "[WARNING] Secret CEPH_ADMIN_KEY is not set..."
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] CEPH_ADMIN_KEY=${CEPH_ADMIN_KEY}"
    echo
fi

echo "#-- Setting TMFS mount options ---------------------------"
MOUNT_OPTIONS="name=admin\\,secret=${CEPH_ADMIN_KEY}"
if [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] The TMFS mount options are: '${MOUNT_OPTIONS}' "
    echo
fi 

echo "#-- Retrieve MEDIUM CHARGER ------------------------------"
#-- Retrieve the 1st generic SCSI device file corresponding to an IBM Medium Changer"
DEVICE="mediumx"; VENDOR="IBM"; PRODUCT="03584L32"
CHANGER=$(lsscsi -g | grep ${DEVICE} | grep ${VENDOR} | grep ${PRODUCT} | head -n 1 | awk '{print $NF}')
if [[ ! ${CHANGER} =~ "/dev/sg" ]]; then
    echo "[WARNING-ERROR] No medium changer device found!"
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] The medium changer device is: '${CHANGER}' "
    echo
fi

echo "#-- Retrieve TAPE DRIVES ---------------------------------"
#-- Retrieve the generic SCSI device files corresponding to IBM Tape Drives
DEVICE="tape"; VENDOR="IBM"; PRODUCT="ULT3580-TD9"
TAPE_DRIVES=($(lsscsi -g | grep ${DEVICE} | grep ${VENDOR} | grep ${PRODUCT} | awk '{print $NF}'))
if [[ ! ${TAPE_DRIVES[0]} =~ "/dev/sg" ]]; then
    echo "[WARNING-ERROR] No tape drive device found!"
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] Found ${#TAPE_DRIVES[@]} tape drive devices"
    for drive in "${TAPE_DRIVES[@]}"; do
        echo -e "\t${drive}"
    done
    echo
fi

echo "#-- Clear existing SCSI reservations ---------------------"
for TAPE_DRIVE in "${TAPE_DRIVES[@]}"; do
    # Read Existing Reservation
    RES=$(sudo sg_persist --in --read-reservation ${TAPE_DRIVE})
    if [ $? -ne 0 ]; then
        echo "[ERROR] Failed to read SCSI reservations for '${TAPE_DRIVE}'"
        exit 1
    elif [ ${VERBOSE} -eq 1 ]; then
        echo "[INFO] Current SCSI reservation for '${TAPE_DRIVE}' "
        echo "${RES}"
    fi
    if [[ ${RES} =~ "Reservation follows:" ]]; then
        echo "[WARNING] A SCSI reservations is in place for '${TAPE_DRIVE}' "
        # Retrieve the reservation type
        RES_TYPE=$(echo "${RES}" | grep -oP ',  type: \K.*')
        if [ $? -ne 0 ]; then
            echo "[ERROR] Failed to retrieve the SCSI reservation type for '${TAPE_DRIVE}' "
            exit 1
        elif [ ${VERBOSE} -eq 1 ]; then
            echo "[INFO] The reservation type for '${TAPE_DRIVE}' is: '${RES_TYPE}'"
        fi
        # Retrieve the reservation key
        RES_KEY=$(echo "${RES}" | grep -oP 'Key=\K0x[0-9a-fA-F]+')
        if [ $? -ne 0 ]; then
            echo "[ERROR] Failed to retrieve the reservation key for '${TAPE_DRIVE}' "
            exit 1
        elif [ ${VERBOSE} -eq 1 ]; then
            echo "[INFO] The reservation key for '${TAPE_DRIVE}' is: '${RES_KEY}'"
        fi
        # Clear the reservation
        if [[ "${RES_TYPE}" == "Exclusive Access" ]]; then
            RES=$(sudo sg_persist --out --clear --param-rk=${RES_KEY} ${TAPE_DRIVE})
            if [ $? -ne 0 ]; then
                echo "[ERROR] Failed to clear the SCSI '${RES_TYPE}}' reservation for '${TAPE_DRIVE}'"
                exit 1
            elif [ ${VERBOSE} -eq 1 ]; then
                echo "[INFO] Cleared the SCSI '${RES_TYPE}}' reservation for '${TAPE_DRIVE}'"
            fi
        else
            echo "[ERROR] The clearing of the SCSI reservation type '${RES_TYPE}' is not supported yet..."
            exit 1
        fi
        # Check if the reservation has been cleared
        RES=$(sudo sg_persist --in --read-reservation ${TAPE_DRIVE})
        if [ $? -ne 0 ]; then
            echo "[ERROR] Failed to read SCSI reservations for '${TAPE_DRIVE}'"
            exit 1
        elif [[ ! ${RES} =~ "there is NO reservation held" ]]; then
            echo "[ERROR] One or more SCSI reservation(s) still pending... "
            exit 1
        fi
    fi

done
echo

if pgrep -x "tmfs" > /dev/null
then
    echo "[INFO] TMFS is already running."
else   
    # Recap all the settings
    echo "[INFO] Summary of the TMFS settings:"
    echo -e "\t BASEDEV is                  : '${BASEDEV}' "
    echo -e "\t The TMFS mount options are  : '${MOUNT_OPTIONS}' "
    echo -e "\t The medium changer device is: '${CHANGER}' "
    echo -e "\t The tape drive device is    : '${TAPE_DRIVES[0]}' "
    echo
    # Note: Allow non-root user to access Fuse filesystem is done during 'noobaa-core' build
    if false; then
        echo "#-- Starting TMFS ----------------------------------------"
        # Unmounting ${TMFS_DATA_DIR}
        if mountpoint -q ${TMFS_DATA_DIR}; then
            if sudo umount ${TMFS_DATA_DIR}; then
                echo "[INFO] '${TMFS_DATA_DIR}' successfully unmounted"
            else
                echo "[ERROR] Failed to unmount '${TMFS_DATA_DIR}'..."
                exit 1
            fi
        else
            echo "[INFO] '${TMFS_DATA_DIR}' was not mounted"
        fi
        # Starting TMFS
        if [ ${VERBOSE} -eq 1 ]; then
            /usr/local/bin/tmfs -f -o allow_other -o basedev="${BASEDEV}" \
                -o mountoptions="${MOUNT_OPTIONS}" -o changer_devname="${CHANGER}" \
                -o mig_wait_sec=0 ${TMFS_DATA_DIR}
        else
            /usr/local/bin/tmfs -o allow_other -o basedev="${BASEDEV}" \
                -o mountoptions="${MOUNT_OPTIONS}" -o changer_devname="${CHANGER}" \
                -o mig_wait_sec=0 ${TMFS_DATA_DIR}  > "/tmp/tmfs_init.log" 2>&1 &
        fi
    else
        echo "[WARNING] Skipping TMFS launch for the time being..."
        echo
    fi
fi
echo