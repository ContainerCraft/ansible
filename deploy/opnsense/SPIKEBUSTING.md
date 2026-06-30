# Stargate OPNsense — Spikebusting Ceremony

Iterative validation of the containercraft.opnsense collection against the live
stargate OPNsense 26.1 box at 10.0.0.1. Covers the full path from fresh
checkout to operational zone networking at `migrating` phase.

Each phase is a dry-run, an apply (automated or manual), and a verification.
Mark the checkboxes only after observing the stated outcome. Do not advance
to the next phase until all checkboxes in the current phase are marked with
observed findings recorded.

Automated commands run from the deploy directory:

```bash
direnv exec /workspace/usrbinkat/github.com/ContainerCraft/ansible/deploy/opnsense <command>
```

Manual steps are performed in the OPNsense web UI at `https://10.0.0.1` unless
otherwise stated.

---

## Phase 0 — Environment and credentials

**Action:**

```bash
./stargate.yml --tags connect
```

**Verification:**

```bash
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/core/firmware/status | python3 -m json.tool
echo $OPNSENSE_NETWORK_PHASE
```

- [x] `--tags connect` exits `failed=0`
- [x] curl returns JSON with firmware status (200, api_version 2, FreeBSD 14.3-RELEASE-p15)
- [x] `OPNSENSE_NETWORK_PHASE` resolves to `coexist`
- [x] `-v` output shows `api_timeout=30`, `api_retries=2` in module args

**Findings:**

```
Phase 0 passed. ok=6 changed=0 failed=0.
OPNsense API reachable at 10.0.0.1.
API returned existing VLANs: VLAN 9 on em0/em1/em2/em3, VLAN 91 on re0 (WAN),
VLAN 30 on em0/em1/em2/em3. Existing live configuration present.
httpx resolved via pythonWithHttpx in flake.nix + source_up in deploy .envrc.
ANSIBLE_PYTHON_INTERPRETER set via flake shellHook to nix-store python3 with httpx.
ansible_python_interpreter: "{{ ansible_playbook_python }}" in inventory as fallback.
```

---

## Phase 1 — System tunables (opn_system)

**Dry run:**

```bash
./stargate.yml --tags system --check --diff
```

**Apply:**

```bash
./stargate.yml --tags system
```

**Verification:**

```bash
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/core/tunables/searchItem | python3 -m json.tool
```

- [x] Apply exits `failed=0`
- [x] `net.inet.carp.senderr_demotion_factor` = `240` in API response
- [x] `net.inet.carp.log` = `2` in API response
- [x] No `net.inet.ip.forwarding` or `net.inet6.ip6.forwarding` in the diff
- [x] Tunables re-run exits `changed=0` (idempotent)
- [x] Identity applied: hostname `stargate` (was `stargate.home.arpa`), domain `home.arpa`
- [x] FQDN now `stargate.home.arpa` (was `stargate.home.arpa.home.arpa`)
- [x] WAN unchanged: dhcp, blockpriv=1, blockbogons=1
- [x] Timezone: America/Los_Angeles

**Findings:**

```
Tunables apply: ok=10 changed=1 failed=0 skipped=2.
net.inet.carp.senderr_demotion_factor: 0 -> 240 (uuid 8719bbfa, result: saved)
net.inet.carp.log: created with value 2 (uuid 037e3faf, result: saved)
Reconfigure tunables handler: status ok, 4s elapsed.
Both entries tagged descr: ansible-managed. No duplicates.
Tunables re-run: ok=8 changed=0 skipped=3 (idempotent).

Identity apply: opnsense_apply_identity enabled, hostname set to "stargate".
API path corrected from core/initialsetup (404) to core/initial_setup (200).
Task changed from set+handler(configure) to single configure call with data
(configureAction calls setAction internally then updateConfig + service reload).
Drift detected: wizard.hostname "stargate.home.arpa" != "stargate".
After apply: hostname=stargate, domain=home.arpa, FQDN=stargate.home.arpa.
WAN settings confirmed unchanged (dhcp, blockpriv=1, blockbogons=1).
```

---

## Phase 2 — VLAN interfaces (opn_interfaces)

**Dry run:**

```bash
./stargate.yml --tags interfaces --check --diff
```

**Apply:**

```bash
./stargate.yml --tags interfaces
```

**Verification:**

```bash
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/interfaces/vlan_settings/searchItem | python3 -m json.tool
```

- [x] Apply exits `failed=0`
- [x] Blackhole VLAN 3999 created on em2 and em3
- [x] Zone VLANs created on correct trunk parents per netspec
- [x] Bridge preparation tasks show `skipping`
- [x] Existing LAN (em0/em1) unaffected
- [x] VLAN re-run exits `changed=0` (idempotent)
- [x] Interface assignment: MGMT opt14 vlan0.10.2 10.10.0.1/24 created
- [x] Interface assignment: IOT opt15 vlan0.20.2 10.20.0.1/24 created
- [x] Interface assignment: DMZ opt8 vlan030.2 10.30.0.1/24 updated (IP added)
- [x] Interface assignment: SYNC opt16 vlan0.4000.2 10.40.0.1/24 created
- [x] All four `configctl interface reconfigure` calls succeeded
- [x] LAN (bridge0 10.0.0.1/24) unchanged, ping 0.051ms
- [x] WAN (re0 73.48.181.18/23) unchanged, ping 8.8.8.8 13.681ms
- [x] API reachable: connection ok
- [x] Assignment idempotency: OPN_IFACE_STATUS=unchanged on re-run

**Findings:**

```
VLAN apply: ok=13 changed=2 failed=0 skipped=3.
All 10 VLAN devices converged (blackhole, transit, mgmt, iot, dmz, sync).

Interface assignment apply: ok=15 changed=3 failed=0 skipped=1.
OPNsense 26.1 has no MVC API for interface assignment (404 on all
interfaces/assignment/* endpoints). Implemented via SSH + inline PHP script
(ansible.builtin.raw) following the bootstrap pattern. The PHP script reads
config.xml, finds or creates the opt entry, sets IP/subnet/descr/enable,
saves config.xml, and triggers configctl interface reconfigure.

Created:
  opt14 MGMT vlan0.10.2 10.10.0.1/24 (new)
  opt15 IOT  vlan0.20.2 10.20.0.1/24 (new)
  opt16 SYNC vlan0.4000.2 10.40.0.1/24 (new)
Updated:
  opt8  DMZ  vlan030.2 10.30.0.1/24 (existed without IP, descr 30DMZEM2 -> DMZ)

All interfaces show inet address in ifconfig output.
All show "no carrier" because em2/em3 trunk ports have no cable connected
to the switches yet. Once switches are configured and cabled, carrier comes
up and interfaces are routable.

Idempotency verified: re-run shows OPN_IFACE_STATUS=unchanged for all four.

Defects fixed during this phase:
  - VLAN filter changed from vlan > 1 to vlan > 0 (transit VLAN 1 was excluded)
  - Device naming: explicit vlan0.<tag>.<parent_index> prevents collision
  - Pre-read lookup preserves existing device names for adopted VLANs
  - Interface assignment via SSH+PHP (API not available on 26.1)
  - template/copy modules fail on OPNsense (no Python); raw works
```

Idempotency re-run: ok=13 changed=1 failed=0 skipped=3.
changed=1 is the reload task (always reports changed). All VLAN create tasks
report ok (no drift). All 10 VLAN devices exist with correct descriptions.
```

---

## Phase 3 — Interface assignment and IP addressing (MANUAL)

The OPNsense MVC API does not expose per-interface IP configuration for opt*
interfaces. The NetworkInterface model (Interfaces/NetworkInterface.xml) only
carries `descr`, `identifier`, and `if` (device). IP addressing is in legacy
config.xml and must be set via the web UI.

**Action: Assign VLAN devices to interface slots**

1. Navigate to `Interfaces → Assignments`
2. For each unassigned VLAN device, click `+` to add it:

   | Device       | Assign as | Description |
   |---|---|---|
   | `vlan0.10` on em2 | opt1 → rename to `mgmt` | MGMT zone |
   | `vlan0.20` on em2 | opt2 → rename to `iot` | IoT zone |
   | `vlan0.30` on em2 | opt3 → rename to `dmz` | DMZ zone |
   | `vlan0.4000` on em2 | opt4 → rename to `sync` | HA sync |

3. Click `Save`

**Action: Configure interface IPs**

For each assigned interface, navigate to `Interfaces → [name]` and set:

| Interface | Enable | IPv4 Type | IPv4 Address | IPv4 Mask | Block Private | Block Bogons |
|---|---|---|---|---|---|---|
| mgmt | ✓ | Static | 10.10.0.1 | 24 | ☐ | ☐ |
| iot | ✓ | Static | 10.20.0.1 | 24 | ☐ | ☐ |
| dmz | ✓ | Static | 10.30.0.1 | 24 | ☐ | ☐ |
| sync | ✓ | Static | 10.40.0.1 | 24 | ☐ | ☐ |

Click `Save` then `Apply changes` on each interface.

**Verification:**

```bash
# Verify interfaces are up with correct IPs
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/interfaces/overview/interfacesInfo/true | python3 -m json.tool

# Verify from the box itself (SSH as barbie)
ssh barbie@10.0.0.1 "ifconfig vlan0.10; ifconfig vlan0.20; ifconfig vlan0.30; ifconfig vlan0.4000"
```

- [ ] mgmt interface (vlan0.10) has IP 10.10.0.1/24 and is UP
- [ ] iot interface (vlan0.20) has IP 10.20.0.1/24 and is UP
- [ ] dmz interface (vlan0.30) has IP 10.30.0.1/24 and is UP
- [ ] sync interface (vlan0.4000) has IP 10.40.0.1/24 and is UP
- [ ] Existing LAN (em0) still has 10.0.0.1 and is UP
- [ ] API still reachable: `./stargate.yml --tags connect` exits `failed=0`

**Findings:**

```
```

---

## Phase 4 — Switch configuration (MANUAL)

Configure both switches to carry the zone VLANs on the trunk ports.

**QNAP switch (em2 trunk):**

1. Set the port connected to em2 as a trunk port
2. Set the native/untagged VLAN to 3999 (blackhole)
3. Add tagged VLANs: 1 (transit), 10 (mgmt), 20 (iot), 30 (dmz), 4000 (sync)
4. Prune VLAN 1 from the native VLAN — it must be tagged only, not the default
5. Ensure the existing cluster segment (untagged LAN) port is NOT on this trunk

**POE switch (em3 trunk):**

1. Set the port connected to em3 as a trunk port
2. Set the native/untagged VLAN to 3999 (blackhole)
3. Add tagged VLANs: 10 (mgmt), 20 (iot), 30 (dmz)
4. Prune VLAN 1 from the native VLAN

**Both switches:**

- Disable port security and sticky MAC on trunk ports
- Disable IGMP snooping on trunk ports or configure CARP multicast passthrough
- If using STP, ensure trunk ports are in forwarding state

**Verification:**

From the OPNsense box (SSH as barbie):

```bash
# Verify VLAN traffic reaches the box on em2
ssh barbie@10.0.0.1 "tcpdump -c 5 -i em2 vlan"

# Verify from a device plugged into the QNAP switch on VLAN 10:
# Configure the device with IP 10.10.0.100/24 gateway 10.10.0.1
ping 10.10.0.1
```

- [ ] VLAN tagged frames visible on em2 tcpdump
- [ ] A device on VLAN 10 can ping 10.10.0.1 (mgmt gateway)
- [ ] A device on VLAN 20 can ping 10.20.0.1 (iot gateway)
- [ ] A device on VLAN 30 can ping 10.30.0.1 (dmz gateway)
- [ ] Existing cluster LAN (10.0.0.0/24) still works

**Findings:**

```
```

---

## Phase 5 — DNS (opn_dns)

**Dry run:**

```bash
./stargate.yml --tags dns --check --diff
```

**Apply:**

```bash
./stargate.yml --tags dns
```

**Verification:**

```bash
# External resolution
dig @10.0.0.1 google.com +short

# Internal forward (home.arpa → CoreDNS)
dig @10.0.0.1 test.home.arpa +short

# Verify hardening
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/unbound/settings/get | python3 -m json.tool | grep -E \
  '"hideidentity"|"hideversion"|"prefetch"|"dnssecstripped"|"belownxdomain"|"privatedomain"|"insecuredomain"|"privateaddress"|"extendedstatistics"|"unwantedreplythreshold"|"logservfail"|"valloglevel"'

# Verify ACL default action
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/unbound/settings/get | python3 -m json.tool | grep default_action

# Verify ACLs
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/unbound/settings/searchAcl | python3 -m json.tool

# Verify forward zone
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/unbound/settings/searchForward | python3 -m json.tool

# Verify DNSBL
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/unbound/settings/searchDnsbl | python3 -m json.tool

# Verify identity hidden
dig @10.0.0.1 id.server CH TXT +short
dig @10.0.0.1 version.bind CH TXT +short
```

- [x] Apply exits `failed=0`
- [x] `dig @10.0.0.1 google.com` returns an IP (142.251.219.14)
- [x] `dig @10.0.0.1 test.home.arpa` times out (forwarded to CoreDNS 10.0.0.51 which is not running — NOT NXDOMAIN from built-in zone, confirming nodefault override is active)
- [x] API shows `hideidentity: "1"` in `unbound.advanced`
- [x] API shows `hideversion: "1"` in `unbound.advanced`
- [x] API shows `prefetch: "1"` in `unbound.advanced`
- [x] API shows `dnssecstripped: "1"` in `unbound.advanced`
- [x] API shows `belownxdomain: "1"` in `unbound.advanced`
- [x] API shows `privatedomain` contains `home.arpa` in `unbound.advanced`
- [x] API shows `insecuredomain` contains `home.arpa` in `unbound.advanced`
- [x] API shows `privateaddress` contains `10.0.0.0/8` (full RFC 1918 + test ranges)
- [x] API shows `extendedstatistics: "1"` in `unbound.advanced`
- [x] API shows `unwantedreplythreshold: "10000000"` in `unbound.advanced`
- [x] API shows `logservfail: "1"` in `unbound.advanced`
- [x] API shows `valloglevel: "1"` (Level 1 selected)
- [x] API shows `msgcachesize: "256m"` in `unbound.advanced`
- [x] API shows `rrsetcachesize: "512m"` in `unbound.advanced`
- [x] API shows ACL `default_action: "refuse"` (selected)
- [x] API shows ACL entries for mgmt, iot, dmz, cluster (4 entries)
- [x] API shows forward entry for `home.arpa` targeting `10.0.0.51`
- [x] API shows DNSBL enabled with ThreatFox (`atf`) and Hagezi TI (`hgz011`) (2 entries)
- [x] `dig id.server CH TXT` returns empty (identity hidden)
- [x] `dig version.bind CH TXT` returns empty (version hidden)
- [x] Existing DNS clients on 10.0.0.0/24 still resolve (google.com works)

**Findings:**

```
Initial apply: ok=16 changed=5 failed=0 skipped=2.
Hardening raw API — changed (raw always reports changed; verified via GET).
ACL default action — changed (raw; verified refuse selected).
Stop/Start Unbound — changed (full restart for nodefault drop-in file copy).
All other tasks ok (converged from prior run).

home.arpa nodefault: file at /usr/local/etc/unbound.opnsense.d/home-arpa-nodefault.conf
written via SSH (ansible.builtin.raw). start.sh copies it to /var/unbound/etc/
on full restart. Verified: dig test.home.arpa times out (forwarding to CoreDNS)
instead of returning instant NXDOMAIN (built-in static zone intercepting).
CoreDNS at 10.0.0.51 is not running (cluster not up) — timeout is correct behavior.
configctl unbound check: no errors in /var/unbound/unbound.conf.

Idempotency re-run: ok=15 changed=3 failed=0 skipped=4.
  - Enable Unbound resolver: ok changed=false (dns64_prefix fix resolved spurious diff)
  - ACLs: ok (4 entries, all converged)
  - DNSBL: search found 2 existing entries, create skipped
  - home.arpa nodefault: ok UNCHANGED (idempotency check passed, no write)
  - Validate config: ok (no errors)
  - Forward zone: ok (converged)
  - Soft reload (not stop+start — nodefault file unchanged, no DNS outage)
  - changed=3: hardening raw + ACL default raw + soft reload (all always-changed)
  - skipped=4: DNSBL create + stop + start + static hosts

Defects fixed during this phase:
  - Hardening fields posted to unbound.advanced.* (not general.*)
  - Removed non-existent fields (hardenglue, hardendnssecstripped, etc.)
  - privateaddress as CSV string (not list), matches model default format
  - DNSBL via addDnsbl CRUD (not bulk set which validates all entries)
  - dhcp_domain set to home.arpa (prevents bare hostname registration)
  - Reload gated: stop+start only when nodefault file changes; soft reload otherwise
  - SSH delegate uses hostvars[inventory_hostname] for variable resolution
  - dns64_prefix as configurable variable (oxlorg validates even when dns64 disabled)
  - All unbound_general params extracted to configurable role defaults

Pre-existing box issue: hostname is stargate.home.arpa (should be stargate),
producing FQDN stargate.home.arpa.home.arpa. Not caused by automation
(opnsense_apply_identity: false). Will be corrected when identity is enabled.
```

---

## Phase 6 — Firewall rules (opn_firewall)

**Dry run:**

```bash
./stargate.yml --tags firewall --check --diff
```

**Apply:**

```bash
./stargate.yml --tags firewall
```

**Verification:**

```bash
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/firewall/alias/searchItem | python3 -m json.tool

curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/firewall/filter/searchRule | python3 -m json.tool

./stargate.yml --tags connect
```

- [x] Apply exits `failed=0`
- [x] 6 aliases (mgmt_net, iot_net, dmz_net, cluster_net, sync_net, cluster_dns)
- [x] 25 rules with `ansible-managed` prefix, correct sequence ordering
- [x] deny-all (seq 1-4) before DHCP (10-12) before isolation (100-113) before allows (200-205) before egress (400-403)
- [x] Savepoint committed (API reachable)
- [x] Existing 10.0.0.0/24 traffic unaffected (LAN 2.005ms, WAN 14.261ms)
- [x] DMZ resolves to opt8 (description-based), not opt6 (device-prefix was ambiguous)
- [x] IPv6 isolation rules present (seq 110-113)
- [x] log=0 on DHCP+egress, log=1 on isolation+allows+deny-all
- [x] transit deny-all (opt17), sync deny-all (opt16) — no blind spots

**Findings:**

```
Apply: ok=20 changed=5 failed=0 skipped=0.
25 rules created. 6 aliases created. Savepoint committed.

Initial run had DMZ resolving to opt6 (device prefix vlan030. matched
vlan030.0/opt6 before vlan030.2/opt8). Fixed by switching from device-prefix
regex matching to description-based matching (zone key uppercased = interface
description set by opn_interfaces assignment script).

Defects fixed during this phase:
  - Device prefix matching replaced with description-based matching
  - Regex dot-as-wildcard eliminated (vlan0.1. matched vlan0.10.)
  - opn_fw_zone_interfaces initialized to {} before loop (no leakage)
  - role-based cluster detection (item.value.role == 'cluster')
  - opn_fw_all_referenced_zones rejects wan/any/cluster_dns sentinels
  - deny_all group added to all matrix references (alias filter, flatten, assert)
  - Task ordering: referenced zones list built before alias filter
  - Transit assigned to interface (opt17) — no unassigned VLANs
  - Sync and transit have explicit deny-all rules (no blind spots)
```

---

## Phase 7 — DHCP/HA/decommission at coexist (no-op verification)

**Action:**

```bash
./stargate.yml --tags dhcp
./stargate.yml --tags ha
./stargate.yml --tags decommission
```

- [x] All DHCP tasks skip (`phase.zone_dhcp: false`, skipped=11)
- [x] HA role inclusion skipped (`opnsense_ha_enabled: false`, skipped=1)
- [x] Decommission role inclusion skipped (`phase.decommission_legacy: false`, skipped=1)

**Findings:**

```
DHCP: ok=6 changed=0 failed=0 skipped=11.
HA: ok=6 changed=0 failed=0 skipped=1.
Decommission: ok=6 changed=0 failed=0 skipped=1.
All gated correctly by phase capabilities and toggle flags.
```

---

## Phase 8 — Full convergence

**Action:**

```bash
./stargate.yml --ask-pass --ask-become-pass
```

- [x] Full run exits `failed=0`
- [x] Non-raw/reload tasks converged (all ok, no drift)
- [x] LAN reachable, WAN reachable
- [x] Run time: 1m24s

**Findings:**

```
Full run: ok=42 changed=8 failed=0 skipped=21.

changed=8 breakdown:
  - Apply system identity (raw, always changed) — identity already correct
  - Apply VLAN interface changes (reload, always changed)
  - Apply Unbound hardening (raw, always changed)
  - Set Unbound ACL default action (raw, always changed)
  - Reconfigure Unbound soft reload (reload, always changed)
  - Apply alias changes (reload, always changed)
  - Apply firewall rule changes (reload, always changed)
  - DHCP server rules seq 10/11/12 (updated: interface changed from
    opt6 to opt8 for DMZ — the description-based resolution fix propagated
    to the previously-created rules on this convergence run)

All non-raw/reload tasks report ok (converged):
  - Tunables: no drift
  - VLANs: all 10 devices ok
  - Interface assignments: all 5 unchanged
  - Unbound general: ok (no dns64_prefix spurious diff)
  - ACLs: 4 entries ok
  - DNSBL: 2 entries found, create skipped
  - home.arpa nodefault: UNCHANGED (soft reload, no DNS outage)
  - Forward zone: ok
  - Aliases: 6 ok
  - Firewall rules: 22 of 25 ok, 3 updated (DMZ interface fix)
  - Savepoint committed
  - DHCP/HA/decommission: all skipped (coexist phase)

skipped=21: DHCP tasks (11) + HA (1) + decommission (1) + tunables
create/update (no drift) + DNSBL create (exists) + stop/start Unbound
(nodefault unchanged) + static hosts (empty) + interface reconfigure
(no changes)
```

---

## Phase 9 — Advance to migrating phase

**Prerequisites:**
- [ ] All Phase 0-8 checkboxes marked
- [ ] Interface IPs confirmed operational (Phase 3)
- [ ] Switch VLANs confirmed operational (Phase 4)
- [ ] At least one device on each VLAN can ping its gateway

**Action: Enable Dnsmasq disable and advance phase**

Edit `deploy/opnsense/vars/stargate_values.yml`:

```yaml
opnsense_enforce_dnsmasq_disabled: true
```

Set the phase in the environment:

```bash
export OPNSENSE_NETWORK_PHASE=migrating
```

Or edit `stargate_values.yml`:

```yaml
network_phase: "migrating"
```

**Dry run:**

```bash
./stargate.yml --check --diff
```

**Expected changes:**
- Dnsmasq disable task runs (was skipping)
- Kea enable task runs (was skipping)
- Per-zone Kea subnets created (mgmt, iot, dmz)
- Per-subnet hardening applied via raw API (allocator, match-client-id, valid_lifetime)
- Kea general hardening applied (socket retries)
- Everything else converged (no change)

- [ ] Dry run shows Dnsmasq disable as would-change
- [ ] Dry run shows Kea enable with interfaces: [mgmt, iot, dmz]
- [ ] Dry run shows 3 subnet creates (mgmt, iot, dmz)
- [ ] No system/interface/DNS/firewall changes

**Apply:**

```bash
./stargate.yml
```

**Verification:**

```bash
# Verify Kea is running
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/kea/service/status | python3 -m json.tool

# Verify subnets
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/kea/dhcpv4/search_subnet | python3 -m json.tool

# Verify Kea general settings
curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://10.0.0.1/api/kea/dhcpv4/get | python3 -m json.tool

# Verify per-subnet hardening (allocator, match-client-id)
# Find the IoT subnet UUID from search_subnet output, then:
# curl -sk -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
#   https://10.0.0.1/api/kea/dhcpv4/get_subnet/<iot-uuid> | python3 -m json.tool

# Test DHCP from a device on VLAN 10 (mgmt):
# Remove static IP, set to DHCP, verify it gets an address in 10.10.0.100-200
# Verify gateway is 10.10.0.1, DNS is 10.10.0.1, domain is home.arpa

# Test DHCP from a device on VLAN 20 (iot):
# Same test, verify address in 10.20.0.100-200

# Test DHCP from a device on VLAN 30 (dmz):
# Same test, verify address in 10.30.0.100-200
```

- [ ] Apply exits `failed=0`
- [ ] Kea service status shows running
- [ ] API lists 3 subnets: mgmt (10.10.0.0/24), iot (10.20.0.0/24), dmz (10.30.0.0/24)
- [ ] Kea general shows `dhcp_socket_type: "udp"`
- [ ] Kea general shows `fwrules: "0"`
- [ ] Kea general shows `service_sockets_max_retries: "5"`
- [ ] IoT subnet shows `allocator: "random"`
- [ ] IoT subnet shows `match-client-id: "0"` (false)
- [ ] IoT subnet shows `valid_lifetime: "3600"`
- [ ] mgmt subnet shows `allocator: "random"`
- [ ] mgmt subnet shows `valid_lifetime: "7200"`
- [ ] All subnets show `option_data_autocollect: "0"` (false)
- [ ] All subnets show explicit `routers` and `domain_name_servers`
- [ ] DHCP client on VLAN 10 gets address in 10.10.0.100-200 range
- [ ] DHCP client on VLAN 10 gets gateway 10.10.0.1
- [ ] DHCP client on VLAN 10 gets DNS 10.10.0.1
- [ ] DHCP client on VLAN 10 gets domain home.arpa
- [ ] DHCP client on VLAN 20 gets address in 10.20.0.100-200 range
- [ ] DHCP client on VLAN 30 gets address in 10.30.0.100-200 range
- [ ] DHCP client can ping its gateway
- [ ] DHCP client can ping 8.8.8.8 (internet via NAT)
- [ ] DHCP client can resolve google.com via its gateway DNS
- [ ] Re-run exits `changed=0` on non-raw tasks

**Findings:**

```
```

---

## Phase 10 — Zone isolation verification

From a DHCP client on each zone, verify the firewall policy matrix:

```bash
# From a device on IoT (10.20.0.x):
ping -c 1 10.10.0.1    # should FAIL (iot deny mgmt)
ping -c 1 10.0.0.1     # should FAIL (iot deny cluster)
ping -c 1 8.8.8.8      # should PASS (iot to internet)
dig @10.20.0.1 google.com +short   # should PASS (DNS via gateway)

# From a device on DMZ (10.30.0.x):
ping -c 1 10.10.0.1    # should FAIL (dmz deny mgmt)
ping -c 1 10.0.0.1     # should FAIL (dmz deny cluster)
ping -c 1 8.8.8.8      # should PASS (dmz to internet)

# From a device on MGMT (10.10.0.x):
ping -c 1 10.20.0.1    # should PASS (mgmt to iot)
ping -c 1 10.30.0.1    # should PASS (mgmt to dmz)
ping -c 1 10.0.0.1     # should PASS (mgmt to cluster)
ping -c 1 8.8.8.8      # should PASS (mgmt to internet)

# From a device on cluster (10.0.0.x):
ping -c 1 8.8.8.8      # should PASS (cluster to internet)
dig @10.0.0.1 google.com +short   # should PASS (DNS)
```

- [ ] IoT CANNOT reach mgmt (10.10.0.1)
- [ ] IoT CANNOT reach cluster (10.0.0.1)
- [ ] IoT CAN reach internet (8.8.8.8)
- [ ] IoT CAN resolve DNS via 10.20.0.1
- [ ] DMZ CANNOT reach mgmt (10.10.0.1)
- [ ] DMZ CANNOT reach cluster (10.0.0.1)
- [ ] DMZ CAN reach internet (8.8.8.8)
- [ ] MGMT CAN reach all zones (iot, dmz, cluster)
- [ ] MGMT CAN reach internet
- [ ] Cluster CAN reach internet
- [ ] Cluster DNS resolves

**Findings:**

```
```

---

## Phase 11 — End-to-end functional verification

```bash
# From the operator workstation:
./stargate.yml --tags connect
./stargate.yml --check --diff

# From a cluster node (10.0.0.x):
ping -c 3 10.0.0.1
ping -c 3 8.8.8.8
dig @10.0.0.1 google.com
dig @10.0.0.1 id.server CH TXT +short
dig @10.0.0.1 version.bind CH TXT +short
```

- [ ] Full run converged, `failed=0`
- [ ] Gateway reachable from all zones
- [ ] Internet reachable from all zones via NAT
- [ ] DNS resolves from all zones
- [ ] Identity hidden (`id.server` empty or REFUSED)
- [ ] Version hidden (`version.bind` empty or REFUSED)
- [ ] Zone isolation enforced per policy matrix

**Findings:**

```
```

---

## Post-ceremony state (migrating phase)

After all phases complete, the stargate box has fully operational zone
networking:

**System:** CARP tunables applied (senderr_demotion 240, log 2)

**Interfaces:** VLAN sub-interfaces on em2/em3 with IPs assigned, UP, routing

**DNS:** Unbound hardened (identity hidden, DNSSEC, prefetch, aggressive-nsec,
private-address, insecure-domain home.arpa, ACL per zone default refuse,
DNSBL ThreatFox + Hagezi TI, cache 256m/512m, extended-statistics,
log-servfail, forward home.arpa → CoreDNS 10.0.0.51)

**Firewall:** 17 rules sequenced (DHCP allow → isolation → allows → egress),
savepoint-committed, automation namespace

**DHCP:** Kea active on mgmt/iot/dmz, socket_type udp, fw_rules false,
auto_options false, explicit routers/dns/domain per subnet, allocator random,
match-client-id false on IoT, valid_lifetime 3600 on IoT/DMZ / 7200 on mgmt,
service_sockets_max_retries 5

**HA:** Not active (disabled). **Decommission:** Not active (migrating phase).

---

## Genuinely not settable via OPNsense API

These items are hardcoded in OPNsense PHP models or absent from the MVC data
model. They cannot be automated through any API path including raw.

| Item | OPNsense constraint | Workaround |
|---|---|---|
| Per-interface IP on opt* | NetworkInterface.xml has only `descr`, `if`; IP is legacy config.xml | GUI (Phase 3 above) |
| Kea `authoritative` | Not in KeaDhcpv4.xml model or getConfigSubnets() | None via API; Kea default is `false` |
| Kea hook libraries | Hardcoded in KeaDhcpv4.php line 362-364 | Patch PHP or use `manual_config` mode |
| Kea `thread-pool-size`, `packet-queue-size` | Not in model | Patch PHP or `manual_config` |
| Kea `cache-threshold`, `statistic-*` | Not in model | Patch PHP or `manual_config` |
| Kea `calculate-tee-times`, `t1/t2-percent` | Not in model | Patch PHP or `manual_config` |
| Unbound `local-zone: "home.arpa." nodefault` | No per-domain local-zone field in model | `insecuredomain` + `privatedomain` applied; verify resolution in Phase 5 |
| Unbound `use-caps-for-id` | Not in Unbound.xml model | Not settable via API |
| Unbound `deny-any` | Not in Unbound.xml model | Not settable via API |
| Unbound `ip-ratelimit`, `ratelimit` | Not in Unbound.xml model | Not settable via API |
| Unbound `answer-cookie` | Not in Unbound.xml model | Not settable via API |

---

## Future ceremonies

| Ceremony | Phase advance | Key actions |
|---|---|---|
| Hardening | migrating → hardening | Tighten firewall posture, prepare CARP (if second node), add `state_policy: floating` to PASS rules |
| HA activation | hardening | Enable `opnsense_ha_enabled`, switch NAT to manual with CARP VIP, disable CARP on one node, add VIPs, re-enable |
| Convergence | hardening → converged | Withdraw legacy-segment DHCP/DNS (evidence-gated on zero leases) |
| IDS | any | Enable Suricata on em2/em3 (parent physical interfaces), disable hardware offloading first, set Hyperscan pattern matcher, HOME_NET=10.0.0.0/8 |
