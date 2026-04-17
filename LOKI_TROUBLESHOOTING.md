# Loki Troubleshooting Guide

## Error 500 Analysis

### Common Causes of Loki Error 500

| Error | Cause | Solution |
|-------|-------|----------|
| **Connection refused** | Loki service not running | Ensure Loki is in `docker service ls` |
| **Invalid config** | Bad YAML in loki-local-config.yaml | Validate YAML syntax |
| **Out of memory** | Loki exceeded memory limit | Increase limits or reduce retention |
| **Invalid request** | Promtail sending bad log format | Check promtail-config.yml |
| **Disk full** | No space for log chunks | Clean `/loki/chunks` directory |

---

## Quick Diagnostics (on DigitalOcean droplet)

### 1. Check if Loki is running:
```bash
sudo docker service ls | grep loki
sudo docker service ps minitwit_stack_loki
```

### 2. Check Loki logs for errors:
```bash
# Find Loki container ID
sudo docker ps | grep loki

# View logs
sudo docker logs <container_id> --tail 50

# Follow logs in real-time
sudo docker logs <container_id> -f
```

### 3. Test Loki connectivity:
```bash
# From inside a container
sudo docker exec <any_container> curl -v http://loki:3100/loki/api/v1/push

# Expected: 204 No Content (or 400 Bad Request, but NOT 500)
```

### 4. Check Promtail logs for connection errors:
```bash
sudo docker ps | grep promtail
sudo docker logs <promtail_container_id> --tail 100 -f
```

### 5. Monitor Loki memory:
```bash
sudo docker stats --no-stream minitwit_stack_loki
```

---

## Configuration Issues

### Issue 1: Invalid YAML in loki-local-config.yaml

**Symptoms:** Loki crashes immediately or returns 500 on every request

**Fix:** Validate the config file locally:
```bash
# Download the file and check syntax
# Or check Docker logs for YAML parse errors
```

**Key settings to watch:**
```yaml
auth_enabled: false              # Must be false unless you setup auth
ingestion_rate_mb: 3             # Low for 1GB droplet - don't increase
ingestion_burst_size_mb: 5       # Allow brief spikes
reject_old_samples_max_age: 168h # 7 days - don't set higher
```

---

### Issue 2: Promtail not connecting to Loki

**Symptoms:** Promtail keeps restarting or shows connection errors in logs

**Current configuration in `logging/promtail-config.yml`:**
```yaml
clients:
  - url: http://loki:3100/loki/api/v1/push
```

**Troubleshoot:**
1. Verify DNS resolution inside Promtail:
```bash
sudo docker exec <promtail_container> nslookup loki
```

2. Verify Loki is listening:
```bash
sudo docker exec <loki_container> netstat -tlnp | grep 3100
```

3. If DNS fails, use IP instead:
   - Get Loki container IP: `sudo docker inspect <loki_container> | grep IPAddress`
   - Update promtail-config.yml to use IP

---

### Issue 3: High Memory Usage (Loki consuming >100MB)

**Symptoms:** `docker stats` shows Loki near memory limit

**Causes:**
1. Too many log streams (each unique label combination = 1 stream)
2. Too much sample data buffered
3. Old chunks not being cleaned up

**Solutions:**

**A) Reduce ingestion rate:**
```yaml
# In loki-local-config.yaml
limits_config:
  ingestion_rate_mb: 2        # Reduce from 3
  ingestion_burst_size_mb: 3  # Reduce from 5
```

**B) Reduce max streams:**
```yaml
limits_config:
  max_streams_per_user: 5000      # Reduce from 10000
  max_global_streams_per_user: 5000
```

**C) Simplify Promtail labels (reduce cardinality):**

In `logging/promtail-config.yml`, only keep essential labels:
```yaml
scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      # Only keep container name (not image, network, etc.)
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      # Add service name
      - source_labels: ['__meta_docker_service_name']
        target_label: 'service'
      # DROP everything else to reduce cardinality
      - source_labels: ['__meta_docker_port_private']
        action: drop
```

---

### Issue 4: 500 Errors from Promtail

**Symptoms:** Promtail logs show "got 500 response code" or "server error"

**Causes:**
1. Loki crashed or restarted
2. Loki overloaded (too many log entries at once)
3. Invalid log format from Promtail

**Fixes:**

**Check Loki is healthy:**
```bash
sudo docker exec <loki_container> curl -s http://localhost:3100/loki/ready
# Should return: ready
```

**Reduce log volume:**
```yaml
# In promtail-config.yml, skip some noisy services
relabel_configs:
  # Skip Docker daemon logs
  - source_labels: ['__meta_docker_container_name']
    regex: 'dockerd'
    action: drop
  # Skip node-exporter logs
  - source_labels: ['__meta_docker_service_name']
    regex: 'node.*exporter'
    action: drop
```

**Increase Loki resources:**
If Promtail is sending legitimate logs but Loki can't handle it:
```yaml
# In docker-compose.yml
  loki:
    deploy:
      resources:
        limits:
          memory: 150M           # Increase from 100M
```

---

## Verify the Fix

After making changes, restart the stack:

```bash
# SSH to droplet
vagrant ssh

# Pull latest
sudo docker compose pull

# Redeploy
sudo docker stack deploy -c docker-compose.yml minitwit_stack

# Monitor status
watch -n 5 'sudo docker service ps minitwit_stack_loki'
watch -n 5 'sudo docker service ps minitwit_stack_promtail'
```

---

## Query Loki Logs

### Via CLI:
```bash
# SSH to droplet, then:
curl -G -s 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query={service="minitwit"}' | jq .
```

### Via Grafana:
1. Open http://your-droplet-ip:3000
2. Create new panel
3. Set datasource to "Loki"
4. Use LogQL query: `{service="minitwit"}`

---

## Memory Budget with Loki

| Service | Memory Limit | Reserved |
|---------|--------------|----------|
| Minitwit (2x) | 256MB | 256MB |
| Prometheus | 200MB | 100MB |
| Grafana | 200MB | 100MB |
| **Loki** | **100MB** | **64MB** |
| Monitoring agents | 128MB | 96MB |
| System/Docker | - | ~300MB |
| **TOTAL** | - | **916MB** ⚠️ Close to limit |

**Warning:** With Loki, you're at ~75% memory reservation. Monitor closely!

If memory issues persist, consider:
1. Removing Loki and using only Prometheus
2. Upgrading to 2GB droplet
3. Using managed Grafana Cloud instead

---

## Alternative: Disable Loki (Keep Only Promtail)

If you want to keep logging without Loki overhead:

**Option A: Send logs to stdout only**
```yaml
# In docker-compose.yml, update promtail to not push anywhere
promtail:
  # Remove clients section entirely
  # This makes Promtail a no-op, but keeps infrastructure ready
```

**Option B: Send logs to external service (ELK Stack)**
```yaml
clients:
  - url: https://your-elasticsearch.example.com/api/logs
    headers:
      Authorization: Bearer YOUR_TOKEN
```

**Option C: Remove Promtail entirely**
```bash
# Just don't include promtail service in docker-compose.yml
# Docker daemon auto-logs to `docker logs` without it
```

---

## Next Steps

1. Verify Loki is running: `docker service ps minitwit_stack_loki`
2. Check for connection errors: `docker logs <loki_container>`
3. Monitor memory: `docker stats minitwit_stack_loki`
4. Test from Grafana: Create a panel with LogQL query
5. If still seeing errors, enable verbose logging:
   ```yaml
   # Add to loki-local-config.yaml
   server:
     log_level: debug
   ```
