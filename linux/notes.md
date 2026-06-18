# Linux Desktop VM Pipeline — Notes

Reference documentation for the Packer → Vagrant → Ansible pipeline that builds
and runs a hardened Ubuntu 26.04 Desktop VM on VMware Fusion.

---

## Architecture Overview

```
┌─────────────┐      ┌──────────────────┐      ┌──────────────────────┐
│  Packer      │      │  Vagrant          │      │  Ansible              │
│  (Image Bake)│─────▶│  (VM Lifecycle)   │─────▶│  (First-Boot Config)  │
│              │      │                   │      │                       │
│  ISO ─▶ .box │      │  .box ─▶ running  │      │  runtime provision    │
└─────────────┘      └──────────────────┘      └──────────────────────┘
```

**Golden Image (Packer)** — builds once, produces a `.box` artifact with all
hardening baked in. Run `packer build` only when you need a fresh base image.

**VM Lifecycle (Vagrant)** — `vagrant up` / `vagrant halt` / `vagrant destroy`
for reproducible spin-up from the `.box`.

**First-Boot (Ansible)** — runtime personalisation (password rotation, SSH key
injection, desktop tweaks) that shouldn't live in the image.

---

## File Inventory

| File | Purpose |
|------|---------|
| `ubuntu-template.pkr.hcl` | Packer template — builds the golden `.box` image |
| `packer.sh` | Wrapper script — loads `.env` and runs Packer (no manual exports) |
| `meta-data.yml` | Cloud-init metadata (instance ID) |
| `user-data.yml` | Cloud-init autoinstall (unattended OS install) |
| `packer-provision.yml` | Ansible playbook run inside Packer — hardening + desktop |
| `Vagrantfile-desk` | Vagrant config for the desktop box (VMware Fusion) |
| `desktop-provision.yml` | Ansible playbook run on first `vagrant up` |
| `Vagrantfile` | **Existing** — bento/ubuntu VirtualBox (do NOT modify) |
| `full-hardening.yml` | **Existing** — bento hardening playbook (do NOT modify) |
| `.env` | Runtime secrets (never committed) |
| `.env.example` | Template for `.env` variables |

---

## Environment Variables

All secrets and config are stored in `.env` (gitignored). Both Packer and Vagrant
read from this file.

| Variable | Used By | Description |
|----------|---------|-------------|
| `INITIAL_USER` | Packer | User created during autoinstall (default: `samworker`) |
| `WORKER_USER` | Vagrant/Ansible | Runtime worker user (can differ from initial) |
| `WORKER_PASSWD` | Vagrant/Ansible | Worker user password (rotated on first boot) |
| `ALLOWED_SUBNET` | Packer + Vagrant | CIDR for SSH UFW rule |
| `SSH_PVK` | Vagrant | Path to SSH private key |
| `SSH_PBK` | Vagrant | Path to SSH public key |
| `HOSTNAME` | Vagrant/Ansible | VM hostname |

Packer can't natively read `.env` files, so the `packer.sh` wrapper handles this
automatically — it sources `.env` and maps vars to `PKR_VAR_*` before calling
`packer`. You never need to export anything manually.

---

## Quick Start

### 1. Build the Golden Image

```bash
cd linux

# Install Packer plugins (first time only)
packer init ubuntu-template.pkr.hcl

# Build — reads all vars from .env automatically
./packer.sh build ubuntu-template.pkr.hcl
```

Output: `output-desktop/buntoo2604-desk.box`

### 2. Add Box to Vagrant

```bash
vagrant box add buntoo2604-desk output-desktop/buntoo2604-desk.box
```

Or let the `Vagrantfile-desk` pick it up automatically via `box_url`.

### 3. Spin Up the Desktop VM

```bash
VAGRANT_VAGRANTFILE=Vagrantfile-desk vagrant up
```

### 4. SSH Into the VM

```bash
VAGRANT_VAGRANTFILE=Vagrantfile-desk vagrant ssh
# or directly:
ssh -p 2223 -i $SSH_PVK $WORKER_USER@127.0.0.1
```

### 5. Teardown

```bash
VAGRANT_VAGRANTFILE=Vagrantfile-desk vagrant destroy -f
```

---

## Security Tooling & Hardening Reference

Every tool and configuration below is installed during the Packer image bake
(`packer-provision.yml`) unless noted otherwise. This section explains **what**
each does, **why** it's here, and **how** to interact with it.

---

### UFW (Uncomplicated Firewall)

**What:** Host-level packet filter (frontend to iptables/nftables). Controls
which network traffic is allowed in and out of the VM.

**Why:** Default-deny incoming means nothing gets in unless explicitly allowed.
Even if a service accidentally starts listening on a port, UFW blocks it.

**Config applied:**
- Default policy: deny incoming, allow outgoing
- SSH (port 22) allowed only from `ALLOWED_SUBNET` (bake-time)
- SSH further locked to localhost-only via `ListenAddress` in sshd_config (cleanup stage)

**Commands:**
```bash
sudo ufw status verbose       # show active rules
sudo ufw allow 8080/tcp       # open a port (e.g., for a local web app)
sudo ufw delete allow 8080    # remove a rule
sudo ufw app list             # show known application profiles
```

---

### fail2ban

**What:** Intrusion prevention daemon that monitors log files for repeated
authentication failures and temporarily bans offending IPs via the firewall.

**Why:** Brute-force SSH attacks are the #1 threat to any Linux box with SSH
exposed. fail2ban auto-bans IPs after repeated failed logins — even though SSH
is locked to localhost, this is defense-in-depth.

**Config applied** (`/etc/fail2ban/jail.local`):
- Watches SSH auth logs
- **5 failed attempts** within 10 minutes → **1 hour ban**
- Starts automatically on boot

**Commands:**
```bash
sudo fail2ban-client status           # show active jails
sudo fail2ban-client status sshd      # show SSH jail details + banned IPs
sudo fail2ban-client set sshd unbanip 1.2.3.4  # manually unban
sudo tail -f /var/log/fail2ban.log    # watch bans in real-time
```

---

### AIDE (Advanced Intrusion Detection Environment)

**What:** File integrity monitoring tool. Takes a snapshot (database) of every
file's hash, permissions, and metadata — then detects unauthorized changes by
comparing against that baseline.

**Why:** If malware modifies a system binary (`/usr/bin/sudo`, `/usr/sbin/sshd`)
or tampers with config files, AIDE catches it. Essential for RE/malware analysis
VMs where you're deliberately handling hostile binaries.

**Status:** AIDE is **installed** but the database init is **deferred** — it
hangs during Packer builds due to the massive desktop filesystem. Initialize
it after the VM is running:

```bash
# Initialize the baseline database (run once, takes 5-10 min)
sudo aideinit

# Check for changes against the baseline
sudo aide --check

# Update the database after intentional changes (e.g., apt upgrade)
sudo aide --update
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

**Config:** `/etc/aide/aide.conf` — controls which directories are monitored
and what attributes are tracked (hash algo, permissions, ownership, etc.).

---

### auditd (Linux Audit Framework)

**What:** Kernel-level audit system that logs security-relevant events —
file access, system calls, user actions, privilege escalation. More granular
than regular syslog.

**Why:** Creates a forensic trail. If someone modifies `/etc/passwd`, loads a
kernel module, or escalates to root, auditd records it with timestamps, PIDs,
and user context. Critical for post-incident analysis.

**Rules applied** (`/etc/audit/rules.d/hardening.rules`):

| Watched path | Event | Key |
|-------------|-------|-----|
| `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/gshadow` | Write/attribute change | `identity` |
| `/etc/sudoers`, `/etc/sudoers.d/` | Write/attribute change | `sudoers` |
| `/etc/ssh/sshd_config` | Write/attribute change | `sshd_config` |
| `/var/log/auth.log`, `/var/log/faillog` | Write/attribute change | `auth_log` / `login_failures` |
| `/sbin/insmod`, `/sbin/rmmod`, `/sbin/modprobe` | Execution | `kernel_modules` |

**Commands:**
```bash
sudo ausearch -k identity             # search by key (e.g., who changed /etc/passwd)
sudo ausearch -k sudoers -ts today     # sudoers changes today
sudo aureport --auth                   # authentication report
sudo auditctl -l                       # list active rules
```

---

### AppArmor (Mandatory Access Control)

**What:** Linux Security Module that confines programs to a limited set of
resources via per-application profiles. Even if an app is compromised, AppArmor
restricts what it can access.

**Why:** Limits blast radius. If a browser exploit gains code execution, AppArmor
prevents it from reading `/etc/shadow` or writing to `/usr/bin/`. Ubuntu ships
with profiles for many apps; we ensure enforcement is active.

**Commands:**
```bash
sudo aa-status                         # show enforced/complain profiles
sudo aa-enforce /etc/apparmor.d/usr.bin.firefox  # enforce a profile
sudo aa-complain /path/to/profile      # switch to complain mode (log only)
sudo journalctl -k | grep apparmor     # view AppArmor denials
```

---

### rkhunter (Rootkit Hunter)

**What:** Scans for known rootkits, backdoors, and local exploits by checking
system binaries, startup files, and network interfaces for suspicious patterns.

**Why:** Complements AIDE — while AIDE detects _changes_, rkhunter knows
specific signatures of known rootkits and checks for common compromise
indicators (hidden processes, suspicious network listeners, etc.).

**Commands:**
```bash
sudo rkhunter --check                  # full system scan
sudo rkhunter --update                 # update signature database
sudo rkhunter --propupd                # update baseline after apt upgrades
sudo cat /var/log/rkhunter.log         # review results
```

---

### Lynis (Security Auditing)

**What:** Comprehensive security audit tool that evaluates the system against
hundreds of checks (CIS benchmarks, NIST guidelines) and produces a hardening
score with actionable suggestions.

**Why:** Validates that all the hardening above actually works. Runs during
image bake and on first boot. The log files show exactly what passed, what
failed, and what to fix.

**Commands:**
```bash
sudo lynis audit system                # full audit (interactive)
sudo lynis audit system --quiet        # quiet mode, log only
sudo cat /var/log/lynis.log            # review audit log
sudo grep Warning /var/log/lynis.log   # quick check for warnings
sudo grep Suggestion /var/log/lynis.log  # improvement suggestions
```

**Logs:**
- `/var/log/lynis-build.log` — from Packer bake-time audit
- `/var/log/lynis-firstboot.log` — from Vagrant first-boot audit

---

### unattended-upgrades (Automatic Security Patches)

**What:** Automatically downloads and installs security updates from Ubuntu's
repos without manual intervention. Does NOT auto-reboot.

**Why:** Zero-day patches shouldn't wait for you to remember to `apt upgrade`.
Only security repos are enabled — feature updates are excluded to prevent
breakage.

**Config applied:**
- `/etc/apt/apt.conf.d/50unattended-upgrades` — allowed origins (security only)
- `/etc/apt/apt.conf.d/20auto-upgrades` — daily check, weekly auto-clean

**Commands:**
```bash
sudo unattended-upgrades --dry-run     # preview what would be installed
sudo cat /var/log/unattended-upgrades/unattended-upgrades.log  # history
```

---

### PAM pwquality (Password Policy)

**What:** Pluggable Authentication Module that enforces password complexity
requirements when users set or change passwords.

**Config applied** (`/etc/security/pwquality.conf`):

| Rule | Value | Meaning |
|------|-------|---------|
| `minlen` | 12 | Minimum 12 characters |
| `dcredit` | -1 | At least 1 digit |
| `ucredit` | -1 | At least 1 uppercase letter |
| `lcredit` | -1 | At least 1 lowercase letter |
| `ocredit` | -1 | At least 1 special character |
| `maxrepeat` | 3 | No more than 3 consecutive identical characters |

---

### Kernel Hardening (sysctl)

Persistent kernel parameters applied via `sysctl`. These can't be changed by
unprivileged users and survive reboots.

| Parameter | Value | What it does |
|-----------|-------|-------------|
| `kernel.randomize_va_space` | 2 | Full ASLR — randomizes memory layout to defeat buffer overflow exploits |
| `kernel.kptr_restrict` | 2 | Hides kernel pointer addresses from all users (prevents info leak for kernel exploits) |
| `kernel.dmesg_restrict` | 1 | Only root can read kernel ring buffer (prevents info leak) |
| `kernel.yama.ptrace_scope` | 1 | Restricts ptrace to parent→child only (prevents process injection). **Note:** set to 0 temporarily if debugging with GDB across processes |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood protection — uses crypto cookies instead of allocating state for half-open connections |
| `net.ipv4.conf.all.rp_filter` | 1 | Reverse path filtering — drops packets with spoofed source IPs |
| `net.ipv4.conf.all.accept_redirects` | 0 | Ignores ICMP redirects (prevents MITM route manipulation) |
| `net.ipv4.conf.all.send_redirects` | 0 | Doesn't send ICMP redirects (this isn't a router) |
| `net.ipv4.conf.all.accept_source_route` | 0 | Rejects source-routed packets (prevents routing bypass) |
| `net.ipv4.icmp_echo_ignore_broadcasts` | 1 | Ignores broadcast pings (Smurf attack protection) |
| `fs.suid_dumpable` | 0 | Prevents core dumps from SUID binaries (could leak privileged memory) |
| `fs.protected_hardlinks` | 1 | Prevents hardlink-based privilege escalation in world-writable dirs |
| `fs.protected_symlinks` | 1 | Same as above for symlinks |

**Check current values:**
```bash
sysctl kernel.randomize_va_space       # check one
sysctl -a | grep ptrace                # search all
```

---

### SSH Hardening

SSH is bound to **localhost only** (`ListenAddress 127.0.0.1`) — it cannot
receive connections from the network. Vagrant reaches it via port forwarding
(`host 127.0.0.1:2223 → guest :22`).

| Setting | Value | Why |
|---------|-------|-----|
| `PermitRootLogin` | no | No direct root SSH — use sudo |
| `PasswordAuthentication` | no | Key-only auth (no brute-forceable passwords) |
| `MaxAuthTries` | 3 | Limits guessing attempts per connection |
| `MaxSessions` | 3 | Limits multiplexed sessions |
| `X11Forwarding` | no | No X11 display forwarding (attack surface reduction) |
| `AllowAgentForwarding` | no | No SSH agent forwarding (prevents key theft via compromised host) |
| `AllowTcpForwarding` | no | No TCP tunneling through SSH |
| `LoginGraceTime` | 30s | Connection dropped if auth not completed in 30s |
| `ClientAliveInterval` | 300s | Idle timeout — drops stale sessions after 5 min |

---

### File Permission Hardening

| File | Mode | Why |
|------|------|-----|
| `/etc/passwd` | 0644 | World-readable (needed by apps) but not writable |
| `/etc/shadow` | 0640 | Password hashes — readable only by root and shadow group |
| `/etc/gshadow` | 0640 | Group password hashes — same restriction |
| `/etc/group` | 0644 | Group membership — readable but not writable |

---

### Disabled Services

| Service | Why disabled |
|---------|-------------|
| `cups-browsed` | Network printer discovery — unnecessary attack surface in a lab VM |
| `avahi-daemon` | mDNS/DNS-SD service discovery — broadcasts presence on network |

---

### Runtime Controls (Vagrant / desktop-provision.yml)

Applied on first `vagrant up`, not baked into the image:

| Control | What it does |
|---------|-------------|
| Password rotation | Worker user password changed from the bake-time value |
| SSH key injection | Fresh public key from `.env` → `~/.ssh/authorized_keys` |
| Baseline verification | Asserts UFW active, fail2ban running, root SSH disabled |
| GNOME screen lock | Lock enabled, delay = 0 (immediate on idle) — enforced via dconf lock |
| GNOME privacy | Recent files disabled, old trash auto-deleted after 7 days |
| GNOME dark theme | `Yaru-dark` + `prefer-dark` color scheme |
| Final Lynis audit | Logged to `/var/log/lynis-firstboot.log` |

---

## Ghidra Setup

The image comes with **JDK 21** and RE tooling pre-installed. After spinning up:

```bash
# Download Ghidra (check https://ghidra-sre.org for latest)
wget https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_11.3.1_build/ghidra_11.3.1_PUBLIC_20250219.zip
unzip ghidra_*.zip
cd ghidra_*
./ghidraRun
```

### Pre-installed RE Dependencies

- `openjdk-21-jdk` — Ghidra runtime
- `build-essential`, `cmake` — native compilation
- `gdb` — debugger
- `binutils` — objdump, readelf, etc.
- `python3-pip`, `python3-venv` — scripting/plugin dev

### JAVA_HOME

Set system-wide in `/etc/profile.d/java.sh`:

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-arm64
```

---

## Provider Notes

- **VMware Fusion** on macOS requires `vagrant-vmware-desktop` plugin (licensed)
- The bento/ubuntu box uses **VirtualBox** — do not mix providers
- SSH port for desktop box: **2223** (bento uses 2222)
- GUI is enabled by default (`vmw.gui = true`)
- 3D acceleration enabled for responsive desktop
- USB passthrough enabled for hardware RE tools (debuggers, etc.)

---

## Rebuilding the Image

When the base ISO updates or you want to refresh hardening:

```bash
cd linux
# Clean old output
rm -rf output-desktop/

# Rebuild
./packer.sh build ubuntu-template.pkr.hcl

# Replace Vagrant box
vagrant box remove buntoo2604-desk 2>/dev/null
vagrant box add buntoo2604-desk output-desktop/buntoo2604-desk.box
```
