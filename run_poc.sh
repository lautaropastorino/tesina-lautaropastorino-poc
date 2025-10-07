#!/bin/bash

is_healthy() {
    local container_name=$1
    
    echo -e "\nEsperando que $container_name este listo"

    while true; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name")
        
        if [ "$status" = "healthy" ]; then
            break
        fi
        
        sleep 5
    done
    
    echo -e "\n$container_name está listo"
}

envFile=".env"

if [ ! -f "$envFile" ]; then
    echo -e "Error: No se encontro el archivo $envFile"
    exit 1
fi

echo -e "\nCargando variables de entorno desde $envFile..."

set -a
source "$envFile"
set +a

echo -e "\nVariables cargadas exitosamente!"

sudo sysctl -w vm.max_map_count=262144

echo -e "\nCreando contenedores"

docker-compose up -d --force-recreate -V

is_healthy "kafka"

echo -e "\nCreando tópico $TOPIC"

docker exec kafka /bin/kafka-topics --bootstrap-server $KAFKA_BROKERS --create --topic $TOPIC

is_healthy "opensearch"

echo -e "\nCreando index template"

curl --location --request PUT "localhost:9200/_index_template/$TOPIC" \
--header 'Content-Type: application/json' \
--data @- <<EOF | jq .
{
    "index_patterns": [
        "$TOPIC-*"
    ],
    "template": {
        "aliases": {
            "$TOPIC": {}
        },
        "settings": {
            "number_of_shards": 1,
            "number_of_replicas": 1
        },
        "mappings": {
            "properties": {
                "establishmentId": {
                    "type": "keyword"
                },
                "transactionAmount": {
                    "type": "double"
                },
                "authorizationDate": {
                    "type": "date"
                }
            }
        }
    }
}
EOF

is_healthy "connect"

echo -e "\nCreando conector"

curl -X POST -H "Content-Type: application/json" --data "{
    \"name\": \"opensearch-sink-connector\",
    \"config\": {
      \"connector.class\": \"io.aiven.kafka.connect.opensearch.OpensearchSinkConnector\",
      \"tasks.max\": \"1\",
      \"topics\": \"$TOPIC\",
      \"key.converter\": \"org.apache.kafka.connect.storage.StringConverter\",

      \"value.converter\": \"com.amazonaws.services.schemaregistry.kafkaconnect.AWSKafkaAvroConverter\",
      \"value.converter.schemas.enable\": \"true\",
      \"value.converter.endpoint\": \"https://glue.us-east-1.amazonaws.com\",
      \"value.converter.region\": \"us-east-1\",
      \"value.converter.schemaAutoRegistrationEnabled\": \"true\",
      \"value.converter.avroRecordType\": \"GENERIC_RECORD\",
      \"value.converter.registryName\": \"concentrador-tx\",

      \"connection.url\": \"http://opensearch:9200\",
      \"aiven.opensearch.mappings.skip\": \"true\",
      \"type.name\": \"_doc\",
      \"key.ignore\": \"false\",
      \"batch.size\": \"2000\",
      \"linger.ms\": \"5000\",
      \"max.retries\": \"10\",
      \"retry.backoff.ms\": \"5000\",
      \"index.write.method\": \"upsert\",

      \"transforms\":\"fieldRouter,replaceField\",

      \"transforms.fieldRouter.type\":\"org.lautaropastorino.poc.FieldRouter\",
      \"transforms.fieldRouter.field.name\":\"authorizationDate\",
      \"transforms.fieldRouter.source.date.format\": \"yyyy-MM-dd\",
      \"transforms.fieldRouter.dest.date.format\": \"yyyy-MM\",
      \"transforms.fieldRouter.dest.topic.format\": \"\${topic}-\${field}\",

      \"transforms.replaceField.type\": \"org.apache.kafka.connect.transforms.ReplaceField\$Value\",
      \"transforms.replaceField.exclude\": \"otherField,anotherField,evenAnotherField\"
    }
  }" http://localhost:8083/connectors  | jq .

echo -e "\nEscribiendo en el topico"

docker-compose run --rm gatling

curl -X GET -H "Content-Type: application/json" --data '{
    "query": {
      "match_all": {}
    }
  }' "http://localhost:9200/$TOPIC/_search"  | jq .
