#!/bin/bash
# Deep memory diagnostics for Docker Swarm
# Run this on your DigitalOcean droplet after deployment

echo "=========================================="
echo "DOCKER SWARM MEMORY DIAGNOSTICS"
echo "=========================================="
echo ""

echo "1. VERIFY DEPLOYMENT HAS NEW CONFIG:"
echo "---"
# Check if memory limits are set (should see "256M" for minitwit)
sudo docker service inspect minitwit_stack_minitwit 2>/dev/null | grep -A 10 "MemoryLimit" || echo "❌ Service not found or no limits set"
echo ""

echo "2. SYSTEM MEMORY USAGE:"
echo "---"
free -h
echo ""

echo "3. DOCKER MEMORY STATS (Top consumers):"
echo "---"
sudo docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}" | sort -k2 -hr | head -15
echo ""

echo "4. INDIVIDUAL SERVICE MEMORY:"
echo "---"
for service in minitwit flagtool prometheus grafana loki node-exporter promtail; do
    container_id=$(sudo docker ps --filter "label=com.docker.swarm.service.name=minitwit_stack_$service" -q | head -1)
    if [ -n "$container_id" ]; then
        mem=$(sudo docker inspect $container_id --format='{{.State.Pid}}' | xargs -I {} cat /proc/{}/status 2>/dev/null | grep VmRSS | awk '{print $2}')
        if [ -n "$mem" ]; then
            mem_mb=$((mem / 1024))
            echo "$service: ${mem_mb}MB"
        fi
    fi
done
echo ""

echo "5. DOCKER DAEMON MEMORY:"
echo "---"
sudo ps aux | grep dockerd | grep -v grep | awk '{print "Docker daemon: " $6 " KB (" $6/1024 " MB)"}'
echo ""

echo "6. VERIFY RESOURCE LIMITS ARE ENFORCED:"
echo "---"
echo "Checking if docker-compose.yml limits are active..."
sudo docker service inspect minitwit_stack_minitwit 2>/dev/null | grep -E "MemoryLimit|MemoryReservation|CpuLimit|CpuReservation" || echo "❌ No resource limits found!"
echo ""

echo "7. CHECK FOR OOM EVENTS:"
echo "---"
sudo journalctl --since "1 hour ago" | grep -i "oom\|memory" | tail -5 || echo "No OOM events in last hour"
echo ""

echo "8. CONTAINER DISK USAGE (Logs, volumes, etc.):"
echo "---"
sudo docker system df
echo ""

echo "9. LOKI MEMORY & STATUS:"
echo "---"
loki_container=$(sudo docker ps --filter "label=com.docker.swarm.service.name=minitwit_stack_loki" -q | head -1)
if [ -n "$loki_container" ]; then
    echo "Loki container running: $loki_container"
    sudo docker stats $loki_container --no-stream
    echo ""
    echo "Loki chunks directory size:"
    sudo docker exec $loki_container du -sh /loki/chunks 2>/dev/null || echo "Could not access /loki/chunks"
else
    echo "❌ Loki container not running!"
fi
echo ""

echo "10. CHECK IF DOCKER-COMPOSE.YML WAS UPDATED:"
echo "---"
echo "Current docker-compose.yml has:"
sudo docker inspect minitwit_stack_minitwit 2>/dev/null | grep -c "MemoryLimit" && echo "✓ Memory limits configured" || echo "❌ NO memory limits found - update not deployed!"
echo ""

echo "11. PROMETHEUS DATA SIZE:"
echo "---"
prometheus_container=$(sudo docker ps --filter "label=com.docker.swarm.service.name=minitwit_stack_prometheus" -q | head -1)
if [ -n "$prometheus_container" ]; then
    sudo docker exec $prometheus_container du -sh /prometheus 2>/dev/null || echo "Could not measure prometheus storage"
fi
echo ""

echo "=========================================="
echo "TROUBLESHOOTING GUIDE:"
echo "=========================================="
echo ""
echo "If memory still > 85%:"
echo "1. Check step 6 - if NO limits shown, deployment didn't take effect:"
echo "   sudo docker stack rm minitwit_stack"
echo "   sudo docker stack deploy -c docker-compose.yml minitwit_stack"
echo ""
echo "2. If Loki is >100MB (step 9), reduce retention or remove it"
echo ""
echo "3. If Prometheus is >200MB (step 11), reduce retention:"
echo "   Update monitoring/prometheus.yml with:"
echo "   --storage.tsdb.retention.time=3d"
echo ""
echo "4. Check Minitwit memory (step 4):"
echo "   If >300MB, there's a memory leak in the app"
echo ""
