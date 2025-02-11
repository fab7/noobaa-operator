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

echo "#-- Setting the TMFS log directory -----------------------"
export TMFS_LOG_DIR="/tmfs_logs"
if [ ! -d "${TMFS_LOG_DIR}" ]; then
    echo "[WARNING] Directory '${TMFS_LOG_DIR}' does not exist"
    exit 1
elif [ ${VERBOSE} -gt 0 ]; then
    echo "[INFO] TMFS_LOG_DIR directory is: '${TMFS_LOG_DIR}' "
    echo
fi

echo "#-- Creating the TMFS_INIT log file ----------------------"
TMFS_INIT_LOG="${TMFS_LOG_DIR}/tmfs_init.log"
touch ${TMFS_INIT_LOG}
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to create the TMFS_INIT log file..."
    exit 1
elif [ ${VERBOSE} -gt 0 ]; then
    echo "[INFO] TMFS_INIT log file created on: $(date)" >> ${TMFS_INIT_LOG}
    echo >> ${TMFS_INIT_LOG}
fi

echo "#-- Setting the TMFS data directory ----------------------" >> ${TMFS_INIT_LOG}
export TMFS_DATA_DIR="/noobaa_storage"
if [ ! -d "${TMFS_DATA_DIR}" ]; then
  echo "[WARNING] Directory '${TMFS_DATA_DIR}' does not exist..." >> ${TMFS_INIT_LOG}
  exit 1
elif [ ${VERBOSE} -gt 0 ]; then
    echo "[INFO] TMFS data directory is: '${TMFS_DATA_DIR}'" >> ${TMFS_INIT_LOG}
    echo >> ${TMFS_INIT_LOG}
fi

echo "#-- Setting the TMFS work directory ----------------------" >> ${TMFS_INIT_LOG}
export TMFS_WORK_DIR="/tmfs_db"
if [ ! -d "${TMFS_WORK_DIR}" ]; then
    echo "[WARNING] Directory '${TMFS_WORK_DIR}' does not exist..." >> ${TMFS_INIT_LOG}
    exit 1
elif [ ${VERBOSE} -gt 0 ]; then
    echo "[INFO] TMFS_WORK_DIR directory is: '${TMFS_WORK_DIR}' " >> ${TMFS_INIT_LOG}
    echo >> ${TMFS_INIT_LOG}
fi

echo "#-- Setting BASEDEV --------------------------------------"  >> ${TMFS_INIT_LOG}
BASEDEV=$(findmnt -n -o SOURCE -M ${TMFS_DATA_DIR})
export BASEDEV=$(echo ${BASEDEV} | sed 's/,/\\,/g')
if [ -z "${BASEDEV}" ]; then
    echo "[ERROR] BASEDEV is is empty." >> ${TMFS_INIT_LOG}
    exit 1;
elif [ ${VERBOSE} -gt 0 ]; then
    echo "[INFO] BASEDEV=${BASEDEV}" >> ${TMFS_INIT_LOG}
    echo  >> ${TMFS_INIT_LOG}
fi

echo "#-- Setting ADMIN_KEY ------------------------------------" >> ${TMFS_INIT_LOG}
if [ -z "${CEPH_ADMIN_KEY}" ]; then
    echo "[WARNING] Secret CEPH_ADMIN_KEY is not set..." >> ${TMFS_INIT_LOG}
    exit 1
elif [ ${VERBOSE} -gt 0 ]; then
    echo "[INFO] CEPH_ADMIN_KEY=${CEPH_ADMIN_KEY}" >> ${TMFS_INIT_LOG} >> ${TMFS_INIT_LOG}
    echo >> ${TMFS_INIT_LOG} >> ${TMFS_INIT_LOG}
fi

echo "#-- Setting TMFS mount options ---------------------------" >> ${TMFS_INIT_LOG}
MOUNT_OPTIONS="name=admin\\,secret=${CEPH_ADMIN_KEY}"
if [ ${VERBOSE} -gt 0 ]; then
    echo "[INFO] The TMFS mount options are: '${MOUNT_OPTIONS}' " >> ${TMFS_INIT_LOG}
    echo >> ${TMFS_INIT_LOG}
fi 

# [INFO]
# The next 2 sections will identify the medium changer and the tape drive
# devices to be used by the BackingStore container. The 3rd section will then
# check if a SCSI reservation is in place and will clear it if required.
#
# [WARNING-TODO-FIXME]
# At this point, we should interact with the TS4500 tape library to find out
# which tape drive is assigned to which logical library. However, for the time
# being, we will assume the following configuration:
#  - there is *ONLY ONE* tape drive assigned per logical library,
#  - the assigned tape drive is *ALWAYS* point-2-point attached to the first
#    port (i.e. port #0) of the *FIRST* host buffer adapter.

echo "#-- Retrieve HOST BUFFER ADAPTERS ------------------------" >> ${TMFS_INIT_LOG}
PCI_ADDRS=$(lspci | grep -i "Fibre Channel" | awk '{print $1}')
readarray -t PCI_ADDRS <<< "${PCI_ADDRS}"
if [[ ${#PCI_ADDRS[@]} = 0 ]]; then
    echo "[WARNING-ERROR] No Fibre Channel host buffer adapter found!" >> ${TMFS_INIT_LOG}
    exit 1
elif [ ${VERBOSE} -gt 0 ]; then
    echo "[INFO] Found ${#PCI_ADDRS[@]} Fibre Channel ports" >> ${TMFS_INIT_LOG}
fi
echo "[INFO] Selecting Fibre Channel HBA located at PCI address '${PCI_ADDRS[0]}'" >> ${TMFS_INIT_LOG}

echo "#-- Retrieve SCSI_HOST -----------------------------------" >> ${TMFS_INIT_LOG}
SCSI_HOST_NAME=$(basename /sys/bus/pci/devices/0000:${PCI_ADDRS[0]}/host*)
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to retrieve the SCSI host name for PCI address '${PCI_ADDR[0]}'" >> ${TMFS_INIT_LOG}
    exit 1
fi
#-- Extract the SCSI host number
SCSI_HOST="${SCSI_HOST_NAME:4}"
echo "[INFO] The corresponding SCSI host is 'host${SCSI_HOST}'" >> ${TMFS_INIT_LOG}

echo "#-- Retrieve MEDIUM CHANGERS -----------------------------" >> ${TMFS_INIT_LOG}
DEVICE="mediumx"; VENDOR="IBM"; PRODUCT="03584L32"
PHY_CHANGERS=$(lsscsi -g | grep "^\[${SCSI_HOST}:" | grep ${DEVICE} | awk '{print $(NF-1)}')
GEN_CHANGERS=$(lsscsi -g | grep "^\[${SCSI_HOST}:" | grep ${DEVICE} | awk '{print $(NF)}')
readarray -t PHY_CHANGERS <<< "${PHY_CHANGERS}"
readarray -t GEN_CHANGERS <<< "${GEN_CHANGERS}"
#-- Retrieve the physical IBM Medium Changers
if [[ ${#PHY_CHANGERS[@]} = 0 ]]; then
    echo "[ERROR] No physical medium changer device found!" >> ${TMFS_INIT_LOG}
    exit 1
else
    for PHY_CHANGER in "${PHY_CHANGERS}"; do
        if [[ ! ${PHY_CHANGER} =~ "/dev/sch" ]]; then
            echo "[ERROR] Expecting physical medium changer device name to match '/dev/sch' but found '${PHY_CHANGER}'!" >> ${TMFS_INIT_LOG}
            exit 1
        fi
    done
fi
#-- Retrieve the generic IBM Medium Changers
if [[ ${#GEN_CHANGERS[@]} = 0 ]]; then
    echo "[ERROR] No generic medium changer device found!" >> ${TMFS_INIT_LOG}
    exit 1
else
    for GEN_CHANGER in "${GEN_CHANGERS}"; do
        if [[ ! ${GEN_CHANGER} =~ "/dev/sg" ]]; then
            echo "[ERROR] Expecting generic medium changer device name to match '/dev/sg' but found '${GEN_CHANGER}'!" >> ${TMFS_INIT_LOG}
            exit 1
        fi
    done
fi
#-- Only keep the 1st generic IBM Medium Changer
GEN_CHANGER=${GEN_CHANGERS[0]}
if [ ${VERBOSE} -gt 0 ]; then
    if [[ ${#GEN_CHANGERS[@]} -gt 1 ]]; then
        echo "[INFO] Found ${#GEN_CHANGERS[@]} medium changers." >> ${TMFS_INIT_LOG}
        echo "[INFO] Selecting the first one: '${GEN_CHANGER}'" >> ${TMFS_INIT_LOG}
    else
        echo "[INFO] Found medium changer to be '${GEN_CHANGER}'" >> ${TMFS_INIT_LOG}
    fi
fi

echo "#-- Retrieve TAPE DRIVES ---------------------------------" >> ${TMFS_INIT_LOG}
DEVICE="tape"; VENDOR="IBM"; PRODUCT="ULT3580-TD9"
PHY_DRIVES=$(lsscsi -g | grep "^\[${SCSI_HOST}:" | grep ${DEVICE} | awk '{print $(NF-1)}')
GEN_DRIVES=$(lsscsi -g | grep "^\[${SCSI_HOST}:" | grep ${DEVICE} | awk '{print $(NF)}')
readarray -t PHY_DRIVES <<< "${PHY_DRIVES}"
readarray -t GEN_DRIVES <<< "${GEN_DRIVES}"
#-- Retrieve the physical IBM Tape Drives
if [[ ${#PHY_DRIVES[@]} = 0 ]]; then
    echo "[ERROR] No physical tape drive device found!" >> ${TMFS_INIT_LOG}
    exit 1
else
    for PHY_DRIVE in "${PHY_DRIVES}"; do
        if [[ ! ${PHY_DRIVE} =~ "/dev/st" ]]; then
            echo "[ERROR] Expecting physical tape drive name to match '/dev/st' but found '${PHY_DRIVE}'!" >> ${TMFS_INIT_LOG}
            exit 1
        fi
    done     
fi
#-- Retrieve the generic IBM Tape Drives
if [[ ${#GEN_DRIVES[@]} = 0 ]]; then
    echo "[ERROR] No generic tape drive device found!" >> ${TMFS_INIT_LOG}
    exit 1
else
    for GEN_DRIVE in "${GEN_DRIVES}"; do
        if [[ ! ${GEN_DRIVE} =~ "/dev/sg" ]]; then
            echo "[ERROR] Expecting generic tape drive device name to match '/dev/sg' but found '${GEN_DRIVE}'!" >> ${TMFS_INIT_LOG}
            exit 1
        fi
    done
fi
#-- Only keep the 1st generic IBM Tape Drive
GEN_DRIVE=${GEN_DRIVE[0]}
if [ ${VERBOSE} -gt 0 ]; then
    if [[ ${#GEN_DRIVES[@]} -gt 1 ]]; then
        echo "[INFO] Found ${#GEN_DRIVES[@]} tape drives." >> ${TMFS_INIT_LOG}
        echo "[INFO] Selecting the first one: '${GEN_DRIVE}'" >> ${TMFS_INIT_LOG}
    else
        echo "[INFO] Found tape drive to be '${GEN_DRIVE}'" >> ${TMFS_INIT_LOG}
    fi
fi

echo "#-- Check and clear existing SCSI reservations -----------" >> ${TMFS_INIT_LOG}
GEN_DEVS=("${GEN_CHANGER}" "${GEN_DRIVE}")
for GEN_DEV in "${GEN_DEVS[@]}"; do
    RES=$(sudo sg_persist --in --read-reservation ${GEN_DEV})
    if [[ ${RES} =~ "Unit attention" ]]; then
        echo "[WARNING] The SCSI device '${GEN_DEV}'experienced a Unit Attention condition in the past. ${RES}" >> ${TMFS_INIT_LOG}
        echo "[INFO] Trying to read the SCSI reservation a second time..." >> ${TMFS_INIT_LOG}
        RES=$(sudo sg_persist --in --read-reservation ${GEN_DEV})
    fi
    if [ $? -ne 0 ]; then
        echo "[ERROR] Failed to read SCSI reservations for '${GEN_DEV}'" >> ${TMFS_INIT_LOG}
        exit 1
    elif [ ${VERBOSE} -gt 0 ]; then
        echo "[INFO] Current SCSI reservation for '${GEN_DEV}' " >> ${TMFS_INIT_LOG}
        echo "${RES}" >> ${TMFS_INIT_LOG}
    fi
    if [[ ${RES} =~ "Reservation follows:" ]]; then
        echo "[WARNING] A SCSI reservations is in place for '${GEN_DEV}' " >> ${TMFS_INIT_LOG}
        # Retrieve the reservation type
        RES_TYPE=$(echo "${RES}" | grep -oP ',  type: \K.*')
        if [ $? -ne 0 ]; then
            echo "[ERROR] Failed to retrieve the SCSI reservation type for '${GEN_DEV}' " >> ${TMFS_INIT_LOG}
            exit 1
        elif [ ${VERBOSE} -gt 0 ]; then
            echo "[INFO] The reservation type for '${GEN_DEV}' is: '${RES_TYPE}'" >> ${TMFS_INIT_LOG}
        fi
        # Retrieve the reservation key
        RES_KEY=$(echo "${RES}" | grep -oP 'Key=\K0x[0-9a-fA-F]+')
        if [ $? -ne 0 ]; then
            echo "[ERROR] Failed to retrieve the reservation key for '${GEN_DEV}' " >> ${TMFS_INIT_LOG}
            exit 1
        elif [ ${VERBOSE} -gt 0 ]; then
            echo "[INFO] The reservation key for  '${GEN_DEV}' is: '${RES_KEY}'" >> ${TMFS_INIT_LOG}
        fi
        # Clear the reservation
        if [[ "${RES_TYPE}" == "Exclusive Access" ]]; then
            RES=$(sudo sg_persist --out --clear --param-rk=${RES_KEY} ${GEN_DEV})
            if [ $? -ne 0 ]; then
                echo "[ERROR] Failed to clear the SCSI '${RES_TYPE}}' reservation for '${GEN_DEV}'" >> ${TMFS_INIT_LOG}
                exit 1
            elif [ ${VERBOSE} -gt 0 ]; then
                echo "[INFO] Cleared the SCSI '${RES_TYPE}}' reservation for '${GEN_DEV}'" >> ${TMFS_INIT_LOG}
            fi
        else
            echo "[ERROR] The clearing of the SCSI reservation type '${RES_TYPE}' is not supported yet..." >> ${TMFS_INIT_LOG}
            exit 1
        fi
        # Check if the reservation has been cleared
        RES=$(sudo sg_persist --in --read-reservation ${GEN_DEV})
        if [ $? -ne 0 ]; then
            echo "[ERROR] Failed to read SCSI reservations for '${GEN_DEV}'" >> ${TMFS_INIT_LOG}
            exit 1
        elif [[ ! ${RES} =~ "there is NO reservation held" ]]; then
            echo "[ERROR] One or more SCSI reservation(s) still pending... " >> ${TMFS_INIT_LOG}
            exit 1
        fi
    fi
done
echo >> ${TMFS_INIT_LOG}

if pgrep -x "tmfs" > /dev/null
then
    echo "[INFO] TMFS is already running." >> ${TMFS_INIT_LOG}
else   
    # Recap all the settings
    echo "[INFO] Summary of the TMFS settings:" >> ${TMFS_INIT_LOG}
    echo -e "\t TMFS data directory is      : '${TMFS_DATA_DIR}' " >> ${TMFS_INIT_LOG}
    echo -e "\t TMFS work directory is      : '${TMFS_WORK_DIR}' " >> ${TMFS_INIT_LOG}
    echo -e "\t TMFS log  directory is      : '${TMFS_LOG_DIR}'  " >> ${TMFS_INIT_LOG}
    echo -e "\t BASEDEV is                  : '${BASEDEV}'       " >> ${TMFS_INIT_LOG}
    echo -e "\t The TMFS mount options are  : '${MOUNT_OPTIONS}' " >> ${TMFS_INIT_LOG}
    echo -e "\t The medium changer device is: '${GEN_CHANGER}'   " >> ${TMFS_INIT_LOG}
    echo -e "\t The tape drive device is    : '${GEN_DRIVE}'     " >> ${TMFS_INIT_LOG}
    echo >> ${TMFS_INIT_LOG}
    # Note: Allow non-root user to access Fuse filesystem is done during 'noobaa-core' build
    if true; then
        echo "#-- Starting TMFS ----------------------------------------" >> ${TMFS_INIT_LOG}
        # Unmounting ${TMFS_DATA_DIR}
        if mountpoint -q ${TMFS_DATA_DIR}; then
            if ! sudo umount ${TMFS_DATA_DIR}; then
                echo "[ERROR] Failed to unmount '${TMFS_DATA_DIR}'..." >> ${TMFS_INIT_LOG}
                exit 1
            fi
        else
            echo "[INFO] '${TMFS_DATA_DIR}' was not mounted" >> ${TMFS_INIT_LOG}
        fi
        if [ ${VERBOSE} -eq 2 ]; then
            # Starting TMFS in foreground mode
            sudo TMFS_WORK_DIR=${TMFS_WORK_DIR} /usr/local/bin/tmfs -f \
                -o allow_other -o basedev="${BASEDEV}" \
                -o mountoptions="${MOUNT_OPTIONS}" -o changer_devname="${GEN_CHANGER}" \
                -o mig_wait_sec=0 ${TMFS_DATA_DIR}
        else
            # Starting TMFS in background mode
            sudo TMFS_WORK_DIR=${TMFS_WORK_DIR} /usr/local/bin/tmfs \
                -o allow_other -o basedev="${BASEDEV}" \
                -o mountoptions="${MOUNT_OPTIONS}" -o changer_devname="${GEN_CHANGER}" \
                -o mig_wait_sec=0 ${TMFS_DATA_DIR}  > "${TMFS_LOG_DIR}/tmfs.log" 2>&1
        fi
        echo "[INFO] 'TMFS successfully started" >> ${TMFS_INIT_LOG}
    else
        echo "[WARNING] Skipping TMFS launch for the time being..." >> ${TMFS_INIT_LOG}
        echo >> ${TMFS_INIT_LOG}
    fi
fi
echo >> ${TMFS_INIT_LOG}