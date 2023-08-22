region             = "us-west-2"
env                = "west2-staging"
project_name       = "wfs3labs"
availability_zones = ["us-west-2a", "us-west-2b"]
dns_zone_name      = "wfs3labs.com"
alb_protocol       = "HTTPS"
tags               = {"project": "wfs3labs", "service": "wfs3labs"}
dns_records        = [{ "dns_subdomain":"vector1", "ttl":300 }, { "dns_subdomain":"vector2", "ttl":300}]
