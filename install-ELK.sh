curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor /user/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update && sudo apt upgrade -y
sudo apt install elasticsearch -y

# /etc/elasticsearch/elasticsearch.yml
sudo mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak
echo "path.data: /var/lib/elasticsearch" | sudo tee -a /etc/elasticsearch/elasticsearch.yml &>/dev/null
echo "path.logs: /var/log/elasticsearch" | sudo tee -a /etc/elasticsearch/elasticsearch.yml &>/dev/null
echo "network.host: 0.0.0.0" | sudo tee -a /etc/elasticsearch/elasticsearch.yml &>/dev/null
echo "http.port: 9200" | sudo tee -a /etc/elasticsearch/elasticsearch.yml &>/dev/null
echo "discovery.type: single-node" | sudo tee -a /etc/elasticsearch/elasticsearch.yml &>/dev/null

sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch

# Elasticsearch Install Test
curl -X GET "localhost:9200"

sudo apt install kibana logstash -y

# /etc/kibana/kibana.yml
sudo mv /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak
echo "server.port: 5601" | sudo tee -a /etc/kibana/kibana.yml
echo "server.host: 0.0.0.0" | sudo tee -a /etc/kibana/kibana.yml
echo 'elasticsearch.hosts: ["http://localhost:9200"]' | sudo tee -a /etc/kibana/kibana.yml

# /etc/logstash/conf.d/30-elasticsearch-output.conf
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
  }' | sudo tee /etc/kibana/kibana.yml

  
