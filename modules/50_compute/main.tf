# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

locals {
  tags = concat(list("multinic-router"), var.tags)
}

module "startup-script-lib" {
  source = "git::https://github.com/terraform-google-modules/terraform-google-startup-scripts.git?ref=v1.0.0"
}

data "template_file" "startup-script-config" {
  template = "${file("${path.module}/templates/startup-script-config.tpl")}"
  vars = {
    nic0_cidrs = join(",", var.nic0_cidrs)
    nic1_cidrs = join(",", var.nic1_cidrs)
  }
}

// Google Service Account to attach to multinic VM instances.
resource "google_service_account" "multinic" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-sa"
  display_name = "multinic vm router"
  description  = "Multinic VM Router"
}

// Allow multinic instances to write log entries
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  member  = "serviceAccount:${google_service_account.multinic.email}"
  role    = "roles/logging.logWriter"
}

resource google_compute_instance_template "multinic" {
  project        = var.project_id
  name_prefix    = var.name_prefix
  machine_type   = var.machine_type
  region         = var.region
  can_ip_forward = true

  tags = local.tags

  network_interface {
    subnetwork         = var.nic0_subnet
    subnetwork_project = var.nic0_project
  }

  network_interface {
    subnetwork         = var.nic1_subnet
    subnetwork_project = var.nic1_project
  }

  disk {
    auto_delete  = true
    boot         = true
    source_image = var.os_image
    type         = "PERSISTENT"
    disk_size_gb = var.disk_size_gb
  }

  metadata = {
    startup-script        = module.startup-script-lib.content
    startup-script-config = data.template_file.startup-script-config.rendered
    # Configure  Linux Policy Routing
    startup-script-custom = file("${path.module}/files/startup-multinic.sh")
    # Deletes the route resources
    shutdown-script       = file("${path.module}/files/shutdown-multinic.sh")
  }

  scheduling {
    preemptible       = var.preemptible
    automatic_restart = var.preemptible ? false : true
  }

  lifecycle {
    create_before_destroy = true
  }

  service_account {
    email  = google_service_account.multinic.email
    scopes = ["cloud-platform"]
  }
}


# The "health" health check is used for auto-healing with the MIG.  The
# timeouts are longer to reduce the risk of removing an otherwise healthy
# instance.
resource google_compute_health_check "multinic-health" {
  project = var.project_id
  name    = "${var.name_prefix}-${var.zone}-hc"

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 9000
    request_path = "/status.json"
  }
}

resource "google_compute_instance_group_manager" "multinic" {
  project  = var.project_id
  name     = "${var.name_prefix}-${var.zone}"

  base_instance_name = var.name_prefix

  zone = var.zone

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_percent     = 20
    max_unavailable_fixed = 1
    min_ready_sec         = 120
  }

  target_size = var.num_instances

  named_port {
    name = "hc-health"
    port = "9000"
  }

  named_port {
    name = "hc-traffic"
    port = "9001"
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.multinic-health.self_link
    initial_delay_sec = var.hc_initial_delay_secs
  }

  version {
    name              = var.name_prefix
    instance_template = google_compute_instance_template.multinic.self_link
  }
}
