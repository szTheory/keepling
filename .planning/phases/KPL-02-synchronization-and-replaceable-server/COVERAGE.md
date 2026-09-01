# API Coverage — Phase 2 infrastructure providers

> Full coverage by default. Opt-outs are explicit, reasoned decisions. Keepling does not call these APIs from product code; OpenTofu, pgBackRest/S3-compatible clients, and the selected DNS adapter own the outward integrations.

| capability | decision | reason |
|---|---|---|
| Hetzner server create/read/update/delete | INTEGRATE | Required for source-driven host provisioning and replacement. |
| Hetzner SSH-key create/read/delete | INTEGRATE | Required to bootstrap and recover a fresh host without snowflake access. |
| Hetzner firewall create/read/update/delete and server attachment | INTEGRATE | Required to expose only 80/443 and administrative access while keeping PostgreSQL private. |
| Hetzner private network/subnet create/read/update/delete and server attachment | INTEGRATE | Required for the declared host/network topology. |
| Hetzner image, location, and server-type discovery | INTEGRATE | Required to validate immutable inputs and measured placement. |
| Hetzner HA and multi-node resources | OPT-OUT | Load balancers, failover IPs, placement groups, and multi-node topology are explicitly outside Phase 2. |
| S3-compatible encrypted object put/get/list/head/delete | INTEGRATE | Required for pgBackRest repositories, logical generations, manifests, and restore selection. |
| S3-compatible object versioning and object-lock retention | INTEGRATE | Required by the locked off-host recovery policy. |
| S3-compatible cross-account/provider mirror copy and verification | INTEGRATE | Required for the independent daily recovery mirror. |
| Object-store public access or application-container credentials | OPT-OUT | Recovery objects remain private and backup/restore credentials are host-owned and least privilege. |
| DNS record read, staged update, propagation check, and rollback | INTEGRATE | Required for the complete host-replacement and DNS rehearsal. |
| DNS zone registration, billing, email, analytics, and traffic steering | OPT-OUT | Phase 2 changes one existing service record and does not own registrar or advanced traffic-management capabilities. |
