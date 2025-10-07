# Tesina de grado - Lautaro Pastorino

El código presente en este repositorio fue desarrollado en el marco de la tesina de grado de Lautaro Pastorino con título "Explotación del paradigma de orientación a eventos en el desarrollo de una herramienta transaccional".

El desarrollo consiste en una prueba de concepto sobre la propuesta de utilizar un conector de Kafka de tipo *sink* para almacenar en un índice de una base de datos Open Search la información de una cola de mensajes de Kafka escrita en formato Avro. Se utiliza el servicio AWS Glue Schema Registry para registrar y validar el esquema de los datos.

## Entorno de ejecución

La infraestructura requerida para ejecutar la prueba de concepto es definida en el archivo [docker-compose.yml](docker-compose.yml) y creada utilizando la tecnología [Docker](https://www.docker.com/) a través de la herramienta de línea de comandos [Docker Compose](https://docs.docker.com/compose/). Sólo el Schema Registry no se despliega de forma local sino que se utiliza el servicio [AWS Glue](https://docs.aws.amazon.com/es_es/glue/latest/dg/schema-registry.html) para ejecutarlo en la nube.

Las tecnologías que participan de la prueba de concepto son las siguientes:

### Apache Kafka

Es una plataforma de streaming de eventos que permite crear colas de mensajes sobre las cuales componentes productores escriben información y componentes consumidores se suscriben para recibir los datos. [Kafka](https://kafka.apache.org/) habilita la comunicación asincrónica mediante eventos.

Para la prueba de concepto Apache Kafka se ejecutará exponiendo el puerto `29092` de forma tal que los productores y consumidores puedan utilizarlo para comunicarse con el broker.

### Kafka Connect

Es un framework que permite desarrollar conectores conocidos como plugins para trasladar de forma confiable información desde y hacia colas de mensajes de Kafka. La infraestructura de [Connect](https://kafka.apache.org/documentation.html#connect) consiste de un cluster de servidores sobre los cuales se ejecutan tareas asociadas a conectores.

Por las necesidades de la prueba, se crea un volumen que permite compartir archivos con el contenedor de Connect creado sobre Docker. En el directorio [./plugins](./plugins/) se almacenan los archivos JAR que el conector necesita para interactuar con AWS Glue Schema Registry y para utilizar el Single Message Transform (SMT) llamado Date Field Router. Este SMT fue desarrollado por Lautaro Pastorino y publicado en el repositorio [smt-date-field-router](https://github.com/lautaropastorino/smt-date-field-router).

En esta prueba de concepto el entorno de Kafka Connect se ejecutará exponiendo su API en el puerto `8083`.

### Open Search

Es una base de datos noSQL o no relacional orientada a documentos que cuenta con grandes capacidades de búsqueda incluyendo operaciones full-text. [Open Search](https://opensearch.org/) almacena su información sobre índices [Lucene](https://lucene.apache.org/).

El puerto `9200` es el configurado para exponer la API de Open Search en esta prueba de concepto

### [AWS Glue Schema Registry](https://docs.aws.amazon.com/es_es/glue/latest/dg/schema-registry.html)

Es un servicio del proveedor de nube AWS que permite ejecutar la implementación de un Schema Registry capaz de almacenar esquemas de información y validar la compatibilidad al registrarse cambios.

### [AKHQ](https://akhq.io/)

Apache Kafka HQ es una herramienta de administración y monitoreo de clústeres de Kafka. Además incluye funcionalidades que le permiten interactuar con Kafka Connect y con implementaciones de Schema Registry.

La herramienta será accesible en esta prueba de concepto a través del puerto `8000`.

### [Gatling](https://www.gatling.io/)

Es una herramienta que permite realizar pruebas de carga sobre diversos tipos de aplicaciones generando las consultas e información requeridas. Entre las operaciones que permite realizar se encuentra la posibilidad de escribir información en colas de mensajes de Kafka.

Para esta prueba de concepto se utiliza el código desarrollado por Lautaro Pastorino disponible en el repositorio [gatling-kafka-avro](https://github.com/lautaropastorino/gatling-kafka-avro) y como imagen de docker en [lautaropastorino/gatling-kafka-avro
](https://hub.docker.com/r/lautaropastorino/gatling-kafka-avro).

## Alcance de la prueba de concepto

El objetivo de la prueba de concepto es conseguir trasladar la información de transacciones presente en una cola de mensajes de Apache Kafka a un índice de Open Search. Se deben tener en cuenta los siguientes requerimientos:

- Los eventos escritos en Kafka deben estar codificados en formato Avro.
- Se debe utilizar AWS Glue Schema Registry para almacenar el esquema utilizado para codificar la información.
- Existen campos en el modelo de datos que no deben ser almacenados en Open Search.
- Los documentos deben ser almacenados en Open Search mediante una operación de *upsert*.
- Se debe utilizar el valor presente en la *key* del evento como ID del documento a almacenar en Open Search.
- Los documentos deben ser creados en el índice de Open Search correspondiente a su propia fecha de autorización.

### Implementación del alcance

Para conseguir cumplir con los objetivos y requerimientos de esta prueba se construirá un conector de Kafka de tipo *sink* que consuma la información de la cola de mensajes de Kafka y la almacene en el índice correspondiente de Open Search.

El código del proyecto [gatling-kafka-avro](https://github.com/lautaropastorino/gatling-kafka-avro) que utiliza gatling para generar información en la cola de mensajes de Kafka configura el productor de forma tal que pueda conectarse a AWS Glue Schema Registry para registrar y validar el esquema de la información. Las configuracioens se pueden observar en la clase [AvroSerializer.java](https://github.com/lautaropastorino/gatling-kafka-avro/blob/master/src/main/java/org/lautaropastorino/poc/AvroSerializer.java). El código genera eventos en la cola de mensjaes utilizando un UUID aleatorio como *key* y una transacción en formato Avro como *value*.

El conector de Kafka se crea con las siguiente configuraciones para descartar campos que existen en cada evento cargado en la cola de mensajes:

```json
"transforms.replaceField.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
"transforms.replaceField.exclude": "otherField,anotherField,evenAnotherField"
```

La configuración `"index.write.method": "upsert"` es utilizada para configurar el tipo de operación de almacenamiento utilizado por el conector.

Mediante la configuración `"key.ignore": "false"` el conector toma la *key* recibida en el evento de Kafka y la utiliza como ID del documento al momento de almacenar en Open Search.

Utilizando el SMT Date Field Router el conector es capaz de determinar el índice destino de cada evento recibido en la cola de mensajes. Las configuraciones son las siguientes:

```json
"transforms.fieldRouter.type": "org.lautaropastorino.poc.FieldRouter" 
"transforms.fieldRouter.field.name": "authorizationDate" 
"transforms.fieldRouter.source.date.format": "yyyy-MM-dd" 
"transforms.fieldRouter.dest.date.format": "yyyy-MM" 
"transforms.fieldRouter.dest.topic.format": "${topic}-${field}"
```

## Ejecución de la prueba de concepto

### Requerimientos

La prueba de concepto requiere que el ejecutante cuente con Docker y docker-compose instalados en su computadora. Además, requiere contar con un usuario de AWS con acceso a Glue Schema Registry.

Para ejecutaro en el sistema operativo Windows particularmente se requiere contar con [Powershell](https://github.com/PowerShell/PowerShell?tab=readme-ov-file) instalado. La prueba en Windows está preparada para interactuar con [Docker Desktop](https://docs.docker.com/desktop/) o con [Rancher Desktop](https://rancherdesktop.io/), en ambos casos utilizando el [WSL](https://learn.microsoft.com/es-es/windows/wsl/).

En el caso que se utilice alguna distribución de Linux para ejecutar la prueba de concepto se requiere contar con las herramientas [jq](https://jqlang.org/) y [cURL](https://curl.se/) instaladas.

### Pasos de la ejecución

A través del script `run_poc.ps1` en Windows o `run_poc.sh` en Linux se ejecuta la prueba de concepto completa. Ambos scripts funcionan de la misma manera y se encargan de crear el entorno y la información y luego verificar el resultado.

En detalle los scripts ejecutan los siguientes pasos:

1. Inician los contenedores de Kafka, Connect, Open Search y AKHQ
2. Crean la cola de mensajes en Kafka
3. Crean un [index-template](https://docs.opensearch.org/latest/im-plugin/index-templates/) en Open Search
4. Crean el conector de Kafka a través de la API de Connect
5. Ejecutan la prueba de carga de Gatling para crear información en la cola de mensajes
6. Obtienen desde Open Search las transacciones cargadas en la base de datos

### Ejecución

### Archivo .env

La ejecución de la prueba de concepto es parametrizable a través de la creación del archivo requerido `.env` en el root del repositorio. En dicho archivo se deben configurar los siguientes valores:

`AWS_ACCESS_KEY_ID`

Clave de acceso de un usuario de AWS que funciona como identificador público utilizado para autenticarse y obtener acceso programático a los servicios del proveedor. El usuario debe tener acceso a AWS Glue Schema Registry.

`AWS_SECRET_ACCESS_KEY`

Clave de acceso de un usuario de AWS que funciona como contraseña privada utilizada para autenticarse y obtener acceso programático a los servicios del proveedor.

`AWS_SESSION_TOKEN`

Token con una validez temporal que permite validar la sesión del usuario que se conecta a los servicios del proveedor de nube.

`AWS_REGION`

Región de AWS donde se encuentra el Glue Schema Registry.

Ejemplo: us-east-1

`KAFKA_BROKERS`

Lista de pares host:port usados como punto de conexión con los brókers de Kafka que contienen la cola de mensajes que se utilizará en la prueba.

Ejemplo: localhost:29092

`TOPIC`

Nombre de la cola de mensajes sobre la que se va a producir la información para la prueba.

Ejemplo: avro-transactions

`SCHEMA_NAME`

Nombre del esquema en AWS Glue Schema Registry donde se va a almacenar la definición del formato de la información generada para la prueba.

Ejemplo: avro-transactions

`REGISTRY_NAME`

Nombre del registry de AWS Glue Schema Registry donde se almacenará el esquema para la prueba.

Ejemplo: concentrador-tx

`SIM_DURATION`

Duración de la simulación que carga información en la cola de mensajes de Kafka. Utiliza el formato definido en ISO-8601 ([documentación](https://docs.oracle.com/javase/8/docs/api/java/time/Duration.html#from-java.time.temporal.TemporalAmount-)).

Ejemplo: PT1M

#### Ejemplo de archivo .env completo

```bash
AWS_ACCESS_KEY_ID=ASIAQJYBDS79PTUDXLL6
AWS_SECRET_ACCESS_KEY=kJ4Pzzx+AtpDpb4Oe6VKmb5SjAX6GOtcjPyekT9+
AWS_SESSION_TOKEN=IQoJb3JpZ2luX2VjENz//////////wEaCXVzLWVhc3QtMSJHMEUCIQDZvg6H1Hm2Steb4BkVTvmDmO4WOxW55zhNroaB1Vcm3wIgIvGqympMJKkVdaXiK08L+4+P7MWUhG5wVnQ7A+ausOMq6wEIdRAAGgwwMTQ0OTg2MzM3MDIiDHcCMx3rRYptD5AF0yrIAWTCUvPP/dsXVF0NaqdsX1XY0cP+fGpC1FS1MXGjR59K2D7JE0MJcNkRsIEJK9P5Ibkn88NnyCT/nwnXo4vneqij9Q0/X/zZbe8Dzw/sgm6S5LmRob82SwInVSWp3oNChRXkjk42QyHszkcCFs0IGzhQuDrJrgccR9hI59ZPUMy54hGCNkd6Oc+TG9be9zFT+EKhZAolQJW1e1NgrL5rDeLHZMZQm+r0kMgPfp1bPBRRMEdpa1DZN9VBbO24veHDoy94a4x0fT7FMMe4iccGOpgBA1XpgqUhEVWFDJuRat03VoQiMro7aH7+t7VsCxwfFr2wg3+h0C5M5zHIu/T6FV45pZtU9EQIXPaHCbkyculbgG6C/2/63UIoMe3UvZ7Slba1F6+izTh/FiFjI/HKVrKWPECBY6G8N8uXKvCu4hu5xrRqIKYS6zRONkc8TOftSMRFXNQwNS/pptqz6Q7WSTYj5/+i6zHyXRo=
AWS_REGION=us-east-1
KAFKA_BROKERS=kafka:29092
TOPIC=avro-transactions
SCHEMA_NAME=avro-transactions
REGISTRY_NAME=concentrador-tx
SIM_DURATION=PT1M
```

### Creación del registry en AWS

La prueba de concepto requiere que exista de antemano el registry con el nombre indicado en AWS Glue Schema Registry. Es posible crear el registry desde la consola de AWS ingresando con un usuario con permisos sobre dicho servicio. Se debe navegar inicialmente al servicio AWS Glue, luego seleccionar en el menú lateral izquierdo la opción "Stream schema registries" y finalmente clickeando en el botón "Add registry". Allí se podrá configurar el nombre, la descripción y las etiquetas del registry. El nombre debe coincidir con el definido en el archivo `.env`.

### Comando de ejecución

Windows:

```powershell
.\run_poc.ps1
```

Linux

```bash
./run_poc.sh
```

### Monitoreo de la ejecución

El ejecutante podrá acceder a la dirección http://localhost:8000/ui/ en su navegador para monitorear la ejecución utilizando AKHQ.
