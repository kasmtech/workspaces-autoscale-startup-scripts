#!/usr/bin/env python3
"""
Template processing script for replacing tokens in files.
This script replaces tokens in working_directory with values from versions_file_name.
"""

import argparse
import os
import sys
import re
import subprocess
import yaml
from pathlib import Path

def load_yaml_file(file_path: str) -> dict:
    """
    Load and parse a YAML file using the yaml library.
        
    Raises:
        SystemExit: If file cannot be read or parsed
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: YAML file not found: {file_path}")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error: Failed to parse YAML file {file_path}: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: Failed to read YAML file {file_path}: {e}")
        sys.exit(1)


def get_nested_value(data: dict, key_path: str) -> str:
    """
    Get a nested value from a dictionary using dot notation.
    """
    keys = key_path.split('.')
    current = data
    
    for key in keys:
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return None
    
    return str(current) if current is not None else None


def replace_tokens_in_content(content: str, values_dict: dict, iteration: int = None) -> str:
    """
    Replace tokens in content using values from a dictionary.
    Tokens are in the format {{ key.path }}
    """
    # Pattern to match {{ key.path }} tokens
    pattern = r'\{\{\s*([^}]+)\s*\}\}'
    
    def replace_token(match):
        token = match.group(1).strip()
        value = get_nested_value(values_dict, token)
        if value is not None:
            iteration_str = f" (iteration {iteration})" if iteration is not None else ""
            print(f"  Replacing {{ {token} }} with '{value}'{iteration_str}")
            return value
        else:
            iteration_str = f" (iteration {iteration})" if iteration is not None else ""
            print(f"  Warning: Token {{ {token} }} not found in values{iteration_str}")
            return match.group(0)  # Return original token if not found
    
    return re.sub(pattern, replace_token, content)


def process_file(file_path: Path, values_dict: dict, iteration: int = None) -> bool:
    """
    Process a single file by replacing tokens with values.
    """
    try:
        # Read file content
        with open(file_path, 'r', encoding='utf-8') as f:
            original_content = f.read()
        
        # Replace tokens
        new_content = replace_tokens_in_content(original_content, values_dict, iteration)
        
        # Write back if content changed
        if new_content != original_content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            return True
        else:
            return False
            
    except Exception as e:
        print(f"Error processing file {file_path}: {e}")
        return False


def process_versions_file_recursively(versions_file: Path, max_iterations: int = 10) -> int:
    """
    Recursively process the versions file until no more changes are made.
    """
    print(f"Starting recursive processing of {versions_file.name}")
    
    for i in range(1, max_iterations + 1):
        print(f"\nIteration {i}")

        # Load current values
        current_values = load_yaml_file(versions_file)
        
        # Process the file
        modified = process_file(versions_file, current_values, i)

        if not modified:
            print(f"No changes made in iteration {i}")
            print(f"Recursive processing completed after {i} iteration(s)")
            return i
        else:
            print(f"File modified in iteration {i}")
        
    print(f"Warning: Maximum iterations ({max_iterations}) reached. There may be circular references or unresolvable tokens.")
    
    return max_iterations


def process_templates(working_dir: str, versions_file_name: str):
    """
    Process templates in two phases within a working directory:
    1. Recursively update tokens in versions_file_name until no more changes
    2. Update all other files using values from versions_file_name
    """
    
    # Get paths
    work_directory = Path(working_dir).resolve()
    versions_file = work_directory / versions_file_name
    
    print(f"Working directory: {work_directory}")
    print(f"Versions file: {versions_file}")
    
    # Verify paths exist
    if not work_directory.exists():
        print(f"Error: Working directory not found: {work_directory}")
        sys.exit(1)
    
    if not work_directory.is_dir():
        print(f"Error: Working directory path is not a directory: {work_directory}")
        sys.exit(1)
    
    if not versions_file.exists():
        print(f"Error: Versions file not found: {versions_file}")
        sys.exit(1)
    
    # Recursively update target versions_file
    iterations_performed = process_versions_file_recursively(versions_file)
    
    # Load updated target versions and process all other files
    print(f"\nProcessing all other files")
    updated_values = load_yaml_file(versions_file)
    print(f"Loaded final values from {versions_file_name}")
    
    processed_files = 1
    modified_files = 1 if iterations_performed > 1 else 0
    
    # Process all files in working directory except versions_file
    for file_path in work_directory.rglob('*'):
        if file_path.is_file() and file_path != versions_file:
            try:
                # Skip binary files by checking if we can read them as text
                with open(file_path, 'r', encoding='utf-8') as f:
                    f.read(1)  # Try to read one character
                
                relative_path = file_path.relative_to(work_directory)
                print(f"Processing: {relative_path}")
                processed_files += 1
                
                if process_file(file_path, updated_values):
                    modified_files += 1
                    print(f"  File modified")
                else:
                    print(f"  No changes needed")
                    
            except (UnicodeDecodeError, UnicodeError):
                relative_path = file_path.relative_to(work_directory)
                print(f"Skipping binary file: {relative_path}")
            except Exception as e:
                relative_path = file_path.relative_to(work_directory)
                print(f"Error reading file {relative_path}: {e}")
    
    print(f"\n=== Template Processing Complete ===")
    print(f"Files processed: {processed_files}")
    print(f"Files modified: {modified_files}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Process template files by replacing tokens with values from a YAML file.",
        formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument(
        'working_directory',
        help='Directory containing all files to process'
    )
    
    parser.add_argument(
        'versions_file_name',
        help='Name of the versions YAML file within the working directory'
    )

    args = parser.parse_args()
    
    print(f"\n=== Template Processing Started ===")
    print(f"Working directory: {args.working_directory}")
    print(f"Source versions file: {args.versions_file_name}")
    
    process_templates(args.working_directory, args.versions_file_name)