variable "region" {
  default = "eu-west-2"
}
variable "repo_name" {}
variable "environment" {}
variable "cluster_name" {}
variable "mhs_state_table_read_capacity" {}
variable "mhs_state_table_write_capacity" {}
variable "mhs_sync_async_table_read_capacity" {}
variable "mhs_sync_async_table_write_capacity" {}

variable "nlb_private_ips" { }

variable "setup_public_dns_record" {
  description = "Should be true for PTL-* environments, and false for OpenTest"
}

variable "recipient_ods_code" {
  description = "ODS code that was used for the MHS (CMA endpoint) registration"
}

variable "inbound_queue_name" {
  default = "inbound"
}

variable "inbound_raw_queue_name" {
  default = "raw-inbound"
}

variable "mhs_inbound_service_minimum_instance_count" {
  description = "The minimum number of instances of MHS inbound to run. This will be the number of instances deployed initially."
}

variable "elasticache_node_type" {
  description = "The type of ElastiCache node to use when deploying the ElastiCache cluster. Possible node types can be found from https://aws.amazon.com/elasticache/features/#Available_Cache_Node_Types"
}

variable "spineroutelookup_service_sds_url" {
  description = "The SDS URL the Spine Route Lookup service should communicate with."
}

variable "spineroutelookup_service_search_base" {
  description = "The LDAP location the Spine Route Lookup service should use as the base of its searches when querying SDS."
}

variable "spineroutelookup_service_disable_sds_tls" {
  description = "Whether TLS should be disabled for connections to SDS."
  default = "False"
}

variable "mhs_log_level" {}

variable "mhs_route_service_minimum_instance_count" {
  description = "The minimum number of instances of MHS route service to run. This will be the number of instances deployed initially."
}

variable "mhs_route_service_maximum_instance_count" {
  description = "The maximum number of instances of MHS route service to run."
}

variable "route_ca_certs_arn" {
  description = "ARN of the secrets manager secret containing the CA certificates to be used to verify the certificate presented by the Spine Route Lookup service. Required if you are using certificates that are not signed by a legitimate CA."
  default = ""
}

variable "mhs_outbound_service_minimum_instance_count" {
  description = "The minimum number of instances of MHS outbound to run. This will be the number of instances deployed initially."
}

variable "mhs_outbound_service_maximum_instance_count" {
  description = "The maximum number of instances of MHS outbound to run."
}

variable "mhs_outbound_http_proxy" {
  description = "Address of the HTTP proxy to proxy downstream requests from MHS outbound via."
  default = ""
}

variable "mhs_resync_initial_delay" {
  description = "The delay before the first poll to the sync async store after receiving an acknowledgement from Spine"
  default = 0.150
}

variable "mhs_resynchroniser_max_retries" {
  description = "The number of retry attempts to the sync-async state store that should be made whilst attempting to resynchronise a sync-async message"
}

variable "mhs_resynchroniser_interval" {
  description = "Time between calls to the sync-async store during resynchronisation"
}

variable "mhs_forward_reliable_endpoint_url" {
  description = "The URL to communicate with Spine for Forward Reliable messaging from the outbound service"
}

variable "mhs_spine_request_max_size" {
  description = "The maximum size of the request body (in bytes) that MHS outbound sends to Spine. This should be set minus any HTTP headers and other content in the HTTP packets sent to Spine."
  default = 4999600 # This is 5 000 000 - 400 ie 5MB - 400 bytes, roughly the size of the rest of the HTTP packet
}

variable "build_id" {
  description = "ID used to identify the current build such as a commit sha."
}

variable "fork_build_id" {}

variable "deregistration_delay" {
  default = 30
}

variable "allowed_mhs_clients" {
  default = "10.0.0.0/8"
  description = "Network from which MHS ALBs should allow connections"
}

variable "spine_cidr" {
  description = "Network where spine services are located"
}

variable "cluster_domain_name" {}
variable "cluster_suffix" {}

variable "sds_port" {}
