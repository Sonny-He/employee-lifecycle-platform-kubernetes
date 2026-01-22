#!/usr/bin/env python3
from flask import Flask, request, jsonify
from flask_cors import CORS
from jose import jwt
from botocore.exceptions import ClientError
from datetime import datetime
from functools import wraps
from ldap3.core.exceptions import LDAPException
import boto3
import psycopg2
import os
import requests
import json
from ldap3 import Server, Connection, ALL, NONE, NTLM, MODIFY_REPLACE, MODIFY_ADD, Tls
import time

app = Flask(__name__)
CORS(app)

# --- CONFIGURATION ---
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_NAME = os.environ.get('DB_NAME', 'employees')
DB_USER = os.environ.get('DB_USER', 'admin')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')
AWS_REGION = os.environ.get('AWS_REGION', 'eu-central-1')
USER_POOL_ID = os.environ.get('COGNITO_USER_POOL_ID', '')
COGNITO_ISSUER = f"https://cognito-idp.{AWS_REGION}.amazonaws.com/{USER_POOL_ID}"
COGNITO_CLIENT_ID = os.environ.get('COGNITO_CLIENT_ID')

# WorkSpaces & AD Configuration
AD_HOST = os.environ.get('AD_HOST', 'innovatech.local')
DIRECTORY_ID = os.environ.get('AD_DIRECTORY_ID', '')
BUNDLE_ID = os.environ.get('AD_BUNDLE_ID', '')

# Initialize AWS Clients
cognito = boto3.client('cognito-idp', region_name=AWS_REGION)
workspaces = boto3.client('workspaces', region_name=AWS_REGION)
secretsmanager = boto3.client('secretsmanager', region_name=AWS_REGION)
ds_client = boto3.client('ds', region_name=AWS_REGION)

# Cache service account credentials
_ad_service_creds = None

print("=" * 80)
print("🔧 ENVIRONMENT CONFIGURATION")
print("=" * 80)
print(f"DB_HOST: {DB_HOST}")
print(f"DB_NAME: {DB_NAME}")
print(f"DB_USER: {DB_USER}")
print(f"COGNITO_USER_POOL_ID: {USER_POOL_ID}")
print(f"COGNITO_CLIENT_ID: {COGNITO_CLIENT_ID}")
print(f"AWS_REGION: {AWS_REGION}")
print(f"AD_HOST: {AD_HOST}")
print(f"DIRECTORY_ID: {DIRECTORY_ID}")
print(f"BUNDLE_ID: {BUNDLE_ID}")
print(f"WorkSpaces Enabled: {bool(DIRECTORY_ID and BUNDLE_ID)}")
print("=" * 80)

def get_db():
    return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)

# --- SERVICE ACCOUNT FUNCTIONS ---
def get_ad_service_credentials():
    """Retrieve service account credentials from Secrets Manager"""
    global _ad_service_creds
    
    if _ad_service_creds is None:
        try:
            response = secretsmanager.get_secret_value(SecretId='cs3-ad-service-account')
            _ad_service_creds = json.loads(response['SecretString'])
            print("✅ Retrieved AD service account credentials from Secrets Manager")
        except Exception as e:
            print(f"⚠️ Could not retrieve service credentials: {e}")
            print(f"⚠️ Falling back to default Admin account")
            # Fallback to environment variables (for local testing)
            _ad_service_creds = {
                'username': os.environ.get('AD_USER', 'Admin'),
                'password': os.environ.get('AD_PASSWORD', '')
            }
    
    return _ad_service_creds

def get_ad_connection():
    """Plain LDAP connection (no SSL) - acceptable for VPC-internal communication"""
    creds = get_ad_service_credentials()
    if not creds or not creds.get('password'):
        print("❌ No AD credentials available")
        return None
    
    try:
        ad_server = '10.0.41.73'
        
        server = Server(
            ad_server,
            port=389,
            use_ssl=False,  # Plain LDAP
            get_info=NONE,
            connect_timeout=5
        )
        
        conn = Connection(
            server,
            user=f'INNOVATECH\\{creds["username"]}',
            password=creds['password'],
            authentication=NTLM,
            auto_bind=True,
            raise_exceptions=True
        )
        
        print(f"✅ Connected to AD (LDAP) at {ad_server}:389")
        return conn
        
    except Exception as e:
        print(f"❌ AD connection failed: {e}")
        import traceback
        traceback.print_exc()
        return None

def ensure_ou_structure():
    """Create OU structure if it doesn't exist - runs on startup"""
    print("🏗️ Ensuring AD OU structure...")
    
    conn = get_ad_connection()
    if not conn:
        print("⚠️ Cannot verify OU structure - no AD connection")
        return False
    
    base_dn = "OU=innovatech,DC=innovatech,DC=local"
    
    ous = [
        {
            'dn': f'OU=Employees,{base_dn}',
            'description': 'Standard employees'
        },
        {
            'dn': f'OU=Developers,{base_dn}',
            'description': 'Software developers'
        },
        {
            'dn': f'OU=Admins,{base_dn}',
            'description': 'IT administrators'
        }
    ]
    
    for ou in ous:
        try:
            # Check if exists
            if conn.search(ou['dn'], '(objectClass=organizationalUnit)', search_scope='BASE'):
                print(f"✓ OU exists: {ou['dn']}")
                continue
            
            # Create if doesn't exist
            attributes = {
                'objectClass': ['top', 'organizationalUnit'],
                'ou': ou['dn'].split(',')[0].split('=')[1],
                'description': ou['description']
            }
            
            success = conn.add(ou['dn'], attributes=attributes)
            if success:
                print(f"✅ Created OU: {ou['dn']}")
            else:
                print(f"❌ Failed to create OU: {conn.result}")
                
        except Exception as e:
            print(f"⚠️ OU check/create error for {ou['dn']}: {e}")
    
    conn.unbind()
    return True

def ensure_security_groups():
    """Create AD security groups if they don't exist"""
    print("👥 Ensuring AD security groups...")
    
    conn = get_ad_connection()
    if not conn:
        return False
    
    base_dn = "OU=innovatech,DC=innovatech,DC=local"
    
    groups = [
        {
            'dn': f'CN=DevelopersGroup,{base_dn}',
            'name': 'DevelopersGroup',
            'description': 'Developers with code access'
        },
        {
            'dn': f'CN=AdminsGroup,{base_dn}',
            'name': 'AdminsGroup',
            'description': 'IT Administrators'
        },
        {
            'dn': f'CN=EmployeesGroup,{base_dn}',
            'name': 'EmployeesGroup',
            'description': 'Standard employees'
        }
    ]
    
    for group in groups:
        try:
            if conn.search(group['dn'], '(objectClass=group)', search_scope='BASE'):
                print(f"✓ Group exists: {group['name']}")
                continue
            
            attributes = {
                'objectClass': ['top', 'group'],
                'cn': group['name'],
                'sAMAccountName': group['name'],
                'description': group['description'],
                'groupType': -2147483646  # Global security group
            }
            
            success = conn.add(group['dn'], attributes=attributes)
            if success:
                print(f"✅ Created group: {group['name']}")
            else:
                print(f"❌ Failed: {conn.result}")
                
        except Exception as e:
            print(f"⚠️ Group error for {group['name']}: {e}")
    
    conn.unbind()
    return True

# --- SECURITY: TOKEN VERIFICATION ---
def verify_token(token):
    """Verify Cognito JWT token"""
    try:
        keys_url = f"{COGNITO_ISSUER}/.well-known/jwks.json"
        keys = requests.get(keys_url).json()['keys']
        header = jwt.get_unverified_header(token)
        key = next((k for k in keys if k['kid'] == header['kid']), None)
        if not key:
            return None
        return jwt.decode(token, key, algorithms=['RS256'], audience=COGNITO_CLIENT_ID, issuer=COGNITO_ISSUER)
    except Exception as e:
        print(f"Token verification error: {e}")
        return None

def admin_required(f):
    """Decorator to require admin group membership"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        if not auth_header:
            return jsonify({'error': 'No authorization token provided'}), 401
        
        token = auth_header.split(" ")[1] if " " in auth_header else auth_header
        claims = verify_token(token)
        
        if not claims:
            return jsonify({'error': 'Invalid or expired token'}), 401
        
        groups = claims.get('cognito:groups', [])
        if 'admins' not in groups:
            return jsonify({'error': 'Access Denied: Administrator privileges required'}), 403
            
        return f(*args, **kwargs)
    return decorated_function

# --- ACTIVE DIRECTORY FUNCTIONS ---
def create_ad_user(username, first_name, last_name, email, role='Employee'):
    """Create AD user with AWS DS API for password"""
    print(f"Creating AD user: {username} (Role: {role})")
    
    conn = get_ad_connection()
    if not conn:
        return False
    
    try:
        # 1. Determine target OU
        ou_map = {
            'Developer': 'OU=Developers,OU=innovatech,DC=innovatech,DC=local',
            'Admin': 'OU=Admins,OU=innovatech,DC=innovatech,DC=local',
            'Employee': 'OU=Employees,OU=innovatech,DC=innovatech,DC=local'
        }
        target_ou = ou_map.get(role, 'OU=Employees,OU=innovatech,DC=innovatech,DC=local')
        user_dn = f'CN={first_name} {last_name},{target_ou}'
        
        # 2. Create user (disabled initially)
        attributes = {
            'objectClass': ['top', 'person', 'organizationalPerson', 'user'],
            'sAMAccountName': username,
            'userPrincipalName': f'{username}@innovatech.local',
            'givenName': first_name,
            'sn': last_name,
            'displayName': f"{first_name} {last_name}",
            'mail': email,
            'userAccountControl': 514  # Disabled
        }
        
        if not conn.add(user_dn, attributes=attributes):
            print(f"Failed to create user: {conn.result}")
            conn.unbind()
            return False
        
        print(f"User created in {target_ou}")
        
        # 3. Set password using AWS DS (Global Client + Retry Logic)
        password_set = False
        password = 'TempPass123!'
        max_retries = 15
        
        for attempt in range(max_retries):
            try:
                ds_client.reset_user_password(
                    DirectoryId=DIRECTORY_ID,
                    UserName=username,
                    NewPassword=password
                )
                print("Password set via AWS DS API")
                password_set = True
                break
            except ClientError as e:
                error_code = e.response['Error']['Code']
                if error_code == 'UserDoesNotExistException' and attempt < max_retries - 1:
                    print(f"AWS DS hasn't seen the user yet. Retrying in 3s... (Attempt {attempt + 1}/{max_retries})")
                    time.sleep(3)
                    continue
                else:
                    print(f"AWS DS password reset failed: {e}")
                    conn.unbind()
                    return False
        
        if not password_set:
            print("Failed to set password after retries")
            conn.unbind()
            return False
            
        # REPLICATION WAIT: Ensure password syncs to the LDAP DC before enabling
        print("Waiting 5s for password replication before enabling...")
        time.sleep(5)
        
        # 4. Enable account
        if conn.modify(user_dn, {'userAccountControl': [(MODIFY_REPLACE, [512])]}):
            print("Account enabled")
        else:
            print(f"Failed to enable account: {conn.result}")
        
        # 5. Add to security group
        group_base_dn = "OU=innovatech,DC=innovatech,DC=local"
        group_map = {
            'Developer': f'CN=DevelopersGroup,{group_base_dn}',
            'Admin': f'CN=AdminsGroup,{group_base_dn}',
            'Employee': f'CN=EmployeesGroup,{group_base_dn}'
        }
        
        target_group = group_map.get(role, f'CN=EmployeesGroup,{group_base_dn}')
        if conn.modify(target_group, {'member': [(MODIFY_ADD, [user_dn])]}):
            print(f"Added to group: {target_group}")
        
        conn.unbind()
        return True
        
    except Exception as e:
        print(f"AD Error: {e}")
        import traceback
        traceback.print_exc()
        return False

def disable_ad_user(first_name, last_name):
    """Disable user in Active Directory (Fixed to search sub-OUs)"""
    print(f"Disabling AD user: {first_name} {last_name}")
    
    conn = get_ad_connection()
    if not conn:
        return False
        
    try:
        # 1. Find the user's correct DN (Distinguished Name)
        # We search the entire innovatech OU subtree
        search_base = 'OU=innovatech,DC=innovatech,DC=local'
        search_filter = f'(&(objectClass=user)(cn={first_name} {last_name}))'
        
        conn.search(search_base, search_filter, attributes=['distinguishedName'])
        
        if not conn.entries:
            print(f"User not found in AD: {first_name} {last_name}")
            conn.unbind()
            return False
            
        user_dn = conn.entries[0].distinguishedName.value
        print(f"✓ Found user at: {user_dn}")
        
        # 2. Disable the account
        # 514 = Normal Account (512) + Disabled (2)
        success = conn.modify(user_dn, {'userAccountControl': [(MODIFY_REPLACE, [514])]})
        
        if success:
            print(f"AD account disabled")
        else:
            print(f"Failed to disable: {conn.result}")
            
        conn.unbind()
        return success
    except Exception as e:
        print(f"Error disabling AD user: {e}")
        return False

def provision_workspace(username, role):
    """Provision AWS WorkSpace with Role Tag for SSM"""
    print(f"Provision_workspace called: username={username}, role={role}")
    
    if not all([DIRECTORY_ID, BUNDLE_ID]):
        print(f"WorkSpace config missing")
        return False
    
    try:
        print(f"📡 Requesting WorkSpace for {username}...")
        
        response = workspaces.create_workspaces(
            Workspaces=[{
                'DirectoryId': DIRECTORY_ID,
                'UserName': username,
                'BundleId': BUNDLE_ID,
                'WorkspaceProperties': {
                    'RunningMode': 'AUTO_STOP',
                    'RunningModeAutoStopTimeoutInMinutes': 60
                },
                'Tags': [
                    {'Key': 'Role', 'Value': role},
                    {'Key': 'CreatedBy', 'Value': 'EmployeePortal'}
                ]
            }]
        )
        
        print(f"✅ WorkSpace API response: {response}")
        
        if response.get('FailedRequests'):
            print(f"WorkSpace creation failed: {response['FailedRequests']}")
            return False
            
        return True
        
    except ClientError as e:
        print(f"AWS Error: {e}")
        return False
    except Exception as e:
        print(f"Error: {e}")
        return False

# --- API ROUTES ---
@app.route('/api/health')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'workspaces_enabled': bool(DIRECTORY_ID and BUNDLE_ID)
    })

@app.route('/api/auth/login', methods=['POST'])
def login():
    """Login with username/password via Cognito"""
    try:
        data = request.json
        username = data.get('username') or data.get('email')  # Accept both username and email
        password = data.get('password')
        
        if not username or not password:
            return jsonify({'error': 'Username/email and password required'}), 400
        
        response = cognito.initiate_auth(
            ClientId=COGNITO_CLIENT_ID,
            AuthFlow='USER_PASSWORD_AUTH',
            AuthParameters={
                'USERNAME': username,  # Changed from email to username
                'PASSWORD': password
            }
        )
        
        if 'ChallengeName' in response:
            if response['ChallengeName'] == 'NEW_PASSWORD_REQUIRED':
                return jsonify({
                    'challenge': 'NEW_PASSWORD_REQUIRED',
                    'session': response['Session'],
                    'message': 'Please change your temporary password'
                }), 200
        
        id_token = response['AuthenticationResult']['IdToken']
        claims = verify_token(id_token)
        
        return jsonify({
            'token': id_token,
            'user': {
                'email': claims.get('email'),
                'name': claims.get('name'),
                'groups': claims.get('cognito:groups', [])
            }
        }), 200
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'NotAuthorizedException':
            return jsonify({'error': 'Invalid username or password'}), 401
        return jsonify({'error': f'Authentication failed: {error_code}'}), 500
    except Exception as e:
        print(f"Login error: {e}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/api/auth/change-password', methods=['POST'])
def change_password():
    """Handle NEW_PASSWORD_REQUIRED challenge"""
    try:
        data = request.json
        email = data.get('email')
        new_password = data.get('new_password')
        session = data.get('session')
        
        if not all([email, new_password, session]):
            return jsonify({'error': 'Missing required fields'}), 400
            
        # Respond to the Cognito challenge
        response = cognito.respond_to_auth_challenge(
            ClientId=COGNITO_CLIENT_ID,
            ChallengeName='NEW_PASSWORD_REQUIRED',
            Session=session,
            ChallengeResponses={
                'USERNAME': email,
                'NEW_PASSWORD': new_password
            }
        )
        
        # If successful, Cognito returns the tokens immediately
        if 'AuthenticationResult' in response:
            id_token = response['AuthenticationResult']['IdToken']
            claims = verify_token(id_token)
            
            return jsonify({
                'token': id_token,
                'user': {
                    'email': claims.get('email'),
                    'name': claims.get('name'),
                    'groups': claims.get('cognito:groups', [])
                }
            }), 200
            
        return jsonify({'error': 'Authentication failed after password change'}), 401

    except ClientError as e:
        print(f"Change password error: {e}")
        return jsonify({'error': str(e)}), 400
    except Exception as e:
        print(f"Server error: {e}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/api/employees', methods=['GET'])
def get_employees():
    """Get all active employees"""
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("""
            SELECT employee_id, first_name, last_name, email, department, position, status
            FROM employees 
            WHERE status = 'active'
            ORDER BY employee_id ASC
        """)
        
        employees = []
        for row in cur.fetchall():
            employees.append({
                'employee_id': row[0],
                'first_name': row[1],
                'last_name': row[2],
                'email': row[3],
                'department': row[4],
                'position': row[5],
                'status': row[6]
            })
        
        cur.close()
        conn.close()
        
        return jsonify({'employees': employees})
        
    except Exception as e:
        print(f"Database error: {e}")
        return jsonify({'error': 'Failed to fetch employees'}), 500

@app.route('/api/create-user', methods=['POST'])
@admin_required
def create_user():
    """Create new employee (Admin only)"""
    try:
        data = request.json
        print(f"Received create-user request: {data}")
        
        email = data.get('email')
        first_name = data.get('first_name')
        last_name = data.get('last_name')
        position = data.get('position', 'Employee')
        department = data.get('department', 'Engineering')
        role = data.get('role', 'Employee')
        
        if not all([email, first_name, last_name]):
            print(f"Validation failed: missing fields")
            return jsonify({'error': 'Missing required fields'}), 400
        
        username = email.split('@')[0]
        
        # Step 1: Create Cognito user
        try:
            print(f"Creating Cognito user: {email}")
            
            cognito.admin_create_user(
                UserPoolId=USER_POOL_ID,
                Username=email,
                UserAttributes=[
                    {'Name': 'email', 'Value': email},
                    {'Name': 'name', 'Value': f'{first_name} {last_name}'}
                ],
                TemporaryPassword='TempPass123!',
                MessageAction='SUPPRESS'
            )
            
            group_name = 'admins' if position.lower() == 'admin' else 'employees'
            cognito.admin_add_user_to_group(
                UserPoolId=USER_POOL_ID,
                Username=email,
                GroupName=group_name
            )
            
            print(f"Cognito user created: {email} (group: {group_name})")
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'UsernameExistsException':
                return jsonify({'error': 'User already exists in Cognito'}), 400
            return jsonify({'error': f"Cognito error: {error_code}"}), 500
        
        # Step 2: Create database record
        try:
            print(f"Creating database record...")
            
            conn = get_db()
            cur = conn.cursor()
            
            cur.execute("""
                INSERT INTO employees 
                (first_name, last_name, email, department, position, status, hire_date)
                VALUES (%s, %s, %s, %s, %s, 'active', CURRENT_DATE)
                RETURNING employee_id
            """, (first_name, last_name, email, department, position))
            
            employee_id = cur.fetchone()[0]
            
            conn.commit()
            cur.close()
            conn.close()
            
            print(f"Database record created: Employee ID = {employee_id}")
            
        except Exception as e:
            print(f"Database error: {str(e)}")
            
            # Rollback: Delete Cognito user
            try:
                cognito.admin_delete_user(UserPoolId=USER_POOL_ID, Username=email)
                print(f"Rolled back Cognito user: {email}")
            except:
                pass
            
            return jsonify({'error': 'Failed to create database record'}), 500
        
        # Step 3: Provision WorkSpace (if configured)
        workspace_status = "not_configured"
        
        if DIRECTORY_ID and BUNDLE_ID:
            print(f"Provisioning WorkSpace for {username}...")
            ad_success = create_ad_user(username, first_name, last_name, email, role)
            if ad_success:
                print(f"AD user created: {username}")
                workspace_success = provision_workspace(username, role)
                workspace_status = "provisioning" if workspace_success else "failed"
                print(f"WorkSpace status: {workspace_status}")
            else:
                print(f"AD user creation failed")
                workspace_status = "ad_failed"
        
        print(f"User creation completed: {email}")
        
        return jsonify({
            'message': f'User {first_name} {last_name} created successfully',
            'employee_id': employee_id,
            'cognito': 'created',
            'database': 'created',
            'workspace': workspace_status
        }), 201
        
    except Exception as e:
        print(f"FATAL ERROR in create-user: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/api/terminate-user', methods=['POST'])
@admin_required
def terminate_user():
    """Offboard an employee"""
    try:
        data = request.json
        email = data.get('email')
        
        if not email:
            return jsonify({'error': 'Email is required'}), 400
            
        print(f"Starting offboarding for: {email}")
        
        conn = get_db()
        cur = conn.cursor()
        
        cur.execute("SELECT first_name, last_name, workspace_id FROM employees WHERE email = %s", (email,))
        user = cur.fetchone()
        
        if not user:
            return jsonify({'error': 'User not found'}), 404
            
        first_name, last_name, workspace_id = user
        
        # Disable in Cognito
        try:
            cognito.admin_disable_user(UserPoolId=USER_POOL_ID, Username=email)
            print(f"Cognito user disabled")
        except Exception as e:
            print(f"Cognito issue: {e}")

        # Disable in Active Directory
        disable_ad_user(first_name, last_name)

        # Terminate WorkSpace
        workspace_status = "none"
        if workspace_id:
            try:
                username = email.split('@')[0]
                ws_resp = workspaces.describe_workspaces(UserName=username, DirectoryId=DIRECTORY_ID)
                
                if ws_resp['Workspaces']:
                    ws_id = ws_resp['Workspaces'][0]['WorkspaceId']
                    print(f"Terminating WorkSpace: {ws_id}")
                    workspaces.terminate_workspaces(TerminateWorkspaceRequests=[{'WorkspaceId': ws_id}])
                    workspace_status = "terminating"
            except Exception as e:
                print(f"WorkSpace error: {e}")
                workspace_status = "failed"

        # Update database
        cur.execute("""
            UPDATE employees 
            SET status = 'terminated', 
                termination_date = CURRENT_DATE 
            WHERE email = %s
        """, (email,))
        
        conn.commit()
        cur.close()
        conn.close()
        
        return jsonify({
            'message': f'User {email} offboarded successfully',
            'workspace': workspace_status
        })

    except Exception as e:
        print(f"Error in terminate-user: {e}")
        return jsonify({'error': str(e)}), 500

# --- AD SYNC AUTOMATION ---
@app.route('/api/maintenance/sync-computers', methods=['POST'])
@admin_required
def sync_computers():
    """Move WorkSpace computer objects to correct OUs based on Tags"""
    print("🔄 Starting AD Computer Sync...")
    
    conn = get_ad_connection()
    if not conn:
        return jsonify({'error': 'Could not connect to AD'}), 500

    moved_count = 0
    errors = []

    try:
        # 1. Get all WorkSpaces from AWS
        ws_resp = workspaces.describe_workspaces()
        
        # 2. Loop through them
        for ws in ws_resp.get('Workspaces', []):
            comp_name = ws.get('ComputerName')
            ws_id = ws.get('WorkspaceId')
            state = ws.get('State')

            # Only process if we have a computer name (it takes time to appear!)
            if not comp_name or state != 'AVAILABLE':
                continue

            # 3. Get Tags to find the Role
            tags_resp = workspaces.describe_tags(ResourceId=ws_id)
            role_tag = next((t['Value'] for t in tags_resp['TagList'] if t['Key'] == 'Role'), 'Employee')
            
            # Determine Target OU based on Role
            base_dn = "OU=innovatech,DC=innovatech,DC=local"
            
            if role_tag == 'Developer':
                target_ou = f"OU=Developers,{base_dn}"
            elif role_tag == 'Admin':
                target_ou = f"OU=Admins,{base_dn}"
            else:
                # Default for 'Employee' or any other role
                target_ou = f"OU=Employees,{base_dn}"

            # 4. Find the computer in AD
            search_filter = f'(&(objectClass=computer)(sAMAccountName={comp_name}$))'
            conn.search('DC=innovatech,DC=local', search_filter, attributes=['distinguishedName'])
            
            if not conn.entries:
                print(f"Computer {comp_name} not found in AD yet.")
                continue
            
            current_dn = conn.entries[0].distinguishedName.value
            
            # 5. Move if not already in target OU
            if target_ou not in current_dn:
                print(f"Moving {comp_name} to {target_ou}...")
                try:
                    # modify_dn moves the object
                    success = conn.modify_dn(current_dn, f"CN={comp_name}", new_superior=target_ou)
                    if success:
                        print(f"✅ Moved {comp_name}")
                        moved_count += 1
                    else:
                        err = f"Failed to move {comp_name}: {conn.result}"
                        print(f"{err}")
                        errors.append(err)
                except Exception as move_ex:
                    print(f" Error moving {comp_name}: {move_ex}")
                    errors.append(str(move_ex))
            else:
                print(f"✓ {comp_name} is already in correct OU")

        return jsonify({
            'message': f'Sync complete. Moved {moved_count} computers.',
            'errors': errors
        })

    except Exception as e:
        print(f"Sync Error: {e}")
        return jsonify({'error': str(e)}), 500
    finally:
        conn.unbind()

# --- STARTUP: Initialize AD Structure ---
if __name__ == '__main__':
    print("=" * 80)
    print("🚀 Employee Portal Starting Up")
    print("=" * 80)
    
    # Auto-create OUs and groups if service account is available
    try:
        ensure_ou_structure()
        ensure_security_groups()
    except Exception as e:
        print(f"⚠️ Could not initialize AD structure: {e}")
        print(f"⚠️ Continuing without automated AD setup")
    
    print(f"✅ Starting Flask server...")
    app.run(host='0.0.0.0', port=5000)