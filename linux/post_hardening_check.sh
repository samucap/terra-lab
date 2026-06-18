#!/usr/bin/env bash

# post_hardening_check.sh – verifies the most important hardening settings
# Usage: sudo ./post_hardening_check.sh   (needs root for many checks)

set -euo pipefail

PASS=0
FAIL=0

echo "=== Ubuntu Hardening Post‑Check Report ==="

# 1. UFW status
if sudo ufw status | grep -q "Status: active"; then
  echo "[PASS] UFW active"
  ((PASS++))
else
  echo "[FAIL] UFW not active"
  ((FAIL++))
fi

# 2. SSH configuration hardening
SSH_CONF="/etc/ssh/sshd_config"
declare -A SSH_EXPECT=(
  [PermitRootLogin]=no
  [PasswordAuthentication]=no
  [PubkeyAuthentication]=yes
  [MaxAuthTries]=3
  [MaxSessions]=3
  [ClientAliveInterval]=300
  [ClientAliveCountMax]=2
  [X11Forwarding]=no
  [AllowAgentForwarding]=no
  [AllowTcpForwarding]=no
  [PermitEmptyPasswords]=no
  [LoginGraceTime]=30
  [Protocol]=2
)
for key in "${!SSH_EXPECT[@]}"; do
  if sudo grep -E "^${key}[[:space:]]+${SSH_EXPECT[$key]}" "$SSH_CONF" >/dev/null; then
    echo "[PASS] SSH ${key} = ${SSH_EXPECT[$key]}"
    ((PASS++))
  else
    echo "[FAIL] SSH ${key} not set to ${SSH_EXPECT[$key]}"
    ((FAIL++))
  fi
done

# 3. Sysctl hardening values
declare -A SYSCTL_EXPECT=(
  [kernel.randomize_va_space]=2
  [kernel.kptr_restrict]=2
  [kernel.dmesg_restrict]=1
  [kernel.yama.ptrace_scope]=1
  [net.ipv4.tcp_syncookies]=1
  [net.ipv4.conf.all.rp_filter]=1
  [net.ipv4.conf.default.rp_filter]=1
)
for key in "${!SYSCTL_EXPECT[@]}"; do
  val=$(sysctl -n "$key" 2>/dev/null || echo "missing")
  if [[ "$val" == "${SYSCTL_EXPECT[$key]}" ]]; then
    echo "[PASS] $key = $val"
    ((PASS++))
  else
    echo "[FAIL] $key expected ${SYSCTL_EXPECT[$key]}, got $val"
    ((FAIL++))
  fi
done

# 4. File permissions
declare -A FILE_PERMS=(
  [/etc/passwd]=0644
  [/etc/shadow]=0640
  [/etc/gshadow]=0640
  [/etc/group]=0644
)
for f in "${!FILE_PERMS[@]}"; do
  perm=$(stat -c "%a" "$f" 2>/dev/null || echo "missing")
  if [[ "$perm" == "${FILE_PERMS[$f]}" ]]; then
    echo "[PASS] $f permissions $perm"
    ((PASS++))
  else
    echo "[FAIL] $f permissions $perm (expected ${FILE_PERMS[$f]})"
    ((FAIL++))
  fi
done

# 5. Critical services running
for svc in auditd apparmor; do
  if systemctl is-active --quiet "$svc"; then
    echo "[PASS] $svc running"
    ((PASS++))
  else
    echo "[FAIL] $svc not running"
    ((FAIL++))
  fi
done

# 6. AIDE database presence (if init was run)
if [[ -f /var/lib/aide/aide.db.new.gz ]]; then
  echo "[PASS] AIDE database present"
  ((PASS++))
else
  echo "[WARN] AIDE database not found (maybe init skipped)"
fi

# 7. Lynis report existence (if run)
if [[ -f /var/log/lynis-harden.log ]]; then
  echo "[PASS] Lynis report generated"
  ((PASS++))
fi

# 8. rkhunter report existence (if run)
if [[ -f /var/log/rkhunter-harden.log ]]; then
  echo "[PASS] rkhunter report generated"
  ((PASS++))
fi

# 9. KDE-specific sanity (only if KDE installed)
if dpkg -l | grep -q "kde-plasma-desktop"; then
  # check that screen saver is enabled via qdbus (returns true/false)
  if qdbus org.kde.screensaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive | grep -q "true"; then
    echo "[PASS] KDE screensaver active"
    ((PASS++))
  else
    echo "[FAIL] KDE screensaver not active"
    ((FAIL++))
  fi
fi

# Summary
TOTAL=$((PASS+FAIL))
echo "\n=== Summary ==="
echo "Tests run: $TOTAL"
echo "PASS: $PASS"
echo "FAIL: $FAIL"

exit $FAIL   # non‑zero if any failures
