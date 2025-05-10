# Define output file name
UBOOT_ROCKCHIP_BIN="u-boot-rockchip.bin"

# Define the offset for u-boot.itb within u-boot-rockchip.bin in bytes
OFFSET_UBOOT_ITB_BYTES=8355840 # This is (16384 - 64) sectors * 512 bytes/sector

echo "IDBLOADER_PATH: $IDBLOADER_PATH"
echo "UBOOT_ITB_PATH: $UBOOT_ITB_PATH"
echo "Target combined file: $UBOOT_ROCKCHIP_BIN"
echo "Offset for u-boot.itb: $OFFSET_UBOOT_ITB_BYTES bytes"

# Copy idbloader.img to be the start of u-boot-rockchip.bin
cp "$IDBLOADER_PATH" "$UBOOT_ROCKCHIP_BIN"

# Pad the u-boot-rockchip.bin file with zeros up to the point where u-boot.itb should start
# This ensures idbloader.img is not overwritten if it's smaller than the offset,
# and the file is extended to the correct size before writing u-boot.itb.
# Using truncate is efficient for creating sparse space if the filesystem supports it,
# or filling with nulls.
truncate -s $OFFSET_UBOOT_ITB_BYTES "$UBOOT_ROCKCHIP_BIN"

# Now, write u-boot.itb at the specified offset
# 'conv=notrunc' ensures that dd does not truncate the output file.
# 'bs=1' ensures byte-level precision for seek.
dd if="$UBOOT_ITB_PATH" of="$UBOOT_ROCKCHIP_BIN" bs=1 seek=$OFFSET_UBOOT_ITB_BYTES conv=notrunc

echo "Created $UBOOT_ROCKCHIP_BIN successfully."
ls -lh "$UBOOT_ROCKCHIP_BIN"
