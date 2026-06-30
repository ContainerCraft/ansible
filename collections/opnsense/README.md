# containercraft.opnsense

A general-purpose Ansible collection that configures an [OPNsense](https://opnsense.org/)
edge router entirely through its REST API. It builds VLAN interfaces, a hardened
Unbound DNS resolver with DNSBL threat intelligence, Kea DHCP with per-subnet
security policy, a sequenced zone-to-zone firewall with savepoint rollback, and
CARP high availability — and it sequences those changes through a monotonic
migration model so a live network can be re-architected without an outage.

The collection ships reusable roles only. A companion *deploy* layer (an
inventory, a values file, and an executable entrypoint) turns those roles into a
running deployment. The two layers are kept strictly separate so the collection
stays publishable and reusable while each site's identity lives in its own deploy
tree.

---

## §0 — How to read this document

This document serves every reader from a first-time hobbyist to a collection
maintainer. It is ordered by **how often a section is revisited**, not by
difficulty: the material an operator returns to daily sits near the top, and the
deep, read-once architecture and contributor material sits lower.

```mermaid
graph TD
    A["§1-2 Orientation & Quickstart<br/>read once, but first"] --> B["§3-5 Mental models<br/>read early, then settle"]
    B --> C["§6-9 Operational reference<br/>revisited constantly"]
    C --> D["§10-12 Troubleshooting & runbooks<br/>revisited under pressure"]
    D --> E["§13-16 Architecture & internals<br/>read deeply, revisit when changing"]
    E --> F["§17-19 Contributing & appendices<br/>maintainer depth, occasional"]
    style C fill:#2d5016,color:#fff
    style D fill:#5c2d00,color:#fff
```

Each section opens at the lowest level of background it can and adds depth toward
the end. A reader can stop at the first heading that answers the question at hand.
Three callout markers flag content by audience:

> ⚠️ **Blast radius** — an operation that changes a live network; read before running.

> 💡 **Shortcut** — a faster or safer path for routine work.

> 🔬 **Deeper** — internals and rationale for maintainers and SMEs; skippable for operation.

### Where to start, by role

| Reader | Read first | Then | Reference |
|---|---|---|---|
| Hobbyist / student | §1, §2 | §3, §4 | §6, §7 |
| Intern / junior operator | §1–§4 | §7, §10, §11 | §6, §9 |
| Senior operator | §3–§5 | §8, §9, §11, §12 | §10, §19 |
| Staff / principal engineer | §5, §13, §14 | §15, §16 | §9, §17 |
| Maintainer / SME | §14–§17 | §18, §19 | all |

---

## §1 — What this is, and what it is not

### What it is

`containercraft.opnsense` automates an OPNsense firewall the way a person would
automate a cloud provider: by calling an API. Every change — a VLAN, a firewall
rule, a DHCP scope, a DNS hardening parameter — is an HTTP request to the
firewall's REST endpoint. There is no configuration file pushed to the box and,
with one deliberate exception, no SSH session. The firewall is treated as a
service with an API, and the roles are clients of that service.

The collection encodes four things that raw API calls do not:

- **A data model.** The network's shape — its zones, subnets, trunk ports, and
  inter-zone policy — is declared once as data. Roles render that data into API
  calls. No role contains a literal subnet, VLAN tag, or IP address.
- **A migration model.** Real edge routers are replaced while in service. A
  monotonic phase variable (`coexist → migrating → hardening → converged`) gates
  which services run where, so the existing LAN keeps working until clients have
  moved.
- **An idempotent, recoverable apply.** Re-running converges to the same state.
  Firewall changes are wrapped in a server-side savepoint that auto-reverts if
  connectivity is lost, so a bad rule cannot lock the operator out.
- **A hardened security posture.** The DNS resolver hides its identity and
  version, validates DNSSEC, enforces rebinding protection with private-address
  filtering, runs DNSBL threat intelligence feeds (Abuse.ch ThreatFox, Hagezi),
  sets the ACL default to refuse with explicit per-zone allows, and sizes caches
  for bare-metal performance. The DHCP server uses UDP sockets (pf-gated, not
  raw), disables option auto-collection to prevent HA race conditions, and applies
  per-subnet allocator, client-ID, and lifetime policies via the raw API. The
  firewall uses explicit sequence numbering, quick-match semantics, and includes
  DHCP server allow rules that are required when Kea's automatic firewall rules
  are disabled.

### What it is not

- It is **not** a replacement for OPNsense's own configuration. It manages the
  objects it creates (tagged with a managed-by marker) and leaves everything else
  alone.
- It is **not** a one-shot installer. It is designed to be run repeatedly, a
  little at a time, advancing through phases.
- It does **not** implement masquerade/outbound NAT. OPNsense's automatic
  outbound NAT already masquerades internal zones to the WAN address; the
  collection relies on that default rather than duplicating it (see §9.6 and §16).
- It does **not** set per-interface IP addresses on opt* interfaces. The OPNsense
  MVC API does not expose this; it is a manual step in the web UI between the
  VLAN creation phase and the DHCP activation phase.
- It is **not** tied to any one site. The collection is general-purpose; the
  example network used throughout this document belongs to a deploy layer, not to
  the collection.

---

## §2 — Quickstart

This section takes a reader from nothing to a safe, read-only dry run against a
firewall. It assumes the firewall is reachable and an operator account exists on
it.

### Prerequisites

- `ansible-core >= 2.17` and Python `>= 3.12` on the controller.
- Network reachability to the firewall's HTTPS API.
- An OPNsense user that can hold an API key. A dedicated service user is
  recommended over a human login.

### Five commands

```bash
# 1. Install this collection and its upstream dependency into a playbook-adjacent
#    collections/ directory (the deploy layer does this automatically; shown here
#    for a standalone install).
ansible-galaxy collection install -r requirements.yml -p collections

# 2. Provide credentials. The deploy layer reads them from the environment.
export OPNSENSE_FIREWALL=10.0.0.1
export OPNSENSE_API_KEY=...        # see §12 to mint these
export OPNSENSE_API_SECRET=...

# 3. Confirm the API answers and the key authenticates (read-only).
ansible-playbook site.yml --tags connect

# 4. Dry-run the whole configuration. Nothing is written; the would-change set
#    and per-object diffs are printed.
ansible-playbook site.yml --check --diff

# 5. Apply one concern at a time once the dry run looks correct.
ansible-playbook site.yml --tags dns
```

> 💡 In a configured deploy tree, the entrypoint replaces `ansible-playbook
> site.yml` with a single executable: `./stargate.yml --tags connect`. See §11.

> ⚠️ Command 5 writes to the firewall. Until an operator has read §4 (phases) and
> §11 (the iterative runbook), it is safest to stay on `--check` and `--tags
> connect`.

### What success looks like

`--tags connect` ends with `OPNsense API reachable at <address>` and
`failed=0`. If it does not, jump to §10.1.

---

## §3 — Mental model 1: an API-driven edge router

The single most important idea in this collection: **the firewall is configured
by calling its REST API, not by editing it.** Internalizing this explains the
structure of every role.

```mermaid
graph LR
    OP["Operator"] -->|ansible-playbook| C["Ansible controller<br/>(connection: local)"]
    C -->|HTTPS REST<br/>key + secret| FW["OPNsense API<br/>https://firewall/api/..."]
    FW --> CFG["config.xml<br/>(applied on reload)"]
    subgraph "controller side"
        C
    end
    subgraph "firewall side"
        FW
        CFG
    end
```

The controller runs the modules locally (`connection: local`) and each module
issues HTTPS requests to the firewall. The firewall validates, stores, and — on a
`reload` call — applies the change. This has several consequences that shape the
whole collection:

- **Authentication is an API key/secret pair**, sent on every request. There is
  no session, no SSH key, no password to the box for normal operation.
- **A change is two steps: configure, then reload.** Roles create or update many
  objects with `reload: false`, then issue a single `reload` per subsystem. This
  is faster and avoids partial-apply churn.
- **Most operations are check-mode safe.** Because they are API reads and writes,
  Ansible can predict and diff them without touching the box.
- **Connection resilience is built in.** The `module_defaults` block sets
  `api_timeout: 30` and `api_retries: 2`, tolerating up to two transient
  connection failures and a 30-second overall timeout per request.

### The one exception: bootstrap

A firewall configured through its API needs an API key before it can be
configured. Minting that first key writes `config.xml`, which is root-gated and
cannot be done through the API. Exactly one role — `opn_bootstrap_apikey` — breaks
the API-only rule: it connects over SSH, escalates to root, mints a key, and
writes it where the API-driven roles can read it. After bootstrap, everything
returns to the API model. This chicken-and-egg resolution is detailed in §12.

### The raw API extension pattern

Some OPNsense model fields are not exposed by the upstream `oxlorg.opnsense`
collection's typed modules. The collection reaches these fields through the
`oxlorg.opnsense.raw` module, which calls any OPNsense API endpoint directly.
This pattern is used for:

- Unbound hardening parameters at `unbound.advanced.*` (identity hiding, DNSSEC
  hardening, rebinding protection, cache sizing, DNSBL, ACL default action)
- Kea general settings at `dhcpv4.general.*` (socket retry configuration)
- Kea per-subnet settings at `dhcpv4/set_subnet/<uuid>` (allocator, client-ID
  matching, per-zone lease lifetimes)

> 🔬 **Deeper.** The collection consumes the `oxlorg.opnsense` collection for the
> actual API module implementations. `containercraft.opnsense` orchestrates;
> `oxlorg.opnsense` speaks the protocol. The boundary between them is described in
> §16, and it is the reason the roles can stay declarative.

---

## §4 — Mental model 2: the migration phases

An edge router is rarely built on a green field. It usually replaces an existing
router while the network stays up. The collection models this as a **monotonic
phase**, a single variable that advances in one direction and gates what each role
is allowed to do.

```mermaid
stateDiagram-v2
    [*] --> coexist
    coexist --> migrating
    migrating --> hardening
    hardening --> converged
    converged --> [*]

    coexist: coexist — new edge stands up beside the live LAN
    migrating: migrating — clients move; zone DHCP/DNS active
    hardening: hardening — posture tightened; HA prepared
    converged: converged — legacy edge services withdrawn
```

The phase is not a feature flag set; it is a promise about what the **existing
network** experiences at each step. The guiding rule is *never strand a client*.

| Phase | Legacy segment edge DHCP/DNS | New zones | Zone DHCP | HA | Decommission |
|---|---|---|---|---|---|
| `coexist` | untouched | created, no clients | off | off | off |
| `migrating` | still served | active | on | off | off |
| `hardening` | still served (fallback) | active | on | prepared | off |
| `converged` | withdrawn | active | on | active | on |

A phase resolves to a small set of capability booleans (defined in
`shared/netspec/phases.yml`), and roles gate their riskier tasks on those
booleans rather than checking the phase string directly:

```yaml
# shared/netspec/phases.yml (excerpt)
phase_defaults:
  coexist:
    zone_dhcp: false
    edge_serves_legacy_lan: true
    decommission_legacy: false
  converged:
    zone_dhcp: true
    edge_serves_legacy_lan: false
    decommission_legacy: true
```

> ⚠️ **Blast radius.** The phase is monotonic by intent. Advancing to `converged`
> instructs `opn_edge_decommission` to remove edge DHCP/DNS from the legacy
> segment. That role is additionally gated on measured evidence (zero active
> leases) so the withdrawal cannot strand a device that has not yet moved. See
> §9.8.

> 💡 The default phase is `coexist` — the safe, non-disruptive posture. A fresh
> run with no configuration touches no existing client traffic.

---

## §5 — Mental model 3: the collection / deploy boundary

The collection contains **reusable roles and nothing site-specific**. A separate
**deploy layer** supplies the site's identity — its inventory, its credentials,
its network data, and an executable entrypoint. Understanding this split explains
why the roles have no subnets in them and where an operator's own values belong.

```mermaid
graph TB
    subgraph "collections/opnsense — GENERAL PURPOSE (published)"
        R["roles/<br/>opn_connect, opn_system, opn_interfaces,<br/>opn_dns, opn_dhcp, opn_firewall,<br/>opn_ha, opn_edge_decommission,<br/>opn_bootstrap_apikey"]
        D["each role's defaults/main.yml<br/>(sane, generic, env-overridable)"]
        G["galaxy.yml, meta/runtime.yml,<br/>changelogs/"]
    end
    subgraph "deploy/opnsense — SITE SPECIFIC (private)"
        E["stargate.yml<br/>(executable entrypoint — box identity)"]
        S["site.yml<br/>(generic orchestration)"]
        V["vars/stargate_values.yml<br/>(this site's overrides)"]
        I["inventory/ + .envrc + ansible.cfg"]
    end
    N["shared/netspec/<br/>zones, phases, firewall_matrix<br/>(network data)"]

    E --> S
    S --> R
    V -.overrides.-> D
    S -.loads.-> N
```

| Layer | Lives in | Contains | Site identity? |
|---|---|---|---|
| **Collection** | `collections/opnsense/` | reusable roles, defaults, galaxy metadata | none |
| **Deploy** | `deploy/opnsense/` | entrypoint, inventory, values, env | confined here |
| **Network data** | `shared/netspec/` | zones, phases, firewall matrix | site topology as data |

The boundary is enforced by a single discipline: **every variable a role needs has
a default inside that role.** A consumer can install the collection from a galaxy
server and run its roles with sane defaults, overriding through the environment or
playbook variables. The example deployment in this repository is one such
consumer; it is not part of the published collection.

---

## §6 — Command reference

The commands below assume a configured deploy tree. In a deploy tree the
executable entrypoint (`./stargate.yml`) is equivalent to `ansible-playbook
site.yml` with the site's values pre-selected; both forms are shown where they
differ.

### Everyday commands

| Goal | Command |
|---|---|
| Confirm API + credentials (read-only) | `./stargate.yml --tags connect` |
| Dry-run everything with diffs | `./stargate.yml --check --diff` |
| Apply one concern | `./stargate.yml --tags <tag>` |
| Apply everything | `./stargate.yml` |
| List the tasks a run would execute | `./stargate.yml --list-tasks` |
| Syntax check only | `./stargate.yml --syntax-check` |

### Tags

Each role contributes one or more tags so a run can be scoped to a single
concern. Tags compose; `--tags dns,dhcp` runs both.

| Tag | Role | Effect |
|---|---|---|
| `connect` | opn_connect | read-only API reachability probe |
| `system` | opn_system | CARP tunables and (gated) identity/WAN |
| `interfaces`, `vlans` | opn_interfaces | trunk VLANs, blackhole VLAN, assignment |
| `dns`, `unbound` | opn_dns | hardened Unbound, DNSBL, ACLs, split-horizon forward |
| `dhcp`, `kea` | opn_dhcp | Kea DHCP per zone with per-subnet hardening |
| `firewall`, `nat` | opn_firewall | sequenced aliases and zone rules with DHCP allow |
| `ha` | opn_ha | CARP VIPs, hasync (pfsync v1400), config sync trigger (gated) |
| `decommission` | opn_edge_decommission | legacy-segment withdrawal (gated) |

### Bootstrap (separate playbook)

```bash
# Mint an API key over SSH as root, write it to the deployment's .env.
ansible-playbook bootstrap.yml \
  -i inventory/bootstrap.yml \
  -e ansible_user=<wheel-user> \
  -e opn_bootstrap_apikey_user=<api-key-user> \
  --ask-pass --ask-become-pass

# Rotate an existing key (mints new, deletes prior keys for the user).
ansible-playbook bootstrap.yml \
  -i inventory/bootstrap.yml \
  -e ansible_user=<wheel-user> \
  -e opn_bootstrap_apikey_user=<api-key-user> \
  -e opn_bootstrap_apikey_force=true \
  --ask-pass --ask-become-pass
```

> 💡 `--check` and `--tags connect` never write to the firewall and are safe to
> run at any time. They are the two commands an operator runs most.

---

## §7 — Configuration reference

Configuration flows from three sources, lowest precedence first: role defaults
(generic), then the environment and the deployment's values file (site-specific),
then command-line `-e` overrides (one-off). Secrets always come from the
environment, never from a committed file.

### Connection (consumed by every role)

| Variable | Environment | Default | Purpose |
|---|---|---|---|
| `opnsense_firewall_address` | `OPNSENSE_FIREWALL` | empty | API host/IP |
| `opnsense_api_key` | `OPNSENSE_API_KEY` | empty | API key |
| `opnsense_api_secret` | `OPNSENSE_API_SECRET` | empty | API secret |
| `opnsense_api_port` | `OPNSENSE_API_PORT` | `443` | API port |
| `opnsense_ssl_verify` | `OPNSENSE_SSL_VERIFY` | `false` | validate TLS cert |
| `opnsense_api_timeout` | — | `30` | request timeout (seconds) |
| `opnsense_api_retries` | — | `2` | retry count on transient errors |

`opnsense_api_args` is a convenience mapping of the connection values, used by
tasks that call modules outside the credential-injecting action group (the `raw`
module and `ansible.builtin.uri`).

### Posture and marking

| Variable | Environment | Default | Purpose |
|---|---|---|---|
| `network_phase` | `OPNSENSE_NETWORK_PHASE` | `coexist` | migration phase |
| `opnsense_managed_tag` | `OPNSENSE_MANAGED_TAG` | `ansible-managed` | description prefix on managed objects; also the idempotency key |
| `opnsense_reload` | — | `false` | per-object reload discipline |

### System tunables (`opn_system`)

| Variable | Default | Purpose |
|---|---|---|
| `opnsense_apply_identity` | `false` | run the initialsetup wizard (off by default) |
| `opnsense_hostname` | `opnsense` | hostname |
| `opnsense_domain` | `home.arpa` | domain |
| `opnsense_timezone` | `UTC` | timezone |
| `opnsense_wan_ipv4_type` | `dhcp` | `dhcp` \| `static` \| `pppoe` |
| `opnsense_wan_block_private` | `true` | block RFC1918 on WAN |
| `opnsense_wan_block_bogons` | `true` | block bogons on WAN |
| `opnsense_tunables` | CARP hardening | sysctl name→value map |

The default tunables configure CARP HA observability:
`net.inet.carp.senderr_demotion_factor: 240` (demote master on NIC send errors)
and `net.inet.carp.log: 2` (log state transitions). IPv4/IPv6 forwarding is
already enabled by OPNsense default and is not configured explicitly.

> ⚠️ **Blast radius.** `opnsense_apply_identity: true` runs OPNsense's
> first-boot wizard, which is the only API path to WAN configuration in current
> releases and re-applies the wizard's settings. Enable it deliberately and
> confirm the WAN settings match the upstream link first.

### DNS hardening (`opn_dns`)

| Variable | Default | Purpose |
|---|---|---|
| `opnsense_dns_hardening` | (dict) | Unbound `advanced.*` settings via raw API |
| `opnsense_dns_acl_default_action` | `refuse` | ACL default for unknown sources |
| `opnsense_dns_acls` | per-zone allow | explicit ACL entries |
| `opnsense_dns_dnsbl_enabled` | `true` | enable DNSBL threat feeds |
| `opnsense_dns_dnsbl_type` | `[atf, hgz011]` | Abuse.ch ThreatFox + Hagezi TI |
| `opnsense_dns_cache` | (dict) | cache sizing for bare metal |

The hardening dict sets identity hiding (`hideidentity`, `hideversion`), DNSSEC
enforcement (`dnssecstripped`, `belownxdomain`), cache poisoning resistance
(`aggressivensec`, `unwantedreplythreshold: 10000000`), privacy
(`qnameminstrict: 0`), rebinding protection (`privateaddress` with full RFC 1918
+ special-use ranges, `privatedomain: home.arpa`), DNSSEC bypass for the
internal zone (`insecuredomain: home.arpa`), and observability
(`extendedstatistics`, `logservfail`, `valloglevel: 1`).

The cache dict sizes `msgcachesize: 256m`, `rrsetcachesize: 512m`,
`outgoingrange: 8192`, `numqueriesperthread: 4096`, `infracachenumhosts: 20000`.

### DHCP (`opn_dhcp`)

| Variable | Default | Purpose |
|---|---|---|
| `opnsense_enforce_dnsmasq_disabled` | `false` | disable default Dnsmasq DHCP before enabling Kea |
| `opnsense_dhcp_socket_type` | `udp` | UDP sockets (pf-gated); `raw` bypasses pf |
| `opnsense_dhcp_general_hardening` | (dict) | Kea general settings via raw API |
| `opnsense_dhcp_subnet_overrides` | (dict per zone) | per-subnet allocator, client-ID, lifetime |

The general hardening sets `service_sockets_max_retries: 5` and
`service_sockets_retry_wait_time: 5000` so Kea retries interface binding on
startup rather than silently failing.

The subnet overrides configure per-zone policies:

| Zone | `allocator` | `match-client-id` | `valid_lifetime` |
|---|---|---|---|
| mgmt | `random` | `1` (true) | `7200` (2h) |
| iot | `random` | `0` (false) | `3600` (1h) |
| dmz | `random` | `1` (true) | `3600` (1h) |

`allocator: random` prevents predictable address assignment.
`match-client-id: 0` on the IoT subnet uses MAC-based identification because
IoT devices frequently generate unstable client IDs. Shorter lifetimes on IoT
and DMZ reduce the window for stale address assignments after device removal.

All subnets use `auto_options: false` with explicit `gateway`, `dns`, and
`domain` values. This prevents the ordering race condition where Kea
auto-collects router/DNS options from an interface that does not yet have an IP
assigned, and prevents HA failover from auto-collecting the backup node's
physical IP instead of the CARP VIP.

### Interfaces (`opn_interfaces`)

| Variable | Default | Purpose |
|---|---|---|
| `opnsense_prepare_trunk_ports` | `false` | remove trunk parents from an existing bridge |
| `opnsense_bridge_description` | empty | bridge to reconfigure (when preparing) |
| `opnsense_bridge_keep_members` | `[]` | members to retain |
| `opnsense_assign_interfaces` | `false` | assign VLAN devices to interface slots |
| `opnsense_interface_assignments` | `[]` | the assignments (zone, device) |

> ⚠️ **Blast radius.** `opnsense_prepare_trunk_ports` mutates an existing bridge —
> a live-network change. It is opt-in for a deliberate, sequenced cutover only.

### Decommission gate (`opn_edge_decommission`)

| Variable | Default | Purpose |
|---|---|---|
| `opnsense_require_zero_leases` | `true` | require zero active leases before withdrawing service |

### High availability (`opn_ha`)

| Variable | Environment | Default | Purpose |
|---|---|---|---|
| `opnsense_carp_password` | `OPNSENSE_CARP_PASSWORD` | empty | CARP VHID group password |
| `opnsense_carp_vhid_base` | `OPNSENSE_CARP_VHID_BASE` | `1` | base VHID; per-zone VHID = base + VLAN |
| `opnsense_carp_advskew` | — | `0` | 0 = master; host_vars override for backup |
| `opnsense_hasync_username` | `OPNSENSE_HASYNC_USERNAME` | `root` | config-sync user |
| `opnsense_hasync_password` | `OPNSENSE_HASYNC_PASSWORD` | empty | config-sync password |
| `opnsense_hasync_pfsyncversion` | — | `1400` | pfsync protocol (OPNsense 24.7+) |
| `opnsense_hasync_syncitems` | — | aliases, rules, nat, virtualip, dhcpd, unbound | sections to sync |

### Bootstrap (`opn_bootstrap_apikey`)

| Variable | Default | Purpose |
|---|---|---|
| `opn_bootstrap_apikey_user` | `ansible` | OPNsense user to mint the key for |
| `opn_bootstrap_apikey_force` | `false` | rotate: mint new, delete prior keys |
| `opn_bootstrap_apikey_env_file` | `{{ playbook_dir }}/.env` | where to write the minted pair |

---

## §8 — The netspec data model

The network's shape is declared as data in `shared/netspec/`, and the roles are
pure functions of that data. To change the network, an operator edits data, not
tasks. There are three files: the zones and trunks (`zones.yml`), the phase map
(`phases.yml`, covered in §4), and the inter-zone policy (`firewall_matrix.yml`).

### Zones and trunks

```mermaid
graph TB
    subgraph "Trunks (physical ports carrying tagged VLANs)"
        QNAP["qnap — em2<br/>cluster/infra power domain"]
        POE["poe — em3<br/>AP/WiFi power domain"]
    end
    subgraph "Zones (tagged VLANs on the trunks)"
        MGMT["mgmt — vlan10<br/>10.10.0.0/24"]
        IOT["iot — vlan20<br/>10.20.0.0/24"]
        DMZ["dmz — vlan30<br/>10.30.0.0/24"]
        SYNC["sync — vlan4000<br/>10.40.0.0/24 (HA pfsync)"]
        CL["cluster — untagged<br/>10.0.0.0/24 (existing LAN)"]
    end
    MGMT --> QNAP
    MGMT --> POE
    IOT --> QNAP
    IOT --> POE
    DMZ --> QNAP
    DMZ --> POE
    SYNC --> QNAP
    CL --> QNAP
```

A **trunk** is a physical OPNsense port carrying tagged zone VLANs to one switch
or power domain. A **zone** is a logical network that declares which trunks it
rides; the interfaces role creates the zone's VLAN sub-interface on each listed
trunk parent. This is how one zone can be present on two independent power
domains.

Each zone is a dictionary entry with a consistent shape:

```yaml
# shared/netspec/zones.yml (one zone)
netspec:
  zones:
    mgmt:
      enabled: true
      vlan: 10
      tagged: true
      trunks: [qnap, poe]      # rides both power domains
      role: zone               # zone | cluster | transit | sync
      subnet: "10.10.0.0/24"
      gateway: "10.10.0.1"
      dhcp: true
      dhcp_pool: "10.10.0.100 - 10.10.0.200"
      description: "MGMT - infrastructure management"
```

| Zone field | Meaning |
|---|---|
| `enabled` | include the zone in a run |
| `vlan` | 802.1q tag (0/untagged for the existing flat LAN) |
| `tagged` | carried as a tagged VLAN vs. the native/untagged segment |
| `trunks` | which trunk parents the zone VLAN is created on |
| `role` | `zone` (client subnet), `cluster` (existing LAN), `transit` (routed core), `sync` (HA state) |
| `subnet` / `gateway` | the zone's network and its gateway address |
| `dhcp` / `dhcp_pool` | whether Kea serves the zone, and the lease range |

Top-level netspec fields carry shared values: `cluster_dns` (the resolver to
forward internal queries to), `cluster_domain` (the internal split-horizon zone),
`wan_interface`, `native_blackhole_vlan` (a deny-all native VLAN per trunk), and
`static_hosts` (Unbound reservations).

### The firewall matrix

Inter-zone policy is a table, not procedural rules. Each row carries an explicit
sequence number for deterministic pf ordering and is rendered into one firewall
rule, matched on its description (which makes it idempotent — see §15).

```yaml
# shared/netspec/firewall_matrix.yml (excerpts)
firewall_matrix:
  dhcp_allow:
    - {seq: 10, from: mgmt, to: any, action: pass, proto: udp, src: any, port: 67, desc: "dhcp server mgmt"}
  isolation:
    - {seq: 100, from: iot, to: mgmt, action: block, proto: any, desc: "iot deny mgmt"}
  allows:
    - {seq: 203, from: mgmt, to: cluster_dns, action: pass, proto: "TCP/UDP", port: 53, desc: "mgmt to dns"}
  wan_egress:
    - {seq: 400, from: mgmt, to: wan, action: pass, proto: any, desc: "mgmt to internet"}
```

| Group | Sequence range | Intent |
|---|---|---|
| `dhcp_allow` | 10–19 | DHCP server allow (UDP 67); required because `fw_rules: false` on Kea |
| `isolation` | 100–199 | explicit inter-zone denies; block rules before pass on the same interface |
| `allows` | 200–299 | explicit permits (mgmt lateral, DNS port 53 per zone) |
| `wan_egress` | 400–499 | per-zone egress to the internet |

All rules use `quick: true` (pf first-match semantics) and `direction: in`
(filter on the source interface inbound).

```mermaid
graph LR
    MGMT["mgmt"]
    IOT["iot"]
    DMZ["dmz"]
    CL["cluster"]
    DNS(["cluster_dns:53"])
    WAN(["WAN / internet"])

    MGMT -->|pass| WAN
    IOT -->|pass| WAN
    DMZ -->|pass| WAN
    CL -->|pass| WAN

    MGMT -->|pass| IOT
    MGMT -->|pass| DMZ
    MGMT -->|pass| CL

    MGMT -->|pass 53| DNS
    IOT -->|pass 53| DNS
    DMZ -->|pass 53| DNS

    IOT -.->|block| MGMT
    IOT -.->|block| CL
    DMZ -.->|block| MGMT
    DMZ -.->|block| CL

    style WAN fill:#1f3a5f,color:#fff
    style DNS fill:#2d5016,color:#fff
```

Solid edges are permits; dashed edges are explicit denies.

### Per-deployment overrides

A deployment overrides the shared netspec without copying it. `netspec_overrides`
is deep-merged over `shared/netspec/zones.yml`, so a deployment sets only the
leaves that differ:

```yaml
# vars/<deploy>_values.yml
netspec_overrides:
  cluster_dns: "10.0.0.51"
  zones:
    mgmt: {subnet: "10.10.0.0/24", gateway: "10.10.0.1"}
```

> 💡 The shared netspec is the single source of truth. Overrides should contain
> only true deviations; mirroring the defaults into an override silently
> decouples the deployment from future changes to the shared data.

---

## §9 — The roles

The collection contains nine roles. One (`opn_bootstrap_apikey`) runs over SSH and
is invoked by its own playbook; the other eight are API-driven and composed by
`site.yml` in dependency order.

```mermaid
graph LR
    CONN["opn_connect"] --> SYS["opn_system"]
    SYS --> IF["opn_interfaces"]
    IF --> DNS["opn_dns"]
    DNS --> DHCP["opn_dhcp"]
    DHCP --> FW["opn_firewall"]
    FW --> HA["opn_ha"]
    HA --> DEC["opn_edge_decommission"]
    style CONN fill:#1f3a5f,color:#fff
    style HA fill:#444,color:#fff
    style DEC fill:#5c2d00,color:#fff
```

### §9.1 opn_connect

Read-only API probe. Issues a single list request and asserts the response
carries data. Tagged `connect` and `always`.

### §9.2 opn_system

Sysctl tunables via `core/tunables` GET-diff-POST (real idempotency). Identity
and WAN via `core/initialsetup` wizard (gated by `opnsense_apply_identity`).
Default tunables: `net.inet.carp.senderr_demotion_factor: 240`,
`net.inet.carp.log: 2`.

> ⚠️ Identity/WAN run the wizard. Leave `opnsense_apply_identity: false` until a
> deliberate identity change is intended.

### §9.3 opn_interfaces

VLAN sub-interfaces on trunk ports: blackhole VLAN 3999 per trunk, zone VLANs
per netspec. Optional trunk-port preparation (bridge mutation) and interface
slot assignment, both off by default.

> 🔬 **Deeper.** The OPNsense MVC API does not expose per-interface IP
> configuration on opt* interfaces. After VLAN creation, the operator assigns
> IPs via the OPNsense web UI before advancing to the `migrating` phase. This
> is documented in the spikebusting ceremony (`SPIKEBUSTING.md`, Phase 3).

### §9.4 opn_dns

Hardened Unbound resolver with split-horizon forwarding and DNS-layer threat
blocking:

1. **General settings** via `oxlorg.opnsense.unbound_general`: enabled, port 53,
   DNSSEC, static mapping registration for Kea reservations.
2. **Security hardening** via raw API to `unbound.advanced.*`: identity hiding,
   DNSSEC enforcement, rebinding protection, cache poisoning detection, cache
   sizing, observability (extended statistics, SERVFAIL logging, DNSSEC
   validation logging).
3. **ACL default action** set to `refuse` via raw API to `unbound.acls.*`. All
   unknown sources are refused; explicit per-zone `allow` ACLs for mgmt, iot,
   dmz, and cluster subnets.
4. **DNSBL** via raw API to `unbound.dnsbl.*`: Abuse.ch ThreatFox IOC and Hagezi
   Threat Intelligence Feeds enabled by default.
5. **Forward zone**: `home.arpa` → CoreDNS at `10.0.0.51`, with
   `privatedomain: home.arpa` (allow RFC 1918 in responses) and
   `insecuredomain: home.arpa` (bypass DNSSEC for unsigned CoreDNS responses).
6. **Static host reservations** for operator-defined entries.

### §9.5 opn_dhcp

Kea DHCPv4 with per-zone scopes, phase-gated (`zone_dhcp`, off at `coexist`):

1. Dnsmasq disabled (conflicts with Kea on the same interfaces).
2. Kea enabled with `socket_type: udp` (pf-gated; raw bypasses pf),
   `fw_rules: false` (DHCP allow rules in the firewall matrix), and socket
   retry configuration via raw API (`service_sockets_max_retries: 5`).
3. Per-zone subnets with `auto_options: false` and explicit routers/dns/domain.
4. Per-subnet hardening via raw API: `allocator`, `match-client-id`,
   `valid_lifetime` set per zone after the oxlorg module creates the subnet.

### §9.6 opn_firewall

Zone aliases, DHCP allow rules, and the inter-zone policy matrix — all
savepoint-wrapped:

1. Network aliases (one per zone) and a `cluster_dns` host alias, created and
   applied before the savepoint.
2. Savepoint create on the filter controller.
3. Flattened matrix rows applied as rules with explicit `sequence`, `quick: true`,
   `direction: in`. DHCP allow rules (seq 10–12, UDP 67) run first. Isolation
   blocks (seq 100–103) run before allows (seq 200–205) on the same interface.
   WAN egress (seq 400–403) last.
4. Reload, verify API reachable, cancel rollback (commit). If verification fails
   or the run is interrupted, the 60-second server timer auto-reverts.

```mermaid
sequenceDiagram
    participant R as opn_firewall
    participant FW as OPNsense
    R->>FW: create zone aliases (reload:false)
    R->>FW: reload aliases
    R->>FW: savepoint create (filter)
    R->>FW: apply matrix rules (reload:false)
    R->>FW: reload rules
    R->>FW: list rules (verify reachable)
    alt verified
        R->>FW: cancel_rollback (commit)
    else not reached in time
        FW-->>FW: auto-revert filter section
    end
```

The collection does not create masquerade NAT rules. OPNsense's automatic
outbound NAT already masquerades internal zones to the WAN address. For HA
deployments, the operator switches to manual outbound NAT with the CARP VIP
as the translation target.

> 🔬 **Deeper — automation namespace.** All rules are in `Firewall → Automation`
> (MVC namespace), isolated from `Firewall → Rules` (legacy namespace).
> Automation rules process before legacy rules on the same interface.

### §9.7 opn_ha

CARP VIPs, HA configuration sync, and explicit sync trigger. Gated by
`opnsense_ha_enabled`. Creates a CARP VIP per zone gateway with a unique VHID
(`opnsense_carp_vhid_base + vlan_tag`), configures hasync with
`pfsync_version: 1400` (OPNsense 24.7+), and on the master triggers
`core/hasync_status/restart_all` to push configuration to the backup.

The per-node identity (`opnsense_carp_advskew`, 0 for master, higher for backup)
comes from inventory `host_vars`; everything else — the VIP addresses, VHIDs, and
sync items — is derived from the netspec and the HA variables.

```mermaid
graph TB
    subgraph "Master (advskew 0)"
        M["OPNsense A"]
    end
    subgraph "Backup (advskew > 0)"
        B["OPNsense B"]
    end
    VIP(["CARP VIP per zone<br/>e.g. 10.10.0.1 (mgmt)<br/>VHID = base + vlan"])
    CLIENTS["zone clients<br/>(gateway = VIP)"]

    CLIENTS --> VIP
    VIP -. elected .-> M
    VIP -. standby .-> B
    M <-->|"pfsync state<br/>(SYNC zone, 10.40.0.0/24)"| B
    M -->|"config sync<br/>(hasync / XMLRPC)"| B

    style M fill:#2d5016,color:#fff
    style VIP fill:#1f3a5f,color:#fff
```

> ⚠️ HA requires a second node and the dedicated SYNC segment. Enable only when the
> peer and sync zone are present.

### §9.8 opn_edge_decommission

Withdraws edge DHCP/DNS from the legacy cluster segment. Evidence-gated: queries
active Kea leases via `kea/leases4/search` and asserts `stats.active == 0`.

> ⚠️ **Blast radius.** This role removes service from the live LAN. The evidence
> gate is a safety, not a formality.

### §9.9 opn_bootstrap_apikey

SSH/root API key mint. Renders a PHP mint script to the box, runs it as root
(the script uses OPNsense's auth model to create and persist a key), removes
the script, parses the result, and writes the key/secret to the deployment's
`.env`. Username sanitized to `[a-zA-Z0-9._-]` at template render time.
Idempotent and non-accumulating: without `force` it does nothing when a key
exists; with `force` it mints a new key and deletes the prior keys for the
user, so exactly one key remains. Full lifecycle in §12.

---

## §10 — Troubleshooting

### §10.1 `opn_connect` fails with 401 Authentication Failed

| Likely cause | Check | Fix |
|---|---|---|
| Credentials not in environment | confirm `OPNSENSE_API_KEY`/`SECRET` exported | `direnv allow`, or source `.env` |
| Key not on the box | mint or rotate (§12) | re-run bootstrap with `force` |
| `lookup('env')` empty | ansible not inheriting shell env | use `direnv exec <dir> ansible-playbook ...` |

> 💡 Prove a credential independently:
> `curl -k -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" https://<fw>/api/core/firmware/status`

### §10.2 "could not resolve the module_defaults group"

Collections not installed. Run:
`ansible-galaxy collection install -r requirements.yml -p collections`

### §10.3 FQCN role "not found"

Same as §10.2. Confirm `collections/ansible_collections/containercraft/opnsense`
exists.

### §10.4 Variables resolve empty

`lookup('env', ...)` reads the ansible process environment. Launch from the
configured deploy shell or use `direnv exec`.

### §10.5 Firewall apply reverted itself

The savepoint auto-reverted because verification did not complete in time. Re-run
the role.

### §10.6 `dig @10.0.0.1 test.home.arpa` returns "localhost"

The built-in `home.arpa` static local zone is intercepting queries before the
forward zone. Verify `insecuredomain` and `privatedomain` are set to `home.arpa`
in `unbound.advanced`. The built-in zone serves `NS localhost` and
`SOA localhost` — if these appear in responses, the hardening raw API task did
not apply correctly.

### §10.7 DHCP clients get no address

Verify: (1) `phase.zone_dhcp` is `true` (phase is `migrating` or later),
(2) `opnsense_enforce_dnsmasq_disabled` is `true` and Dnsmasq is off,
(3) interface IPs are assigned on zone gateways (manual step),
(4) DHCP allow rules (seq 10–12) exist in the firewall,
(5) Kea `socket_type` is `udp` (if `raw`, pf rules do not gate DHCP traffic).

---

## §11 — The iterative rollout runbook

### Principles

- **One change per iteration.** Run a single tag, or flip a single toggle.
- **Dry-run before every apply.** `--check --diff` shows exactly what changes.
- **Stay in `coexist` until interfaces have IPs and switches are configured.**

```mermaid
graph LR
    SCOPE["pick ONE scope<br/>(a tag or a toggle)"] --> DRY["--check --diff"]
    DRY --> READ{"diff correct?"}
    READ -->|no| FIX["adjust values / data"]
    FIX --> DRY
    READ -->|yes| APPLY["apply (same tag)"]
    APPLY --> NEXT["next scope"]
    NEXT --> SCOPE
    style DRY fill:#1f3a5f,color:#fff
    style APPLY fill:#2d5016,color:#fff
```

### Procedure

```bash
# 0. Prove connectivity and credentials.
./stargate.yml --tags connect

# 1. System baseline (CARP tunables; identity stays off).
./stargate.yml --tags system --check --diff
./stargate.yml --tags system

# 2. Interfaces (zone VLANs + blackhole).
./stargate.yml --tags interfaces --check --diff
./stargate.yml --tags interfaces

# 3. DNS (hardened Unbound, DNSBL, ACLs, forward zone).
./stargate.yml --tags dns --check --diff
./stargate.yml --tags dns

# 4. Firewall (DHCP allow + isolation + allows + egress, savepoint-wrapped).
./stargate.yml --tags firewall --check --diff
./stargate.yml --tags firewall

# 5. Assign interface IPs in the OPNsense web UI (manual step — see SPIKEBUSTING.md Phase 3).
# 6. Configure switches with VLAN trunks (manual step — see SPIKEBUSTING.md Phase 4).

# 7. Advance phase and enable zone DHCP.
#    Set OPNSENSE_NETWORK_PHASE=migrating and opnsense_enforce_dnsmasq_disabled=true.
./stargate.yml --tags dhcp --check --diff
./stargate.yml --tags dhcp
```

### The values file as the iteration surface

A deployment's values file disables every optional capability so a full run is
minimal. Each toggle is a single iteration: set it, re-run that role's tag
with `--check --diff`, read the diff, apply.

```yaml
# vars/<deploy>_values.yml (capability toggles, all disabled to start)
opnsense_apply_identity: false        # flip for opn_system identity/WAN
opnsense_prepare_trunk_ports: false   # flip for a deliberate trunk cutover
opnsense_assign_interfaces: false     # flip once per-interface IPs are handled
opnsense_enforce_dnsmasq_disabled: false  # flip when bringing up Kea
opnsense_ha_enabled: false            # flip when the HA peer exists
opnsense_require_zero_leases: true    # safety gate — leave on
```

The deployment includes a `SPIKEBUSTING.md` ceremony document with checkbox
verification for every phase, including manual steps (interface IP assignment
in the web UI, switch VLAN configuration). The ceremony covers the full path
from `coexist` through `migrating` with zone isolation verification.

---

## §12 — Bootstrap and the credential lifecycle

```mermaid
sequenceDiagram
    participant OP as Operator
    participant C as Controller
    participant FW as Firewall (SSH+root)
    participant ENV as deploy/.env

    OP->>C: ansible-playbook bootstrap.yml --ask-pass --ask-become-pass
    C->>FW: render mint script (template)
    C->>FW: run mint script as root
    Note over FW: createKey() generates key+secret,<br/>persists crypted secret to config.xml
    FW-->>C: STATUS=created, KEY, SECRET (returned once)
    C->>FW: remove mint script
    C->>ENV: write OPNSENSE_API_KEY / OPNSENSE_API_SECRET
    Note over ENV: subsequent API-driven runs read these
```

| Condition | Behavior | Result |
|---|---|---|
| key exists, no `force` | do nothing | `exists`; `.env` unchanged |
| no key, no `force` | mint one | `created`; `.env` written |
| `force` | mint new, then delete all prior keys for the user | `created`; exactly one key remains |

```mermaid
graph TD
    START["mint requested"] --> Q1{"user has a key?"}
    Q1 -->|no| MINT["add key, persist"]
    Q1 -->|yes| Q2{"force?"}
    Q2 -->|no| EXISTS["STATUS=exists<br/>(no change)"]
    Q2 -->|yes| ROTATE["add new key,<br/>delete prior keys"]
    MINT --> VERIFY["re-read; confirm count >= 1"]
    ROTATE --> VERIFY
    VERIFY --> CREATED["STATUS=created<br/>write .env"]
    style EXISTS fill:#444,color:#fff
    style CREATED fill:#2d5016,color:#fff
```

The plaintext secret is returned exactly once at creation and is not retrievable
afterward (OPNsense stores it hashed). If a key exists but its secret was not
captured, the only way to obtain a usable secret is to rotate with `force`.

> ⚠️ A dedicated, least-privilege service user is recommended as the API-key
> holder, distinct from the SSH/wheel user used to run bootstrap.

---

## §13 — Architecture: a run end to end

```mermaid
sequenceDiagram
    participant E as ./stargate.yml
    participant S as site.yml (play)
    participant PRE as pre_tasks
    participant ROLES as roles (FQCN)
    participant FW as OPNsense API

    E->>S: import_playbook, vars: values_file=stargate_values.yml
    S->>PRE: load netspec, phases, matrix, run toggles
    PRE->>PRE: load operator values (this deploy)
    PRE->>PRE: merge netspec_overrides; resolve phase capabilities
    S->>ROLES: opn_connect ... opn_edge_decommission (gated)
    ROLES->>FW: configure objects (reload:false)
    ROLES->>FW: one reload per subsystem
    ROLES->>FW: verify; commit (firewall savepoint)
```

1. **Entry.** The executable entrypoint selects the deployment's values file and
   imports the generic `site.yml`.
2. **Data load.** `pre_tasks` load the netspec, phase map, firewall matrix, and
   operator values, then deep-merge overrides and resolve phase capabilities.
3. **Role composition.** Eight API-driven roles in dependency order. Each
   configures objects with deferred reloads, then issues a single reload. The
   firewall role wraps its changes in a savepoint. The DNS role applies
   hardening and DNSBL via raw API. The DHCP role applies per-subnet overrides
   via raw API after the typed module creates the subnets.
4. **Convergence.** Re-running produces no changes once the firewall matches the
   declared state.

---

## §14 — The collection / deploy split, in depth

### Why the collection holds only roles

Every variable a role reads has a default inside that role. A galaxy install
works without the deploy tree.

### Why the deploy layer holds identity

The site's name, inventory, real network data, and credentials are not reusable
and must not leak into the published artifact. It lives in `deploy/opnsense/`:

| Deploy artifact | Role |
|---|---|
| `stargate.yml` | executable entrypoint; the only place the box name appears |
| `site.yml` | generic orchestration (no site specifics) |
| `vars/<deploy>_values.yml` | this site's overrides |
| `inventory/` | API target, connection mode |
| `.envrc`, `.env`, `ansible.cfg` | environment, credentials, runtime config |

### How values reach a generic playbook

```yaml
# deploy/opnsense/stargate.yml
#!/usr/bin/env -S ansible-playbook --inventory=inventory/hosts.yml
- name: "ContainerCraft | stargate | OPNsense edge"
  import_playbook: site.yml
  vars:
    values_file: "{{ playbook_dir }}/vars/stargate_values.yml"
```

`import_playbook` propagates `vars:` to the imported plays but not `vars_files:`.
Setting `values_file` via `vars:` is the mechanism that lets a generic `site.yml`
load a site-specific values file without naming it. One executable per site, a
generic playbook shared by all sites.

---

## §15 — Idempotency, savepoints, and the safety model

### Description-keyed idempotency

Most objects are matched on their description, which carries the managed-by
prefix (`opnsense_managed_tag`). Re-running finds the existing object and updates
it in place rather than creating a duplicate. Changing a managed value is detected
as a change; running again with no change is a no-op. Composite keys are used
where a description is insufficient (for example, Unbound host records match on
hostname + domain + record type).

### Savepoint rollback

Firewall filter changes can lock out the operator if a rule is wrong. The
firewall role wraps its changes in a server-side savepoint: it applies the rules,
verifies the API is still reachable, and only then cancels the savepoint's
auto-rollback. If the verification does not complete within the 60-second timer
window, the filter section reverts automatically. The operator cannot be
permanently locked out by a bad apply. The savepoint covers `firewall/filter`
only — not interfaces, DHCP, or DNS.

### Deferred reloads

Bulk object tasks set `reload: false` and each role issues a single reload per
subsystem at its end. This avoids applying a half-built configuration and reduces
churn. A run interrupted mid-role generally leaves staged but un-applied changes
rather than a partial live configuration.

```mermaid
graph TD
    A["declare desired state (data)"] --> B["match existing by description"]
    B -->|found| C["update in place if drifted"]
    B -->|absent| D["create"]
    C --> E["reload subsystem once"]
    D --> E
    E --> F["verify reachable"]
    F -->|ok| G["commit / converged"]
    F -->|fail| H["savepoint auto-revert"]
```

---

## §16 — The oxlorg.opnsense dependency seam

`containercraft.opnsense` orchestrates; `oxlorg.opnsense` implements the API
modules.

| Concern | Owned by |
|---|---|
| API protocol, request/response, module argument specs | `oxlorg.opnsense` |
| Which objects to create and in what order | `containercraft.opnsense` roles |
| The network's shape (zones, trunks, matrix) | `shared/netspec/` data |
| Credential injection into module calls | `module_defaults` action group |
| Fields not exposed by typed modules | `oxlorg.opnsense.raw` API calls |

```mermaid
graph TB
    DATA["shared/netspec/ data<br/>(zones, trunks, matrix)"]
    ROLES["containercraft.opnsense roles<br/>(what to create, in what order)"]
    MD["module_defaults<br/>group/oxlorg.opnsense.all<br/>(injects credentials + timeout + retries)"]
    OXL["oxlorg.opnsense modules<br/>(speak the REST protocol)"]
    RAW["raw API tasks<br/>(hardening, per-subnet overrides, DNSBL, ACL default)"]
    API["OPNsense REST API"]

    DATA --> ROLES
    ROLES --> MD
    ROLES --> RAW
    MD --> OXL
    OXL --> API
    RAW -->|explicit opnsense_api_args| API

    style ROLES fill:#2d5016,color:#fff
    style OXL fill:#1f3a5f,color:#fff
    style RAW fill:#5c2d00,color:#fff
```

The `module_defaults` group injects the connection arguments (including
`api_timeout` and `api_retries`) into all modules that upstream lists in its
action groups. The `raw` module and `ansible.builtin.uri` are not in that group,
so tasks using them pass the connection arguments explicitly via
`opnsense_api_args`.

> 🔬 **Deeper.** Upstream pins matter. The collection declares an exact dependency
> (`oxlorg.opnsense == <version>`) because module argument specs and action-group
> membership change between versions. Upgrading the dependency is a deliberate,
> tested change.

---

## §17 — Extending the collection

### Add a zone

A zone is data. Add an entry to `shared/netspec/zones.yml` with the standard
shape. No role changes required.

### Add a firewall rule

A rule is a row in `shared/netspec/firewall_matrix.yml` with a unique `seq` and
`desc`. The firewall role flattens all groups and applies each row.

### Add a phase capability

A capability is a boolean in `shared/netspec/phases.yml` under each phase, and a
`when:` gate in the consuming role. Define the capability for every phase so the
phase map stays total, then gate the role's task on `phase.<capability>`.

### Add a role

Give the role a complete `defaults/main.yml` with the connection surface, its own
toggles, and safe data fallbacks. Compose it into `site.yml` with an FQCN
reference and a tag. Match the existing roles' shape: deferred reloads,
description-keyed idempotency, check-mode guards on tasks that cannot dry-run,
and the savepoint pattern for anything that can sever connectivity.

---

## §18 — Contributing, testing, and publishing

### Local validation

```bash
ansible-lint collections/opnsense
ansible-galaxy collection build collections/opnsense --output-path build/
./stargate.yml --check --diff
```

### What makes a change mergeable

- Lints clean at the production profile.
- Roles remain self-contained (every variable has a role default).
- No site identity leaks into the collection.
- Mutating tasks are check-mode guarded; connectivity-severing tasks are
  savepoint-wrapped.
- The changelog records the change.

### CI

The repository's workflows lint on pull request and publish on a version tag
(`<collection>-v<semver>`). The `version` field in `galaxy.yml` is a placeholder
the publish step overwrites from the git tag.

---

## §19 — Appendices

### §19.1 Glossary

| Term | Meaning |
|---|---|
| **Zone** | a logical network (usually a VLAN) with a subnet, gateway, and policy |
| **Trunk** | a physical port carrying tagged zone VLANs to a switch/power domain |
| **Blackhole VLAN** | a deny-all native VLAN per trunk; carries no addresses |
| **Phase** | the monotonic migration state (`coexist`…`converged`) |
| **netspec** | the network's shape declared as data in `shared/netspec/` |
| **Firewall matrix** | inter-zone policy declared as a table of sequenced rows |
| **Savepoint** | a server-side firewall checkpoint with a 60-second auto-revert timer |
| **Managed tag** | the description prefix marking automation-owned objects; also the idempotency key |
| **Action group** | the upstream module set into which `module_defaults` injects credentials |
| **Deploy layer** | the site-specific tree (`deploy/<name>/`) that consumes the collection |
| **Entrypoint** | the executable, shebang-driven playbook that carries a site's identity |
| **CARP / pfsync** | the HA mechanisms: virtual IPs (CARP) and state sync (pfsync v1400) |
| **Kea / Unbound** | the DHCP server and the DNS resolver OPNsense uses |
| **DNSBL** | DNS-based blocklist; Unbound blocks queries for known-malicious domains |
| **Raw API** | `oxlorg.opnsense.raw` module calling OPNsense endpoints not exposed by typed modules |

### §19.2 Environment variable index

| Variable | Consumed by | Default |
|---|---|---|
| `OPNSENSE_FIREWALL` | connection | empty |
| `OPNSENSE_API_KEY` / `OPNSENSE_API_SECRET` | connection | empty |
| `OPNSENSE_API_PORT` | connection | 443 |
| `OPNSENSE_SSL_VERIFY` | connection | false |
| `OPNSENSE_NETWORK_PHASE` | posture | coexist |
| `OPNSENSE_MANAGED_TAG` | marking | ansible-managed |
| `OPNSENSE_APPLY_IDENTITY` | opn_system | false |
| `OPNSENSE_HOSTNAME` / `OPNSENSE_DOMAIN` / `OPNSENSE_TIMEZONE` | opn_system | opnsense / home.arpa / UTC |
| `OPNSENSE_WAN_IPV4_TYPE` | opn_system | dhcp |
| `OPNSENSE_ENFORCE_DNSMASQ_DISABLED` | opn_dhcp | false |
| `OPNSENSE_REQUIRE_ZERO_LEASES` | opn_edge_decommission | true |
| `OPNSENSE_CARP_PASSWORD` / `OPNSENSE_CARP_VHID_BASE` | opn_ha | empty / 1 |
| `OPNSENSE_HASYNC_USERNAME` / `OPNSENSE_HASYNC_PASSWORD` | opn_ha | root / empty |

### §19.3 File index

| Path | Purpose |
|---|---|
| `collections/opnsense/roles/` | the nine roles |
| `collections/opnsense/galaxy.yml` | collection manifest |
| `collections/opnsense/meta/runtime.yml` | required Ansible version |
| `collections/opnsense/changelogs/` | release history |
| `shared/netspec/zones.yml` | zones and trunks |
| `shared/netspec/phases.yml` | phase → capability map |
| `shared/netspec/firewall_matrix.yml` | sequenced inter-zone policy |
| `deploy/opnsense/stargate.yml` | executable site entrypoint |
| `deploy/opnsense/site.yml` | generic orchestration |
| `deploy/opnsense/bootstrap.yml` | API-key mint (SSH/root) |
| `deploy/opnsense/SPIKEBUSTING.md` | validation ceremony with manual steps |
| `deploy/opnsense/vars/*_values.yml` | per-site values |
| `deploy/opnsense/inventory/` | API target and connection mode |

### §19.4 API surface

Each role maps to one or more OPNsense API controllers via the upstream
`oxlorg.opnsense` modules. The authoritative mapping is the role's
`tasks/main.yml` — the module name encodes the controller. Roles that use
`oxlorg.opnsense.raw` name the controller explicitly in the task's `controller:`
parameter. The raw API pattern extends the collection's reach to model fields
not exposed by typed modules, including Unbound `advanced.*`, Kea
`dhcpv4/set_subnet/<uuid>`, and Unbound `acls.*` / `dnsbl.*`.

### §19.5 Version compatibility

| Component | Requirement |
|---|---|
| `ansible-core` | `>= 2.17` |
| Python (controller) | `>= 3.12` |
| `oxlorg.opnsense` | pinned exact version (see `galaxy.yml` dependencies) |
| OPNsense | 26.1 or compatible release |

---

*This document is the canonical reference for `containercraft.opnsense`. For the
collection's machine-readable metadata see `galaxy.yml` and `meta/runtime.yml`;
for release history see `changelogs/`.*
