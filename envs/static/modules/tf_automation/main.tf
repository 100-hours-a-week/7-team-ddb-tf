# Pub/Sub 토픽: Scheduler 메시지 큐
resource "google_pubsub_topic" "tf_scheduler_topic" {
  name = "tf-scheduler-topic-${var.env}"
}

# Cloud Scheduler Job: Pub/Sub으로 Terraform 트리거
resource "google_cloud_scheduler_job" "tf_scheduler_jobs" {
  for_each = local.flat_schedules

  name      = "tf-${each.key}"
  schedule  = each.value.schedule
  time_zone = "Asia/Seoul"

  pubsub_target {
    topic_name = google_pubsub_topic.tf_scheduler_topic.id
    attributes = {
      branch       = each.value.branch
      action       = each.value.action
      path         = each.value.branch == "main" ? "prod" : each.value.branch
      dbinstance   = var.envs_parameter[each.value.branch == "main" ? "prod" : each.value.branch].db_instance
      dbname       = var.envs_parameter[each.value.branch == "main" ? "prod" : each.value.branch].db_name
      cloudstorage = var.envs_parameter[each.value.branch == "main" ? "prod" : each.value.branch].cloudstorage
    }
  }
}

# GCS 백업 버킷 생성
resource "google_storage_bucket" "backup_bucket" {
  name          = var.backup_bucket_name
  location      = var.location
  force_destroy = true

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    name        = "${var.env}-backup-bucket"
    environment = var.env
    component   = "backup"
    type        = "gcs"
    managed_by  = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Cloud Build Trigger: Pub/Sub 구독하여 Terraform 실행
resource "google_cloudbuild_trigger" "tf_build_trigger" {
  name        = "tf-${var.env}"
  description = "Terraform automation"

  pubsub_config {
    topic = google_pubsub_topic.tf_scheduler_topic.id
  }
  substitutions = {
    _BRANCH       = "$(body.message.attributes.branch)"
    _ACTION       = "$(body.message.attributes.action)"
    _PATH         = "$(body.message.attributes.path)"
    _DBINSTANCE   = "$(body.message.attributes.dbinstance)"
    _DBNAME       = "$(body.message.attributes.dbname)"
    _CLOUDSTORAGE = "$(body.message.attributes.cloudstorage)"
  }

  service_account = google_service_account.build_sa.id

  build {
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
    # 1) Git clone
    step {
      name       = "gcr.io/cloud-builders/git"
      entrypoint = "bash"
      args = [
        "-c",
        "git clone --branch=$${_BRANCH} --single-branch ${var.repo_url} repo"
      ]
    }
    # Secret 세팅
    step {
      name       = "gcr.io/google.com/cloudsdktool/cloud-sdk:slim"
      entrypoint = "bash"
      args = [
        "-c",
        <<-EOF
          # 클론 전에 워크스페이스 생성
          mkdir -p /workspace/repo/secrets
          # Secret Manager 에서 키 가져오기
          gcloud secrets versions access latest --secret="${var.account_key_name}" \
            --format='get(payload.data)' | tr '_-' '/+' | base64 -d \
            > repo/secrets/account.json
        EOF
      ]
    }
    # Terraform init
    step {
      name       = "hashicorp/terraform:1.11.4"
      entrypoint = "sh"
      args = [
        "-c",
        "cd repo/envs/$${_PATH} && terraform init"
      ]
    }
    # Backup on destroy
    step {
      name       = "google/cloud-sdk:slim"
      entrypoint = "bash"
      args = ["-c",
        <<-EOF
        set -e
        if [ "$${_ACTION}" = "destroy" ]; then
          TS=$$(date +%Y%m%d_%H%M%S)

          # DB Export
          gcloud sql export sql $${_DBINSTANCE} \
            "gs://${google_storage_bucket.backup_bucket.name}/$${_PATH}/db/db_backup_$$TS.sql" \
            --database=$${_DBNAME} --quiet

          # Storage backup
          gsutil -m rsync -r \
            "gs://$${_CLOUDSTORAGE}" \
            "gs://${google_storage_bucket.backup_bucket.name}/$${_PATH}/storage/storage_backup_$$TS/"
        fi
        EOF
      ]
    }

    # Terraform apply/destroy
    step {
      name       = "hashicorp/terraform:1.11.4"
      entrypoint = "sh"
      args = [
        "-c",
        <<-EOF
        set -e
        if [ "$${_ACTION}" = "destroy" ] || [ "$${_ACTION}" = "apply" ]; then
          cd repo/envs/$${_PATH} && terraform $${_ACTION} -auto-approve
        fi
        EOF
      ]
    }

    step {
      name       = "google/cloud-sdk:slim"
      entrypoint = "bash"
      args = ["-c",
        <<-EOF
        set -e
        if [ "$${_ACTION}" = "apply" ]; then
          # Latest DB dump
          LATEST_DB_URI=$$( \
            gsutil ls "gs://${google_storage_bucket.backup_bucket.name}/$${_PATH}/db/db_backup_*.sql" \
              | sort | tail -n1 \
          )
          gcloud sql import sql $${_DBINSTANCE} \
            "$$LATEST_DB_URI" \
            --database=$${_DBNAME} --quiet

          # Latest storage backup
          LATEST_STORAGE_PREFIX=$$( \
            gsutil ls -d "gs://${google_storage_bucket.backup_bucket.name}/$${_PATH}/storage/*/" \
              | sort | tail -n1 \
          )
            gsutil -m rsync -r \
            "$$LATEST_STORAGE_PREFIX" \
            "gs://$${_CLOUDSTORAGE}/"
        fi
        EOF
      ]
    }

    timeout = "1200s"
  }
}

# Scheduler(Pub/Sub 퍼블리셔) Secvice Account
resource "google_service_account" "scheduler_sa" {
  account_id   = "tf-scheduler-publisher"
  display_name = "SA for Cloud Scheduler to Pub/Sub"
}

# Scheduler Secvice Account에 pubsub publisher 권한 
resource "google_pubsub_topic_iam_binding" "allow_scheduler" {
  topic = google_pubsub_topic.tf_scheduler_topic.name
  role  = "roles/pubsub.publisher"
  members = [
    "serviceAccount:${google_service_account.scheduler_sa.email}",
  ]
}
# Cloud Build 실행용 (Terraform Runner)
resource "google_service_account" "build_sa" {
  account_id   = "tf-build-runner"
  display_name = "SA for Terraform in Cloud Build"
}

# Pub/Sub IAM: Build 계정 구독 권한
resource "google_pubsub_topic_iam_binding" "build_sub" {
  topic = google_pubsub_topic.tf_scheduler_topic.name
  role  = "roles/pubsub.subscriber"
  members = [
    "serviceAccount:${google_service_account.build_sa.email}",
  ]
}

# Build 계정에 프로젝트 권한 일괄 부여
resource "google_project_iam_member" "build_sa" {
  for_each = {
    editor          = "roles/editor"
    log_writer      = "roles/logging.logWriter"
    secret_accessor = "roles/secretmanager.admin"
    storage_admin   = "roles/storage.admin"
    cloudsql_admin  = "roles/cloudsql.admin"
  }

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.build_sa.email}"
}
