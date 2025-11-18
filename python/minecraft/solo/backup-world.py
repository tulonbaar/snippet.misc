#!/usr/bin/env python3
"""
Minecraft World Backup Script
Creates backups of worlds from CurseForge and FTB Electron App instances.
"""

import os
import sys
import json
import shutil
import tarfile
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple


# Default launcher paths
DEFAULT_PATHS = {
    "curseforge": "/mnt/d/Minecraft/Instances",
    "ftb": "/mnt/c/users/user_name/AppData/local/.ftba/instances"
}

# Configuration file path
CONFIG_FILE = Path.home() / ".minecraft_backup_config.json"

# Default backup folder
BACKUP_BASE_DIR = "/mnt/d/minecraft/backup"


def load_config() -> Dict[str, str]:
    """Loads configuration with launcher paths."""
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading configuration: {e}")
    return DEFAULT_PATHS.copy()


def save_config(config: Dict[str, str]) -> None:
    """Saves configuration with launcher paths."""
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        print(f"Configuration saved to {CONFIG_FILE}")
    except Exception as e:
        print(f"Error saving configuration: {e}")


def check_and_configure_paths(config: Dict[str, str]) -> Dict[str, str]:
    """Checks and configures paths to launcher folders."""
    print("\n=== Path Configuration ===")
    
    for launcher_name, path in config.items():
        print(f"\n{launcher_name.upper()}:")
        print(f"Current path: {path}")
        
        if os.path.exists(path) and os.path.isdir(path):
            print("✓ Path exists")
        else:
            print("✗ Path does not exist or is not a directory")
            change = input(f"Do you want to change the path for {launcher_name}? (y/n): ").lower()
            
            if change == 'y':
                new_path = input(f"Enter new path for {launcher_name}: ").strip()
                if os.path.exists(new_path) and os.path.isdir(new_path):
                    config[launcher_name] = new_path
                    print("✓ Path updated")
                else:
                    print("✗ Provided path does not exist, keeping old value")
    
    save_config(config)
    return config


def get_instances(config: Dict[str, str]) -> List[Tuple[str, str, str]]:
    """
    Collects list of instances from both launchers.
    Returns list of tuples: (launcher_name, instance_name, instance_path)
    """
    instances = []
    
    # Scan CurseForge
    cf_path = config.get("curseforge", "")
    if os.path.exists(cf_path):
        try:
            for item in os.listdir(cf_path):
                instance_path = os.path.join(cf_path, item)
                saves_path = os.path.join(instance_path, "saves")
                
                if os.path.isdir(instance_path) and os.path.exists(saves_path):
                    instances.append(("CurseForge", item, instance_path))
        except Exception as e:
            print(f"Error scanning CurseForge: {e}")
    
    # Scan FTB
    ftb_path = config.get("ftb", "")
    if os.path.exists(ftb_path):
        try:
            for item in os.listdir(ftb_path):
                instance_path = os.path.join(ftb_path, item)
                saves_path = os.path.join(instance_path, "saves")
                
                if os.path.isdir(instance_path) and os.path.exists(saves_path):
                    instances.append(("FTB", item, instance_path))
        except Exception as e:
            print(f"Error scanning FTB: {e}")
    
    return instances


def display_menu(instances: List[Tuple[str, str, str]]) -> Optional[Tuple[str, str, str]]:
    """Displays instance selection menu."""
    if not instances:
        print("\nNo instances found!")
        return None
    
    print("\n=== Available Instances ===")
    for idx, (launcher, name, path) in enumerate(instances, 1):
        print(f"{idx}. [{launcher}] {name}")
    
    print("\n0. Exit")
    
    while True:
        try:
            choice = input("\nSelect instance number: ").strip()
            
            if choice == "0":
                return None
            
            choice_num = int(choice)
            if 1 <= choice_num <= len(instances):
                return instances[choice_num - 1]
            else:
                print(f"Please choose a number between 0 and {len(instances)}")
        except ValueError:
            print("Please enter a valid number")


def create_backup(launcher: str, instance_name: str, instance_path: str) -> bool:
    """
    Creates backup of the saves folder for the given instance.
    """
    saves_path = os.path.join(instance_path, "saves")
    
    if not os.path.exists(saves_path):
        print(f"Saves folder does not exist: {saves_path}")
        return False
    
    # Prepare timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Backup filename
    backup_filename = f"{instance_name}-world-{timestamp}.tar.gz"
    
    # Ensure backup folder exists
    os.makedirs(BACKUP_BASE_DIR, exist_ok=True)
    
    backup_path = os.path.join(BACKUP_BASE_DIR, backup_filename)
    
    # Temporary folder
    temp_dir = f"/tmp/minecraft_backup_{timestamp}"
    temp_saves = os.path.join(temp_dir, "saves")
    
    try:
        print(f"\nCreating backup for instance: {instance_name}")
        print(f"Launcher: {launcher}")
        print(f"Path: {instance_path}")
        
        # Copy to /tmp/
        print(f"Copying to {temp_saves}...")
        shutil.copytree(saves_path, temp_saves)
        
        # Pack to tar.gz
        print(f"Packing to {backup_path}...")
        with tarfile.open(backup_path, "w:gz") as tar:
            tar.add(temp_saves, arcname="saves")
        
        # Remove temporary folder
        print("Cleaning up temporary files...")
        shutil.rmtree(temp_dir)
        
        # Check size
        backup_size = os.path.getsize(backup_path)
        size_mb = backup_size / (1024 * 1024)
        
        print(f"\n✓ Backup created successfully!")
        print(f"  File: {backup_path}")
        print(f"  Size: {size_mb:.2f} MB")
        
        return True
        
    except Exception as e:
        print(f"\n✗ Error creating backup: {e}")
        
        # Cleanup on error
        if os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
            except:
                pass
        
        return False


def main():
    """Main program function."""
    print("=" * 50)
    print("Minecraft World Backup Script")
    print("=" * 50)
    
    # Load configuration
    config = load_config()
    
    # Check and configure paths
    config = check_and_configure_paths(config)
    
    # Collect instance list
    print("\nScanning instances...")
    instances = get_instances(config)
    
    if not instances:
        print("\nNo instances found with 'saves' folder.")
        print("Make sure paths are configured correctly.")
        sys.exit(1)
    
    print(f"Found {len(instances)} instance(s)")
    
    # Selection menu
    while True:
        selected = display_menu(instances)
        
        if selected is None:
            print("\nExiting program...")
            break
        
        launcher, instance_name, instance_path = selected
        
        # Create backup
        success = create_backup(launcher, instance_name, instance_path)
        
        # Ask about next backup
        if success:
            another = input("\nDo you want to create another backup? (y/n): ").lower()
            if another != 'y':
                print("\nExiting program...")
                break
    
    print("\nThank you for using this program!")


if __name__ == "__main__":
    main()
