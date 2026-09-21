# NexCell DevOps Assessment

## ABOUT YOU

**Name / Time spent (minutes):**  
Akshay Nagaraj / ~195 minutes total. I spent about 150 minutes planning, implementing and testing the solution, then around 45 minutes on the AWS design, cost review and documentation.

**AI tools used, and one thing you changed or corrected from their output:**  
I used ChatGPT and Claude mainly to compare ideas and review my approach. I did not follow the suggestions directly; I checked the assessment requirements and researched the options before deciding what made sense for this setup.

---

## BUILD AND RUN

**What I delivered, and how to run and verify it (commands):**  
I created a small FastAPI service, a Redis worker, a PostgreSQL migration step, a production Docker image, Docker Compose setup, smoke tests and GitHub Actions CI/CD for ECS.

```bash
cp .env.example .env
docker compose up --build -d
docker compose ps -a
./smoke_test.sh
docker compose down -v
```

**Top 3 problems fixed in the starting Dockerfile, and why each matters:**  

1. I replaced `python:latest` with `python:3.11.9-slim-bookworm`. The slim image keeps the image smaller, and pinning the Python version avoids unexpected changes if `latest` moves to a newer release.
2. I removed the hard-coded secret and run the container as a non-root `appuser`. Secrets should not be stored inside source code or container images, and running as non-root reduces the impact if the container is compromised.
3. I used a pinned and hashed dependency lock file. This means the same dependency versions are installed each time. I also copy the lock file before the application code so Docker can reuse the dependency layer when the code changes.

**How dependencies are kept reproducible, and how migrations run safely on deploy:**  
`requirements.in` contains the direct dependencies and `requirements.lock` contains the resolved versions and hashes. During deployment, the same SHA-tagged image tested in CI is used for the migration task. The API and worker are updated only if the migration finishes successfully with exit code `0`.

---

## AWS DESIGN

**Target architecture in 3 to 5 lines:**  
I kept the existing AWS approach rather than redesigning the whole platform. The system stays in `eu-west-2` across two Availability Zones, with CloudFront in front of the Next.js frontend and an ALB sending traffic to ECS Fargate services in private subnets. The API and workers stay on Fargate, Redis remains on ElastiCache, and the vector DB/admin EC2 stay private. PostgreSQL remains outside AWS and is accessed securely over TLS through NAT egress.

**Networking and security: VPC and subnets, IAM, secrets, how CI authenticates to AWS:**  
The ALB and NAT Gateways are placed in public subnets, while ECS tasks, Redis, the vector DB and admin EC2 remain private. Security groups restrict traffic so the application is not directly exposed. I would store production secrets in AWS Secrets Manager and use SSM Session Manager for admin access instead of public SSH. GitHub Actions uses OIDC to assume an AWS IAM role, so there is no need to keep long-lived AWS access keys in GitHub.

**Deploying without downtime, and how you would roll back:**  
I use a normal ECS rolling deployment because it is simple and fits the scope of this task. The migration runs first, then the API and worker services are updated only if it succeeds. `minimumHealthyPercent=100` keeps the existing healthy tasks running while replacements start, and the ECS deployment circuit breaker can roll back to the previous task definition if the new deployment becomes unhealthy.

**Monitoring: the three alarms you would add first, with thresholds:**  
These would be my starting thresholds and I would tune them after seeing real production behaviour:

1. API 5xx error rate above **2% for 5 minutes**.
2. API p95 response latency above **1 second for 5 minutes**.
3. Oldest queued job waiting for more than **60 seconds**.

CloudWatch alarms would notify the operations team through SNS.

---

## COST

**Top 3 savings: change, estimated £/month, and the risk each introduces:**  

1. **Staging: save ~£175/month (from £260 to ~£85)**  
   The staging environment is currently a full production copy running all day. I would reduce the number/size of staging resources and scale them down when the environment is not being used.  
   **Risk:** staging may not always be available immediately outside normal development hours.

2. **API and worker Fargate: save ~£150/month (from £400 to ~£250)**  
   The API currently runs 4 × `1 vCPU / 2 GB` tasks and workers run 2 × `2 vCPU / 4 GB`. Since average API CPU is only 12% and the queue is empty 70% of the time, I would test smaller tasks: `0.5 vCPU / 1 GB` for the API and `1 vCPU / 2 GB` for workers, then use autoscaling when load increases.  
   **Risk:** if the tasks are made too small, traffic spikes could increase latency or cause worker backlog, so I would validate this with load testing and CloudWatch metrics first.

3. **Redis: save ~£75/month (from £150 to ~£75, estimated)**  
   `cache.r6g.large` has about 13 GiB of memory, but the brief says only 8% is being used, which is roughly 1 GiB. I would test a smaller node such as `cache.m6g.large` and check CPU, memory, latency, evictions and queue backlog before changing production.  
   **Risk:** a smaller node gives less headroom during sudden traffic spikes.

**Additional estimated savings:**  

- **CloudWatch Logs: ~£65/month** — change normal production logging from DEBUG to INFO and use a 30-day retention period instead of keeping logs forever.
- **NAT Gateways: ~£55/month** — keep two NAT Gateways for availability, but reduce unnecessary NAT data processing by using suitable VPC endpoints where they are cheaper.
- **ECR:** add a lifecycle policy because the brief says there are around 400 old images. I have not included a separate saving because ECR is grouped with other services in the supplied bill.
- **Admin EC2:** I would not immediately resize or stop it. The brief does not give CPU or memory utilisation, so I would first check CloudWatch and Compute Optimizer and only change the instance size if the data shows it is oversized.

**New projected AWS total and cost per customer (show the sum):**

```text
Current AWS total:                         £1,415

Estimated savings:
Staging                                    -£175
API / worker Fargate                       -£150
Redis                                      -£75
CloudWatch Logs                            -£65
NAT optimisation                           -£55
                                           -----
Total estimated saving                     £520

Projected AWS total:
£1,415 - £520 = £895/month

Cost per customer:
£895 / 20 customers = £44.75/customer/month
```

This brings the estimate to **£44.75 per customer/month**, just below the £45 target. These are planning estimates based on the figures in the brief, so I would validate them with actual CloudWatch and Cost Explorer data before making production changes.

**One cost you would deliberately not cut, and how you would catch a cost spike early:**  
I would not reduce the £130/month vector database EC2 just to save money. It is already a single-instance dependency, so availability is a bigger concern than cost at this point. I would first add monitoring/backups and review an HA approach. I would also use AWS Budgets and Cost Anomaly Detection to catch unexpected increases in spend.

The £900/month LLM API bill is outside the AWS total. Since around 40% of messages are repeat FAQ-style questions, I would look at caching repeated responses and using smaller models for simpler requests.

---

## JUDGEMENT

**How this scales to 100 customers:**  
I would not assume that 5× more customers means 5× more infrastructure. Assuming the API remains stateless, ECS can add more API tasks when CPU or request load increases, while workers can scale based on queue backlog or how long jobs are waiting. I would also keep an eye on Redis, PostgreSQL connection limits and the vector database. The single vector EC2 is the main area I would review before the platform grows significantly.

**The biggest production risk in the current setup, and your first fix:**  
For me, the biggest immediate risk is the manual database migration process because the brief already says code and schema have been deployed in the wrong order before. My first fix is therefore to make migration part of the deployment pipeline: run one ECS migration task using the tested image, wait for exit code `0`, and only then update the API and worker services. If it fails, the existing services stay on the previous version.

**One thing kept intentionally simple, and what you would do with 3 more hours:**  
I kept deployment to a standard ECS rolling deployment instead of adding blue/green or canary deployment because I did not want to over-engineer the assessment. With three more hours I would add a proper staging promotion step using the same tested image, add container vulnerability scanning, and run post-deployment smoke/health checks so a bad release can be detected quickly and rolled back.
