#!/bin/bash

declare -x ES_HOME="/usr/share/elasticsearch"
declare -x ES_PATH_CONF="/etc/elasticsearch"
declare -x KIBANA_HOME="/usr/share/kibana"
declare -x KIBANA_PATH_CONFIG="/etc/kibana"

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update && sudo apt upgrade -y
sudo apt install vim curl git tree unzip -y

#*** Install Kibana ***
sudo apt install kibana -y

A=$(grep -c "127.0.0.1 node1.local kibana.local logstash.local" /etc/hosts 2>/dev/null)
if  [[ $A -eq 0 || $A == "" ]]
then
  echo '127.0.0.1 node1.local kibana.local logstash.local' | sudo tee -a /etc/hosts
fi

echo "instances:
  - name: 'node1'
    dns: [ 'node1.local' ]
  - name: 'kibana'
    dns: [ 'kibana.local' ]
  - name: 'logstash'
    dns: [ 'logstash.local' ]
" | tee /tmp/instance.yml

sudo cp /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak

# /etc/kibana/kibana.yml
sudo sed -i 's/#server.name:.*/server.name: "Kis-ELK"/' /etc/kibana/kibana.yml
sudo sed -i 's/#server.ssl.enabled:.*/server.ssl.enabled: true/' /etc/kibana/kibana.yml
sudo sed -i 's/#server.ssl.certificate:.*/server.ssl.certificate: \/etc\/kibana\/kibana.crt/' /etc/kibana/kibana.yml
sudo sed -i 's/#server.ssl.key:.*/server.ssl.key: \/etc\/kibana\/kibana.key/' /etc/kibana/kibana.yml
sudo sed -i 's/#server.port:.*/server.port: 5601/' /etc/kibana/kibana.yml
sudo sed -i 's/#server.host:.*/server.host: "kibana.local"/' /etc/kibana/kibana.yml
sudo sed -i 's/#elasticsearch.hosts:.*/elasticsearch.hosts: ["http://localhost:9200"]/' /etc/kibana/kibana.yml &>/dev/null

#*** Install Elasticsearch ***
sudo apt install elasticsearch -y | tee ~/elastic.txt
P=$(grep "generated password" ~/elastic.txt 2>/dev/null | awk '{ print $11 }')

sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak

# /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.cluster.name:.*/cluster.name: kiselk/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.node.name:.*/node.name: node1/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.network.host:.*/network.host: 0.0.0.0/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.http.port:/http.port: 9200/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.xpack.security.enabled:.*/xpack.security.enabled: true' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.xpack.security.enrollment.enabled:.*/xpack.security.enrollment.enabled: true' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.xpack.security.http.ssl:/xpack.security.http.ssl:/' /etc/elasticsearch/elasticsearch.yml
#xpack.security.http.ssl:
#  enabled: true
#  key: certs/node1/node1.key
#  certificate: certs/node1/node1.crt
#  certificate_authorities: certs/ca/ca.crt
#  #keystore.path: certs/http.p12 (comment-out)

#xpack.security.transport.ssl:
#  enabled: true
#  verification_mode: certificate
#  key: certs/node1/node1.key
#  certificate: certs/node1/node1.crt
#  certificate_authorities: certs/ca/ca.crt
#  #keystore.path: certs/transport.p12 (comment-out)
#  #truststore.path: certs/transport.p12 (comment-out)
sudo sed -i 's/.http.host:.*/http.host: 0.0.0.0/' /etc/elasticsearch/elasticsearch.yml
#sudo sed -i 's/  keystore.path: certs\/http.p12/#  keystore.path:/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/  truststore.path:.*/#  truststore.path:/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.cluster.initial_master_nodes:/cluster.initial_master_nodes: ["node1"]/' /etc/elasticsearch/elasticsearch.yml

# Create ES Certificate Authority & Certs for TLS
# Note: By default, elastic-stack-ca.p12 file is created in /usr/share/elasticsearch/
sudo $ES_HOME/bin/elasticsearch-certutil ca --pem --out $ES_PATH_CONF/certs/ca.zip --pass password
sudo $ES_HOME/bin/elasticsearch-certutil cert --keep-ca-key --pem --ca-pass password --in /tmp/instance.yml --out $ES_PATH_CONF/certs.zip
cd $ES_PATH_CONF/certs
sudo unzip ca.zip
sudo unzip certs.zip

echo "Elasticsearch CONFIG complete."
echo "Press any key to continue..."
read -s -n 1
sudo systemctl daemon-reload
#sudo systemctl enable elasticsearch
#sudo systemctl start elasticsearch
echo "Press any key to continue..."
read -s -n 1

# Elasticsearch Install Test
curl -v -u elastic:$P -X GET "https://localhost:9200"
echo ""
echo "Press any key to continue..."
read -s -n 1

sudo apt install logstash -y
# /etc/logstash/conf.d/30-elasticsearch-output.conf
echo 'input {
  beats {
    port => 5044
    }
  }' | sudo tee /etc/logstash/conf.d/02-beats-input.conf &>/dev/null

echo 'output {
  if [@metadata][pipeline] {
    elasticsearch {
      hosts => ["localhost:9200"]
      manage_template => false
      index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY-MM-dd}"
      pipeline => "%{[@metadata][pipeline]}"
    }
  } else {
    elasticsearch {
      hosts => ["localhost:9200"]
      manage_template => false
      index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY-MM-dd}"
      }
    }
  }' | sudo tee /etc/logstash/conf.d/30-elasticsearch-output.yml &>/dev/null

sudo -u logstash /usr/share/logstash/bin/./logstash --path.settings /etc/logstash -t
sudo systemctl enable logstash
#sudo systemctl start logstash


sudo apt install filebeat -y
sudo cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak
# /etc/filebeat/filebeat.yml
sudo sed -i 's/#output.logstash:/output.logstash:/' /etc/filebeat/filebeat.yml
sudo sed -i 's/#hosts: ["localhost:5044"]/hosts: ["localhost:5044"]/' /etc/filebeat/filebeat.yml
sudo sed -i 's/output.elasticsearch:/#output.elasticsearch:/' /etc/filebeat/filebeat.yml
sudo sed -i 's/hosts: ["localhost:9200"]/#hosts: ["localhost:9200"]/' /etc/filebeat/filebeat.yml
sudo filebeat modules enable system
sudo filebeat setup --pipelines --modules system
sudo filebeat setup --index-management -E output.logstash.enabled=false -E 'output.elasticsearch.hosts=["localhost:9200"]'
sudo filebeat setup -E output.logstash.enabled=false -E 'output.elasticsearch.hosts=["localhost:9200"]' -E setup.kibana.host=localhost:5601
sudo filebeat modules enable system
sudo systemctl enable filebeat
