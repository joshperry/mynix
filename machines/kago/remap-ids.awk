# Remap TOS uids/gids to kago's NixOS ids in `getfacl -R -n` output, for
# `setfacl --restore` (which also applies the "# owner:"/"# group:" lines).
#
#   cd /mnt/md0 && getfacl -R -n -P DIR | awk -f remap-ids.awk | setfacl --restore=-
#
# Named ACL entries that collapse onto the same id (TOS admin=3 and
# allusers=4 both become nas=2000) are merged by OR-ing their permissions,
# since setfacl rejects duplicate entries. Ids not in the maps are kept.
BEGIN {
  # TOS josh, janus, ada, plex
  u["2"] = "1000"; u["5"] = "1001"; u["7"] = "1100"; u["5555"] = "193"
  # TOS admin, allusers, TimeMachine -> nas; plex
  g["3"] = "2000"; g["4"] = "2000"; g["1000"] = "2000"; g["5555"] = "193"
  n = 0
}

function orperm(a, b,    i, r, ca, cb) {
  r = ""
  for (i = 1; i <= 3; i++) {
    ca = substr(a, i, 1); cb = substr(b, i, 1)
    r = r ((ca != "-") ? ca : cb)
  }
  return r
}

function flush(    i) {
  for (i = 1; i <= n; i++) print line[i]
  print ""
  n = 0; delete line; delete seen
}

/^$/ { if (n) flush(); next }

/^# owner: / { if ($3 in u) $3 = u[$3]; line[++n] = $0; next }
/^# group: / { if ($3 in g) $3 = g[$3]; line[++n] = $0; next }
/^#/         { line[++n] = $0; next }

{
  sub(/\t+#effective:.*/, "")
  k = split($0, f, ":")
  # [default:]tag:qualifier:perms
  off = (f[1] == "default") ? 1 : 0
  tag = f[1 + off]; q = f[2 + off]; p = f[3 + off]
  if (q != "") {
    if (tag == "user" && (q in u)) q = u[q]
    if (tag == "group" && (q in g)) q = g[q]
    key = (off ? "default:" : "") tag ":" q
    if (key in seen) {
      i = seen[key]
      split(line[i], e, ":")
      line[i] = key ":" orperm(e[3 + off], p)
      next
    }
    line[++n] = key ":" p
    seen[key] = n
    next
  }
  line[++n] = $0
}

END { if (n) flush() }
