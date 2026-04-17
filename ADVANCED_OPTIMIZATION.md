# Advanced Docker Swarm Optimization for 1GB RAM

This guide covers additional optimizations if memory usage remains high after the initial fixes.

---

## Issue 1: Python Gunicorn Memory Footprint

Python apps often use more memory than expected due to:
- Module imports in memory
- SQLAlchemy connection pools
- Request overhead

**Solution: Optimize Gunicorn in your app**

In `minitwit_refactor.py` or where you start Gunicorn, configure workers:

```bash
# Current: gunicorn --bind 0.0.0.0:5000 minitwit_refactor:app

# Optimized for 1GB:
gunicorn \
  --bind 0.0.0.0:5000 \
  --workers 2 \                    # Reduce from default 4
  --worker-class sync \             # Avoid eventlet/gevent overhead
  --max-requests 1000 \             # Recycle workers to prevent memory creep
  --max-requests-jitter 100 \       # Prevent thundering herd
  --timeout 60 \                    # Prevent hanging requests
  minitwit_refactor:app
```

**Update [Dockerfile-minitwit](Dockerfile-minitwit):**
```dockerfile
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

# Optimized for low-memory environments
CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--worker-class", "sync", \
     "--max-requests", "1000", \
     "--max-requests-jitter", "100", \
     "--timeout", "60", \
     "minitwit_refactor:app"]
```

---

## Issue 2: SQLAlchemy Connection Pool Leaks

Check [db.py](db.py) for proper pool configuration:

```python
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool

# Good for 1GB:
engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=3,              # Small pool
    max_overflow=2,           # Allow 2 overflow connections
    pool_pre_ping=True,       # Test connections before use
    pool_recycle=3600,        # Recycle connections every hour (MySQL default)
    echo=False                # Don't log every SQL query (memory + I/O waste)
)
```

⚠️ **Common leak:** If `pool_size` is too high or `max_overflow` is unlimited, connections accumulate.

---

## Issue 3: Prometheus Disk → Memory Bloat

Prometheus stores metrics on disk but loads them into memory. On a 1GB droplet with 7-14 days of metrics, this explodes.

**Solution: Limit Prometheus retention**

Update [docker-compose.yml](docker-compose.yml) Prometheus service:

```yaml
prometheus:
  image: prom/prometheus:v2.40-alpine    # Use alpine (smaller footprint)
  command: 
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.retention.time=3d'      # Only keep 3 days (vs 15d default)
    - '--storage.tsdb.retention.size=256MB'   # Cap disk usage at 256MB
  volumes:
    - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    - prometheus_data:/prometheus           # Named volume (trackable)
  ports:
    - "9090:9090"
  deploy:
    replicas: 1
    placement:
      constraints:
        - "node.role==manager"
    resources:
      limits:
        cpus: '0.2'       # Reduce from 0.3
        memory: 128M      # Reduce from 200M
      reservations:
        cpus: '0.1'
        memory: 64M

volumes:
  prometheus_data:
```

Also update [monitoring/prometheus.yml](monitoring/prometheus.yml):
```yaml
global:
  scrape_interval: 60s      # Increase from 15s (fewer data points = less memory)
  evaluation_interval: 60s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
      
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
    # Remove high-cardinality metrics that consume memory:
    scrape_configs:
      - metric_relabel_configs:
          - source_labels: [__name__]
            regex: 'node_filesystem_.*|node_network_.*'
            action: drop
```

---

## Issue 4: Loki (if you add it back)

Loki is a log aggregation system that's **heavy on 1GB**. Only use if you absolutely need it.

If you must use Loki, configure it for low memory:

```yaml
loki:
  image: grafana/loki:2.9-alpine
  ports:
    - "3100:3100"
  volumes:
    - loki_data:/loki
  command:
    - -config.file=/etc/loki/loki-config.yaml
  environment:
    - GOGC=50                          # Aggressive garbage collection
  deploy:
    replicas: 1
    placement:
      constraints:
        - "node.role==manager"
    resources:
      limits:
        cpus: '0.2'
        memory: 100M
      reservations:
        cpus: '0.1'
        memory: 50M
```

**Better alternative:** Use Promtail → Grafana Loki cloud (offload to managed service) or skip centralized logging entirely for 1GB.

---

## Issue 5: OS-Level Tuning

SSH into your droplet and apply these:

```bash
# Enable memory swap (emergency buffer)
sudo fallocate -l 512M /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Tune Docker daemon memory
sudo mkdir -p /etc/docker
cat | sudo tee /etc/docker/daemon.json <<EOF
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "memory": "900m",
  "memswap": "1g",
  "live-restore": true
}
EOF

sudo systemctl restart docker
```

---

## Monitoring Script

Create a memory monitoring dashboard:

```bash
# Run this every 5 min via cron to track trends
*/5 * * * * /path/to/log-memory.sh >> /var/log/docker-memory.log 2>&1
```

**[log-memory.sh](./scripts/log-memory.sh):**
```bash
#!/bin/bash
echo "$(date '+%Y-%m-%d %H:%M:%S') - $(free -h | grep Mem | awk '{print "Total:", $2, "Used:", $3, "Free:", $4, "Percent:", int($3/$2*100)"%"}')" 
sudo docker stats --no-stream --format "{{.Container}}: {{.MemUsage}}" >> /tmp/docker-memory.txt
```

---

## Decision Tree: When to Upgrade

If memory usage > 85% **after all these optimizations**:

1. **Scale vertically** (simpler now):
   - Upgrade to 2GB droplet ($12/month → $18/month on DigitalOcean)
   - Update [Vagrantfile](Vagrantfile): `provider.size = 's-1vcpu-2gb'`
   - Run `vagrant up` to recreate

2. **Scale horizontally** (if you have 2+ nodes):
   - Add second droplet
   - Join it to Swarm: `docker swarm join-token worker`
   - Docker will auto-distribute load

3. **Remove monitoring on prod** (temporary):
   - Keep only node-exporter + Promtail
   - Move Prometheus/Grafana to separate "monitoring" droplet

---

## Summary of Memory Optimizations

| Optimization | Memory Saved | Effort |
|--------------|--------------|--------|
| Reduce replicas 3→2 | ~100MB | ✅ Done |
| Add resource limits | Prevents spikes | ✅ Done |
| Remove Loki | ~50MB | ✅ Done |
| Prometheus retention 3d | ~80-150MB | 🟡 Recommended |
| Gunicorn workers 2 | ~40-60MB | 🟡 Recommended |
| Alpine images | ~20-30MB | 🟡 Easy win |
| Enable swap | Safety buffer | 🟡 Recommended |
| Upgrade to 2GB | Full solution | 🔴 If all else fails |

---

**Test these changes incrementally:**
1. Apply docker-compose.yml changes first
2. Monitor for 48 hours
3. If stable, apply Prometheus retention changes
4. Monitor another 48 hours
5. If needed, apply Gunicorn optimizations
6. If still high, upgrade droplet size
