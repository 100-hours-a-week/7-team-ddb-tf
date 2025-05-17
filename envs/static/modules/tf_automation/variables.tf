variable "env" {
  description = "배포 환경 (static)"
  type        = string
}

variable "location" {
  description = "리소스를 생성할 GCP 지역 또는 영역"
  type        = string
}

variable "schedules" {
  description = "스케줄 목록: key: action, value: branch, cron schedule"
  type = map(list(object({
    branch   = string
    schedule = string
  })))
}

variable "envs_parameter" {
  description = "환경별 필요 파라미터"
  type = map(object({
    db_name     = string
    db_instance = string
    cloudstorage = string
  }))

}

variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "repo_url" {
  description = "Terraform 코드가 위치한 Git 저장소 URL"
  type        = string
}

variable "account_key_name" {
  description = "Secret Manager에 저장된 서비스 계정 키 비밀 이름"
  type        = string
}


variable "backup_bucket_name" {
  description = "백업에 사용할 버킷 이름"
  type = string
}