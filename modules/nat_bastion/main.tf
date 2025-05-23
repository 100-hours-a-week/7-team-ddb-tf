# Nat_Bastion instance가 사용할 ip address
resource "google_compute_address" "nat_bastion" {
  name = "nat-bastion-ip-${var.env}"
}

# nat_bastion instance가 사용할 ssh key 생성 및 secret manager에 저장
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

data "tls_public_key" "bastion" {
  private_key_pem = tls_private_key.bastion.private_key_pem
}

resource "google_secret_manager_secret" "bastion_ssh_key" {
  secret_id = "bastion-ssh-key-${var.env}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "bastion_ssh_key_version" {
  secret      = google_secret_manager_secret.bastion_ssh_key.id
  secret_data = tls_private_key.bastion.private_key_pem
}

locals {
  ssh_key_entries = [
    for u in var.ssh_users :
    "${u}:${data.tls_public_key.bastion.public_key_openssh}"
  ]
  bastion_tag = "nat-bastion"
}

// NAT/Bastion instance 생성
resource "google_compute_instance" "nat_bastion" {
  name         = "nat-bastion-${var.env}"
  machine_type = var.machine_type
  zone         = var.zone

  can_ip_forward = true

  tags = [
    local.bastion_tag,
    var.public_route_tag
  ]

  labels = {
    name        = "natbastion-isntance-${var.env}"
    component   = "natbastion"
    environment = var.env
    managed_by  = "terraform"
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-jammy-v20250425"
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork


    access_config {
      nat_ip = google_compute_address.nat_bastion.address
    }
  }

  metadata = {
    ssh-keys = join("\n", local.ssh_key_entries)
  }
  metadata_startup_script = file("${path.module}/scripts/startup.sh")
}

// nat_bastion instance의 방화벽
resource "google_compute_firewall" "bastion_ssh" {
  name      = "bastion-ssh-${var.env}"
  network   = var.network
  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = [local.bastion_tag]
}

resource "google_compute_firewall" "nat_ingress_from_private" {
  name      = "nat-allow-from-private-${var.env}"
  network   = var.network
  direction = "INGRESS"

  source_tags = ["private"]         # private 인스턴스가 보낸 트래픽만
  target_tags = [local.bastion_tag] # 이 태그가 붙은 인스턴스만

  allow {
    protocol = "icmp"
  } # ping
  allow {
    protocol = "udp"
    ports    = ["53"]
  } # DNS
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  } # HTTP/HTTPS
}

resource "google_compute_route" "private_route" {
  name              = "private-route-${var.env}"
  network           = var.network
  dest_range        = "0.0.0.0/0"
  next_hop_instance = google_compute_instance.nat_bastion.self_link
  priority          = 1000
  tags              = [var.private_route_tag]
}