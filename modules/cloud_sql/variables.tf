variable "env" {
  description = "Deployment environment name"
  type        = string
}

variable "component" {
  description = "같은 환경의 여러 DB를 구분하기 위한 컴포넌트 (i.e., primary)"
  type        = string
}

variable "tier" {
  description = "Cloud SQL instance tier"
  type        = string

  validation {
    condition     = contains(["db-f1-micro", "db-g1-small", "db-standard-1"], var.tier)
    error_message = "tier 값은 유효한 Cloud SQL 인스턴스 타입이어야 합니다."
  }
}

variable "vpc_network_id" {
  description = "Cloud SQL에 private ip로 연결하기 위한 vpc network resource id"
  type        = string
}

variable "resource_type" {
  description = "resource type, 필터링 용도"
  type        = string
}

variable "deletion_protection" {
  description = "Cloud SQL instance 삭제 방지 설정 여부"
  type        = bool
  default     = false
}

variable "db_user" {
  description = "Cloud SQL 사용자 이름"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "생성할 database 이름"
  type        = string
}

variable "backup_bucket_name" {
  description = "백업할 bucket 이름"
  type = string
}

variable "nat_ip_address" {
  description = "nat의 ip 주소"
  type = string
}

variable "project_id" {
  description = "프로젝트 id"
  type = string
}

variable "shared_nat_ip_address" {
  description = "공유 vpc 의 nat ip 주소"
  type = string
}