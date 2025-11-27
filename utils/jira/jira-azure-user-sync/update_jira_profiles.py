#!/usr/bin/env python3
"""
Script for updating user profiles in Atlassian Organization API
based on comparison report with M365.

Updates:
- Display name (display_name)
- Job title (job_title)
- Department (department)
- Location (location)

Uses M365 data as source of truth.
"""

import os
import sys
import json
import requests
from dotenv import load_dotenv
from typing import Dict, List, Optional
import time


def load_config() -> Dict[str, str]:
    """Loads configuration from .env file"""
    load_dotenv()
    
    config = {
        'org_id': os.getenv('ATLASSIAN_ORG_ID'),
        'org_api_key': os.getenv('ATLASSIAN_ORG_API_KEY'),
    }
    
    missing = []
    if not config['org_id']:
        missing.append('ATLASSIAN_ORG_ID')
    if not config['org_api_key']:
        missing.append('ATLASSIAN_ORG_API_KEY')
    
    if missing:
        print(f"❌ Error: Missing environment variables: {', '.join(missing)}")
        print("\nAdd to .env file:")
        print("ATLASSIAN_ORG_ID=your-org-id")
        print("ATLASSIAN_ORG_API_KEY=your-org-api-key")
        sys.exit(1)
    
    return config


def load_sync_report(filename: str = 'sync_report.json') -> Dict:
    """Loads synchronization report"""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"❌ Error: File {filename} not found")
        print("First run: python compare_users.py")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"❌ Error: File {filename} is not valid JSON")
        sys.exit(1)


def update_user_profile(account_id: str, profile_data: Dict, api_key: str) -> bool:
    """
    Updates user profile in Atlassian Organization API.
    
    Args:
        account_id: User's Account ID
        profile_data: Data to update (job_title, department, location)
        api_key: Organization API key
    
    Returns:
        True if update succeeded, False otherwise
    """
    url = f"https://api.atlassian.com/users/{account_id}/manage/profile"
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {api_key}'
    }
    
    # Prepare payload - flat structure according to API documentation
    # https://developer.atlassian.com/cloud/admin/user-management/rest/api-group-profile/
    payload = {
        'extended_profile': {}
    }
    
    if profile_data.get('job_title') is not None:
        payload['extended_profile']['job_title'] = profile_data['job_title']
    
    if profile_data.get('department') is not None:
        payload['extended_profile']['department'] = profile_data['department']
    
    if profile_data.get('location') is not None:
        payload['extended_profile']['location'] = profile_data['location']
    
    try:
        response = requests.patch(url, headers=headers, json=payload)
        
        if response.status_code in [200, 204]:
            return True
        else:
            print(f"   ⚠️  Status {response.status_code}: {response.text[:200]}")
            return False
            
    except Exception as e:
        print(f"   ❌ Error: {str(e)}")
        return False


def update_user_display_name(account_id: str, display_name: str, api_key: str) -> bool:
    """
    Updates user's display name.
    
    WARNING: Atlassian Organization API may not allow changing display_name
    via API - this field is often managed by the user or SSO.
    
    Args:
        account_id: User's Account ID
        display_name: New display name
        api_key: Organization API key
    
    Returns:
        True if update succeeded, False otherwise
    """
    url = f"https://api.atlassian.com/users/{account_id}/manage/profile"
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {api_key}'
    }
    
    # Flat structure according to documentation
    payload = {
        'name': display_name
    }
    
    try:
        response = requests.patch(url, headers=headers, json=payload)
        
        if response.status_code in [200, 204]:
            return True
        else:
            # Often this field cannot be changed via API
            return False
            
    except Exception:
        return False


def prepare_update_plan(report: Dict) -> List[Dict]:
    """
    Prepares update plan based on report.
    
    For each user in users_with_differences:
    - Checks which fields have differences
    - Prepares data for update from M365
    
    Args:
        report: Report from compare_users.py
    
    Returns:
        List of users to update with data
    """
    updates = []
    
    for user_diff in report.get('users_with_differences', []):
        jira_data = user_diff.get('jira_data', {})
        m365_data = user_diff.get('m365_data', {})
        differences = user_diff.get('differences', {})
        
        account_id = jira_data.get('account_id')
        email = user_diff.get('email')
        
        if not account_id:
            continue
        
        # Check what needs to be updated
        profile_updates = {}
        name_update = None
        has_updates = False
        
        # Display name
        if differences.get('display_name', {}).get('differs'):
            m365_name = m365_data.get('display_name')
            if m365_name:
                name_update = m365_name
                has_updates = True
        
        # Job title - update only if missing in Jira but present in M365
        job_title_msg = differences.get('job_title', {}).get('message', '')
        if 'Missing in Jira' in job_title_msg:
            m365_job = m365_data.get('job_title')
            if m365_job:
                profile_updates['job_title'] = m365_job
                has_updates = True
        
        # Department - update only if missing in Jira but present in M365
        dept_msg = differences.get('department', {}).get('message', '')
        if 'Missing in Jira' in dept_msg:
            m365_dept = m365_data.get('department')
            if m365_dept:
                profile_updates['department'] = m365_dept
                has_updates = True
        
        # Location - update only if missing in Jira but present in M365
        loc_msg = differences.get('location', {}).get('message', '')
        if 'Missing in Jira' in loc_msg:
            m365_loc = m365_data.get('office_location')
            if m365_loc:
                profile_updates['location'] = m365_loc
                has_updates = True
        
        if has_updates:
            updates.append({
                'account_id': account_id,
                'email': email,
                'jira_name': jira_data.get('display_name'),
                'm365_name': m365_data.get('display_name'),
                'name_update': name_update,
                'profile_updates': profile_updates,
                'jira_current': {
                    'job_title': jira_data.get('job_title'),
                    'department': jira_data.get('department'),
                    'location': jira_data.get('location')
                },
                'm365_source': {
                    'job_title': m365_data.get('job_title'),
                    'department': m365_data.get('department'),
                    'location': m365_data.get('office_location')
                }
            })
    
    return updates


def print_update_plan(updates: List[Dict]):
    """Displays update plan before execution"""
    print("="*80)
    print("📋 JIRA PROFILE UPDATE PLAN")
    print("="*80)
    print(f"\nNumber of users to update: {len(updates)}")
    
    if not updates:
        print("\n✅ No users require updates!")
        return
    
    print("\nPreview of first 10 updates:")
    print("-"*80)
    
    for i, update in enumerate(updates[:10], 1):
        print(f"\n[{i}] {update['email']}")
        print(f"    Account ID: {update['account_id']}")
        
        if update.get('name_update'):
            print(f"    📝 Name: '{update['jira_name']}' → '{update['name_update']}'")
        
        profile = update.get('profile_updates', {})
        if profile.get('job_title'):
            jira_val = update['jira_current'].get('job_title') or 'None'
            print(f"    💼 Job title: '{jira_val}' → '{profile['job_title']}'")
        
        if profile.get('department'):
            jira_val = update['jira_current'].get('department') or 'None'
            print(f"    🏢 Department: '{jira_val}' → '{profile['department']}'")
        
        if profile.get('location'):
            jira_val = update['jira_current'].get('location') or 'None'
            print(f"    📍 Location: '{jira_val}' → '{profile['location']}'")
    
    if len(updates) > 10:
        print(f"\n... and {len(updates) - 10} more")


def execute_updates(updates: List[Dict], api_key: str, dry_run: bool = True) -> Dict:
    """
    Executes user profile updates.
    
    Args:
        updates: List of updates to execute
        api_key: Organization API key
        dry_run: If True, only simulates updates
    
    Returns:
        Execution statistics
    """
    if dry_run:
        print("\n" + "="*80)
        print("🔍 TEST MODE (DRY RUN) - Simulating updates")
        print("="*80)
        print("No actual changes will be made.\n")
    else:
        print("\n" + "="*80)
        print("🚀 EXECUTING UPDATES")
        print("="*80)
        print()
    
    stats = {
        'total': len(updates),
        'success': 0,
        'failed': 0,
        'skipped': 0,
        'profile_updated': 0,
        'name_updated': 0,
        'name_failed': 0
    }
    
    for i, update in enumerate(updates, 1):
        email = update['email']
        account_id = update['account_id']
        
        print(f"[{i}/{stats['total']}] {email}")
        
        if dry_run:
            print(f"   ✓ [DRY RUN] Simulating profile update")
            stats['success'] += 1
            if update.get('profile_updates'):
                stats['profile_updated'] += 1
            if update.get('name_update'):
                stats['name_updated'] += 1
            continue
        
        # Actual update
        success = False
        
        # Update profile (job title, department, location)
        if update.get('profile_updates'):
            if update_user_profile(account_id, update['profile_updates'], api_key):
                print(f"   ✓ Profile updated")
                stats['profile_updated'] += 1
                success = True
            else:
                print(f"   ❌ Profile update error")
                stats['failed'] += 1
        
        # Update display name (if needed)
        if update.get('name_update'):
            if update_user_display_name(account_id, update['name_update'], api_key):
                print(f"   ✓ Display name updated")
                stats['name_updated'] += 1
                success = True
            else:
                print(f"   ⚠️  Failed to update name (may be managed by SSO)")
                stats['name_failed'] += 1
        
        if success:
            stats['success'] += 1
        
        # Rate limiting - wait between requests
        time.sleep(0.5)
    
    return stats


def print_summary(stats: Dict):
    """Displays summary of executed updates"""
    print("\n" + "="*80)
    print("📊 SUMMARY")
    print("="*80)
    print(f"\nAll operations:     {stats['total']}")
    print(f"✅ Success:          {stats['success']}")
    print(f"❌ Errors:           {stats['failed']}")
    print(f"⏭️  Skipped:          {stats['skipped']}")
    print(f"\nDetails:")
    print(f"   Profiles updated:          {stats['profile_updated']}")
    print(f"   Names updated:             {stats['name_updated']}")
    print(f"   Names failed:              {stats['name_failed']}")
    
    if stats['name_failed'] > 0:
        print(f"\nℹ️  Display names are often managed by the user or SSO")
        print(f"   and may not be modifiable via Organization API.")


def main():
    """Main program function"""
    print("="*80)
    print("🔄 Updating Jira user profiles from M365 data")
    print("="*80)
    
    # Load configuration
    config = load_config()
    
    # Load report
    print("\n📂 Loading synchronization report...")
    report = load_sync_report()
    
    print(f"   ✓ Loaded report from: {report.get('generated_at')}")
    print(f"   ✓ Comparison mode: {report.get('comparison_mode')}")
    
    stats = report.get('statistics', {})
    print(f"\nReport statistics:")
    print(f"   - Users in Jira: {stats.get('total_jira')}")
    print(f"   - Matched: {stats.get('matched')}")
    print(f"   - With differences: {stats.get('with_differences')}")
    
    # Prepare update plan
    print("\n🔍 Preparing update plan...")
    updates = prepare_update_plan(report)
    
    # Display plan
    print_update_plan(updates)
    
    if not updates:
        return
    
    # Ask for confirmation
    print("\n" + "="*80)
    print("⚠️  WARNING: Updates will change data in Atlassian!")
    print("="*80)
    print("\nOptions:")
    print("  1. Test mode (DRY RUN) - simulation without changes")
    print("  2. Execute updates")
    print("  3. Cancel")
    
    choice = input("\nChoice (1/2/3) [default 1]: ").strip() or "1"
    
    if choice == "1":
        # Dry run
        stats = execute_updates(updates, config['org_api_key'], dry_run=True)
        print_summary(stats)
        print("\n💡 To execute actual updates, run again and choose option 2")
    
    elif choice == "2":
        # Actual updates
        confirm = input("\n⚠️  Are you sure you want to execute updates? (yes/no): ").strip().lower()
        if confirm in ['yes', 'y']:
            stats = execute_updates(updates, config['org_api_key'], dry_run=False)
            print_summary(stats)
            print("\n✅ Updates completed!")
            print("💡 Run compare_users.py again to check results")
        else:
            print("\n❌ Cancelled.")
    
    else:
        print("\n❌ Cancelled.")


if __name__ == '__main__':
    main()
