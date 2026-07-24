### AnyKernel3 Ramdisk Mod Script
## Redmi K80 Pro (miro / SM8750)
## GKI 2.0: boot=kernel only, init_boot=ramdisk
## K80 Pro Power Optimized Kernel

### AnyKernel setup
# global properties
properties() { '
kernel.string=K80 Pro Power Optimized Kernel by SukiSU-Ultra
kernel.derivative=K80Pro-Power-Kernel
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=1
device.name1=miro
device.name2=zircon
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
## GKI 2.0: only flash boot partition (kernel), init_boot (ramdisk) untouched
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install: replace kernel only, no ramdisk modifications
split_boot;
flash_boot;
## end boot install
