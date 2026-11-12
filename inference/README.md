# QuestaCase distributed inference

This directory creates two images:

1. `questacase-inference` runs Ollama with the selected Qwen model baked into the
   image.
2. `questacase-inference-lb` runs HAProxy on the Web API EC2 instance and routes
   requests to inference containers on separate EC2 instances.

The load balancer forwards Ollama API paths unchanged, including `/api/chat`,
`/api/generate`, and `/api/tags`. It uses `leastconn`, limits concurrent requests
per inference node, and removes unhealthy nodes after failed `/api/tags` checks.

## Network layout

```text
Web API container
  INFERENCE_API_URL=http://inference:11434
              |
              | Docker network: questacase
              v
HAProxy container on Web API EC2
              |
              | private traffic over VPC peering on TCP 11434
              +------> Ollama container on inference EC2 A
              +------> Ollama container on inference EC2 B
              +------> Ollama container on inference EC2 C
```

Docker networks exist only on one Docker host. Therefore the remote inference
containers are linked with their EC2 private IP addresses or private DNS names,
not with Docker container names.

## Inference nodes owned by different AWS accounts

Different IAM users in the same AWS account and VPC need no special networking.
If each participant uses a separate AWS account and VPC, create one VPC peering
connection from the Web API VPC to each inference VPC:

1. Give every VPC a unique, non-overlapping CIDR range. For example, use
   `10.10.0.0/16` for the Web API and `10.20.0.0/16`, `10.30.0.0/16`, and so on
   for inference participants.
2. The Web API account requests peering using the participant's AWS account ID,
   VPC ID, and Region.
3. The participant accepts the request in their account.
4. Add a route in the Web API subnet route table to the inference VPC CIDR through
   that peering connection.
5. Add the return route in the inference subnet route table to the Web API VPC
   CIDR through the same peering connection.
6. On the inference security group, allow TCP `11434` from the Web API security
   group. Cross-account security-group references work for same-Region peers; use
   the Web API VPC CIDR when the peer is in a different Region.
7. Put the inference instance's private IP in `INFERENCE_NODES` on the Web API
   machine.

VPC peering is not transitive: every inference VPC needs its own direct peering
connection to the Web API VPC. The inference VPCs do not need connections to one
another. Keep all demo instances in one Region when possible to reduce latency
and simplify security-group rules.

## Build without running

Copy this directory to the relevant machines or publish the resulting images to
an image registry. Building the inference image downloads the pinned Ollama image
and the configured model; it can take significant time and disk space.

```bash
cp .env.example .env
chmod 600 .env

./build.sh inference
./build.sh load-balancer
```

The default model is `qwen3:4b`. Change `OLLAMA_MODEL` and `INFERENCE_IMAGE`
together before building if a smaller model is required.

## Run each inference EC2 instance

On every inference EC2 instance:

```bash
./run-inference.sh
curl http://127.0.0.1:11434/api/tags
```

Use one security group for inference nodes. Allow inbound TCP `11434` from the
Web API EC2 security group only. Do not allow `0.0.0.0/0` and do not expose the
Ollama API through a public load balancer.

For the internet-facing POC stack, CloudFormation deliberately allows the
configured `InferenceIngressCidr` to reach port `11434`. Its default is
`0.0.0.0/0`. Ollama has no authentication on this endpoint, so use a narrower
CIDR such as the Web API node's public IP with `/32` whenever that address is
known, and delete the stack after the demonstration.

Record each instance's private address, for example:

```text
10.0.2.10:11434
10.0.3.10:11434
10.0.4.10:11434
```

## Run HAProxy on the Web API EC2 instance

Set the comma-separated private endpoints in `.env`:

```bash
INFERENCE_NODES=10.0.2.10:11434,10.0.3.10:11434,10.0.4.10:11434
```

Then run:

```bash
./run-load-balancer.sh
curl http://127.0.0.1:11435/api/tags
```

The script attaches HAProxy to the external `questacase` Docker network with the
DNS alias `inference`. The existing Web API default therefore works unchanged:

```bash
INFERENCE_API_URL=http://inference:11434
```

The host endpoint is bound to `127.0.0.1:11435` by default. It is intended for
diagnostics, not public exposure. HAProxy statistics are available only inside
the container network on port `8404` unless an operator explicitly publishes
that port.

## Add or remove an inference instance

1. Start or stop its inference container.
2. Update `INFERENCE_NODES` in the load balancer `.env`.
3. Run `./run-load-balancer.sh` again.

Compose recreates the load balancer with the new backend list. Existing Web API
configuration does not change. For automatic EC2 scaling later, replace the
static list with AWS Cloud Map service discovery or an internal AWS load
balancer.

## GPU execution

The base Compose definition remains usable for local CPU testing. Set
`INFERENCE_GPU_ENABLED=true` to add `compose.inference.gpu.yaml`, which reserves
one NVIDIA GPU for Ollama. `run-inference.sh` fails early if the host driver is
not visible through `nvidia-smi`.

The inference CloudFormation stack uses the latest AWS ECS-optimized Amazon
Linux 2023 GPU AMI. That AMI includes the NVIDIA kernel drivers and Docker GPU
runtime, so the container can use the GPU without installing a driver during
bootstrap.
