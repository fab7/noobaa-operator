####################################################################
#
#    SCRIPT TO START THE TIERING MANAGEMENT FILE SYSTEM (TMFS)
#                    on a KUBERNETES NODE
#
# Warning: 
#  - Do not run this script with privilege rights otherwise NooBaa, 
#    which is run as user 'noob', won't be able to access the TMFS. 
####################################################################

VERBOSE=1
unset GREP_OPTIONS

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
export TMFS_WORK_DIR="/tmfs_db"
mkdir -p ${TMFS_WORK_DIR}
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to create directory '${TMFS_WORK_DIR}' "
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] TMFS_WORK_DIR directory is: '${TMFS_WORK_DIR}' "
    echo
fi

echo "#-- Setting the TMFS log directory -----------------------"
export TMFS_LOG_DIR="/tmfs_logs"
mkdir -p ${TMFS_LOG_DIR}
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to create directory '${TMFS_LOG_DIR}' "
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] TMFS_LOG_DIR directory is: '${TMFS_LOG_DIR}' "
    echo
fi

echo "#-- Setting BASEDEV --------------------------------------"
BASEDEV=$(findmnt -n -o SOURCE -M ${TMFS_DATA_DIR})
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

# [OBSOLETE - This part is now handled by the initContainer]
# echo "#-- Re-Scanning the SCSI Bus -----------------------------"
# #-- This operation might be required if you changed any HW config
# SCSI_HOSTS=($(ls /sys/class/scsi_host))
# if [[ ! ${SCSI_HOSTS[0]} =~ "host" ]]; then
#     echo "[WARNING-ERROR] No SCSI host adapter found!"
#     exit 1
# elif [ ${VERBOSE} -eq 1 ]; then
#     echo "[INFO] Found ${#SCSI_HOSTS[@]} SCSI host adapter ports"
# fi
# #-- WARNING: This operation should be performed on the Host (Safer)
# sudo mount -o remount,rw /sys
# for host in "${SCSI_HOSTS[@]}"; do
#     echo "- - -" | sudo tee /sys/class/scsi_host/${host}/scan 2>&1 > /dev/null
#     if [ $? -ne 0 ]; then
#         echo "[ERROR] Failed to re-scan SCSI host adapter port: ${host}"
#         exit 1
#     elif [ ${VERBOSE} -eq 1 ]; then
#         echo "[INFO] Re-scanned SCSI host adapter port: ${host}"
#     fi
# done
# sudo mount -o remount,ro /sys 
# # echo

echo "#-- Retrieve MEDIUM CHANGERS -----------------------------"
DEVICE="mediumx"; VENDOR="IBM"; PRODUCT="03584L32"
PHY_CHANGERS=$(lsscsi -g | grep ${DEVICE} | grep ${VENDOR} | grep ${PRODUCT} | awk '{print $(NF-1)}')
GEN_CHANGERS=$(lsscsi -g | grep ${DEVICE} | grep ${VENDOR} | grep ${PRODUCT} | awk '{print $(NF)}')
readarray -t PHY_CHANGERS <<< "${PHY_CHANGERS}"
readarray -t GEN_CHANGERS <<< "${GEN_CHANGERS}"
#-- Retrieve the 1st physical IBM Medium Changer"
if [[ ${#PHY_CHANGERS[@]} = 0 ]]; then
    echo "[WARNING-ERROR] No physical medium changer device found!"
    exit 1
elif [[ ${PHY_CHANGERS[0]} != "/dev/sch0" ]]; then
    echo "[WARNING-ERROR] Expecting physical medium changer device to be '/dev/sch0' but found '${PHY_CHANGERS[0]}'!"
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] Found ${#PHY_CHANGERS[@]} medium changers"
fi
#-- Retrieve the 1st generic IBM Medium Changer"
if [[ ${#GEN_CHANGERS[@]} = 0 ]]; then
    echo "[WARNING-ERROR] No generic medium changer device found!"
    exit 1
elif [[ ! ${GEN_CHANGERS[0]} =~ "/dev/sg" ]]; then
    echo "[WARNING-ERROR] Expecting generic medium changer device name to match '/dev/sg' but found '${GEN_CHANGERS[0]}'!"
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] Assuming medium device changer to be '${GEN_CHANGERS[0]}' "
fi

echo "#-- Retrieve TAPE DRIVES ---------------------------------"
DEVICE="tape"; VENDOR="IBM"; PRODUCT="ULT3580-TD9"
PHY_DRIVES=$(lsscsi -g | grep ${DEVICE} | grep ${VENDOR} | grep ${PRODUCT} | awk '{print $(NF-1)}')
GEN_DRIVES=$(lsscsi -g | grep ${DEVICE} | grep ${VENDOR} | grep ${PRODUCT} | awk '{print $(NF)}')
readarray -t PHY_DRIVES <<< "${PHY_DRIVES}"
readarray -t GEN_DRIVES <<< "${GEN_DRIVES}"
#-- Retrieve the 1st physical IBM Tape Drive"
if [[ ${#PHY_DRIVES[@]} = 0 ]]; then
    echo "[WARNING-ERROR] No physical tape drive device found!"
    exit 1
elif [[ ! ${PHY_DRIVES[0]} =~ "/dev/st" ]]; then
    echo "[WARNING-ERROR] Expecting physical tape drive name to match '/dev/st' but found '${PHY_DRIVES[0]}'!"
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] Found ${#PHY_DRIVES[@]} tape drives"
fi
#-- Retrieve the 1st generic IBM Tape Drive"
if [[ ${#GEN_DRIVES[@]} = 0 ]]; then
    echo "[WARNING-ERROR] No generic tape drive device found!"
    exit 1
elif [[ ! ${GEN_DRIVES[0]} =~ "/dev/sg" ]]; then
    echo "[WARNING-ERROR] Expecting generic tape drive device name to match '/dev/sg' but found '${GEN_DRIVES[0]}'!"
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] Assuming tape drive to be '${GEN_DRIVES[0]}' "
fi

echo "#-- Clear existing SCSI reservations in TAPE DRIVES ------"
for TAPE_DRIVE in "${GEN_DRIVES[0]}"; do
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
    echo -e "\t TMFS data directory is      : '${TMFS_DATA_DIR}' "
    echo -e "\t TMFS work directory is      : '${TMFS_WORK_DIR}' "
    echo -e "\t TMFS log  directory is      : '${TMFS_LOG_DIR}' "
    echo -e "\t BASEDEV is                  : '${BASEDEV}' "
    echo -e "\t The TMFS mount options are  : '${MOUNT_OPTIONS}' "
    echo -e "\t The medium changer device is: '${CHANGER}' "
    echo -e "\t The tape drive device is    : '${TAPE_DRIVES[0]}' "
    echo
    # Note: Allow non-root user to access Fuse filesystem is done during 'noobaa-core' build
    if true; then
        echo "#-- Starting TMFS ----------------------------------------"
        # Unmounting ${TMFS_DATA_DIR}
        if mountpoint -q ${TMFS_DATA_DIR}; then
            if ! sudo umount ${TMFS_DATA_DIR}; then
                echo "[ERROR] Failed to unmount '${TMFS_DATA_DIR}'..."
                exit 1
            fi
        else
            echo "[INFO] '${TMFS_DATA_DIR}' was not mounted"
        fi
        # Starting TMFS
        if [ ${VERBOSE} -eq 1 ]; then
            sudo TMFS_WORK_DIR=${TMFS_WORK_DIR} /usr/local/bin/tmfs -f \
                -o allow_other -o basedev="${BASEDEV}" \
                -o mountoptions="${MOUNT_OPTIONS}" -o changer_devname="${CHANGER}" \
                -o mig_wait_sec=0 ${TMFS_DATA_DIR}
        else
            sudo TMFS_WORK_DIR=${TMFS_WORK_DIR} /usr/local/bin/tmfs \
                -o allow_other -o basedev="${BASEDEV}" \
                -o mountoptions="${MOUNT_OPTIONS}" -o changer_devname="${CHANGER}" \
                -o mig_wait_sec=0 ${TMFS_DATA_DIR}  > "${TMFS_LOG_DIR}/tmfs.log" 2>&1
        fi
        echo "[INFO] 'TMFS successfully started"
    else
        echo "[WARNING] Skipping TMFS launch for the time being..."
        echo
    fi
fi
echo