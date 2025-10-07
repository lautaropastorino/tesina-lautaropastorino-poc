function is-healthy {
    param(
        [string]$ContainerName
    )

    echo "Esperando que $ContainerName este listo"
    echo ""

    do {
        $status = docker inspect --format='{{.State.Health.Status}}' $ContainerName
        if ($status -ne "healthy") {
            Start-Sleep 5
        }
    } while ($status -ne "healthy")

    echo "$ContainerName esta listo"
    echo ""
}

$distros = wsl -l -q
$target = $null

if ($distros -contains "docker-desktop") {
    $target = "docker-desktop"
} 

if ($distros -contains "rancher-desktop") {
    $target = "rancher-desktop"
} 

if ($target -eq $null) {
    Write-Error "Distros WSL docker-desktop o rancher-desktop no encontradas"
    exit 1
}

echo "Creando contenedores"

wsl -d $target sh -c "sysctl -w vm.max_map_count=262144"

docker-compose up -d --force-recreate -V

is-healthy -ContainerName kafka

echo "Creando topico transactions"

docker exec kafka /bin/kafka-topics --bootstrap-server localhost:9092 --create --topic avro-transactions

is-healthy -ContainerName opensearch

echo "Creando index template"

Invoke-WebRequest -Method PUT -Uri 'http://localhost:9200/_index_template/avro-transactions' `
-ContentType "application/json" `
-Body '{
    "index_patterns": [
        "avro-transactions-*"
    ],
    "template": {
        "aliases": {
            "avro-transactions": {}
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
}' | ConvertFrom-Json | ConvertTo-Json -Depth 10

is-healthy -ContainerName connect

echo "Creando conector"

$config  = @{
  "name" = "opensearch-sink-connector" 
    "config" = @{
      "connector.class" = "io.aiven.kafka.connect.opensearch.OpensearchSinkConnector" 
      "tasks.max" = "1" 
      "topics" = "avro-transactions" 
      "key.converter" = "org.apache.kafka.connect.storage.StringConverter" 

      "value.converter" = "com.amazonaws.services.schemaregistry.kafkaconnect.AWSKafkaAvroConverter" 
      "value.converter.schemas.enable" = "true" 
      "value.converter.endpoint" = "https://glue.us-east-1.amazonaws.com" 
      "value.converter.region" = "us-east-1" 
      "value.converter.schemaAutoRegistrationEnabled" = "true" 
      "value.converter.avroRecordType" = "GENERIC_RECORD" 
      "value.converter.registryName" = "concentrador-tx" 

      "connection.url" = "http://opensearch:9200" 
      "aiven.opensearch.mappings.skip" = "true" 
      "type.name" = "_doc" 
      "key.ignore" = "false" 
      "batch.size" = "2000" 
      "linger.ms" = "5000" 
      "max.retries" = "10" 
      "retry.backoff.ms" = "5000" 
      "index.write.method" = "upsert" 

      "transforms" ="fieldRouter,replaceField" 

      "transforms.fieldRouter.type" = "org.lautaropastorino.poc.FieldRouter" 
      "transforms.fieldRouter.field.name" = "authorizationDate" 
      "transforms.fieldRouter.source.date.format" = "yyyy-MM-dd" 
      "transforms.fieldRouter.dest.date.format" = "yyyy-MM" 
      "transforms.fieldRouter.dest.topic.format" = '${topic}-${field}' 

      "transforms.replaceField.type" = 'org.apache.kafka.connect.transforms.ReplaceField$Value' 
      "transforms.replaceField.exclude" = "otherField,anotherField,evenAnotherField"
    }
}

$body  = $config | ConvertTo-Json -Compress

Invoke-WebRequest -Method POST -Uri http://localhost:8083/connectors -ContentType "application/json" -Body $body | ConvertFrom-Json | ConvertTo-Json -Depth 10

echo "Escribiendo en el tópico"

docker-compose run --rm gatling

echo "Obteniendo transacciones desde Open Search"

Invoke-WebRequest -Method POST -Uri http://localhost:9200/avro-transactions/_search `
-ContentType "application/json" `
-Body '{
    "query": { 
        "match_all": { } 
    } 
}' | ConvertFrom-Json | ConvertTo-Json -Depth 10