# AWS EC2 : Stripped Startup Scripts 

AWS EC2 enforces a **hard 16,384-byte (16 KiB) limit on instance user data**. It is
*not* an adjustable quota — you cannot raise it via Service Quotas or a support
request. The only lever is making the script smaller.

The canonical [`deb.sh`](../deb.sh) and [`rpm.sh`](../rpm.sh) exceed (or sit right at)
that limit once Kasm substitutes the template variables, so they cannot be pasted
directly into an EC2 launch template / autoscale user-data field.

This folder holds **auto-generated, stripped-down copies** of those scripts that fit
under the limit. They are a **temporary fix** for the AWS path only — every other
provider Kasm autoscale supports has a far larger limit (Azure ~64 KB, GCP ~256 KB,
OCI ~32 KB, DigitalOcean ~64 KB) and should keep using the readable canonical scripts.

## What was stripped

The stripped versions are **functionally identical** to the originals — verified by
canonicalizing both and diffing (no logic changed). Only non-executable bytes were
removed:

- full-line comments (shebangs preserved)
- blank lines
- trailing inline comments
- leading indentation (bash ignores it; heredoc bodies are preserved verbatim)

| File | Canonical | Stripped | Headroom under 16,384 |
|------|-----------|----------|------------------------|
| `deb.sh` | 16,010 B | 12,382 B | ~4,002 B |
| `rpm.sh` | 18,901 B | 13,913 B | ~2,471 B |

## Watch the headroom : variables expand at deploy time

The byte counts above are for the *unrendered* files. Kasm substitutes the template
variables (`{checkin_jwt}`, `{upstream_auth_address}`, `{domain}`, etc.) **before** the
script becomes user data, and the rendered values are larger than the placeholders.
`{checkin_jwt}` in particular is a JWT that can be several hundred bytes and appears
more than once. Budget for that: if a long token pushes the rendered `rpm.sh` back over
16,384, comment-stripping is no longer enough and you should switch to a more robust
approach (below).

## Keeping these in sync

These are generated from the parent scripts. **If you edit `../deb.sh` or `../rpm.sh`,
regenerate these** (run from `linux_vms/`):

```bash
gen() {
  awk '
    !inh && /<<-?'\''?EOF'\''?/ { print; inh=1; next }                 # heredoc start (verbatim)
    inh { print; if ($0 ~ /^EOF'\''?[[:space:]]*$/) inh=0; next }       # heredoc body (verbatim)
    /^[[:space:]]*#!/ { print; next }                                   # keep shebangs
    /^[[:space:]]*#/  { next }                                          # drop full-line comments
    /^[[:space:]]*$/  { next }                                          # drop blank lines
    { line=$0; sub(/[[:space:]]+#.*$/,"",line); sub(/^[[:space:]]+/,"",line); print line }
  ' "$1"
}
gen deb.sh > aws_scripts/deb.sh
gen rpm.sh > aws_scripts/rpm.sh
chmod +x aws_scripts/deb.sh aws_scripts/rpm.sh
```

