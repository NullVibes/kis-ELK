#!/bin/bash

echo "export ES_HOME=/usr/share/elasticsearch
export ES_PATH_CONFIG=/etc/elasticsearch
export KIBANA_HOME=/usr/share/kibana
export KIBANA_PATH_CONFIG=/etc/kibana" | tee /tmp/exports.sh

chmod +x /tmp/exports.sh
source /tmp/./exports.sh

ES_HOME=/usr/share/elasticsearch
ES_PATH_CONFIG=/etc/elasticsearch
KIBANA_HOME=/usr/share/kibana
KIBANA_PATH_CONFIG=/etc/kibana

EGPG=/usr/share/keyrings/elastic.gpg
if [[ ! -f "$EGPG" ]]; then
  curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
fi

EDEB=/etc/apt/sources.list.d/elastic-8.x.list
if [[ ! -f "EDEB" ]]; then
  echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
fi

sudo apt update && sudo apt upgrade -y
sudo apt install tree unzip -y

#*** Install Kibana ***
sudo apt install kibana -y

A=$(sudo grep -c "127.0.0.1 node1.local kibana.local logstash.local" /etc/hosts)
if  [[ $A -eq 0 || $A == "" ]]
then
  echo '127.0.0.1 node1.local kibana.local logstash.local' | sudo tee -a /etc/hosts
fi

TMPINST=/tmp/instance.yml
if [[ ! -f "$TMPINST" ]]; then
  echo "instances:
  - name: 'node1'
    dns: [ 'node1.local' ]
  - name: 'kibana'
    dns: [ 'kibana.local' ]
  - name: 'logstash'
    dns: [ 'logstash.local' ]
" | tee /tmp/instance.yml
fi

KBAK=/etc/kibana/kibana.yml.bak
if [[ ! -f "$KBAK" ]]; then
  sudo cp /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak
fi

# /etc/kibana/kibana.yml
sudo sed -i 's/.*server.port:.*/server.port: 5601/' /etc/kibana/kibana.yml
sudo sed -i 's/.*server.name:.*/server.name: "Kis-ELK"/' /etc/kibana/kibana.yml
sudo sed -i 's/.*server.ssl.enabled:.*/server.ssl.enabled: true/' /etc/kibana/kibana.yml
sudo sed -i 's/.*server.ssl.certificate:.*/server.ssl.certificate: \/etc\/kibana\/kibana.crt/' /etc/kibana/kibana.yml
sudo sed -i 's/.*server.ssl.key:.*/server.ssl.key: \/etc\/kibana\/kibana.key/' /etc/kibana/kibana.yml
sudo sed -i 's/.*server.host:.*/server.host: "kibana.local"/' /etc/kibana/kibana.yml
sudo sed -i 's/.*elasticsearch.hosts:.*/elasticsearch.hosts: \["http:\/\/localhost:9200"\]/' /etc/kibana/kibana.yml
sudo sed -i 's/.*elasticsearch.username:.*/elasticsearch.username: "kibana"/' /etc/kibana/kibana.yml
sudo sed -i 's/.*elasticsearch.password:.*/elasticsearch.password: "pass"/' /etc/kibana/kibana.yml
sudo sed -i 's/.*elasticsearch.ssl.certificate:.*/elasticsearch.ssl.certificate: /etc/kibana/certs/kibana.crt/' /etc/kibana/kibana.yml
sudo sed -i 's/.*elasticsearch.ssl.key:.*/elasticsearch.ssl.key: /etc/kibana/certs/kibana.key/' /etc/kibana/kibana.yml
sudo sed -i 's/.*elasticsearch.ssl.certificateAuthorities:.*/elasticsearch.ssl.certificateAuthorities: \[ "/etc/kibana/certs/ca.crt" \]/' /etc/kibana/kibana.yml

if [[ ! -d "/usr/share/kibana/config" ]]; then
  # Is this hard-coded?
  sudo mkdir /usr/share/kibana/config
fi

if [[ ! -d "/etc/kibana/certs" ]]; then
  # Is this hard-coded?
  sudo mkdir /etc/kibana/certs
fi

if [[ ! -f "/usr/share/kibana/config/kibana.yml" ]]; then
  sudo ln -s /etc/kibana/kibana.yml /usr/share/kibana/config/kibana.yml
fi

#*** Install Elasticsearch ***
sudo apt install elasticsearch -y | tee ~/elastic.txt
P=$(grep "generated password" ~/elastic.txt 2>/dev/null | awk '{ print $11 }')

EBAK=/etc/elasticsearch/elasticsearch.yml.bak
if [[ ! -f "$EBAK" ]]; then
 sudo cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak
fi

# /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.*cluster.name:.*/cluster.name: kiselk/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.*node.name:.*/node.name: node1/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.*network.host:.*/network.host: 0.0.0.0/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.*http.port:.*/http.port: 9200/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.*xpack.security.enabled:.*/xpack.security.enabled: true/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.*xpack.security.enrollment.enabled:.*/xpack.security.enrollment.enabled: true/' /etc/elasticsearch/elasticsearch.yml

#xpack.security.http.ssl:
#  enabled: true
#  key: certs/node1/node1.key
#  certificate: certs/node1/node1.crt
#  certificate_authorities: certs/ca/ca.crt
#  #keystore.path: certs/http.p12 (comment-out)
sudo sed -i 's/.*xpack.security.http.ssl:/xpack.security.http.ssl:/' /etc/elasticsearch/elasticsearch.yml
B=$(sudo grep -c "node1.crt" /etc/elasticsearch/elasticsearch.yml)
if [[ $B -eq 0 ]]; then
  sudo sed -i '/.*keystore.path: certs\/http.p12/i\  key: certs\/node1\/node1.key\n  certificate: certs\/node1\/node1.crt\n  certificate_authorities: certs\/ca\/ca.crt' /etc/elasticsearch/elasticsearch.yml
fi
sudo sed -i 's/.*keystore.path: certs\/http.p12/# keystore.path:/' /etc/elasticsearch/elasticsearch.yml

#xpack.security.transport.ssl:
#  enabled: true
#  verification_mode: certificate
#  key: certs/node1/node1.key
#  certificate: certs/node1/node1.crt
#  certificate_authorities: certs/ca/ca.crt
#  #keystore.path: certs/transport.p12 (comment-out)
#  #truststore.path: certs/transport.p12 (comment-out)
sudo sed -i 's/#xpack.security.transport.ssl:/xpack.security.transport.ssl:/' /etc/elasticsearch/elasticsearch.yml
C=$(sudo grep -c "node1.crt" /etc/elasticsearch/elasticsearch.yml)
if [[ $C -eq 1 ]]; then
  sudo sed -i '/.*keystore.path: certs\/transport.p12/i\  key: certs\/node1\/node1.key\n  certificate: certs\/node1\/node1.crt\n  certificate_authorities: certs\/ca\/ca.crt' /etc/elasticsearch/elasticsearch.yml
fi
sudo sed -i 's/.*keystore.path: certs\/transport.p12/# keystore.path: certs\/transport.p12/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/.*truststore.path: certs\/transport.p12/# truststore.path: certs\/transport.p12/' /etc/elasticsearch/elasticsearch.yml
#
sudo sed -i 's/.*http.host:.*/http.host: 0.0.0.0/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/cluster.initial_master_nodes:.*/cluster.initial_master_nodes: \["node1"\]/' /etc/elasticsearch/elasticsearch.yml

# Create ES Certificate Authority & Certs for TLS
# Note: By default, elastic-stack-ca.p12 file is created in /usr/share/elasticsearch/
sudo $ES_HOME/bin/elasticsearch-certutil ca --pem --out $ES_PATH_CONFIG/certs/ca.zip --pass password
sudo unzip $ES_PATH_CONFIG/certs/ca.zip -d $ES_PATH_CONFIG/certs/
echo ""
echo "Press any key to continue..."
read -s -n 1

sudo $ES_HOME/bin/elasticsearch-certutil cert --ca-cert /etc/elasticsearch/certs/ca/ca.crt --ca-key /etc/elasticsearch/certs/ca/ca.key --pem --ca-pass password --in /tmp/instance.yml --out /etc/elasticsearch/certs/certs.zip
sudo unzip $ES_PATH_CONFIG/certs/certs.zip -d $ES_PATH_CONFIG/certs/
echo "Press any key to continue..."
read -s -n 1

sudo cp /$ES_PATH_CONFIG/certs/kibana/* /etc/kibana/certs/
sudo cp /$ES_PATH_CONFIG/certs/ca/ca.crt /etc/kibana/certs/

echo "Elasticsearch CONFIG complete."
echo "Press any key to continue..."
read -s -n 1
sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch
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
sudo systemctl start logstash

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

sudo systemctl enable kibana
sudo systemctl start kibana
