locals {
  mon_tag            = "mon"
  prometheus_content = file("${path.module}/files/prometheus.yml")
  loki_content       = file("${path.module}/files/loki.yml")
  thanosgcs_content  = file("${path.module}/files/thanos-gcs.yml")
  endpoints_content  = file("${path.module}/files/endpoints.yml")

  dockercompose_content = templatefile("${path.module}/files/docker-compose.yml", {
    DEV_DB_PW  = data.google_secret_manager_secret_version.dev_db_password.secret_data
  })

  rendered_startup_script = templatefile("${path.module}/scripts/startup.sh", {
    name                  = "monitoring"
    dockercompose_content = local.dockercompose_content
    prometheus_content    = local.prometheus_content
    loki_content          = local.loki_content
    thanosgcs_content     = local.thanosgcs_content
    endpoints_content     = local.endpoints_content
  })

  ssh_key_entries = [
    for user in var.ssh_users :
    "${user}:${var.public_key}"
  ]
}
