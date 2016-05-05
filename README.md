kafka-auto-partition-reassignment
================================

The purpose of this script is to automate the process of reassigning Kafka partition replicas when adding a new node to the cluster.

Usage
----

This script needs to run on a host that has the Kafka system tools.

Before using it for the first time you should check the following two variables:

* `KAFKA_BIN="/usr/lib/kafka/bin/"`: This should be set to the directory containing the Kafka system tools
* `TMP="/tmp/kafka"`

After this is done you can run the following to get instructions on how to use the script and description of all its arguments:

`./kafka-auto-partition-reassignment.sh -h`

License
------

This script is licensed under the Apache License, version 2.0
