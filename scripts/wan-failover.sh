#!/usr/bin/env bash
# wan-failover.sh — keep signi online while mino's WAN flaps (kernel bisect).
#
# Probes the internet *strictly via mino* (wlp2s0f0). While mino's WAN is up,
# traffic uses the normal wifi default (dhcp, metric 600). When the probe
# fails, install a higher-priority default route via the bluetooth phone
# tether (enp0s20f0u10) so signi stays online; remove it once mino recovers.
#
# The probe target is pinned through mino with a /32 route, so the health
# check keeps measuring mino's WAN even while we're failed over to BT.
#
# Must run as root (it edits the routing table). Ctrl-C restores routes.
set -u

WIFI_DEV=${WIFI_DEV:-wlp2s0f0}
WIFI_GW=${WIFI_GW:-10.0.2.1}
BT_DEV=${BT_DEV:-enp0s20f0u10}
BT_GW=${BT_GW:-10.179.80.193}
PROBE=${PROBE:-1.1.1.1}            # pinned via mino; measures mino's WAN only
OVERRIDE_METRIC=${OVERRIDE_METRIC:-50}   # beats wifi's dhcp metric (600)
INTERVAL=${INTERVAL:-5}
FAIL_THRESH=${FAIL_THRESH:-3}     # consecutive fails before failover
OK_THRESH=${OK_THRESH:-2}         # consecutive oks before failback

log() {
  printf '%s wan-failover: %s\n' "$(date +%H:%M:%S)" "$*"
  logger -t wan-failover "$*" 2>/dev/null || true
}

if [ "$(id -u)" -ne 0 ]; then
  echo "must run as root" >&2; exit 1
fi

# Pin the probe target via mino so the check reflects mino's WAN, not BT's.
ip route replace "$PROBE/32" via "$WIFI_GW" dev "$WIFI_DEV"

failover() {
  ip route replace default via "$BT_GW" dev "$BT_DEV" metric "$OVERRIDE_METRIC"
  log "mino WAN DOWN -> default via BT tether ($BT_DEV metric $OVERRIDE_METRIC)"
}
failback() {
  ip route del default via "$BT_GW" dev "$BT_DEV" metric "$OVERRIDE_METRIC" 2>/dev/null || true
  log "mino WAN UP -> removed BT override, back on $WIFI_DEV"
}
cleanup() {
  failback
  ip route del "$PROBE/32" via "$WIFI_GW" dev "$WIFI_DEV" 2>/dev/null || true
  log "exiting, routes restored"
  exit 0
}
trap cleanup INT TERM

probe() { ping -n -c1 -W2 "$PROBE" >/dev/null 2>&1; }

state=up
fails=0; oks=0
log "monitoring mino WAN via $PROBE (pinned through $WIFI_DEV), interval ${INTERVAL}s"
while true; do
  if probe; then
    oks=$((oks+1)); fails=0
    if [ "$state" = down ] && [ "$oks" -ge "$OK_THRESH" ]; then failback; state=up; fi
  else
    fails=$((fails+1)); oks=0
    if [ "$state" = up ] && [ "$fails" -ge "$FAIL_THRESH" ]; then failover; state=down; fi
  fi
  sleep "$INTERVAL"
done
