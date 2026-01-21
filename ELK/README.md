# Installation and use

Run the latest version of the Elastic stack with Docker and Docker Compose.


1. Install [Docker, "Docker compose"]

It gives you the ability to analyze any data set by using the searching/aggregation capabilities of Elasticsearch and the visualization power of Kibana.

Based on the official Docker images from Elastic:

Elasticsearch
Logstash
Kibana

Tasks:
    1. Create automation with github actions which will deploy the infra with docker-compose container
    2. Create Docker compose file which will deploy Elasticsearch + logstash + kibana and configure all 3
    3. Collect logs from syslog and auth.log

## Structure

- docker-compose.yml    # For running 3 services (elasticserch, kibanna, logstresh)
- elasticsearch/        # Directory for all config container elasticsearch
- kibana/               # Directory for all config container kibana
- logstash/pipeline/    # Directory for all config container logstash
- docs/                 # Directory for 3 services documentations (elasticserch, kibanna, logstresh)
