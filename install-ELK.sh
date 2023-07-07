#!/bin/bash

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update && sudo apt upgrade -y
sudo apt install tree apt-transport-https -y

#*** Install Kibana ***
sudo apt install kibana -y
# /etc/kibana/kibana.yml
sudo sed -i 's/#server.port: 5601/server.port: 5601/' /etc/kibana/kibana.yml
sudo sed -i 's/#server.host: 192.168.0.1/server.host: 0.0.0.0/' /etc/kibana/kibana.yml
sudo sed -i 's/#elasticsearch.hosts: ["http://localhost:9200"]/elasticsearch.hosts: ["http://localhost:9200"]/' /etc/kibana/kibana.yml &>/dev/null

#*** Install Elasticsearch ***
E=$(grep -c "generated password" ~/elastic.txt 2>/dev/null)
if  [[ $E -eq 0 || $E == "" ]]
then
  sudo apt install elasticsearch -y | tee ~/elastic.txt
  P=$(grep "generated password" ~/elastic.txt 2>/dev/null | awk '{ print $11 }')
else
  P=$(grep "generated password" ~/elastic.txt 2>/dev/null | awk '{ print $11 }')
fi

echo "Elasticsearch installation complete."
echo "Press any key to continue..."
read -s -n 1


# /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/#network.host: 192.168.0.1/network.host: 0.0.0.0/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/#http.port: 9200/http.port: 9200/' /etc/elasticsearch/elasticsearch.yml

# elastic-stack-ca.p12 file is created in /usr/share/elasticsearch/
sudo /usr/share/elasticsearch/bin/elasticsearch-certutil ca --out elastic-stack-ca.p12 --pass $P
sudo /usr/share/elasticsearch/bin/elasticsearch-certutil cert --ca elastic-stack-ca.p12 --ca-pass $P --name elastic-certificates --pass "" --out elastic-certificates.p12
sudo cp /usr/share/elasticsearch/elastic-certificates.p12 /etc/elasticsearch/certs/

sudo sed -i 's/#cluster.name: my-application/cluster.name: kiselk/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/#node.name:/node.name:/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/keystore.path: certs\/transport.p12/keystore.path: elastic-certificates.p12/' /etc/elasticsearch/elasticsearch.yml
sudo sed -i 's/truststore.path: certs\/transport.p12/truststore.path: elastic-certificates.p12/' /etc/elasticsearch/elasticsearch.yml

sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch

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

echo ""
echo "Press any key to continue..."
read -s -n 1

sudo apt install filebeat -y
# /etc/filebeat/filebeat.yml
sudo sed -i 's/#output.logstash:/output.logstash:/' /etc/filebeat/filebeat.yml
sudo sed -i 's/#hosts: \["localhost:5044"\]/hosts: \["localhost:5044"\]/' /etc/filebeat/filebeat.yml
sudo sed -i 's/output.elasticsearch:/#output.elasticsearch:/' /etc/filebeat/filebeat.yml
sudo sed -i 's/hosts: \["localhost:9200"\]/#hosts: \["localhost:9200"\]/' /etc/filebeat/filebeat.yml
sudo filebeat modules enable system
sudo filebeat setup --pipelines --modules system
sudo filebeat setup --index-management -E output.logstash.enabled=false -E 'output.elasticsearch.hosts=["localhost:9200"]'
sudo filebeat setup -E output.logstash.enabled=false -E 'output.elasticsearch.hosts=["localhost:9200"]' -E setup.kibana.host=localhost:5601
sudo filebeat modules enable system
sudo systemctl enable filebeat
