# Docker Swarm Memory Optimization

## Problem Analysis
Your DigitalOcean droplet (1 vCPU, 1GB RAM) experienced memory spike from 66% → 90% due to:

1. **No resource limits** - Every container could consume unlimited memory
2. **Too many replicas** - 3 minitwit instances on 1GB is excessive
3. **Heavy monitoring stack** - Prometheus + Grafana + Loki consuming precious RAM
4. **Promtail global mode** - Can cause memory leaks with Docker socket logging

---

## Changes Made to `docker-compose.yml`

### 1. Reduced Minitwit Replicas: 3 → 2
```yaml
deploy:
  replicas: 2  # Was 3
```
**Why:** 2 replicas still provide redundancy but use ~33% less memory. For a 1GB droplet, this is critical.

---

### 2. Added Memory Limits to ALL Services

#### Minitwit (Core App)
```yaml
resources:
  limits:
    cpus: '0.4'        # Max 40% of 1 vCPU
    memory: 256M       # Max 256MB per instance
  reservations:
    cpus: '0.25'       # Guaranteed 25%
    memory: 128M       # Guaranteed 128MB per instance
```

#### Flagtool
```yaml
resources:
  limits:
    cpus: '0.2'
    memory: 128M
  reservations:
    cpus: '0.1'
    memory: 64M
```

#### Prometheus
```yaml
resources:
  limits:
    cpus: '0.3'
    memory: 200M       # Time-series DB needs reasonable memory
  reservations:
    cpus: '0.15'
    memory: 100M
```

#### Grafana
```yaml
resources:
  limits:
    cpus: '0.3'
    memory: 200M
  reservations:
    cpus: '0.15'
    memory: 100M
```

#### Node Exporter
```yaml
resources:
  limits:
    cpus: '0.1'
    memory: 64M        # Lightweight monitoring
  reservations:
    cpus: '0.05'
    memory: 32M
```

#### Promtail
```yaml
resources:
  limits:
    cpus: '0.1'
    memory: 64M        # Prevent log backpressure
  reservations:
    cpus: '0.05'
    memory: 32M
```

---

### 3. Removed Loki Service
**Why:** Loki (log aggregation) was unused and consuming memory. Promtail still ships logs to Grafana.

---

## Memory Budget Calculation (1GB = ~950MB usable)

| Service | Instances | Limit | Reserved | Notes |
|---------|-----------|-------|----------|-------|
| Minitwit | 2 | 512MB | 256MB | Core workload |
| Prometheus | 1 | 200MB | 100MB | Metrics DB |
| Grafana | 1 | 200MB | 100MB | Dashboard UI |
| Flagtool | 1 | 128MB | 64MB | Flag service |
| Node-exporter | 1 | 64MB | 32MB | System metrics |
| Promtail | 1 | 64MB | 32MB | Log shipping |
| **Docker daemon & OS** | - | - | ~300MB | System overhead |
| **TOTAL RESERVED** | - | - | **~884MB** | Safe headroom |

---

## Deployment

### 1. Pull the latest images:
```bash
source .env
sudo docker compose pull
```

### 2. Redeploy the stack:
```bash
sudo docker stack deploy -c docker-compose.yml minitwit_stack
```

### 3. Monitor memory usage:
```bash
# SSH to droplet
vagrant ssh

# Check overall memory
free -h

# Monitor Docker containers
docker stats --no-stream

# Monitor Swarm services
docker service ls
docker service ps minitwit_stack_minitwit
```

---

## What These Settings Do

**`resources.limits`**: Hard cap - container is killed if it exceeds the limit  
**`resources.reservations`**: Soft cap - Docker tries to guarantee this memory, but won't kill on overflow

For a 1GB droplet, **reservations** should sum to ~80-85% of available RAM, leaving headroom for kernel and spikes.

---

## Expected Improvements

✅ Memory won't spike above 85% under normal load  
✅ If one service has a leak, others won't crash (resource isolation)  
✅ Load balancing across 2 minitwit instances (still redundant)  
✅ Prometheus pre-configured with adequate memory (common bottleneck)

---

## If Memory is Still High (>85%)

1. **Check which service is consuming most:**
   ```bash
   docker stats --format "table {{.Container}}\t{{.MemUsage}}"
   ```

2. **Check for memory leaks in minitwit app:**
   - Review database connections in `db.py`
   - Check for unbounded caches in `models.py`
   - Ensure SQLAlchemy connection pooling: `pool_size=5, max_overflow=10`

3. **Reduce Prometheus retention (if old data piling up):**
   ```yaml
   prometheus:
     command: --storage.tsdb.retention.time=7d  # Default is 15d
   ```

4. **Switch to lightweight Prometheus if needed:**
   ```yaml
   image: prom/prometheus:v2.40-alpine  # Instead of latest
   ```

---

## Next Steps

1. Commit these changes to git
2. Redeploy using `./deploy.sh`
3. Monitor memory for 24-48 hours
4. If issues persist, enable verbose logging to track the culprit
