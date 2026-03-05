#!/bin/bash

default_backup_dir="$HOME/backup"
default_files_dir="$HOME/Documents"
default_file_name="backup_$(date +%Y%m%d).tar.gz"
default_compression_method="gzip"
default_compression_level=5
files_dir="${2:-$default_files_dir}"
backup_dir="${1:-$default_backup_dir}"
compression_method="${3:-$default_compression_method}"
compression_level="${4:-$default_compression_level}"

echo "Starting backup process..."
echo "default_backup_dir: $default_backup_dir"
echo "default_files_dir: $default_files_dir"
echo "default_file_name: $default_file_name"
echo "Files directory: $files_dir"
echo "Backing up to: $backup_dir"

for file in $files_dir/*; do
    if [ -f "$file" ]; then
        echo "Backing up file: $file"
        tar -cvf - "$file" | $compression_method -$compression_level > "$backup_dir/$(basename "$file").tar.gz"
        if [ $? -eq 0 ]; then
            echo "Successfully backed up: $file"
        else
            echo "Failed to back up: $file"
        fi
    else
        echo "Skipping non-file: $file"
    fi
done