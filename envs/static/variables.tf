variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-northeast3"
}

variable "credentials_file" {
  type        = string
  description = "Path to the GCP credentials JSON file"
  default     = "../../secrets/account.json"
}

variable "project_id" {
  type        = string
  description = "GCP Project ID"
  default     = "velvety-calling-458402-c1"
}

variable "env" {
  type        = string
  description = "환경 이름"
  default     = "static"
}

variable "tf_automation_schedules" {
  type = map(list(object({
    branch   = string
    schedule = string
  })))
  description = "테라폼 자동화 스케줄"
  default = {
    apply = [
      # main 브랜치: 평일 오전 9시 30분 시작
      { branch = "main", schedule = "30 9 * * 1-5" },

      # dev 브랜치: 일~목 오후 12시 30분 시작
      { branch = "dev", schedule = "30 12 * * 0-4" },

      # dev 브랜치: 금요일 오전 8시 30분 시작
      { branch = "dev", schedule = "30 8 * * 5" },

      # dev 브랜치: 토요일 오후 12시 30분 시작
      { branch = "dev", schedule = "30 12 * * 6" }
    ]
    destroy = [
      # main 브랜치: 평일(월~금) 오후 8시에 종료
      # { branch = "main", schedule = "0 20 * * 1-5" },

      # # dev 브랜치: 일~목 오후 11시에 종료
      # { branch = "dev", schedule = "22 00 * * 0-4" },

      # # dev 브랜치: 금요일 오후 11시에 종료
      # { branch = "dev", schedule = "0 23 * * 5" },

      # # dev 브랜치: 일요일 새벽 4시에 종료 (토 → 일로 넘어간 시점)
      # { branch = "dev", schedule = "0 4 * * 0" }
    ]
  }
}


variable "bucket_location" {
  type        = string
  description = "버킷 지역 위치"
  default     = "Asia"
}

variable "repo_url" {
  type        = string
  description = "테라폼 repository url"
  default     = "https://github.com/100-hours-a-week/7-team-ddb-tf.git"
}

variable "account_key_name" {
  type        = string
  description = "권한이 있는 account.json secret key 이름"
  default     = "terraform-sa-key"
}
