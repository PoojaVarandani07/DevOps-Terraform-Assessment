# DevOps Assessment – Hotel Booking Platform

> **Stack**: Terraform · AWS ECS/Fargate · RDS PostgreSQL · Docker Compose · GitHub Actions · Shell

A production-grade infrastructure-as-code project demonstrating:
- AWS architecture design with Terraform modules
- Multi-environment management (dev / prod)
- PostgreSQL schema design, indexing, and query optimisation
- Automated database backup and restore

---

## Table of Contents

1. [Repository Structure](#repository-structure)
2. [Architecture Overview](#architecture-overview)
3. [Part 1 & 2 – Terraform Infrastructure](#part-1--2--terraform-infrastructure)
4. [Part 3 – GitHub Actions CI](#part-3--github-actions-ci)
5. [Part 4 – Local Database Setup](#part-4--local-database-setup)
6. [Part 5 – Seed Data & Index Strategy](#part-5--seed-data--index-strategy)
7. [Part 6 – Backup & Restore](#part-6--backup--restore)
8. [Verification Steps](#verification-steps)
9. [Design Decisions](#design-decisions)

---

## Repository Structure

```
devops-assessment/
├── .github/
│   └── workflows/
│       └── terraform.yml          # PR checks: fmt + init + validate + plan
│
├── infra/
│   ├── modules/
│   │   ├── network/               # VPC, subnets, IGW, NAT GW, security groups
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── alb/                   # Application Load Balancer + listeners
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── ecs/                   # ECS Cluster, Task Definition, Fargate Service, Auto Scaling
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── rds/                   # RDS PostgreSQL, KMS encryption, Secrets Manager
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   │
│   └── envs/
│       ├── dev/
│       │   ├── main.tf            # Wires all modules with dev settings
│       │   ├── variables.tf
│       │   ├── dev.tfvars         # Dev-specific values (safe to commit)
│       │   └── outputs.tf
│       └── prod/
│           ├── main.tf            # Wires all modules with prod settings
│           ├── variables.tf
│           ├── prod.tfvars        # Prod-specific values (safe to commit)
│           └── outputs.tf
│
├── db/
│   └── migrations/
│       ├── 001_create_tables.sql  # Schema + indexes
│       └── 002_seed_data.sql      # 120 bookings + events
│
├── scripts/
│   ├── backup.sh                  # Timestamped compressed dump
│   └── restore.sh                 # Drop/recreate + restore + verify
│
├── docker-compose.yml             # PostgreSQL + pgAdmin
├── .env.example                   # Copy to .env and fill in values
├── .gitignore
└── README.md
```

---

## Architecture Overview

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────┐
│                  Public Subnets                  │
│  ┌──────────────────────────────────────────┐   │
│  │      Application Load Balancer (ALB)     │   │
│  │      Port 80 → redirect to 443 (prod)    │   │
│  └──────────────────┬───────────────────────┘   │
└─────────────────────│───────────────────────────┘
                      │ (ALB SG → ECS SG on container port)
┌─────────────────────│───────────────────────────┐
│                Private ECS Subnets               │
│  ┌───────────────────▼──────────────────────┐   │
│  │           ECS / Fargate Tasks            │   │
│  │    (nginx:alpine placeholder container)  │   │
│  │    CPU/Memory auto-scaled 1→10 tasks     │   │
│  └───────────────────┬──────────────────────┘   │
└─────────────────────│───────────────────────────┘
                      │ (ECS SG → RDS SG on port 5432)
┌─────────────────────│───────────────────────────┐
│                Private RDS Subnets               │
│  ┌───────────────────▼──────────────────────┐   │
│  │      RDS PostgreSQL 16 (Multi-AZ)        │   │
│  │    Encrypted at rest (KMS)               │   │
│  │    Credentials in Secrets Manager        │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘

NAT Gateway (in public subnet) provides outbound internet
access from private subnets (ECR pulls, AWS API calls).
```

**Security model:**
| Resource | Inbound | Outbound |
|----------|---------|----------|
| ALB | 0.0.0.0/0 on 80/443 | All |
| ECS Tasks | ALB SG on container port only | All (via NAT) |
| RDS | ECS SG on 5432 only | — |

---

## Part 1 & 2 – Terraform Infrastructure

### Prerequisites

```bash
terraform --version   # ≥ 1.6.0
aws --version         # AWS CLI configured with appropriate IAM permissions
```

### Running Terraform (dev)

```bash
cd infra/envs/dev

# 1. Initialise – replace bucket/table with your actual S3 backend resources
terraform init \
  -backend-config="bucket=my-terraform-state-dev" \
  -backend-config="key=devops-assessment/dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=terraform-locks"

# 2. Check formatting
terraform fmt -check -recursive ../..

# 3. Validate
terraform validate

# 4. Plan (no actual deployment needed for assessment)
export TF_VAR_db_password="supersecret123"
terraform plan -var-file="dev.tfvars" -refresh=false

# 5. Apply (optional – requires real AWS credentials)
terraform apply -var-file="dev.tfvars"
```

### Running Terraform (local validation – no AWS credentials)

```bash
cd infra/envs/dev
terraform init -backend=false
terraform fmt -check -recursive ../..
terraform validate
terraform plan -var-file="dev.tfvars" -refresh=false -var="db_password=localtest"
```

### Module Overview

#### `modules/network`
- VPC with DNS support enabled
- 3-tier subnets: public (ALB), private-ecs, private-rds (one subnet per AZ)
- Internet Gateway + NAT Gateway (single-AZ, toggleable to save cost)
- Three security groups with least-privilege rules:
  - **ALB SG**: internet → 80/443
  - **ECS SG**: ALB SG → container port
  - **RDS SG**: ECS SG → 5432

#### `modules/alb`
- Internet-facing ALB across public subnets
- HTTP → HTTPS redirect when `https_certificate_arn` is set (prod)
- Target group with IP target type (required for Fargate `awsvpc` mode)
- Health check on configurable path
- Deletion protection toggle per environment

#### `modules/ecs`
- ECS Cluster with Container Insights toggle
- FARGATE / FARGATE_SPOT capacity providers
- Task Definition with:
  - `awslogs` log driver → CloudWatch
  - Secrets Manager integration (DB credentials injected as env vars)
  - Health check via `curl`
- ECS Service with:
  - Deployment circuit breaker + auto-rollback
  - `ignore_changes = [desired_count]` (lets App Auto Scaling own the count)
- Application Auto Scaling: CPU ≥70% and Memory ≥80% trigger scale-out

#### `modules/rds`
- PostgreSQL 16 in private subnets only (`publicly_accessible = false`)
- KMS CMK for encryption at rest (with key rotation enabled)
- Secrets Manager secret storing host/user/password/dbname as JSON
- Custom parameter group enabling slow query logging and `pg_stat_statements`
- Enhanced monitoring and Performance Insights (prod only)
- Automated backups with configurable retention
- `deletion_protection` and `skip_final_snapshot` differ between dev/prod

---

## Part 3 – GitHub Actions CI

File: `.github/workflows/terraform.yml`

Triggers on pull requests that touch `infra/**` against `main`/`master`.

**Jobs**: `terraform-dev` and `terraform-prod` run in parallel.

Each job performs:
1. `terraform fmt -check` – fails if any file needs formatting
2. `terraform init -backend=false` – initialises without remote state
3. `terraform validate` – validates configuration syntax and references
4. `terraform plan -refresh=false` – generates a plan without AWS API calls
5. Posts the plan output as a PR comment (collapsible `<details>` block)
6. Uploads the plan binary as a workflow artifact (5-day retention)

**Required GitHub Secret:**
```
TF_VAR_DB_PASSWORD   ← set in repo Settings → Secrets → Actions
```

---

## Part 4 – Local Database Setup

### Prerequisites

- Docker ≥ 20.10
- Docker Compose plugin (v2) or standalone `docker-compose` v1.29+

### Start the database

```bash
# Copy and customise environment variables (optional – defaults work out of the box)
cp .env.example .env

# Start PostgreSQL
docker compose up -d

# Check it is healthy
docker compose ps
# Expected: hotel_postgres   running (healthy)

# Optional: start pgAdmin UI at http://localhost:5050
docker compose --profile tools up -d
```

Docker Compose automatically runs every `.sql` file in `db/migrations/` in
alphabetical order on the **first** startup (via `docker-entrypoint-initdb.d`).
This creates the schema, indexes, and seed data automatically.

### Verify the database is ready

```bash
docker exec hotel_postgres \
  psql -U hoteluser -d hoteldb \
  -c "\dt"
#  List of relations
#  Schema │      Name      │ Type  │   Owner
# ────────┼────────────────┼───────┼───────────
#  public │ booking_events │ table │ hoteluser
#  public │ hotel_bookings │ table │ hoteluser
```

---

## Part 5 – Seed Data & Index Strategy

### Seed data summary

| Dimension | Values |
|-----------|--------|
| Total bookings | 120 |
| Cities | delhi (40), mumbai (20), bangalore (20), chennai (10), hyderabad (10) |
| Organisations | 6 (b1000001 … b1000006) |
| Statuses | confirmed, completed, cancelled, pending, no_show |
| Hotels | 5 per city (HTL-DL-001…005, HTL-MB-001…005, etc.) |
| Booking events | ~30 events covering 20 unique bookings |
| Event types | booking_created, payment_received, status_changed, checkin_completed, checkout_completed, refund_processed |

### Target query

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

### Index strategy

#### Primary index: `idx_bookings_city_created_at`

```sql
CREATE INDEX idx_bookings_city_created_at
    ON hotel_bookings (city, created_at DESC)
    INCLUDE (org_id, status, amount);
```

**Why this index:**

1. **`city` as the leading column** – the `WHERE city = 'delhi'` equality
   predicate is highly selective; placing it first allows Postgres to seek
   directly to all "delhi" rows.

2. **`created_at DESC` as the second column** – the `created_at >= NOW() -
   INTERVAL '30 days'` range predicate is evaluated next; the DESC ordering
   means the newest rows (most likely to satisfy the predicate) are visited
   first, enabling an early termination.

3. **`INCLUDE (org_id, status, amount)`** – these columns are needed only for
   the `SELECT` and `GROUP BY` clauses, not for the WHERE filter. Adding them
   as non-key columns makes the index **covering**: Postgres can resolve the
   entire query from the index without a heap fetch, avoiding a costly
   Index Scan + Heap Fetch → Aggregate pattern.

4. **Result**: the query plan becomes an **Index Only Scan → HashAggregate**
   with no sequential table scan.

#### Supporting indexes

| Index | Columns | Purpose |
|-------|---------|---------|
| `idx_bookings_org_status` | `(org_id, status)` | Organisation dashboard queries |
| `idx_bookings_hotel_id` | `(hotel_id)` | Property management lookups |
| `idx_events_booking_id` | `(booking_id, created_at DESC)` | FK join + event timeline |
| `idx_events_event_type` | `(event_type)` | Filter events by type |

### Verify query plan

```bash
docker exec hotel_postgres psql -U hoteluser -d hoteldb -c "
  EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
  SELECT org_id, status, COUNT(*), SUM(amount)
  FROM hotel_bookings
  WHERE city = 'delhi'
    AND created_at >= NOW() - INTERVAL '30 days'
  GROUP BY org_id, status;
"
# Look for: Index Only Scan using idx_bookings_city_created_at
```

---

## Part 6 – Backup & Restore

### Prerequisites

```bash
chmod +x scripts/backup.sh scripts/restore.sh
docker compose up -d   # postgres must be healthy
```

### Backup

```bash
./scripts/backup.sh
```

**What it does:**
1. Validates that Docker and the `hotel_postgres` container are running
2. Runs `pg_dump` inside the container (no local `pg_dump` needed)
3. Pipes output through `gzip -9` on the host
4. Saves to `./backups/backup_hoteldb_YYYYMMDD_HHMMSS.sql.gz`
5. Creates/updates `./backups/latest_hoteldb.sql.gz` symlink
6. Prunes backups older than the 7 most recent

**Sample output:**
```
[INFO]  Starting backup of database 'hoteldb'
[INFO]  Running pg_dump inside container 'hotel_postgres'...
[INFO]  Backup completed successfully!
[INFO]    File  : ./backups/backup_hoteldb_20250707_143022.sql.gz
[INFO]    Size  : 12K
[INFO]    Latest: ./backups/latest_hoteldb.sql.gz
```

### Restore

```bash
# Restore latest backup
./scripts/restore.sh

# Restore a specific backup
./scripts/restore.sh ./backups/backup_hoteldb_20250707_143022.sql.gz
```

**What it does:**
1. Prompts for confirmation (type `yes`)
2. Terminates all active connections to the target database
3. Drops and recreates the database for a clean slate
4. Decompresses the backup and pipes it into `psql`
5. Runs a 4-step verification:
   - Row counts for both tables
   - Smoke-test aggregation query (city=delhi, last 30 days)

### Verification of a successful restore

After running `./scripts/restore.sh` you should see output like:

```
══════════════════════════════════════
  Step 3 / 4 — Verification
══════════════════════════════════════
[INFO]  Row counts after restore:
   table_name    | rows
-----------------+------
 booking_events  |   30
 hotel_bookings  |  120

══════════════════════════════════════
  Step 4 / 4 — Smoke test query
══════════════════════════════════════
[INFO]  Running optimised aggregation query (city=delhi, last 30 days):
              org_id              |  status   | booking_count | total_amount
----------------------------------+-----------+---------------+--------------
 b1000001-0000-0000-0000-00000001 | confirmed |             4 |     59300.00
 b1000001-0000-0000-0000-00000001 | pending   |             1 |     18000.00
 ...

 Restore verified successfully!
```

**Additional manual checks:**

```bash
# Verify row counts manually
docker exec hotel_postgres psql -U hoteluser -d hoteldb \
  -c "SELECT COUNT(*) FROM hotel_bookings;"   # expect: 120
docker exec hotel_postgres psql -U hoteluser -d hoteldb \
  -c "SELECT COUNT(*) FROM booking_events;"   # expect: 30

# Verify data integrity – check all cities are present
docker exec hotel_postgres psql -U hoteluser -d hoteldb \
  -c "SELECT city, COUNT(*) FROM hotel_bookings GROUP BY city ORDER BY city;"

# Verify all statuses are present
docker exec hotel_postgres psql -U hoteluser -d hoteldb \
  -c "SELECT status, COUNT(*) FROM hotel_bookings GROUP BY status ORDER BY status;"

# Verify indexes are present
docker exec hotel_postgres psql -U hoteluser -d hoteldb \
  -c "\di hotel_bookings*"
```

---

## Verification Steps (Reviewer Checklist)

### Terraform

```bash
cd infra/envs/dev
terraform init -backend=false
terraform fmt -check -recursive ../..
terraform validate
terraform plan -var-file="dev.tfvars" -refresh=false -var="db_password=test"
```

```bash
cd ../prod
terraform init -backend=false
terraform validate
terraform plan -var-file="prod.tfvars" -refresh=false -var="db_password=test"
```

### Database

```bash
docker compose up -d
./scripts/backup.sh
./scripts/restore.sh   # type 'yes' when prompted
```

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| 3-module structure | Separation of concerns; each module is independently testable and reusable across environments |
| Modules accept SG IDs as inputs | Avoids circular dependencies; lets the network module own SG creation |
| `INCLUDE` columns on primary index | Makes the hot aggregation query an Index Only Scan, avoiding heap access |
| KMS CMK per environment | Separate encryption domains; compromising one key doesn't affect the other |
| Secrets Manager for DB password | Avoids plaintext credentials in task definitions; ECS execution role retrieves at launch |
| `skip_final_snapshot = true` (dev) | Allows fast `terraform destroy` in dev without manual snapshot cleanup |
| `ignore_changes = [desired_count]` | Prevents Terraform from resetting the task count after App Auto Scaling adjusts it |
| Fargate Spot in dev | ~70% cost saving; interruptions are acceptable in non-production |
| Single NAT Gateway | Sufficient for dev/prod at this scale; a per-AZ NAT can be added by modifying `count` in the NAT resource |
| `docker-entrypoint-initdb.d` | Zero-touch DB init: migrations run automatically on first `docker compose up` |
| Backup prune (keep 7) | Balances disk usage vs. recovery window for local backups |
