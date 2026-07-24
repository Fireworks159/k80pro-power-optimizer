# AnyKernel3 Configuration for Redmi K80 Pro (miro)
# K80 Pro Power Optimized Kernel + SukiSU-Ultra Root
# ================================================================

## Kernel Configuration
kernel.string=K80 Pro Power Optimized Kernel by SukiSU-Ultra
kernel.derivative=K80Pro-Power-Kernel

## Target Device
device.name1=miro
device.name2=zircon
device.name3=K80 Pro

## Block Device (auto-detect for A/B slot devices)
block=auto;
is_slot_device=auto;

## Flash Options
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=1

## Supported Partitions
ramdisk_compression=auto;
no_block_display=1

## AnyKernel3 Operations
dump_boot;
split_boot;

write_boot;