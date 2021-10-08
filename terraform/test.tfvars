environment = "test"
cluster_name = "repo"
repo_name = "prm-mhs-infra"
mhs_state_table_read_capacity = 5
mhs_state_table_write_capacity = 5
mhs_sync_async_table_read_capacity = 5
mhs_sync_async_table_write_capacity = 5
mhs_inbound_service_minimum_instance_count = 1
recipient_ods_code                  = "B86041"

spine_cidr = "0.0.0.0/0" # FIXME: narrow down to only the services that we talk to
mhs_forward_reliable_endpoint_url  = "https://msg.intspineservices.nhs.uk/reliablemessaging/reliablerequest"
mhs_asynchronous_reliable_endpoint_url  = "https://msg.intspineservices.nhs.uk/reliablemessaging/reliablerequest"
mhs_synchronous_endpoint_url = "https://msg.intspineservices.nhs.uk/sync-service"
mhs_log_level                       = "DEBUG"
mhs_outbound_service_maximum_instance_count = 2
mhs_outbound_service_minimum_instance_count = 1
mhs_resynchroniser_max_retries="20"
mhs_resynchroniser_interval="1"
spine_org_code="YES"
mhs_vpc_cidr_block = "10.239.68.128/25"
mhs_outbound_lookup_method = "SDS_API"
allow_vpn_to_mhs_outbound_lb = true


