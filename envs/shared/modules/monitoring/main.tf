# Monitoring 외부 고정 IP
resource "google_compute_address" "monitoring" {
  name = "monitoring-ip-${var.env}"
}

resource "google_service_account" "monitoring" {
  account_id = "monitoring-sa"
}

resource "google_project_iam_member" "monitoring_sa_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.monitoring.email}"
}

resource "google_compute_instance" "monitoring" {
  name         = "mon-instance-${var.env}"
  machine_type = var.machine_type
  zone         = var.zone

  tags = [
    local.mon_tag
  ]

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-jammy-v20250425"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    network_ip = "10.30.10.3"

    access_config {
      nat_ip = google_compute_address.monitoring.address
    }
  }

  service_account {
    email  = google_service_account.monitoring.email
    scopes = ["https://www.googleapis.com/auth/compute.readonly"]
  }

  labels = {
    name        = "mon-instance-${var.env}"
    component   = local.mon_tag
    environment = var.env
    managed_by  = "terraform"
  }

  metadata = {
    ssh-keys = join("\n", local.ssh_key_entries)
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = local.rendered_startup_script
}

// 방화벽
resource "google_compute_firewall" "monitoring_to_target" {
  for_each = var.instance_monitoring

  name      = "${each.key}-to-monitoring-firewall-${var.env}"
  network   = var.network
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = each.value.ports
  }

  source_ranges = each.value.cidrs
  target_tags   = [local.mon_tag]
}

resource "google_compute_firewall" "jenkins_to_monitoring" {
  name      = "jenkins-to-monitoring"
  network   = var.network
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags   = ["jenkins"]
  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.mon_tag]
}

resource "google_compute_firewall" "lb_to_monitoring" {
  name    = "allow-lb-to-monitoring"
  network = var.network

  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = [local.mon_tag]
}

resource "google_compute_instance_group" "monitoring_group" {
  name      = "monitoring-group"
  zone      = var.zone
  instances = [google_compute_instance.monitoring.self_link]

  named_port {
    name = var.service_name
    port = "3000"
  }
}

resource "google_compute_health_check" "health_check" {
  name = "monitoring-health-check"

  http_health_check {
    port         = "3000"
    request_path = "/api/health"
  }
}

resource "google_project_iam_member" "monitoring_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.monitoring.email}"
}
