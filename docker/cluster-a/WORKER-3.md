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

Deployment status: prepared; runtime validation pending.
