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

variable "name_prefix" {
  description = "The name prefix to us for managed resources, for example 'multinic'"
  type        = string
}

variable "project_id" {
  description = "The project ID containing the managed resources"
  type        = string
}

variable "region" {
  description = "The region containing the managed resources"
  type        = string
}

variable "zone" {
  description = "The zone containing the managed resources"
  type        = string
}

variable "os_image" {
  description = "The os_image used with the MIG instance template"
  type        = string
  default     = "centos-cloud/centos-8"
}

variable "nic0_network" {
  description = "The VPC network nic0 is attached to."
  type        = string
}

variable "nic0_subnet" {
  description = "The name of the subnet the nic0 interface of multinic instance will use.  Do not specify as a fully qualified name."
  type        = string
}

variable "nic0_project" {
  description = "The project id which hosts the shared vpc network."
  type        = string
}

variable "nic0_cidrs" {
  description = "A list of subnets in cidr notation, traffic destined for these subnets will route out nic0.  Used to configure routes. (e.g. 10.16.0.0/20)"
  type        = list(string)
  default     = []
}

variable "nic1_network" {
  description = "The VPC network nic1 is attached to."
  type        = string
}

variable "nic1_subnet" {
  description = "The name of the subnet the nic1 interface of multinic instance will use.  Do not specify as a fully qualified name."
  type        = string
}

variable "nic1_project" {
  description = "The project id which hosts the shared vpc network."
  type        = string
}

variable "nic1_cidrs" {
  description = "A list of subnets in cidr notation, traffic destined for these subnets will route out nic1.  Used to configure routes. (e.g. 10.16.0.0/20)"
  type        = list(string)
  default     = []
}

variable "machine_type" {
  description = "The machine type of each IP Router Bridge instance"
  type        = string
  default     = "n1-standard-1"
}

variable "num_instances" {
  description = "The number of instances in the instance group"
  type        = number
  default     = 3
}

variable "hc_initial_delay_secs" {
  description = "The number of seconds that the managed instance group waits before it applies autohealing policies to new instances or recently recreated instances."
  type        = number
  default     = 60
}

variable "route_priority" {
  description = "The route priority MIG instances use when creating their Route resources.  Lower numbers take precedence."
  type        = number
  default     = 900
}

variable "tags" {
  description = "Additional network tags added to instances.  Useful for opening VPC firewall access.  TCP Port 80 must be allowed into nic0 for health checking to work."
  type        = list(string)
  default     = ["allow-health-check"]
}

variable "disk_size_gb" {
  description = "The size in GB of the persistent disk attached to each multinic instance."
  type        = string
  default     = "100"
}

variable "preemptible" {
  description = "Allows instance to be preempted. This defaults to false. See https://cloud.google.com/compute/docs/instances/preemptible"
  type        = bool
  default     = false
}
