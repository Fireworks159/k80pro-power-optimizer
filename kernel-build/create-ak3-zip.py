#!/usr/bin/env python3
"""Create a standard-compliant AnyKernel3 ZIP file.

Usage: python3 create-ak3-zip.py <source_dir> <output_zip> [kernel_image]

Unlike the `zip` command, this script uses Python's zipfile module
to ensure the ZIP is compatible with all Android recoveries (TWRP,
OrangeFox, etc.) and Magisk/KernelSU apps.
"""
import os
import sys
import zipfile
import stat

def create_zip(src_dir: str, output_zip: str, kernel_image: str | None = None):
    """Create a ZIP preserving Unix permissions."""
    with zipfile.ZipFile(output_zip, 'w', zipfile.ZIP_DEFLATED, allowZip64=False) as zf:
        # Walk the source directory
        for root, dirs, files in os.walk(src_dir):
            # Skip git files
            dirs[:] = [d for d in dirs if '.git' not in d]

            for name in sorted(files):
                if '.git' in name:
                    continue
                filepath = os.path.join(root, name)
                arcname = os.path.relpath(filepath, src_dir)

                # Get file info and preserve permissions
                info = zipfile.ZipInfo(arcname)
                st = os.stat(filepath)
                # Set Unix permissions in external_attr
                info.external_attr = (st.st_mode & 0oFFFF) << 16

                # Force executable bits for tools and update-binary
                if arcname.startswith('tools/') or arcname == 'META-INF/com/google/android/update-binary':
                    info.external_attr = (0o755 & 0oFFFF) << 16

                # Read and write file data
                with open(filepath, 'rb') as src:
                    zf.writestr(info, src.read())

        # Add kernel image if provided
        if kernel_image and os.path.isfile(kernel_image):
            info = zipfile.ZipInfo('Image')
            info.external_attr = (0o644 & 0oFFFF) << 16
            with open(kernel_image, 'rb') as src:
                zf.writestr(info, src.read())

    print(f"Created: {output_zip} ({os.path.getsize(output_zip)} bytes)")

if __name__ == '__main__':
    src_dir = sys.argv[1]
    output_zip = sys.argv[2]
    kernel = sys.argv[3] if len(sys.argv) > 3 else None
    create_zip(src_dir, output_zip, kernel)