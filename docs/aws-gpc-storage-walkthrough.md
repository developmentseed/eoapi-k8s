# Production Storage

Most folks will want to use a cloud provider's PasS database service for production situations. Below 
we walkthrough the chnages to make that doable

---

## AWS RDS

Step 1: First, we'll need to provision an RDS or Cloud SQL instance (see [GCP](#gcp-cloud-sql) below)

> &#9432; The Terraform below is just for edification and examples. 
> It's not meant to be exhaustive something you execute from this repo

```terraform
terraform {
  required_version = "1.3.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

resource "aws_db_subnet_group" "db" {
  name       = "tf-${var.project_name}-${var.env}-subnet-group"
  subnet_ids = ${var.private_subnet_ids_array}
  tags = {
    Name = "tf-${var.project_name}-subnet-group"
  }
}

# NOTE: the below params are just examples of modifications
# they have nothing to do with what is a recommended default
# b/c that depends largely on your data and other variables
resource "aws_db_parameter_group" "default" {
  name   = "tf-${var.project_name}-${var.env}-postgres14-param-group"
  family = "postgres14"

  parameter {
    name  = "work_mem"
    value = "8192"
  }

  parameter {
    name  = "max_connections"
    value = "475"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "shared_buffers"
    value = "4032428"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "seq_page_cost"
    value = "1"
  }

  parameter {
    name  = "random_page_cost"
    value = "1.2"
  }
}

resource "aws_db_instance" "db" {
  db_name                  = "eoapi-prod-db"
  identifier               = "${var.project_name}-${var.env}"
  engine                   = "postgres"
  engine_version           = "14.7"
  // https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateDBInstance.html
  allocated_storage        = 100
  max_allocated_storage    = 500
  storage_type             = "gp2"
  instance_class           = "db.r5.large"
  db_subnet_group_name     = aws_db_subnet_group.db.name
  vpc_security_group_ids   = security_group_ids_array
  skip_final_snapshot      = true
  apply_immediately        = true
  backup_retention_period  = 7
  username                 = "postgres"
  password                 = var.db_password
  allow_major_version_upgrade = true
  parameter_group_name     = aws_db_parameter_group.default.name
}

output "db_hostname" {
  value = aws_db_instance.db.endpoint
}
```

## GCP Cloud SQL

```terraform
terraform {
  required_version = "1.3.9"
  required_providers {
    google = {
      source = "hashicorp/google"
      version = ">= 3.5.0"
    }
  }
}

resource "google_sql_database_instance" "default" {
  name             = "eoapi-prod-db-instance"
  database_version = "POSTGRES_14"
  region           = "us-central1"

  settings {
    tier = "db-n1-standard-2"

    ip_configuration {
      ipv4_enabled    = true
      private_network = ${var.vpc_network_self_link}

      authorized_networks {
        value           = "0.0.0.0/0" # Caution: This opens to all IPs
        name            = "all-ips"
      }
    }
  }
}

resource "google_sql_database" "default" {
  name       = "eoapi-prod-db"
  instance   = google_sql_database_instance.default.name
  collation  = "en_US.UTF8"
}

resource "google_sql_user" "users" {
  name     = "postgres"
  instance = google_sql_database_instance.default.name
  password = "${var.db_password}
}

output "instance_address" {
  value = google_sql_database_instance.default.ip_address[0].ip_address
}
```

## Write eoapi-k8s config.yaml

Step 2: Next we just need to develop some `config.yaml` overrides that `helm install` will use with our new host, port, username etc

```bash
 $ cat config.yaml 
      db:
        environment: "rds"
        settings:
          secrets:
              POSTGRES_DB: "postgis"
              POSTGRES_USER: "<your-s00pers3cr3t-user>"
              POSTGRES_PASSWORD: "<your-s00pers3cr3t-password>"
              POSTGRES_PORT: "5432"
              POSTGRES_HOST: "<your-rds-host>"
              POSTGRES_HOST_READER: "<your-rds-host>"
              POSTGRES_HOST_WRITER: "<your-rds-host>"
              # default connect: https://www.postgresql.org/docs/current/libpq-envars.html
              PGDATA: "/var/lib/postgresql/data/pgdata"
              PGUSER: "<your-s00pers3cr3t-user>"
              PGPASSWORD: "<your-s00pers3cr3t-password>"
              PGDATABASE: "postgis"
```