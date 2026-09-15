# Worker 3

Target: cluster-a-worker-3.agents-anywhere.com (192.168.1.37), 8 vCPUs and 16 GiB RAM.
Reuse the verified worker-1 image agents-anywhere:cluster-a-c4be624b,
sha256:889e0809bc057de3010e3d85348a80235ad8f52268af77051ece56f8e2b26557.

Apply compose.worker-3.yml over compose.yml. This starts eight FastAPI processes,
with event subprocess pools disabled as on workers 1 and 2. The container may use
all eight CPUs and up to 12 GiB RAM. HTTP remains on 127.0.0.1:8000 for the existing
host proxy. Ingress and DNS are managed separately by the user.

Copy the protected production .env directly from worker 1 and replace its instance
ID with cluster-a-worker-3. Never commit credentials. Use the same PostgreSQL,
Redis, signing secret, public origin, and object storage configuration.
No database migration is needed for this unchanged application image.

The new node permits up to 80 PostgreSQL connections (8 times a 5+5 pool), bringing
the three application nodes to at most 140 against the previously recorded 300
server limit. Validate current database capacity and readiness before handoff.

Deployment verified on 2026-09-15 at 12:00-12:02 Asia/Shanghai:

- Image ID matches the running worker-1 image exactly.
- Container healthy, zero restarts, and all eight distinct worker instance IDs
  returned ready with PostgreSQL schema 2.35 and Redis OK.
- Public HTTPS homepage and readiness both returned HTTP 200; readiness identified
  worker 3. Workers 1 and 2 ingress independently returned HTTP 200.
- Confirmed Docker limit: 8 CPUs, 12 GiB memory, loopback port 8000.
- Initial traffic snapshot: 124.58% Docker CPU (about 1.25 cores), 1.339 GiB memory.
  This is a point-in-time observation, not a benchmark.

During preparation, public DNS already resolved to worker 3 before the application
was started. Its OpenResty logs showed upstream connection refused on port 8000,
causing public 502 responses. Starting the worker restored the public checks.
No DNS, ingress, or existing application-node configuration was changed.

Remote deployment directory:
/root/code/github/Agents-Anywhere-releases/c4be624b/docker/cluster-a

Run from that directory:

```sh
docker compose -f compose.yml -f compose.worker-3.yml ps
docker compose -f compose.yml -f compose.worker-3.yml logs --tail 100 server
docker stats agents-anywhere-cluster-a-server-1
```

