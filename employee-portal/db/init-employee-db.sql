-- ============================================================================
-- Employee Portal Database Schema (IDEMPOTENT VERSION)
-- Safe to run multiple times - Updated 2024-12-06
-- ============================================================================

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- TABLE: departments
-- ============================================================================
CREATE TABLE IF NOT EXISTS departments (
    department_id SERIAL PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TABLE: employees
-- ============================================================================
CREATE TABLE IF NOT EXISTS employees (
    employee_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    department VARCHAR(100),
    position VARCHAR(100),
    hire_date DATE DEFAULT CURRENT_DATE,
    termination_date DATE,
    status VARCHAR(20) DEFAULT 'active',
    cognito_user_id VARCHAR(255),
    ad_user_id VARCHAR(255),
    workspace_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TABLE: access_requests
-- ============================================================================
CREATE TABLE IF NOT EXISTS access_requests (
    request_id SERIAL PRIMARY KEY,
    employee_id INTEGER REFERENCES employees(employee_id) ON DELETE CASCADE,
    request_type VARCHAR(50) NOT NULL,
    resource_name VARCHAR(255) NOT NULL,        -- Added this column
    justification TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    approved_at TIMESTAMP,
    approved_by VARCHAR(255)
);

-- ============================================================================
-- TABLE: onboarding_tasks
-- ============================================================================
CREATE TABLE IF NOT EXISTS onboarding_tasks (
    task_id SERIAL PRIMARY KEY,
    employee_id INTEGER REFERENCES employees(employee_id) ON DELETE CASCADE,
    task_name VARCHAR(255) NOT NULL,
    task_description TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- TABLE: audit_logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id SERIAL PRIMARY KEY,
    employee_id INTEGER REFERENCES employees(employee_id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(255),
    details TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES (idempotent - drop first, then create)
-- ============================================================================
DROP INDEX IF EXISTS idx_employees_email;
DROP INDEX IF EXISTS idx_employees_status;
DROP INDEX IF EXISTS idx_employees_department;
DROP INDEX IF EXISTS idx_access_requests_employee;
DROP INDEX IF EXISTS idx_access_requests_status;
DROP INDEX IF EXISTS idx_onboarding_employee;
DROP INDEX IF EXISTS idx_audit_employee;
DROP INDEX IF EXISTS idx_audit_timestamp;

CREATE INDEX idx_employees_email ON employees(email);
CREATE INDEX idx_employees_status ON employees(status);
CREATE INDEX idx_employees_department ON employees(department);
CREATE INDEX idx_access_requests_employee ON access_requests(employee_id);
CREATE INDEX idx_access_requests_status ON access_requests(status);
CREATE INDEX idx_onboarding_employee ON onboarding_tasks(employee_id);
CREATE INDEX idx_audit_employee ON audit_logs(employee_id);
CREATE INDEX idx_audit_timestamp ON audit_logs(timestamp);

-- ============================================================================
-- FUNCTION & TRIGGER (idempotent - drop first, then create)
-- ============================================================================
DROP TRIGGER IF EXISTS update_employees_updated_at ON employees;
DROP FUNCTION IF EXISTS update_updated_at_column();

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_employees_updated_at
    BEFORE UPDATE ON employees
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SAMPLE DATA (insert only if not exists)
-- ============================================================================

-- Insert departments
INSERT INTO departments (department_name, description)
SELECT 'Engineering', 'Software development and technical operations'
WHERE NOT EXISTS (SELECT 1 FROM departments WHERE department_name = 'Engineering');

INSERT INTO departments (department_name, description)
SELECT 'Human Resources', 'People operations and talent management'
WHERE NOT EXISTS (SELECT 1 FROM departments WHERE department_name = 'Human Resources');

INSERT INTO departments (department_name, description)
SELECT 'Finance', 'Financial planning and accounting'
WHERE NOT EXISTS (SELECT 1 FROM departments WHERE department_name = 'Finance');

-- Insert sample employees
INSERT INTO employees (first_name, last_name, email, department, position, status)
SELECT 'John', 'Doe', 'john.doe@innovatech.local', 'Engineering', 'Senior Developer', 'active'
WHERE NOT EXISTS (SELECT 1 FROM employees WHERE email = 'john.doe@innovatech.local');

INSERT INTO employees (first_name, last_name, email, department, position, status)
SELECT 'Jane', 'Smith', 'jane.smith@innovatech.local', 'Human Resources', 'HR Manager', 'active'
WHERE NOT EXISTS (SELECT 1 FROM employees WHERE email = 'jane.smith@innovatech.local');

INSERT INTO employees (first_name, last_name, email, department, position, status)
SELECT 'Bob', 'Johnson', 'bob.johnson@innovatech.local', 'Engineering', 'DevOps Engineer', 'active'
WHERE NOT EXISTS (SELECT 1 FROM employees WHERE email = 'bob.johnson@innovatech.local');

INSERT INTO employees (first_name, last_name, email, department, position, status)
SELECT 'Alice', 'Williams', 'alice.williams@innovatech.local', 'Finance', 'Financial Analyst', 'active'
WHERE NOT EXISTS (SELECT 1 FROM employees WHERE email = 'alice.williams@innovatech.local');

-- ============================================================================
-- VERIFICATION
-- ============================================================================
\echo '==================================================='
\echo 'Database initialized successfully!'
\echo '==================================================='
SELECT COUNT(*) AS department_count FROM departments;
SELECT COUNT(*) AS employee_count FROM employees;
\echo '==================================================='