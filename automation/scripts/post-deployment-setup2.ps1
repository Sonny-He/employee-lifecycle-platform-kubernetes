# ============================================================================
# CS3 Post-Deployment Setup (FINAL VERIFIED)
# Idempotent, robust error handling, deep verification.
# ============================================================================

param(
    [string]$AWS_PROFILE = "student"
)

$ErrorActionPreference = "Stop"

# --- HELPER: Runs commands, checks success ---
function Exec {
    param(
        [Parameter(Mandatory=$true)] [scriptblock]$ScriptBlock,
        [string]$SuccessMessage,
        [string]$ErrorMessage = "Command failed"
    )
    
    # Reset exit code to prevent stale failures leaking in
    $global:LASTEXITCODE = 0
    
    & $ScriptBlock
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ $ErrorMessage" -ForegroundColor Red
        exit 1
    }
    
    if ($SuccessMessage) {
        Write-Host "✓ $SuccessMessage" -ForegroundColor Green
    }
}

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  CS3 SETUP - ROBUST DEMO" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. Get dynamic values from Terraform
Write-Host "Retrieving configuration..." -ForegroundColor Gray
try {
    $AWS_REGION = (terraform output -raw aws_region)
    if ($LASTEXITCODE -ne 0) { throw "Terraform output failed" }
    
    $ACCOUNT_ID = (terraform output -raw aws_account_id)
    $CLUSTER_NAME = (terraform output -raw eks_cluster_name)
    $USER_POOL_ID = (terraform output -raw cognito_user_pool_id)
    
    # CONFIGURATION: Matches Terraform resources
    $ADMIN_USERNAME = "admin"
    $ADMIN_EMAIL = "admin@innovatech.local"
    $ADMIN_PASSWORD = "TempPass123!" 
    
    Write-Host "  ✓ Region: $AWS_REGION" -ForegroundColor Green
    Write-Host "  ✓ Cluster: $CLUSTER_NAME" -ForegroundColor Green
    Write-Host "  ✓ User Pool: $USER_POOL_ID" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to get Terraform outputs. Did you add aws_region/account_id to cs3-outputs.tf?" -ForegroundColor Red
    exit 1
}

# 2. Configure kubectl
Write-Host "`nStep 1: Configuring kubectl..." -ForegroundColor Yellow
Exec -ScriptBlock { 
    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME --profile $AWS_PROFILE 
} -SuccessMessage "kubectl configured"

# 3. Create ECR Repositories (List & Compare Approach - Safest)
Write-Host "`nStep 2: Checking ECR Repositories..." -ForegroundColor Yellow
$repos = @("employee-portal", "employee-portal-frontend")

# Fetch list of existing repos once
$existingRepos = aws ecr describe-repositories --region $AWS_REGION --profile $AWS_PROFILE --query "repositories[].repositoryName" --output text
if ($LASTEXITCODE -ne 0) { Write-Host "✗ Failed to list ECR repositories" -ForegroundColor Red; exit 1 }

foreach ($repo in $repos) {
    if ($existingRepos -match "(^|\s)$repo(\s|$)") {
        Write-Host "  ✓ Repo exists: $repo" -ForegroundColor Green
    } else {
        Write-Host "  - Repo '$repo' missing. Creating..." -ForegroundColor Gray
        Exec -ScriptBlock {
            aws ecr create-repository --repository-name $repo --region $AWS_REGION --profile $AWS_PROFILE 
        } -SuccessMessage "Created repo: $repo"
        # Update local list so consistent for future steps
        $existingRepos += " $repo"
    }
}

# 4. Login to ECR (Split for Safety)
Write-Host "`nStep 3: Logging into ECR..." -ForegroundColor Yellow
# Step A: Get Password
$ecrPassword = aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ecrPassword)) {
    Write-Host "✗ Failed to retrieve ECR password" -ForegroundColor Red
    exit 1
}

# Step B: Login
Exec -ScriptBlock {
    echo $ecrPassword | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
} -SuccessMessage "Docker logged in"

# 5. Namespace (Check first)
Write-Host "`nStep 4: Checking Namespace..." -ForegroundColor Yellow
$null = kubectl get ns employee-services 2>$null
if ($LASTEXITCODE -ne 0) {
    Exec -ScriptBlock { kubectl create namespace employee-services } -SuccessMessage "Namespace created"
} else {
    Write-Host "✓ Namespace 'employee-services' exists" -ForegroundColor Green
}

# 6. Apply Manifests (Force Namespace)
Write-Host "`nStep 5: Deploying Database..." -ForegroundColor Yellow
Exec -ScriptBlock { kubectl apply -f kubernetes/db-secret.yaml -n employee-services }
Exec -ScriptBlock { kubectl apply -f kubernetes/postgres.yaml -n employee-services } -SuccessMessage "Database manifests applied"

# 7. Wait for Database (Using Rollout Status)
Write-Host "`nStep 6: Waiting for Database..." -ForegroundColor Yellow
Exec -ScriptBlock {
    kubectl rollout status statefulset/postgres -n employee-services --timeout=5m
} -SuccessMessage "Database is ready"

# 8. Dynamic Pod Discovery
# We verified 'app: postgres' matches your YAML
$DB_POD = kubectl get pods -n employee-services -l app=postgres -o jsonpath="{.items[0].metadata.name}"
if (-not $DB_POD) { 
    Write-Host "✗ Could not find Postgres pod. Is the StatefulSet running?" -ForegroundColor Red
    exit 1 
}
Write-Host "  ✓ Found Database Pod: $DB_POD" -ForegroundColor Gray

# 9. Initialize Schema (Deep Verification)
Write-Host "`nStep 7: Initializing Schema..." -ForegroundColor Yellow

# A) Copy file
Exec -ScriptBlock {
    kubectl cp init-employee-db.sql "employee-services/$($DB_POD):/tmp/init-employee-db.sql"
} -SuccessMessage "SQL script copied to pod"

# B) Verify if schema exists (Strict Check)
$schemaCheck = kubectl exec -n employee-services $DB_POD -- psql -U admin -d employees -t -c "SELECT to_regclass('public.employees') IS NOT NULL AND to_regclass('public.departments') IS NOT NULL;" 2>$null
if ($schemaCheck.Trim() -eq "t") {
    Write-Host "✓ Schema already exists (Skipping init)" -ForegroundColor Green
} else {
    # Table missing, run the script
    Exec -ScriptBlock {
        kubectl exec -n employee-services $DB_POD -- psql -U admin -d employees -f /tmp/init-employee-db.sql 
    } -SuccessMessage "Schema initialized successfully"
}

# 10. Insert Admin User
Write-Host "`nStep 8: Checking Admin User..." -ForegroundColor Yellow
$checkAdmin = kubectl exec -n employee-services $DB_POD -- psql -U admin -d employees -t -c "SELECT email FROM employees WHERE email='$ADMIN_EMAIL';" 2>$null
if (-not $checkAdmin.Trim()) {
    Exec -ScriptBlock {
        kubectl exec -n employee-services $DB_POD -- psql -U admin -d employees -c "INSERT INTO employees (first_name, last_name, email, department, position, status, hire_date) VALUES ('Admin', 'User', '$ADMIN_EMAIL', 'IT', 'Administrator', 'active', CURRENT_DATE);"
    } -SuccessMessage "Admin user inserted into DB"
} else {
    Write-Host "✓ Admin user already in DB" -ForegroundColor Green
}

# 11. Cognito Setup (Robust)
Write-Host "`nStep 9: Configuring Cognito..." -ForegroundColor Yellow

# A) Ensure Group Exists
$null = aws cognito-idp get-group --user-pool-id $USER_POOL_ID --group-name "admins" --profile $AWS_PROFILE 2>$null
if ($LASTEXITCODE -ne 0) {
    Exec -ScriptBlock {
        aws cognito-idp create-group --user-pool-id $USER_POOL_ID --group-name "admins" --profile $AWS_PROFILE
    } -SuccessMessage "Created 'admins' group"
}

# B) Ensure User Exists
$null = aws cognito-idp admin-get-user --user-pool-id $USER_POOL_ID --username $ADMIN_USERNAME --profile $AWS_PROFILE 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  - User '$ADMIN_USERNAME' missing. Creating..." -ForegroundColor Gray
    Exec -ScriptBlock {
        aws cognito-idp admin-create-user --user-pool-id $USER_POOL_ID --username $ADMIN_USERNAME --user-attributes Name=email,Value=$ADMIN_EMAIL Name=email_verified,Value=true --temporary-password $ADMIN_PASSWORD --message-action SUPPRESS --profile $AWS_PROFILE
    } -SuccessMessage "Created user $ADMIN_USERNAME"
} else {
    Write-Host "  ✓ User '$ADMIN_USERNAME' already exists" -ForegroundColor Green
}

# C) ALWAYS Set Password (Ensures consistency for demos)
Exec -ScriptBlock {
    aws cognito-idp admin-set-user-password --user-pool-id $USER_POOL_ID --username $ADMIN_USERNAME --password $ADMIN_PASSWORD --permanent --profile $AWS_PROFILE
} -SuccessMessage "Password synchronized"

# D) Add to Group (Strict Check)
$groups = aws cognito-idp admin-list-groups-for-user --user-pool-id $USER_POOL_ID --username $ADMIN_USERNAME --query "Groups[].GroupName" --output text --profile $AWS_PROFILE
if ($groups -notmatch "(^|\s)admins(\s|$)") {
    Exec -ScriptBlock {
        aws cognito-idp admin-add-user-to-group --user-pool-id $USER_POOL_ID --username $ADMIN_USERNAME --group-name "admins" --profile $AWS_PROFILE
    } -SuccessMessage "User added to 'admins' group"
} else {
    Write-Host "✓ User already in 'admins' group" -ForegroundColor Green
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "  SETUP COMPLETE & VERIFIED!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

Write-Host "`n👇 COPY AND RUN THESE COMMANDS TO BUILD/PUSH DOCKER IMAGES 👇" -ForegroundColor Yellow
Write-Host "------------------------------------------------------------" -ForegroundColor Gray
Write-Host "# 1. Build and Push Backend"
Write-Host "cd employee-portal/backend"
Write-Host "docker build -t employee-portal ."
Write-Host "docker tag employee-portal:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/employee-portal:latest"
Write-Host "docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/employee-portal:latest"
Write-Host ""
Write-Host "# 2. Build and Push Frontend"
Write-Host "cd ../frontend"
Write-Host "docker build -t employee-portal-frontend ."
Write-Host "docker tag employee-portal-frontend:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/employee-portal-frontend:latest"
Write-Host "docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/employee-portal-frontend:latest"
Write-Host ""
Write-Host "# 3. Deploy to Kubernetes"
Write-Host "cd ../.."
Write-Host "kubectl apply -f kubernetes/employee-portal.yaml"
Write-Host "kubectl apply -f kubernetes/employee-portal-frontend.yaml"
Write-Host "------------------------------------------------------------" -ForegroundColor Gray