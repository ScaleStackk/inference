# QuestaCase inference infrastructure

Infrastructure definitions for the distributed QuestaCase demonstration.

- `aws/` creates the phase-one AWS upload and messaging infrastructure.
- `inference/` builds and runs Ollama inference nodes and the HAProxy inference
  load balancer.

The distributed inference CloudFormation template defaults to a `g6.xlarge`
node using AWS's GPU-optimized Amazon Linux 2023 AMI. Its NVIDIA-enabled Compose
override gives the Ollama container access to the host GPU and publishes port
`11434` through a configurable security-group CIDR for the POC.

The inference nodes may run on separate EC2 instances. Only the load balancer is
joined to the Web API's Docker network; it reaches inference nodes through their
private VPC addresses.
