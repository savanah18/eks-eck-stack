Nodes and shards are what make Elasticsearch distributed and scalable. These concepts aren’t essential if you’re just getting started. How you deploy Elasticsearch in production determines what you need to know:

- Self-managed Elasticsearch: You are responsible for setting up and managing clusters, nodes, shards, and replicas. This includes managing the underlying infrastructure, scaling, and ensuring high availability through failover and backup strategies.
- Managed deployments: This includes deployments on ECH, ECE, and ECK. Elastic can autoscale resources in response to workload changes. Choose from different deployment types to apply sensible defaults for your use case. A basic understanding of nodes, shards, and replicas is still important.
- Elastic Cloud Serverless: You don’t need to worry about nodes, shards, or replicas. These resources are 100% automated on the serverless platform, which is designed to scale with your workload.

**Decision**
- opt for managed deployments using Elastic Cloud on Kubernetes (ECK)
- operator pattern
- mode: Cluster-wide Installation (vs Namespace-restricted installation)
- Install ECK using helm chart (vs YAML manifests)

