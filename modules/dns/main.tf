resource "google_compute_global_address" "lb_ip" {
  name = "lb-ip-${var.env}"
}

resource "google_dns_record_set" "lb_dns" {
  for_each     = var.services
  name         = "${each.value.domain}."
  type         = "A"
  ttl          = 300
  managed_zone = var.dns_managed_zone
  rrdatas      = [google_compute_global_address.lb_ip.address]
}

resource "google_compute_managed_ssl_certificate" "ssl_cert" {
  for_each = var.services

  name = "lb-ssl-${var.env}-${each.key}"

  managed {
    domains = [each.value.domain]
  }
}

resource "google_compute_backend_service" "svc" {
  for_each = {
    for k, v in var.services : k => v if k != "cdn"
  }

  name          = "${each.key}-backend-${var.env}"
  protocol      = "HTTP"
  port_name     = each.value.port_name
  health_checks = [each.value.health_check]

  backend {
    group = each.value.instance_group
  }

  timeout_sec = 10
}

resource "google_compute_url_map" "https_map" {
  name = "https-map-${var.env}"

  dynamic "host_rule" {
    for_each = var.services
    content {
      hosts        = [host_rule.value.domain]
      path_matcher = "${host_rule.key}-matcher"
    }
  }

  dynamic "path_matcher" {
    for_each = var.services
    content {
      name = "${path_matcher.key}-matcher"
      default_service = (
        path_matcher.key == "cdn"
        ? var.cdn_backend_bucket_self_link
        : google_compute_backend_service.svc[path_matcher.key].self_link
      )
    }
  }

  default_service = google_compute_backend_service.svc[var.fallback_service_key].self_link
}

resource "google_compute_target_https_proxy" "https" {
  name    = "https-proxy-${var.env}"
  url_map = google_compute_url_map.https_map.self_link

  ssl_certificates = [
    for cert in google_compute_managed_ssl_certificate.ssl_cert :
    cert.id
  ]
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "https-fw-${var.env}"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.lb_ip.address
  port_range            = "443"
  target                = google_compute_target_https_proxy.https.self_link
}

resource "google_compute_url_map" "redirect_map" {
  count = var.env == "prod" ? 1 : 0
  name = "redirect-map-${var.env}"
  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  count = var.env == "prod" ? 1 : 0
  name    = "redirect-proxy-${var.env}"
  url_map = google_compute_url_map.redirect_map[0].self_link
}

resource "google_compute_global_forwarding_rule" "redirect" {
  count = var.env == "prod" ? 1 : 0
  name                  = "redirect-fw-${var.env}"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.lb_ip.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.redirect[0].self_link
}

resource "google_compute_firewall" "lb_to_instances" {
  name      = "lb-to-instances-${var.env}"
  network   = var.network
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]
  # 각 서비스 모듈이 인스턴스에 붙인 태그(서비스 키)
  target_tags = [for svc in keys(var.services) : svc if svc != "cdn"]
}
