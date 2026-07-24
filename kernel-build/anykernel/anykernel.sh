### AnyKernel3 Ramdisk Mod Script
## Redmi K80 Pro (miro / SM8750)
## K80 Pro Power Optimized Kernel + SukiSU-Ultra Root

### AnyKernel setup
# global properties
properties() { '
kernel.string=K80 Pro Power Optimized Kernel by SukiSU-Ultra
kernel.derivative=K80Pro-Power-Kernel
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=1
device.name1=miro
device.name2=zircon
device.name3=K80 Pro
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
# boot shell variables
BLOCK=auto;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install: replace kernel in boot partition
dump_boot;
write_boot;
## end boot install

## init_boot files attributes
init_boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# init_boot shell variables
BLOCK=init_boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# reset for init_boot patching
reset_ak;

# init_boot install: keep ramdisk modifications (Magisk/KernelSU/SukiSU)
dump_boot;
write_boot;
## end init_boot install
