#!/usr/bin/env python3
"""Create a standard AnyKernel3 ZIP package.

Usage:
    python3 create-ak3-zip.py <anykernel_template_dir> <output_zip> [kernel_image]

This script rebuilds the AK3 package from a clean AnyKernel3 template directory
and an optional kernel image. It ensures the resulting ZIP is compatible with
Android recoveries (TWRP/OrangeFox) and KernelFlasher/ReKernelFlasher apps.
"""
import os
import sys
import zipfile
import stat


def add_file(zf: zipfile.ZipFile, src_path: str, arcname: str, mode: int):
    """Add a single file to the ZIP with explicit Unix permissions."""
    info = zipfile.ZipInfo(arcname)
    # Unix permissions go in the upper 16 bits of external_attr.
    info.external_attr = (mode & 0o7777) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    with open(src_path, 'rb') as f:
        zf.writestr(info, f.read())


def add_directory(zf: zipfile.ZipFile, arcname: str, mode: int = 0o755):
    """Add an explicit directory entry (helps some recovery ZIP parsers)."""
    if not arcname.endswith('/'):
        arcname += '/'
    info = zipfile.ZipInfo(arcname)
    info.external_attr = ((mode & 0o7777) << 16) | stat.S_IFDIR
    info.compress_type = zipfile.ZIP_STORED
    zf.writestr(info, b'')


def create_zip(src_dir: str, output_zip: str, kernel_image: str | None = None):
    src_dir = os.path.abspath(src_dir)
    output_zip = os.path.abspath(output_zip)

    with zipfile.ZipFile(
        output_zip, 'w', compression=zipfile.ZIP_DEFLATED, allowZip64=False
    ) as zf:
        # Walk the template directory and add every real file.
        for root, dirs, files in os.walk(src_dir):
            # Skip git metadata and macOS resource forks if present.
            dirs[:] = [
                d for d in dirs
                if not d.startswith('.git') and d != '__MACOSX'
            ]

            # Ensure directory entries exist for important paths.
            relpath = os.path.relpath(root, src_dir)
            if relpath != '.':
                add_directory(zf, relpath.replace(os.sep, '/'))

            for name in sorted(files):
                if name.startswith('.git') or name == '.DS_Store':
                    continue
                filepath = os.path.join(root, name)
                if not os.path.isfile(filepath):
                    continue
                arcname = os.path.relpath(filepath, src_dir).replace(os.sep, '/')

                st = os.stat(filepath)
                mode = st.st_mode & 0o777

                # Force executable bits for the update-binary and any tool.
                if arcname == 'META-INF/com/google/android/update-binary':
                    mode = 0o755
                elif arcname.startswith('tools/'):
                    mode = 0o755
                elif mode == 0:
                    mode = 0o644

                add_file(zf, filepath, arcname, mode)

        # Add the kernel image if provided.
        if kernel_image and os.path.isfile(kernel_image):
            add_file(zf, kernel_image, 'Image', 0o644)

    print(f"Created: {output_zip} ({os.path.getsize(output_zip)} bytes)")


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    src = sys.argv[1]
    out = sys.argv[2]
    kernel = sys.argv[3] if len(sys.argv) > 3 else None
    create_zip(src, out, kernel)
