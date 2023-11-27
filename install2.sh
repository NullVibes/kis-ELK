#!/bin/bash

echo "export ES_HOME=/usr/share/elasticsearch
export ES_PATH_CONFIG=/etc/elasticsearch
export KIBANA_HOME=/usr/share/kibana
export KIBANA_PATH_CONFIG=/etc/kibana
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64" | tee /tmp/exports.sh

ES_PATH_CONFIG=/etc/elasticsearch
ES_HOME=/usr/share/elasticsearch
KIBANA_HOME=/usr/share/kibana
KIBANA_PATH_CONFIG=/etc/kibana

chmod +x /tmp/exports.sh
source /tmp/./exports.sh

EGPG=/usr/share/keyrings/elastic.gpg
if [[ ! -f "$EGPG" ]]; then
  curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
fi

EDEB=/etc/apt/sources.list.d/elastic-8.x.list
if [[ ! -f "$EDEB" ]]; then
  echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
fi

echo -n "Updating System... " && sudo apt update && sudo apt upgrade -y &>/dev/null && echo "Done"
echo -n "Adding apt-transport-https package... " && sudo apt install apt-transport-https -y &>/dev/null && echo "Done"
echo -n "Adding unzip package... " && sudo apt install unzip -y &>/dev/null && echo "Done"
clear

read -p "Enter DNS suffix (i.e. domain.xyz) for this ELK stack: " TMPDOMAIN
read -s -p "Enter password you want to set for the CA certificate: " TMPPWORD1
echo ""
echo "DNS suffix [ $TMPDOMAIN ] and password [ PickleWizard9000! ] will be used."
TMPIP=$(ip a | grep 172 | awk '{print $2}' | cut -d '/' -f1)
TMPINST=/tmp/instance.yml
if [[ ! -f "$TMPINST" ]]; then
  echo "instances:
  - name: 'node1'
    dns: [ 'node1.$TMPDOMAIN' ]
    ip:
      - $TMPIP
      - 127.0.0.1
  - name: 'kibana'
    dns: [ 'kibana.$TMPDOMAIN' ]
    ip:
      - $TMPIP
      - 127.0.0.1
  - name: 'logstash'
    dns: [ 'logstash.$TMPDOMAIN' ]
    ip:
      - $TMPIP
      - 127.0.0.1
" | tee /tmp/instance.yml &>/dev/null
fi

#Install OpenJDK
echo -n "Installing OpenJDK..." && sudo apt install openjdk-11-jdk -y &>/tmp/openjdk.txt && echo "Done."
java --version
echo ""
echo "Press any key to continue..."
read -s -n 1

#*** Install Elasticsearch ***
echo -n "Installing Elasticsearch"
sudo apt install elasticsearch -y &> /tmp/elastic.txt && echo "Done."
P=$(grep "generated password" /tmp/elastic.txt 2>/dev/null | awk '{ print $11 }')
EBAK=$ES_PATH_CONFIG/elasticsearch.yml.bak
if [[ ! -f "$EBAK" ]]; then
 sudo cp $ES_PATH_CONFIG/elasticsearch.yml $ES_PATH_CONFIG/elasticsearch.yml.bak
fi

# /etc/elasticsearch/elasticsearch.yml
echo "Elasticsearch sed #1"
sudo sed -i 's/.*cluster.name:.*/cluster.name: kiselk/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #2"
sudo sed -i 's/.*node.name:.*/node.name: node1/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #3"
sudo sed -i 's/.*network.host:.*/network.host: 0.0.0.0/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #4"
sudo sed -i 's/.*http.port:.*/http.port: 9200/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #5"
sudo sed -i 's/.*xpack.security.enabled:.*/xpack.security.enabled: true/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #6"
sudo sed -i 's/.*xpack.security.enrollment.enabled:.*/xpack.security.enrollment.enabled: true/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #7"
sudo sed -i 's/.*xpack.security.http.ssl:/xpack.security.http.ssl:/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #8"
sudo sed -i 's/#xpack.security.transport.ssl:/xpack.security.transport.ssl:/' $ES_PATH_CONFIG/elasticsearch.yml

B=$(sudo grep -c "node1.crt" $ES_PATH_CONFIG/elasticsearch.yml)
if [[ $B -eq 0 ]]; then
  echo "Elasticsearch sed #9"
  sudo sed -i '/.*keystore.path: certs\/http.p12/i\  key: certs\/node1\/node1.key\n  certificate: certs\/node1\/node1.crt\n  certificate_authorities: certs\/ca\/ca.crt' $ES_PATH_CONFIG/elasticsearch.yml
fi

C=$(sudo grep -c "node1.crt" $ES_PATH_CONFIG/elasticsearch.yml)
if [[ $C -eq 1 ]]; then
  echo "Elasticsearch sed #10"
  sudo sed -i '/.*keystore.path: certs\/transport.p12/i\  key: certs\/node1\/node1.key\n  certificate: certs\/node1\/node1.crt\n  certificate_authorities: certs\/ca\/ca.crt' $ES_PATH_CONFIG/elasticsearch.yml
fi

echo "Elasticsearch sed #11"
sudo sed -i 's/.*keystore.path: certs\/http.p12/# keystore.path: certs\/http.p12/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #12"
sudo sed -i 's/.*keystore.path: certs\/transport.p12/# keystore.path: certs\/transport.p12/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #13"
sudo sed -i 's/.*truststore.path: certs\/transport.p12/# truststore.path: certs\/transport.p12/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #14"
sudo sed -i 's/.*http.host:.*/http.host: 0.0.0.0/' $ES_PATH_CONFIG/elasticsearch.yml
echo "Elasticsearch sed #15"
sudo sed -i 's/cluster.initial_master_nodes:.*/cluster.initial_master_nodes: \["node1"\]/' $ES_PATH_CONFIG/elasticsearch.yml

# Create ES Certificate Authority & Certs for TLS
# Notes:
#        - By default, elastic-stack-ca.p12 file is created in /usr/share/elasticsearch/
#        - Test for previous certificates first
CERTTEST=$ES_PATH_CONFIG/certs/node1
if [[ ! -d "$CERTTEST" ]]; then
  echo "Building CA certificate... "
  sudo $ES_HOME/bin/elasticsearch-certutil ca --pem --out $ES_PATH_CONFIG/certs/ca.zip --pass $TMPPWORD1 -s &> /tmp/certutil.txt
  echo "Unzip CA... " && sudo unzip $ES_PATH_CONFIG/certs/ca.zip -d $ES_PATH_CONFIG/certs/ && echo "Done"
  echo -n "Building client certificates... " && sudo $ES_HOME/bin/elasticsearch-certutil cert --ca-cert $ES_PATH_CONFIG/certs/ca/ca.crt --ca-key $ES_PATH_CONFIG/certs/ca/ca.key --pem --ca-pass $TMPPWORD1 --in /tmp/instance.yml --out $ES_PATH_CONFIG/certs/certs.zip &> /tmp/certutil.txt && echo "Done."
  echo -n "Unzip client certs... " && sudo unzip $ES_PATH_CONFIG/certs/certs.zip -d $ES_PATH_CONFIG/certs/ && echo "Done"
  echo "Press any key to continue..."
  read -s -n 1
fi

sudo systemctl daemon-reload
ESSTATUS=$(systemctl status elasticsearch | grep -c "Active")
if [[ $ESSTATUS -eq 0 ]]; then
  sudo systemctl enable elasticsearch
  sudo systemctl start elasticsearch
else
  sudo systemctl restart elasticsearch
fi

ESSTATUS=$(systemctl status elasticsearch | grep Active | awk '{print $2}')
echo "Elasticsearch status: $ESSTATUS"
if [[ $ESSTATUS == "failed" ]]; then
  echo "Elasticsearch config failed!"
  exit
fi

# Elasticsearch Install Test
curl -k -v "https://localhost:9200" -u elastic:$P
echo ""
echo "Elasticsearch install/config complete."
echo "Press any key to continue..."
read -s -n 1

#*** Install Kibana ***
KB_PATH=/etc/kibana
echo "" && echo -n "Installing Kibana..." && sudo apt install kibana -y &> /tmp/kibana.txt && echo "Done"
sudo cp /$ES_PATH_CONFIG/certs/kibana/* $KB_PATH/certs/
sudo cp /$ES_PATH_CONFIG/certs/ca/ca.crt $KB_PATH/certs/

A=$(sudo grep -c "127.0.0.1 node1.local kibana.local logstash.local" /etc/hosts)
if  [[ $A -eq 0 || $A == "" ]]
then
  echo '127.0.0.1 node1.local kibana.local logstash.local' | sudo tee -a /etc/hosts
fi

KBAK=$KB_PATH/kibana.yml.bak
if [[ ! -f "$KBAK" ]]; then
  sudo cp $KB_PATH/kibana.yml $KB_PATH/kibana.yml.bak
fi

# /etc/kibana/kibana.yml
echo "Kibana sed #1"
sudo sed -i 's/.*server.port:.*/server.port: 5601/' $KB_PATH/kibana.yml
echo "Kibana sed #2"
sudo sed -i 's/.*server.name:.*/server.name: "Kis-ELK"/' $KB_PATH/kibana.yml
echo "Kibana sed #3"
sudo sed -i 's/.*server.ssl.enabled:.*/server.ssl.enabled: true/' $KB_PATH/kibana.yml
echo "Kibana sed #4"
sudo sed -i 's/.*server.ssl.certificate:.*/server.ssl.certificate: \/etc\/kibana\/kibana.crt/' $KB_PATH/kibana.yml
echo "Kibana sed #5"
sudo sed -i 's/.*server.ssl.key:.*/server.ssl.key: \/etc\/kibana\/kibana.key/' /etc/kibana/kibana.yml
echo "Kibana sed #6"
sudo sed -i 's/.*server.host:.*/server.host: "kibana.local"/' /etc/kibana/kibana.yml
echo "Kibana sed #7"
sudo sed -i 's/.*elasticsearch.hosts:.*/elasticsearch.hosts: \["https:\/\/localhost:9200"\]/' /etc/kibana/kibana.yml
echo "Kibana sed #8"
sudo sed -i 's/.*elasticsearch.username:.*/elasticsearch.username: "kibana"/' /etc/kibana/kibana.yml
echo "Kibana sed #9"
sudo sed -i 's/.*elasticsearch.password:.*/elasticsearch.password: "pass"/' /etc/kibana/kibana.yml
echo "Kibana sed #10"
sudo sed -i 's/.*elasticsearch.ssl.certificate:.*/elasticsearch.ssl.certificate: "\/etc\/kibana\/certs\/kibana.crt"/' /etc/kibana/kibana.yml
echo "Kibana sed #11"
sudo sed -i 's/.*elasticsearch.ssl.key:.*/elasticsearch.ssl.key: "\/etc\/kibana\/certs\/kibana.key"/' /etc/kibana/kibana.yml
echo "Kibana sed #12"
sudo sed -i 's/.*elasticsearch.ssl.certificateAuthorities:.*/elasticsearch.ssl.certificateAuthorities: \["\/etc\/kibana\/certs\/ca.crt"\]/' /etc/kibana/kibana.yml

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
# Create enrollment token for Kibana _AFTER_ Elasticsearch is installed/configured
/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana

echo ""
echo "Kibana install/config complete."
echo "Press any key to continue..."
read -s -n 1

#*** Install Logstash ***
sudo apt install logstash -y &> /tmp/logstash.txt
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

#*** Install Filebeat ***
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
