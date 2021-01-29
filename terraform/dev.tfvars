environment = "dev"
cluster_name = "repo"
mhs_state_table_read_capacity = 5
mhs_state_table_write_capacity = 5
repo_name = "prm-mhs-infra"
mhs_sync_async_table_read_capacity = 5
mhs_sync_async_table_write_capacity = 5
elasticache_node_type               = "cache.t3.micro"

mhs_inbound_service_minimum_instance_count = 1
recipient_ods_code                  = "opentest" # Not enforced in opentest

spineroutelookup_service_sds_url    = "ldap://192.168.128.11:389" # MUST BE AN IP in dev environment
mhs_forward_reliable_endpoint_url  = "https://192.168.128.11/reliablemessaging/forwardreliable"
spineroutelookup_service_search_base = "ou=services,o=nhs"
spineroutelookup_service_disable_sds_tls = "True"
mhs_log_level                       = "DEBUG"
mhs_route_service_maximum_instance_count = 2
mhs_route_service_minimum_instance_count = 1
mhs_outbound_service_maximum_instance_count = 2
mhs_outbound_service_minimum_instance_count = 1
mhs_resynchroniser_max_retries="20"
mhs_resynchroniser_interval="1"

