# Copyright 2020 Open Infrastructure Services, LLC
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

variable "num_instances" {
  description = "Set to 0 to reduce costs when not actively developing."
  type        = number
  default     = 0
}

# Number of instances in zone b
variable "num_instances_b" {
  description = "Set to 0 to reduce costs when not actively developing."
  type        = number
  default     = 0
}

locals {
  project_id = "multinic-networks-18d1"
  region     = "us-west1"
  zone_a     = "us-west1-a"
  zone_b     = "us-west1-b"

  # shared vpc netblock
  shared_vpc_netblock = "10.32.0.0/14"
  # transit vpc netblock
  transit_netblock = "10.36.0.0/14"

  shared_vpc_network = "main"
  shared_vpc_subnet  = "main-bridge"
  transit_network = "transit"
  transit_subnet  = "transit-bridge"
}

# Manage the regional MIG formation
module "multinic-a" {
  source = "../../modules/50_compute"

  num_instances = var.num_instances

  project_id  = local.project_id
  name_prefix = "multinic-a"
  region      = local.region
  zone        = local.zone_a

  nic0_network = local.shared_vpc_network
  nic0_project = local.project_id
  nic0_subnet  = local.shared_vpc_subnet
  nic0_cidrs   = [local.shared_vpc_netblock]

  nic1_network = local.transit_network
  nic1_project = local.project_id
  nic1_subnet  = local.transit_subnet
  nic1_cidrs   = [local.transit_netblock]
}

module "multinic-b" {
  source = "../../modules/50_compute"

  num_instances = var.num_instances_b

  project_id  = local.project_id
  name_prefix = "multinic-b"
  region      = local.region
  zone        = local.zone_b

  nic0_network = local.shared_vpc_network
  nic0_project = local.project_id
  nic0_subnet  = local.shared_vpc_subnet
  nic0_cidrs   = [local.shared_vpc_netblock]

  nic1_network = local.transit_network
  nic1_project = local.project_id
  nic1_subnet  = local.transit_subnet
  nic1_cidrs   = [local.transit_netblock]
}

# The "traffic" health check is used by the load balancer.  The instance will
# be taken out of service if the health check fails and other instances have
# passing traffic checks.  This check is more agressive so that the a
# preemptible instance is able to take itself out of rotation within the 30
# second window provided for shutdown.
resource google_compute_health_check "multinic-traffic" {
  project = local.project_id
  name    = "multinic-traffic"

  check_interval_sec  = 3
  timeout_sec         = 2
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 9001
    request_path = "/status.json"
  }
}

resource "google_compute_region_backend_service" "multinic-main" {
  provider = google-beta
  project  = local.project_id

  name                  = "multinic-main"
  network               = local.shared_vpc_network
  region                = local.region
  load_balancing_scheme = "INTERNAL"

  backend {
    group = module.multinic-a.instance_group
  }

  backend {
    group = module.multinic-b.instance_group
  }

  # Note this is the traffic health check, not the auto-healing check
  health_checks = [google_compute_health_check.multinic-traffic.id]
}

resource "google_compute_region_backend_service" "multinic-transit" {
  provider = google-beta
  project  = local.project_id

  name                  = "multinic-transit"
  network               = local.transit_network
  region                = local.region
  load_balancing_scheme = "INTERNAL"

  backend {
    group = module.multinic-a.instance_group
  }

  backend {
    group = module.multinic-b.instance_group
  }

  # Note this is the traffic health check, not the auto-healing check
  health_checks = [google_compute_health_check.multinic-traffic.id]
}

# Reserve an address so we have a well known address to configure for policy routing.
resource "google_compute_address" "main" {
  name         = "main-fwd"
  project      = local.project_id
  region       = local.region
  subnetwork   = local.shared_vpc_subnet
  address_type = "INTERNAL"
}

resource "google_compute_address" "transit" {
  name         = "transit-fwd"
  project      = local.project_id
  region       = local.region
  subnetwork   = local.transit_subnet
  address_type = "INTERNAL"
}

resource google_compute_forwarding_rule "main" {
  name    = "multinic-main"
  project = local.project_id
  region  = local.region

  ip_address      = google_compute_address.main.address
  backend_service = google_compute_region_backend_service.multinic-main.id
  network         = local.shared_vpc_network
  subnetwork      = local.shared_vpc_subnet

  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true
}

resource google_compute_forwarding_rule "transit" {
  name    = "multinic-transit"
  project = local.project_id
  region  = local.region

  ip_address      = google_compute_address.transit.address
  backend_service = google_compute_region_backend_service.multinic-transit.id
  network         = local.transit_network
  subnetwork      = local.transit_subnet

  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true
}

// Route resources
resource google_compute_route "main" {
  name         = "main"
  project      = local.project_id
  network      = local.shared_vpc_network
  dest_range   = local.transit_netblock
  priority     = 900
  next_hop_ilb = google_compute_forwarding_rule.main.self_link
}

resource google_compute_route "transit" {
  name         = "transit"
  project      = local.project_id
  network      = local.transit_network
  dest_range   = local.shared_vpc_netblock
  priority     = 900
  next_hop_ilb = google_compute_forwarding_rule.transit.self_link
}
