VERBOSE=1

echo "#-- Re-Scanning the SCSI Bus -----------------------------"
#-- This operation might be required if you changed a HW config
SCSI_HOSTS=($(ls /sys/class/scsi_host))
if [[ ! ${SCSI_HOSTS[0]} =~ "host" ]]; then
    echo "[WARNING-ERROR] No SCSI host adapter found!"
    exit 1
elif [ ${VERBOSE} -eq 1 ]; then
    echo "[INFO] Found ${#SCSI_HOSTS[@]} SCSI host adapter ports"
fi
for host in "${SCSI_HOSTS[@]}"; do
    echo "- - -" | sudo tee /sys/class/scsi_host/${host}/scan 2>&1 > /dev/null
    if [ $? -ne 0 ]; then
        echo "[ERROR] Failed to re-scan SCSI host adapter port: ${host}"
        exit 1
    elif [ ${VERBOSE} -eq 1 ]; then
        echo "[INFO] Re-scanned SCSI host adapter port: ${host}"
    fi
done
echo