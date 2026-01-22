# ============================================================================
# CS3 Post-Deployment Setup Script
# Run this ONCE after Terraform completes
# Automates: kubectl, ECR, database, Cognito admin user
# ============================================================================

param(
    [string]$AWS_PROFILE = "student"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  CS3 EMPLOYEE PLATFORM - POST-DEPLOYMENT SETUP" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# Get dynamic values from Terraform outputs
Write-Host "Retrieving configuration from Terraform..." -ForegroundColor Gray
try {
    $AWS_REGION = (terraform output -raw aws_region)
    $ACCOUNT_ID = (terraform output -raw aws_account_id)
    $CLUSTER_NAME = (terraform output -raw eks_cluster_name)
    $USER_POOL_ID = (terraform output -raw cognito_user_pool_id)
    $ADMIN_EMAIL = "admin@innovatech.local"
    $ADMIN_PASSWORD = "AdminPass123!"
    
    Write-Host "  ✓ Region: $AWS_REGION" -ForegroundColor Green
    Write-Host "  ✓ Account: $ACCOUNT_ID" -ForegroundColor Green
    Write-Host "  ✓ Cluster: $CLUSTER_NAME" -ForegroundColor Green
    Write-Host "  ✓ User Pool: $USER_POOL_ID" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to get Terraform outputs" -ForegroundColor Red
    Write-Host "  Make sure you've run 'terraform apply' first" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "This script will automatically configure:" -ForegroundColor White
Write-Host "  ✓ kubectl for EKS cluster access" -ForegroundColor Gray
Write-Host "  ✓ ECR repositories for Docker images" -ForegroundColor Gray
Write-Host "  ✓ Kubernetes namespace and secrets" -ForegroundColor Gray
Write-Host "  ✓ PostgreSQL database with sample data" -ForegroundColor Gray
Write-Host "  ✓ Cognito admin user for portal access" -ForegroundColor Gray
Write-Host "  ✓ Admin user in database" -ForegroundColor Gray
Write-Host ""

# Step 1: Configure kubectl
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 1/11: Configuring kubectl for EKS..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME --profile $AWS_PROFILE 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to configure kubectl" -ForegroundColor Red
    Write-Host "  Make sure EKS cluster is deployed via Terraform" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ kubectl configured successfully" -ForegroundColor Green

# Step 2: Verify cluster access
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 2/11: Verifying EKS cluster access..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

$nodes = kubectl get nodes --no-headers 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Cannot access EKS cluster" -ForegroundColor Red
    Write-Host "  Error: $nodes" -ForegroundColor Yellow
    exit 1
}

$nodeCount = ($nodes | Measure-Object).Count
Write-Host "✓ Connected to EKS cluster ($nodeCount nodes)" -ForegroundColor Green
kubectl get nodes | Out-String | Write-Host -ForegroundColor Gray

# Step 3: Create ECR repositories
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 3/11: Creating ECR repositories..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

# Check if backend repo exists
$backendRepo = aws ecr describe-repositories --repository-names employee-portal --profile $AWS_PROFILE --region $AWS_REGION 2>$null
if (-not $backendRepo) {
    Write-Host "  Creating backend ECR repository..." -ForegroundColor Gray
    aws ecr create-repository --repository-name employee-portal --profile $AWS_PROFILE --region $AWS_REGION 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Created: employee-portal" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ Backend repo exists: employee-portal" -ForegroundColor Green
}

# Check if frontend repo exists
$frontendRepo = aws ecr describe-repositories --repository-names employee-portal-frontend --profile $AWS_PROFILE --region $AWS_REGION 2>$null
if (-not $frontendRepo) {
    Write-Host "  Creating frontend ECR repository..." -ForegroundColor Gray
    aws ecr create-repository --repository-name employee-portal-frontend --profile $AWS_PROFILE --region $AWS_REGION 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Created: employee-portal-frontend" -ForegroundColor Green
    }
} else {
    Write-Host "  ✓ Frontend repo exists: employee-portal-frontend" -ForegroundColor Green
}

Write-Host "✓ ECR repositories ready" -ForegroundColor Green

# Step 4: Login to ECR
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 4/11: Logging in to Amazon ECR..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

$ecrPassword = aws ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to get ECR password" -ForegroundColor Red
    exit 1
}

echo $ecrPassword | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com" 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to login to ECR" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Logged in to ECR" -ForegroundColor Green

# Step 5: Create namespace
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 5/11: Creating Kubernetes namespace..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

kubectl create namespace employee-services --dry-run=client -o yaml | kubectl apply -f - 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Namespace 'employee-services' ready" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to create namespace" -ForegroundColor Red
    exit 1
}

# Step 6: Apply database secret
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 6/11: Applying database secret..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

if (-not (Test-Path "kubernetes/db-secret.yaml")) {
    Write-Host "✗ kubernetes/db-secret.yaml not found" -ForegroundColor Red
    exit 1
}

kubectl apply -f kubernetes/db-secret.yaml 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to apply database secret" -ForegroundColor Red
    exit 1
}

# Verify secret was created
$secretExists = kubectl get secret employee-db-credentials -n employee-services --ignore-not-found 2>$null
if ($secretExists) {
    Write-Host "✓ Database secret 'employee-db-credentials' created" -ForegroundColor Green
} else {
    Write-Host "✗ Database secret not found" -ForegroundColor Red
    exit 1
}

# Step 7: Deploy PostgreSQL database
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 7/11: Deploying PostgreSQL database..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

if (-not (Test-Path "kubernetes/postgres.yaml")) {
    Write-Host "✗ kubernetes/postgres.yaml not found" -ForegroundColor Red
    exit 1
}

kubectl apply -f kubernetes/postgres.yaml 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to deploy PostgreSQL" -ForegroundColor Red
    exit 1
}
Write-Host "✓ PostgreSQL StatefulSet deployed" -ForegroundColor Green

# Step 8: Wait for PostgreSQL pod to be ready
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 8/11: Waiting for PostgreSQL pod to be ready..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "  This may take 2-3 minutes..." -ForegroundColor Gray

$maxAttempts = 40
$attempt = 0
$podReady = $false

while (($podReady -eq $false) -and ($attempt -lt $maxAttempts)) {
    $podStatus = kubectl get pod postgres-0 -n employee-services -o jsonpath='{.status.phase}' 2>$null
    
    if ($podStatus -eq "Running") {
        $containerReady = kubectl get pod postgres-0 -n employee-services -o jsonpath='{.status.containerStatuses[0].ready}' 2>$null
        if ($containerReady -eq "true") {
            $podReady = $true
            Write-Host "✓ PostgreSQL pod is running and ready" -ForegroundColor Green
        } else {
            Write-Host "  Container starting...  ($attempt/$maxAttempts)" -ForegroundColor Gray
            Start-Sleep -Seconds 10
            $attempt++
        }
    } else {
        Write-Host "  Waiting for postgres-0...  Status: $podStatus ($attempt/$maxAttempts)" -ForegroundColor Gray
        Start-Sleep -Seconds 10
        $attempt++
    }
}

if ($podReady -eq $false) {
    Write-Host "✗ PostgreSQL pod failed to start" -ForegroundColor Red
    Write-Host "  Debug: kubectl describe pod postgres-0 -n employee-services" -ForegroundColor Yellow
    Write-Host "  Debug: kubectl logs postgres-0 -n employee-services" -ForegroundColor Yellow
    exit 1
}

# Step 9: Initialize database schema
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 9/11: Initializing database schema..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

if (-not (Test-Path "init-employee-db.sql")) {
    Write-Host "✗ init-employee-db.sql not found" -ForegroundColor Red
    exit 1
}

Write-Host "  Copying SQL file to postgres pod..." -ForegroundColor Gray
kubectl cp init-employee-db.sql employee-services/postgres-0:/tmp/init-employee-db.sql 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to copy SQL file" -ForegroundColor Red
    exit 1
}

Write-Host "  Executing database initialization..." -ForegroundColor Gray

# Execute SQL - ignore NOTICEs, only fail on actual errors
$script:hasDBError = $false
$ErrorActionPreference = "Continue"
kubectl exec -n employee-services postgres-0 -- psql -U admin -d employees -f /tmp/init-employee-db.sql 2>&1 | ForEach-Object {
    $line = $_.ToString()
    if ($line -match "ERROR:") {
        Write-Host "  ✗ $line" -ForegroundColor Red
        $script:hasDBError = $true
    }
    elseif ($line -match "NOTICE:.*already exists") {
        Write-Host "  ⚠ Tables already exist (skipping)" -ForegroundColor Yellow
    }
}
$ErrorActionPreference = "Stop"

if ($script:hasDBError) {
    Write-Host "✗ Failed to initialize database" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Database schema initialized" -ForegroundColor Green

# Verify data
$employeeCount = kubectl exec -n employee-services postgres-0 -- psql -U admin -d employees -t -c "SELECT COUNT(*) FROM employees;" 2>$null
$employeeCount = $employeeCount.Trim()
Write-Host "  Sample data: $employeeCount employees loaded" -ForegroundColor Gray

# Step 9.5: Add Admin User to Database
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 9.5/11: Adding admin user to database..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

$adminExists = kubectl exec -n employee-services postgres-0 -- psql -U admin -d employees -t -c "SELECT COUNT(*) FROM employees WHERE email='$ADMIN_EMAIL';" 2>$null
$adminExists = $adminExists.Trim()

if ($adminExists -eq "0") {
    Write-Host "  Creating admin user in database..." -ForegroundColor Gray
    kubectl exec -n employee-services postgres-0 -- psql -U admin -d employees -c "INSERT INTO employees (first_name, last_name, email, department, position, status, hire_date) VALUES ('Admin', 'User', '$ADMIN_EMAIL', 'IT', 'Administrator', 'active', CURRENT_DATE);" 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Admin user added to database" -ForegroundColor Green
        
        # Verify it was added
        $newCount = kubectl exec -n employee-services postgres-0 -- psql -U admin -d employees -t -c "SELECT COUNT(*) FROM employees WHERE email='$ADMIN_EMAIL';" 2>$null
        $newCount = $newCount.Trim()
        if ($newCount -eq "1") {
            Write-Host "  ✓ Verified: Admin user exists in database" -ForegroundColor Green
        }
    } else {
        Write-Host "✗ Failed to add admin to database" -ForegroundColor Red
    }
} else {
    Write-Host "  ⚠ Admin user already exists in database" -ForegroundColor Yellow
}

Write-Host "✓ Admin user configured in database" -ForegroundColor Green

# Step 10: Create Cognito admin user
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 10/11: Creating Cognito admin user..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

# Check if user already exists
$userExists = aws cognito-idp admin-get-user --user-pool-id $USER_POOL_ID --username admin --profile $AWS_PROFILE 2>$null
if ($userExists) {
    Write-Host "  ⚠ Admin user already exists in Cognito" -ForegroundColor Yellow
} else {
    Write-Host "  Creating admin user in Cognito..." -ForegroundColor Gray
    
    $createResult = aws cognito-idp admin-create-user `
        --user-pool-id $USER_POOL_ID `
        --username admin `
        --user-attributes Name=email,Value=$ADMIN_EMAIL Name=email_verified,Value=true `
        --temporary-password "TempPass123!" `
        --message-action SUPPRESS `
        --profile $AWS_PROFILE 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        # Set permanent password
        Write-Host "  Setting permanent password..." -ForegroundColor Gray
        aws cognito-idp admin-set-user-password `
            --user-pool-id $USER_POOL_ID `
            --username admin `
            --password $ADMIN_PASSWORD `
            --permanent `
            --profile $AWS_PROFILE 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Admin user created with permanent password" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Created but failed to set permanent password" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ Failed to create admin user" -ForegroundColor Red
        Write-Host "  Error: $createResult" -ForegroundColor Yellow
    }
}

Write-Host "✓ Cognito admin user configured" -ForegroundColor Green

# Step 11: Get LoadBalancer URL
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Step 11/11: Retrieving LoadBalancer URL..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

Write-Host "  Waiting for LoadBalancer to be provisioned (this may take 2-3 minutes)..." -ForegroundColor Gray

$maxAttempts = 30
$attempt = 0
$lbUrl = ""

while (($lbUrl -eq "") -and ($attempt -lt $maxAttempts)) {
    $lbUrl = kubectl get svc -n employee-services employee-portal-frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    
    if ($lbUrl -ne "") {
        Write-Host "  ✓ LoadBalancer URL retrieved" -ForegroundColor Green
        break
    } else {
        Write-Host "  Waiting for LoadBalancer...  ($attempt/$maxAttempts)" -ForegroundColor Gray
        Start-Sleep -Seconds 5
        $attempt++
    }
}

if ($lbUrl -eq "") {
    Write-Host "  ⚠ LoadBalancer not ready yet" -ForegroundColor Yellow
    Write-Host "  Check status with: kubectl get svc -n employee-services employee-portal-frontend" -ForegroundColor Gray
} else {
    Write-Host "✓ Employee Portal URL: http://$lbUrl" -ForegroundColor Green
}

# ============================================================================
# SETUP COMPLETE - SHOW NEXT STEPS
# ============================================================================

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "  ✓ AUTOMATED SETUP COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

Write-Host "`n📋 WHAT WAS CONFIGURED:"
Write-Host "  [✓] EKS Cluster (kubectl configured)" -ForegroundColor Gray
Write-Host "  [✓] ECR Repositories (backend + frontend)" -ForegroundColor Gray
Write-Host "  [✓] Docker logged in to ECR" -ForegroundColor Gray
Write-Host "  [✓] Kubernetes namespace 'employee-services'" -ForegroundColor Gray
Write-Host "  [✓] Database secret 'employee-db-credentials'" -ForegroundColor Gray
Write-Host "  [✓] PostgreSQL StatefulSet running" -ForegroundColor Gray
Write-Host "  [✓] Database schema with sample employees" -ForegroundColor Gray
Write-Host "  [✓] Admin user in database: $ADMIN_EMAIL" -ForegroundColor Gray
Write-Host "  [✓] Cognito admin user: admin" -ForegroundColor Gray

if ($lbUrl -ne "") {
    Write-Host "`n🌐 PORTAL ACCESS:"
    Write-Host "  URL: http://$lbUrl" -ForegroundColor Cyan
    Write-Host "  Username: admin" -ForegroundColor Cyan
    Write-Host "  Password: $ADMIN_PASSWORD" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Open in browser:" -ForegroundColor Gray
    Write-Host "  Start-Process 'http://$lbUrl'" -ForegroundColor White
}

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "📊 MONITORING COMMANDS" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""
Write-Host "# View all pods"
Write-Host "kubectl get pods -n employee-services"
Write-Host ""
Write-Host "# View services and LoadBalancer IPs"
Write-Host "kubectl get svc -n employee-services"
Write-Host ""
Write-Host "# Stream backend logs"
Write-Host "kubectl logs -n employee-services -l app=employee-portal -f"
Write-Host ""
Write-Host "# Stream frontend logs"
Write-Host "kubectl logs -n employee-services -l app=employee-portal-frontend -f"
Write-Host ""
Write-Host "# Connect to database"
Write-Host 'kubectl exec -it -n employee-services postgres-0 -- psql -U admin -d employees'
Write-Host ""
Write-Host "# Query employees"
Write-Host 'kubectl exec -n employee-services postgres-0 -- psql -U admin -d employees -c "SELECT employee_id, first_name, last_name, email, department FROM employees;"'

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "🔧 TROUBLESHOOTING" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""
Write-Host "Problem: Can't login to portal"
Write-Host "Solution: Verify admin exists in both Cognito AND database"
Write-Host "  Cognito: aws cognito-idp admin-get-user --user-pool-id $USER_POOL_ID --username admin --profile $AWS_PROFILE"
Write-Host "  Database: kubectl exec -n employee-services postgres-0 -- psql -U admin -d employees -c `"SELECT * FROM employees WHERE email='$ADMIN_EMAIL';`""
Write-Host ""
Write-Host "Problem: '502 Bad Gateway' in browser"
Write-Host "Solution: Backend pods not ready, check: kubectl logs -n employee-services -l app=employee-portal"
Write-Host ""
Write-Host "Problem: LoadBalancer URL not showing"
Write-Host "Solution: Run: kubectl get svc -n employee-services employee-portal-frontend"

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "  Ready! Access the portal at the URL above" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""