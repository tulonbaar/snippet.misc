#!/usr/bin/env python3
"""
Script comparing user data from Jira and M365.
Generates a report showing where data is out of date.
"""

import json
import sys
from typing import Dict, List, Tuple, Optional
from datetime import datetime


def load_json_file(filename: str) -> List[Dict]:
    """Loads data from JSON file"""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"❌ File not found: {filename}")
        print(f"   Run the appropriate data fetching script first.")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"❌ JSON parsing error in file {filename}: {e}")
        sys.exit(1)


def normalize_email(email: Optional[str]) -> str:
    """Normalizes email to lowercase, handles None"""
    if not email or email == 'N/A':
        return ''
    return email.lower().strip()


def create_email_mapping(users: List[Dict], email_field: str) -> Dict[str, Dict]:
    """
    Creates email -> user mapping
    
    Args:
        users: List of users
        email_field: Name of email field ('email' for M365, 'email' for Jira)
    
    Returns:
        Dictionary {email: user_data}
    """
    mapping = {}
    for user in users:
        email = normalize_email(user.get(email_field))
        if email:
            mapping[email] = user
    return mapping


def compare_field(jira_value: Optional[str], m365_value: Optional[str]) -> Tuple[bool, str]:
    """
    Compares field values from Jira and M365
    
    Returns:
        (is_different, status_message)
    """
    # Normalize values
    jira_val = (jira_value or '').strip()
    m365_val = (m365_value or '').strip()
    
    # Handle empty values
    if not jira_val and not m365_val:
        return False, "✓ Both empty"
    
    if not jira_val:
        return True, f"⚠️  Missing in Jira (M365: '{m365_val}')"
    
    if not m365_val:
        return True, f"⚠️  Missing in M365 (Jira: '{jira_val}')"
    
    # Compare values
    if jira_val.lower() == m365_val.lower():
        return False, f"✓ '{m365_val}'"
    
    return True, f"❌ Mismatch: Jira='{jira_val}' ≠ M365='{m365_val}'"


def compare_users(jira_users: List[Dict], m365_users: List[Dict], has_profiles: bool = False) -> Dict:
    """
    Compares users from both systems and generates difference report.
    
    Args:
        jira_users: List of users from Jira
        m365_users: List of users from M365
        has_profiles: Whether Jira data contains profiles (job title/department/location)
    
    Returns:
        Dictionary with comparison results
    """
    print("🔍 Comparing users from Jira and M365...")
    
    if not has_profiles:
        print("ℹ️  Mode: basic comparison (display names only)")
        print("   M365 data will be shown as source of truth\n")
    else:
        print("ℹ️  Mode: full comparison (names + job title + department + location)\n")
    
    # Create email -> user mappings
    jira_map = create_email_mapping(jira_users, 'email')
    m365_map = create_email_mapping(m365_users, 'email')
    
    # Filter only 'atlassian' type users (real users)
    jira_real_users = {
        email: user for email, user in jira_map.items() 
        if user.get('account_type') == 'atlassian'
    }
    
    print(f"  📊 Jira: {len(jira_real_users)} users (atlassian)")
    print(f"  📊 M365: {len(m365_map)} active users")
    
    # Results
    results = {
        'matched': [],           # Users found in both systems
        'only_jira': [],        # Only in Jira
        'only_m365': [],        # Only in M365
        'differences': [],      # Users with data differences
        'stats': {},
        'has_profiles': has_profiles
    }
    
    # Compare users
    for email, jira_user in jira_real_users.items():
        if email in m365_map:
            m365_user = m365_map[email]
            
            # Always compare display name
            diff_display_name = compare_field(
                jira_user.get('display_name'),
                m365_user.get('display_name')
            )
            
            if has_profiles:
                # Full comparison with profiles
                diff_job_title = compare_field(
                    jira_user.get('job_title'),
                    m365_user.get('job_title')
                )
                
                diff_department = compare_field(
                    jira_user.get('department'),
                    m365_user.get('department')
                )
                
                diff_location = compare_field(
                    jira_user.get('location'),
                    m365_user.get('office_location')
                )
                
                has_differences = any([
                    diff_display_name[0],
                    diff_job_title[0],
                    diff_department[0],
                    diff_location[0]
                ])
                
                differences_dict = {
                    'display_name': diff_display_name,
                    'job_title': diff_job_title,
                    'department': diff_department,
                    'location': diff_location
                }
            else:
                # Compare name only, rest as info
                m365_job_title = m365_user.get('job_title') or 'None'
                m365_department = m365_user.get('department') or 'None'
                m365_location = m365_user.get('office_location') or 'None'
                
                has_differences = diff_display_name[0]
                
                differences_dict = {
                    'display_name': diff_display_name,
                    'job_title': (False, f"ℹ️  M365: '{m365_job_title}'"),
                    'department': (False, f"ℹ️  M365: '{m365_department}'"),
                    'location': (False, f"ℹ️  M365: '{m365_location}'")
                }
            
            user_comparison = {
                'email': email,
                'jira': jira_user,
                'm365': m365_user,
                'differences': differences_dict,
                'has_differences': has_differences
            }
            
            results['matched'].append(user_comparison)
            
            if has_differences:
                results['differences'].append(user_comparison)
        else:
            results['only_jira'].append(jira_user)
    
    # Find users only in M365
    for email, m365_user in m365_map.items():
        if email not in jira_real_users:
            results['only_m365'].append(m365_user)
    
    # Statistics
    results['stats'] = {
        'total_jira': len(jira_real_users),
        'total_m365': len(m365_map),
        'matched': len(results['matched']),
        'with_differences': len(results['differences']),
        'only_jira': len(results['only_jira']),
        'only_m365': len(results['only_m365'])
    }
    
    return results


def print_report(results: Dict, has_profiles: bool = False):
    """Displays comparison report"""
    stats = results['stats']
    
    print("\n" + "="*80)
    print("📊 JIRA ↔ M365 COMPARISON REPORT")
    print("="*80)
    
    print(f"\n📈 Statistics:")
    print(f"   Users in Jira:             {stats['total_jira']}")
    print(f"   Users in M365:             {stats['total_m365']}")
    print(f"   Matched (same email):      {stats['matched']}")
    print(f"   With data differences:     {stats['with_differences']} {'❌' if stats['with_differences'] > 0 else '✅'}")
    print(f"   Only in Jira:              {stats['only_jira']}")
    print(f"   Only in M365:              {stats['only_m365']}")
    
    # Users with differences
    if results['differences']:
        print(f"\n{'='*80}")
        if has_profiles:
            print(f"❌ USERS WITH OUTDATED DATA IN JIRA ({len(results['differences'])})")
        else:
            print(f"❌ USERS WITH DISPLAY NAME DIFFERENCES ({len(results['differences'])})")
        print(f"{'='*80}")
        
        for i, comp in enumerate(results['differences'], 1):
            print(f"\n[{i}] {comp['email']}")
            print(f"    Display name:  {comp['differences']['display_name'][1]}")
            
            if has_profiles:
                print(f"    Job title:     {comp['differences']['job_title'][1]}")
                print(f"    Department:    {comp['differences']['department'][1]}")
                print(f"    Location:      {comp['differences']['location'][1]}")
    else:
        if has_profiles:
            print(f"\n✅ All matched data is consistent!")
        else:
            print(f"\n✅ All matched names are consistent!")
    
    # Show sample data
    if not has_profiles and results['matched']:
        print(f"\n{'='*80}")
        print(f"📋 SAMPLE M365 DATA FOR JIRA USERS (first 10)")
        print(f"{'='*80}")
        print("(Job title/department/location information from Microsoft 365)\n")
        
        for i, comp in enumerate(results['matched'][:10], 1):
            m365 = comp['m365']
            name = m365.get('display_name', 'N/A')
            email = comp['email']
            job = m365.get('job_title') or 'None'
            dept = m365.get('department') or 'None'
            loc = m365.get('office_location') or 'None'
            
            print(f"[{i}] {name} ({email})")
            print(f"    Job title:   {job}")
            print(f"    Department:  {dept}")
            print(f"    Location:    {loc}")
            print()
        
        if len(results['matched']) > 10:
            print(f"... and {len(results['matched']) - 10} more in sync_report.json file")
    
    # Users only in Jira
    if results['only_jira']:
        print(f"\n{'='*80}")
        print(f"⚠️  USERS ONLY IN JIRA ({len(results['only_jira'])})")
        print(f"{'='*80}")
        print("These users don't have an M365 account or have a different email:")
        
        for user in results['only_jira'][:20]:  # Show max 20
            email = user.get('email', 'N/A')
            name = user.get('display_name', 'N/A')
            print(f"   • {name} ({email})")
        
        if len(results['only_jira']) > 20:
            print(f"   ... and {len(results['only_jira']) - 20} more")
    
    # Users only in M365
    if results['only_m365']:
        print(f"\n{'='*80}")
        print(f"⚠️  USERS ONLY IN M365 ({len(results['only_m365'])})")
        print(f"{'='*80}")
        print("These users don't have a Jira account or have a different email:")
        
        for user in results['only_m365'][:20]:  # Show max 20
            email = user.get('email') or user.get('user_principal_name', 'N/A')
            name = user.get('display_name', 'N/A')
            dept = user.get('department', 'N/A')
            job = user.get('job_title', 'N/A')
            print(f"   • {name} ({email})")
            if dept != 'N/A' or job != 'N/A':
                print(f"     {job} - {dept}")
        
        if len(results['only_m365']) > 20:
            print(f"   ... and {len(results['only_m365']) - 20} more")


def save_detailed_report(results: Dict, has_profiles: bool = False, filename: str = 'sync_report.json'):
    """Saves detailed report to JSON file"""
    report = {
        'generated_at': datetime.now().isoformat(),
        'comparison_mode': 'full_profiles' if has_profiles else 'basic',
        'statistics': results['stats'],
        'users_with_differences': [
            {
                'email': comp['email'],
                'jira_name': comp['jira'].get('display_name'),
                'm365_name': comp['m365'].get('display_name'),
                'differences': {
                    'display_name': {
                        'differs': comp['differences']['display_name'][0],
                        'message': comp['differences']['display_name'][1]
                    },
                    'job_title': {
                        'differs': comp['differences']['job_title'][0],
                        'message': comp['differences']['job_title'][1]
                    },
                    'department': {
                        'differs': comp['differences']['department'][0],
                        'message': comp['differences']['department'][1]
                    },
                    'location': {
                        'differs': comp['differences']['location'][0],
                        'message': comp['differences']['location'][1]
                    }
                },
                'jira_data': comp['jira'],
                'm365_data': comp['m365']
            }
            for comp in results['differences']
        ],
        'only_in_jira': results['only_jira'],
        'only_in_m365': results['only_m365']
    }
    
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Detailed report saved to: {filename}")


def main():
    """Main program function"""
    print("="*80)
    print("Comparing Jira ↔ M365 users")
    print("="*80)
    
    # Select Jira data source
    print("\n📂 Select Jira data source:")
    print("   1. jira_users.json - basic data (without profiles)")
    print("   2. jira_users_with_profiles.json - data from Organization API (job title/department/location)")
    
    choice = input("\nChoice (1/2) [default 2]: ").strip() or "2"
    
    if choice == "1":
        jira_file = 'jira_users.json'
        has_profiles = False
        print(f"✓ Selected: {jira_file} (name comparison only)")
    elif choice == "2":
        jira_file = 'jira_users_with_profiles.json'
        has_profiles = True
        print(f"✓ Selected: {jira_file} (full comparison with profiles)")
    else:
        print("❌ Invalid choice, using jira_users_with_profiles.json by default")
        jira_file = 'jira_users_with_profiles.json'
        has_profiles = True
    
    # Load data
    print(f"\n📂 Loading data...")
    jira_users = load_json_file(jira_file)
    m365_users = load_json_file('m365_users_active.json')
    
    print(f"   ✓ Loaded {len(jira_users)} users from Jira")
    print(f"   ✓ Loaded {len(m365_users)} users from M365")
    
    # Compare
    results = compare_users(jira_users, m365_users, has_profiles)
    
    # Display report
    print_report(results, has_profiles)
    
    # Save detailed report
    save_detailed_report(results, has_profiles)
    
    # Summary
    print(f"\n{'='*80}")
    if results['stats']['with_differences'] > 0:
        print(f"⚠️  Found {results['stats']['with_differences']} users with outdated data in Jira")
    else:
        print(f"✅ All data is synchronized!")
    print(f"{'='*80}\n")


if __name__ == "__main__":
    main()
