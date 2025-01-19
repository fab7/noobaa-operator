#!/bin/sh

# This script automates the procedure for tagging and pushing the latest 
# NooBaa Operator Image that includes the tiering management file system (TMFS)
# to https://quay.io/repository/fab/noobaa-operator-tmfs.
#
# The script is expected to be run after a NooBaa-Operator build done by:
#      $ make clean; make gen-api; make clean
# 

echo
echo "Tagging and pushing the NooBaa Operator image to Quay.io"
echo "========================================================"

# STEP-1: List created image
docker images noobaa/noobaa-operator
echo

# STEP-2: Set the NooBaa CLI version (NOOB-CLI).
NOOB_CLI="5.18.0"
echo "NooBaa CLI version: $NOOB_CLI"

# STEP-3: Retrieve the commit date of the master branch on which the tmfs-devel branch is based.
master_date=$(git show -s --format=%ci $(git merge-base master tmfs-devel) | cut -d' ' -f1 | sed 's/-//g')
echo "Master branch commit date: $master_date"

# STEP-4: Tag the new image
docker tag noobaa/noobaa-operator:${NOOB_CLI} quay.io/fab/noobaa-operator-tmfs:master-${master_date}-tmfs-devel-$(date +%Y%m%d)
docker images quay.io/fab/noobaa-operator-tmfs:master-${master_date}-tmfs-devel-$(date +%Y%m%d)
echo

# STEP-5: Push the newly created image to Quay.io
docker push quay.io/fab/noobaa-operator-tmfs:master-${master_date}-tmfs-devel-$(date +%Y%m%d)
echo
