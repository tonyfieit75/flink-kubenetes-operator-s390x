import json
import random
import time
import uuid
from datetime import datetime
from kafka import KafkaProducer

KAFKA_BOOTSTRAP = "kafka.confluent-platform.svc.cluster.local:9092"
TOPIC = "flink-demo-transactions"

customers = [
    "Alice", "Bob", "Charlie", "Daniel",
    "Emma", "Fiona", "George", "Hannah"
]

producer = KafkaProducer(
    bootstrap_servers=KAFKA_BOOTSTRAP,
    value_serializer=lambda v: json.dumps(v).encode("utf-8")
)

print("🚀 Starting real-time Kafka generator...")
print(f"   → Topic: {TOPIC}")
print(f"   → Bootstrap: {KAFKA_BOOTSTRAP}")

while True:
    message = {
        "id": str(uuid.uuid4()),
        "customer": random.choice(customers),
        "amount": round(random.uniform(5, 500), 2),
        "ts": datetime.utcnow().isoformat()
    }

    producer.send(TOPIC, message)
    print("📤 Sent:", message)

    time.sleep(1)   # 1 record/second

