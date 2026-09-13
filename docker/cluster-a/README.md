# Cluster A

Two identical Docker workers expose HTTP port 8000, including the static Web UI,
API and WebSockets. Each runs three FastAPI processes. PostgreSQL and Redis run
on 192.168.1.35 and accept LAN traffic only. Both workers must share their database,
Redis, token secret and S3 configuration; instance IDs differ by node.

The six application processes allow at most 60 pooled PostgreSQL connections in
total (5 persistent + 5 overflow per process), leaving room under the current
100-connection server limit. Redis requires AOF with appendfsync everysec and
maxmemory-policy noeviction because it buffers accepted Timeline writes.

Build one image from a committed release and distribute that exact image to both
workers. Keep the checkout under /root/code/github/Agents-Anywhere on each node.
Copy .env.example to .env, fill credentials, and chmod 600 .env. Never commit it.
Run commands in this directory:

```sh
docker compose --profile migration run --rm migrate
docker compose up -d server
docker compose ps
curl -f http://127.0.0.1:8000/api/v2/health/ready
```

Run the migration once before starting either worker on a fresh database. For
updates, follow docs/upgrading.md; do not mix incompatible writer versions.

Use the public S3 endpoint with virtual host addressing: attachment open URLs
are presigned using the configured endpoint and must be reachable by browsers.
No public origin is configured until the external routing domain is chosen.
DNS distribution alone does not provide an HTTP health-checking load balancer.

The HTTP port is intended for the separately managed TLS ingress. After ingress
is ready, restrict direct access to that ingress if required by the deployment.
