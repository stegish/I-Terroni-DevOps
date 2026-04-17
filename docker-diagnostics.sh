#!/bin/bash
# Diagnostic script for Docker Swarm memory issues
# Run this on your DigitalOcean droplet to identify memory bottlenecks

echo "=== Docker Swarm Health Check ==="
echo ""

# Check Swarm status
echo "1. Swarm Status:"
sudo docker info | grep -A2 "Swarm"
echo ""

# Check available memory
echo "2. System Memory:"
free -h
echo ""

# Check swap
echo "3. Swap Usage:"
swapon -s || echo "No swap configured"
echo ""

# Check Docker disk usage
echo "4. Docker Storage:"
sudo docker system df
echo ""

# Real-time container memory usage
echo "5. Container Memory Usage:"
sudo docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}" | head -20
echo ""

# Check service status
echo "6. Service Status:"
sudo docker service ls
echo ""

# Detailed service replicas
echo "7. Service Replicas:"
sudo docker service ps minitwit_stack_minitwit 2>/dev/null || echo "Stack not deployed yet"
echo ""

# Check for restarting containers
echo "8. Recently Restarted Containers:"
sudo docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -i "restarting\|exited"
echo ""

# Check logs for OOM errors
echo "9. Out-of-Memory Errors in Last Hour:"
sudo journalctl --since "1 hour ago" | grep -i "OOMKilled\|oom\|memory" || echo "No OOM events found"
echo ""

# DNS resolution test
echo "10. DNS Resolution Test:"
sudo docker run --rm busybox nslookup docker.com | head -5
echo ""

echo "=== Diagnostics Complete ==="
echo ""
echo "Recommendations:"
echo "- If memory > 85%, reduce minitwit replicas or monitoring overhead"
echo "- If containers keep restarting, check resource limits"
echo "- If DNS fails, restart dockerd: sudo systemctl restart docker"
