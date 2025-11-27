#!/usr/bin/env python3
"""
Script for fetching extended user profiles from Atlassian Organization API.
Requires Organization Admin permissions.
"""

import os
import sys
import json
import requests
from dotenv import load_dotenv
from typing import List, Dict, Optional


def load_config() -> Dict[str, str]:
    """Loads configuration from .env file"""
    load_dotenv()
    
    config = {
        'org_id': os.getenv('ATLASSIAN_ORG_ID'),
        'org_api_key': os.getenv('ATLASSIAN_ORG_API_KEY'),
        'jira_email': os.getenv('JIRA_EMAIL')  # Optional, for logging
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
        print("\n📚 How to obtain Organization API key:")
        print("1. Go to: https://admin.atlassian.com/")
        print("2. Select your organization")
        print("3. Settings → API keys")
        print("4. Create API key")
        sys.exit(1)
    
    return config


def get_org_users(org_id: str, api_key: str) -> List[Dict]:
    """
    Fetches users from Organization API.
    
    Args:
        org_id: Organization ID
        api_key: Organization API key
    
    Returns:
        List of users from the organization
    """
    url = f"https://api.atlassian.com/admin/v1/orgs/{org_id}/users"
    headers = {
        'Accept': 'application/json',
        'Authorization': f'Bearer {api_key}'
    }
    
    all_users = []
    
    print(f"\n🔍 Fetching organization users (Org ID: {org_id})...")
    
    while url:
        try:
            response = requests.get(url, headers=headers)
            
            if response.status_code != 200:
                print(f"❌ HTTP Error {response.status_code}")
                print(f"   Response: {response.text[:300]}")
                
                if response.status_code == 401:
                    print("\n   Check the validity of ATLASSIAN_ORG_API_KEY")
                elif response.status_code == 403:
                    print("\n   No permissions. Check if API key has access to the organization.")
                elif response.status_code == 404:
                    print("\n   Organization not found. Check ATLASSIAN_ORG_ID")
                break
            
            data = response.json()
            users = data.get('data', [])
            
            all_users.extend(users)
            print(f"  ✓ Fetched {len(users)} users (total: {len(all_users)})")
            
            # Check next page
            links = data.get('links', {})
            url = links.get('next')
            
        except requests.exceptions.RequestException as e:
            print(f"❌ Connection error: {e}")
            break
        except Exception as e:
            print(f"❌ Error: {e}")
            break
    
    return all_users


def get_user_profile(account_id: str, api_key: str) -> Optional[Dict]:
    """
    Fetches detailed user profile from Organization API.
    
    Args:
        account_id: User's Account ID
        api_key: Organization API key
    
    Returns:
        User profile or None
    """
    url = f"https://api.atlassian.com/users/{account_id}/manage/profile"
    headers = {
        'Accept': 'application/json',
        'Authorization': f'Bearer {api_key}'
    }
    
    try:
        response = requests.get(url, headers=headers)
        
        if response.status_code == 200:
            data = response.json()
            # Data is in account.extended_profile
            account = data.get('account', {})
            extended_profile = account.get('extended_profile', {})
            
            return {
                'job_title': extended_profile.get('job_title'),
                'organization': extended_profile.get('organization'),
                'department': extended_profile.get('department'),
                'location': extended_profile.get('location'),
                'full_profile': extended_profile  # Keep full profile
            }
        else:
            return None
            
    except Exception:
        return None


def enrich_users_with_profiles(users: List[Dict], api_key: str) -> List[Dict]:
    """
    Enriches user data with profile information.
    
    Args:
        users: List of users from Organization API
        api_key: Organization API key
    
    Returns:
        List of users with additional profile data
    """
    print(f"\n🔍 Fetching detailed user profiles...")
    
    enriched_users = []
    total = len(users)
    
    for i, user in enumerate(users, 1):
        account_id = user.get('account_id')
        
        if account_id:
            profile = get_user_profile(account_id, api_key)
            
            # Combine user data with profile
            enriched_user = {
                'account_id': account_id,
                'account_status': user.get('account_status'),
                'account_type': user.get('account_type'),
                'name': user.get('name'),
                'email': user.get('email'),
                'picture': user.get('picture'),
                'access_billable': user.get('access_billable'),
                'last_active': user.get('last_active'),
            }
            
            # Add profile data if available
            if profile:
                enriched_user.update({
                    'job_title': profile.get('job_title'),
                    'organization': profile.get('organization'),
                    'department': profile.get('department'),
                    'location': profile.get('location'),
                    'extended_profile': profile.get('full_profile', {})
                })
            else:
                enriched_user.update({
                    'job_title': None,
                    'organization': None,
                    'department': None,
                    'location': None,
                    'extended_profile': {}
                })
            
            enriched_users.append(enriched_user)
            
            if i % 10 == 0:
                print(f"  ✓ Processed: {i}/{total}")
        
    print(f"  ✓ Completed fetching profiles")
    
    return enriched_users


def format_user_for_sync(user: Dict) -> Dict:
    """Formats user to a format compatible with other scripts"""
    return {
        'account_id': user.get('account_id'),
        'email': user.get('email', 'N/A'),
        'display_name': user.get('name'),
        'active': user.get('account_status') == 'active',
        'account_type': user.get('account_type'),
        'job_title': user.get('job_title'),
        'department': user.get('department'),
        'location': user.get('location'),
        'organization': user.get('organization'),
        'last_active': user.get('last_active'),
        'access_billable': user.get('access_billable')
    }


def save_to_file(users: List[Dict], filename: str):
    """Saves users to JSON file"""
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(users, f, indent=2, ensure_ascii=False)
    print(f"\n💾 Data saved to file: {filename}")


def print_summary(users: List[Dict]):
    """Displays summary of fetched data"""
    print(f"\n{'='*80}")
    print(f"📊 Summary:")
    print(f"{'='*80}")
    
    total = len(users)
    active = sum(1 for u in users if u.get('active'))
    with_job_title = sum(1 for u in users if u.get('job_title'))
    with_department = sum(1 for u in users if u.get('department'))
    with_location = sum(1 for u in users if u.get('location'))
    
    print(f"Number of users:                    {total}")
    print(f"  - Active:                         {active}")
    print(f"  - With job title:                 {with_job_title}")
    print(f"  - With department:                {with_department}")
    print(f"  - With location:                  {with_location}")
    
    # Show example users with data
    users_with_data = [u for u in users if u.get('job_title') or u.get('department') or u.get('location')]
    
    if users_with_data:
        print(f"\n📋 Sample users with completed profiles:")
        for user in users_with_data[:10]:
            name = user.get('display_name', 'N/A')
            email = user.get('email', 'N/A')
            job = user.get('job_title', 'None')
            dept = user.get('department', 'None')
            loc = user.get('location', 'None')
            
            print(f"\n  • {name} ({email})")
            if job != 'None':
                print(f"    Job Title:  {job}")
            if dept != 'None':
                print(f"    Department: {dept}")
            if loc != 'None':
                print(f"    Location:   {loc}")
        
        if len(users_with_data) > 10:
            print(f"\n  ... and {len(users_with_data) - 10} more")
    else:
        print(f"\n⚠️  No users have completed profile data")


def main():
    """Main program function"""
    print("="*80)
    print("Fetching user profiles from Atlassian Organization API")
    print("="*80)
    print("Requires Organization API key with Org Admin permissions\n")
    
    # Load configuration
    config = load_config()
    
    print(f"📝 Configuration:")
    print(f"   Organization ID: {config['org_id']}")
    print(f"   API Key:         {'*' * 20}...\n")
    
    # Fetch organization users
    org_users = get_org_users(config['org_id'], config['org_api_key'])
    
    if not org_users:
        print("\n❌ Failed to fetch users")
        sys.exit(1)
    
    # Enrich with profiles
    enriched_users = enrich_users_with_profiles(org_users, config['org_api_key'])
    
    # Format to standard format
    formatted_users = [format_user_for_sync(user) for user in enriched_users]
    
    # Save full data
    save_to_file(enriched_users, 'jira_org_users_full.json')
    
    # Save only active users in compatible format
    active_users = [u for u in formatted_users if u.get('active')]
    save_to_file(active_users, 'jira_users_with_profiles.json')
    
    # Display summary
    print_summary(formatted_users)
    
    print(f"\n{'='*80}")
    print(f"✅ Successfully fetched profiles for {len(enriched_users)} users!")
    print(f"   Active users: {len(active_users)}")
    print(f"\n📄 Files:")
    print(f"   • jira_org_users_full.json - full data from Organization API")
    print(f"   • jira_users_with_profiles.json - active users (standard format)")
    print(f"\n💡 Use jira_users_with_profiles.json with compare_users.py")
    print(f"{'='*80}\n")


if __name__ == "__main__":
    main()
