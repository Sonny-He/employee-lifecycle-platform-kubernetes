Write-Host "================================================================" -ForegroundColor Yellow
Write-Host "WARNING: DATABASE RESET - This will delete all data!" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Type 'yes' to reset the database"
if ($confirm -ne "yes") {
    Write-Host "Aborted" -ForegroundColor Red
    exit 0
}

Write-Host "`nResetting database..." -ForegroundColor Cyan

kubectl exec postgres-0 -- psql -U admin -d employees -c "DROP SCHEMA public CASCADE;" 2>&1 | Out-Null
kubectl exec postgres-0 -- psql -U admin -d employees -c "CREATE SCHEMA public;" 2>&1 | Out-Null
kubectl exec postgres-0 -- psql -U admin -d employees -c "GRANT ALL ON SCHEMA public TO admin;" 2>&1 | Out-Null
kubectl exec postgres-0 -- psql -U admin -d employees -c "GRANT ALL ON SCHEMA public TO public;" 2>&1 | Out-Null

Write-Host "Database reset complete" -ForegroundColor Green
Write-Host ""
Write-Host "Now run: post-deployment-setup.ps1" -ForegroundColor Cyan