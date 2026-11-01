
# ============================================================
# Docker-PHP - Redis Server
# Redis 7.4 Alpine
# ============================================================

FROM redis:7.4-alpine

LABEL maintainer="Docker-PHP"
LABEL description="Redis Server for Docker-PHP"

# Redis data directory
WORKDIR /data

# Redis service port
EXPOSE 6379

# Persistent data directory
VOLUME ["/data"]

# Start Redis with AOF persistence
CMD ["redis-server", \
     "--appendonly", "yes", \
     "--appendfsync", "everysec"]
