#!/usr/bin/env python3
"""
Package script for creating kasm-windows-startup.zip
This script creates a ZIP archive of all files in the src directory.
The archive is compatible with standard Windows extraction tools.
"""

import argparse
import os
import sys
import zipfile
from pathlib import Path


def create_archive(archive_filename, source_path):
    """
    Create a ZIP archive of the specified source directory.
    
    Args:
        archive_filename (str): Name of the ZIP file to create
        source_path (str): Relative path to the source directory from project root
    """
    
    # Get project root (parent of the build directory)
    build_dir = Path(__file__).parent
    project_root = build_dir.parent
    src_dir = project_root / source_path
    dist_dir = project_root / "dist"
    archive_path = dist_dir / archive_filename
    
    print(f"\n=== Packaging Process Started ===")
    print(f"Source directory: {src_dir}")
    print(f"Output directory: {dist_dir}")
    print(f"Archive path: {archive_path}")
    
    # Create dist directory if it doesn't exist
    dist_dir.mkdir(exist_ok=True)
    print(f"Ensured dist directory exists: {dist_dir}")
    
    # Check if source directory exists
    if not src_dir.exists():
        print(f"Error: Source directory does not exist: {src_dir}")
        sys.exit(1)
    
    if not src_dir.is_dir():
        print(f"Error: Source path is not a directory: {src_dir}")
        sys.exit(1)
    
    # Remove existing archive if it exists
    if archive_path.exists():
        print(f"Removing existing archive: {archive_path}")
        archive_path.unlink()
    
    # Create the ZIP archive
    try:
        with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zipf:
            # Walk through all files in source directory
            file_count = 0
            for file_path in src_dir.rglob('*'):
                if file_path.is_file():
                    # Calculate relative path from source directory
                    relative_path = file_path.relative_to(src_dir)
                    
                    # Add file to archive with forward slashes (Windows compatible)
                    archive_name = str(relative_path).replace(os.sep, '/')
                    
                    print(f"Adding: {archive_name}")
                    zipf.write(file_path, archive_name)
                    file_count += 1
            
            print(f"Archive created successfully with {file_count} files")
            
    except Exception as e:
        print(f"Error creating archive: {e}")
        sys.exit(1)
    
    # Verify the archive was created
    if not archive_path.exists():
        print("Error: Archive file was not created")
        sys.exit(1)
    
    # Show archive info
    archive_size = archive_path.stat().st_size
    print(f"Archive size: {archive_size:,} bytes ({archive_size / 1024 / 1024:.2f} MB)")
    
    # Verify archive integrity
    try:
        with zipfile.ZipFile(archive_path, 'r') as zipf:
            bad_file = zipf.testzip()
            if bad_file:
                print(f"Error: Archive integrity check failed on file: {bad_file}")
                sys.exit(1)
            else:
                print("Archive integrity verified")
    except Exception as e:
        print(f"Error verifying archive: {e}")
        sys.exit(1)

    print(f"=== Packaging Process Complete ===")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Create a ZIP archive of all files in a source directory.",
        formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument(
        'archive_filename',
        help='Name of the ZIP file to create.'
    )
    
    parser.add_argument(
        'source_path',
        help='Relative path to the source directory from project root (e.g., "src")'
    )

    args = parser.parse_args()
   
    create_archive(args.archive_filename, args.source_path)