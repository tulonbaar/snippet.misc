import os
import json
import csv
from keycloak import KeycloakAdmin
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

KEYCLOAK_SERVER_URL = os.getenv('KEYCLOAK_SERVER_URL')
if KEYCLOAK_SERVER_URL:
    KEYCLOAK_SERVER_URL = KEYCLOAK_SERVER_URL.rstrip('/')
KEYCLOAK_ADMIN_USERNAME = os.getenv('KEYCLOAK_ADMIN_USERNAME')
KEYCLOAK_ADMIN_PASSWORD = os.getenv('KEYCLOAK_ADMIN_PASSWORD')
KEYCLOAK_REALMS = os.getenv('KEYCLOAK_REALMS', '').split(',')

def get_users_from_realms():
    if not KEYCLOAK_SERVER_URL or not KEYCLOAK_ADMIN_USERNAME or not KEYCLOAK_ADMIN_PASSWORD:
        print("Error: Missing Keycloak configuration in .env file.")
        return

    try:
        # Check if server is reachable or basic config is okay (optional)
        pass

        for realm in KEYCLOAK_REALMS:
            realm = realm.strip()
            if not realm:
                continue
                
            print(f"\n--- Processing Realm: {realm} ---")
            try:
                # Initialize Keycloak Admin connection for the specific realm
                # We authenticate against 'master' (user_realm_name) but manage 'realm' (realm_name)
                keycloak_admin = KeycloakAdmin(
                    server_url=KEYCLOAK_SERVER_URL,
                    username=KEYCLOAK_ADMIN_USERNAME,
                    password=KEYCLOAK_ADMIN_PASSWORD,
                    realm_name=realm,
                    user_realm_name='master',
                    verify=True
                )
                
                print(f"Successfully connected to Keycloak Admin for realm '{realm}'.")
                
                # Get users
                users = keycloak_admin.get_users()
                
                print(f"Found {len(users)} users in realm '{realm}'. Saving to CSV...")
                
                # Ensure data directory exists
                os.makedirs('data', exist_ok=True)
                
                csv_filename = os.path.join('data', f'{realm}.csv')
                with open(csv_filename, mode='w', newline='', encoding='utf-8') as csv_file:
                    fieldnames = ['username']
                    writer = csv.DictWriter(csv_file, fieldnames=fieldnames, extrasaction='ignore')
                    
                    writer.writeheader()
                    for user in users:
                        writer.writerow(user)
                        
                print(f"Saved users to {csv_filename}")
                    
            except Exception as e:
                print(f"Error fetching users from realm '{realm}': {e}")

    except Exception as e:
        print(f"Failed to connect to Keycloak: {e}")

if __name__ == "__main__":
    get_users_from_realms()
