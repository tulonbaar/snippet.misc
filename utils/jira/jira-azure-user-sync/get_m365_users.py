#!/usr/bin/env python3
"""
Script for fetching users from Microsoft 365 via Graph API.
Requires App Registration in Azure AD with appropriate permissions.
"""

import os
import sys
import json
import requests
from dotenv import load_dotenv
from msal import ConfidentialClientApplication
from typing import List, Dict, Optional


def load_config() -> Dict[str, str]:
    """Loads configuration from .env file"""
    load_dotenv()
    
    config = {
        'tenant_id': os.getenv('M365_TENANT_ID'),
        'client_id': os.getenv('M365_CLIENT_ID'),
        'client_secret': os.getenv('M365_CLIENT_SECRET')
    }
    
    # Validate configuration
    missing = [key for key, value in config.items() if not value]
    if missing:
        print(f"❌ Error: Missing environment variables: {', '.join(missing)}")
        print("Make sure the .env file contains all required M365 variables.")
        sys.exit(1)
    
    return config


def get_access_token(tenant_id: str, client_id: str, client_secret: str) -> str:
    """
    Obtains access token for Microsoft Graph API using Client Credentials Flow.
    
    Args:
        tenant_id: Azure AD tenant ID
        client_id: Application ID (App Registration)
        client_secret: Application secret
    
    Returns:
        Access token
    """
    authority = f"https://login.microsoftonline.com/{tenant_id}"
    scope = ["https://graph.microsoft.com/.default"]
    
    app = ConfidentialClientApplication(
        client_id=client_id,
        client_credential=client_secret,
        authority=authority
    )
    
    print("🔐 Authenticating with Microsoft Graph API...")
    
    try:
        result = app.acquire_token_for_client(scopes=scope)
        
        if "access_token" in result:
            print("  ✓ Successfully obtained access token")
            return result["access_token"]
        else:
            error = result.get("error", "Unknown error")
            error_desc = result.get("error_description", "No description")
            print(f"❌ Authentication error: {error}")
            print(f"   Description: {error_desc}")
            sys.exit(1)
            
    except Exception as e:
        print(f"❌ Error during authentication: {e}")
        sys.exit(1)


def get_m365_users(access_token: str) -> List[Dict]:
    """
    Fetches list of users from Microsoft 365 via Graph API.
    
    Args:
        access_token: Access token for Graph API
    
    Returns:
        List of dictionaries with user data
    """
    graph_url = "https://graph.microsoft.com/v1.0/users"
    
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json',
        'ConsistencyLevel': 'eventual'  # Add for advanced queries
    }
    
    # Query parameters - select only needed fields
    params = {
        '$select': 'id,userPrincipalName,displayName,givenName,surname,mail,jobTitle,department,officeLocation,accountEnabled,userType',
        '$top': 999,  # Maximum number of results per page
        '$count': 'true'  # Enable counting
    }
    
    all_users = []
    
    print(f"🔍 Fetching users from Microsoft 365...")
    
    while graph_url:
        try:
            response = requests.get(graph_url, headers=headers, params=params)
            
            # Additional diagnostic information
            if response.status_code != 200:
                print(f"\n⚠️  HTTP Status: {response.status_code}")
                print(f"Response: {response.text}")
                
                # Parse error response if it's JSON
                try:
                    error_data = response.json()
                    if 'error' in error_data:
                        error_info = error_data['error']
                        print(f"\n❌ Error code: {error_info.get('code')}")
                        print(f"Message: {error_info.get('message')}")
                        
                        # Help details for common errors
                        if response.status_code == 403:
                            print("\n🔧 Solutions for 403 error:")
                            print("1. Check if App Registration has permissions:")
                            print("   - User.Read.All (Application permission)")
                            print("   or")
                            print("   - Directory.Read.All (Application permission)")
                            print("\n2. Ensure Admin Consent has been granted:")
                            print("   Azure Portal → App Registration → API permissions")
                            print("   → 'Grant admin consent for [tenant]'")
                            print("\n3. Wait a few minutes after granting consent (change propagation)")
                            print("\n4. Check if Client Secret has not expired")
                            print("\n5. Verify that application type is: 'Web' not 'Public client'")
                except:
                    pass
            
            response.raise_for_status()
            
            data = response.json()
            users = data.get('value', [])
            
            all_users.extend(users)
            total_count = data.get('@odata.count', '?')
            print(f"  ✓ Fetched {len(users)} users (total: {len(all_users)}, expected: {total_count})")
            
            # Check if there are more pages (pagination)
            graph_url = data.get('@odata.nextLink')
            params = None  # Parameters are already in nextLink
            
        except requests.exceptions.HTTPError as e:
            print(f"\n❌ HTTP error: {e}")
            sys.exit(1)
        except requests.exceptions.RequestException as e:
            print(f"❌ Connection error: {e}")
            sys.exit(1)
    
    return all_users


def format_user_info(user: Dict) -> Dict:
    """Formats user information to readable form"""
    return {
        'id': user.get('id'),
        'user_principal_name': user.get('userPrincipalName'),
        'email': user.get('mail'),
        'display_name': user.get('displayName'),
        'given_name': user.get('givenName'),
        'surname': user.get('surname'),
        'job_title': user.get('jobTitle'),
        'department': user.get('department'),
        'office_location': user.get('officeLocation'),
        'account_enabled': user.get('accountEnabled'),
        'user_type': user.get('userType')
    }


def filter_active_users(users: List[Dict]) -> List[Dict]:
    """Filters only active users"""
    return [user for user in users if user.get('accountEnabled', False)]


def save_to_file(users: List[Dict], filename: str = 'm365_users.json'):
    """Saves list of users to JSON file"""
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(users, f, indent=2, ensure_ascii=False)
    print(f"💾 Data saved to file: {filename}")


def print_summary(users: List[Dict], active_only: bool = False):
    """Displays summary of fetched users"""
    print(f"\n{'='*60}")
    print(f"📊 Summary:")
    print(f"{'='*60}")
    
    active_users = [u for u in users if u.get('accountEnabled', False)]
    inactive_users = [u for u in users if not u.get('accountEnabled', True)]
    
    print(f"Total number of users: {len(users)}")
    print(f"  - Active: {len(active_users)}")
    print(f"  - Inactive: {len(inactive_users)}")
    
    if users:
        user_types = {}
        for user in users:
            user_type = user.get('userType', 'unknown')
            user_types[user_type] = user_types.get(user_type, 0) + 1
        
        print(f"\nUser types:")
        for user_type, count in user_types.items():
            print(f"  - {user_type}: {count}")
        
        # Department statistics
        departments = {}
        for user in users:
            if user.get('accountEnabled', False):
                dept = user.get('department', 'None')
                if dept:
                    departments[dept] = departments.get(dept, 0) + 1
        
        if departments:
            print(f"\nTop 5 departments (active users):")
            sorted_depts = sorted(departments.items(), key=lambda x: x[1], reverse=True)[:5]
            for dept, count in sorted_depts:
                print(f"  - {dept}: {count}")
        
        display_users = active_users if active_only else users
        print(f"\nSample users:")
        for user in display_users[:5]:
            info = format_user_info(user)
            status = "✓" if info['account_enabled'] else "✗"
            email = info['email'] or info['user_principal_name']
            dept = info['department'] or 'N/A'
            print(f"  {status} {info['display_name']} ({email}) - {dept}")
        
        if len(display_users) > 5:
            print(f"  ... and {len(display_users) - 5} more")


def main():
    """Main program function"""
    print("=" * 60)
    print("Fetching users from Microsoft 365 (Graph API)")
    print("=" * 60)
    
    # Load configuration
    config = load_config()
    
    # Obtain access token
    access_token = get_access_token(
        tenant_id=config['tenant_id'],
        client_id=config['client_id'],
        client_secret=config['client_secret']
    )
    
    # Fetch users
    users = get_m365_users(access_token)
    
    if users:
        # Format data
        formatted_users = [format_user_info(user) for user in users]
        
        # Save all users
        save_to_file(formatted_users, 'm365_users.json')
        
        # Save only active users
        active_users = [user for user in formatted_users if user.get('account_enabled', False)]
        save_to_file(active_users, 'm365_users_active.json')
        
        # Display summary
        print_summary(users)
        
        print(f"\n✅ Successfully fetched {len(users)} users!")
        print(f"   (including {len(active_users)} active)")
    else:
        print("\n⚠️  No users found.")


if __name__ == "__main__":
    main()
