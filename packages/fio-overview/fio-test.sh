#!/usr/bin/env bash
# 
# This script performs FIO performance tests on a specified bcachefs mount point.
# It expects the mount point as its first argument.

# Check if a mount point argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <MOUNT_POINT>"
    echo "Example: $0 /mnt/volume"
    exit 1
fi

MOUNT_POINT="$1"

# Ensure the directory exists
if [ ! -d "$MOUNT_POINT" ]; then
    echo "Error: Directory '$MOUNT_POINT' does not exist or is not a directory."
    echo "Please ensure the bcachefs filesystem is mounted at the specified path."
    exit 1
fi

echo "Starting FIO performance tests on '$MOUNT_POINT'..."
echo "---"

# Test 1: Sequential Write Throughput (Large Files)
echo "Running Test 1: Sequential Write Throughput (1M BS, 20G size, 5 min runtime)"
fio --name=seq_write_throughput --rw=write --direct=1 --bs=1M --size=20G --runtime=300s --ioengine=libaio --numjobs=4 --group_reporting --directory="$MOUNT_POINT"
echo "---"

# Test 2: Sequential Read Throughput
echo "Running Test 2: Sequential Read Throughput (1M BS, 20G size, 5 min runtime)"
fio --name=seq_read_throughput --rw=read --direct=1 --bs=1M --size=20G --runtime=300s --ioengine=libaio --numjobs=4 --group_reporting --directory="$MOUNT_POINT"
echo "---"

# Test 3: Random Write IOPS (Small Files)
echo "Running Test 3: Random Write IOPS (4k BS, 10G size, iodepth 64, 5 min runtime)"
fio --name=rand_write_iops --rw=randwrite --direct=1 --bs=4k --size=10G --iodepth=64 --runtime=300s --ioengine=libaio --numjobs=4 --group_reporting --directory="$MOUNT_POINT"
echo "---"

# Test 4: Random Read IOPS
echo "Running Test 4: Random Read IOPS (4k BS, 10G size, iodepth 64, 5 min runtime)"
fio --name=rand_read_iops --rw=randread --direct=1 --bs=4k --size=10G --iodepth=64 --runtime=300s --ioengine=libaio --numjobs=4 --group_reporting --directory="$MOUNT_POINT"
echo "---"

# Test 5: Mixed Read/Write
echo "Running Test 5: Mixed Read/Write (4k BS, 10G size, iodepth 64, 70% read, 5 min runtime)"
fio --name=mixed_workload --rw=randrw --direct=1 --bs=4k --size=10G --iodepth=64 --runtime=300s --ioengine=libaio --numjobs=4 --rwmixread=70 --group_reporting --directory="$MOUNT_POINT"
echo "---"

echo "FIO tests complete. Cleaning up test files..."

# Clean up test files
# IMPORTANT: This command will remove ALL files created by FIO in the specified directory.
# Ensure MOUNT_POINT is correct to avoid accidental data loss.
find "$MOUNT_POINT" -name "*.fio-test-file*" -delete

echo "Test files cleaned up."
echo "Script finished."

