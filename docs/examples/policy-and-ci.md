---
layout: default
render_with_liquid: false
---

# Policy and CI

Use these examples when cron schedule checks should run automatically.

## Enforce schedule policy in CI

Create a policy file:

```sh
cat > croncheck.policy <<'EOF'
forbid_every_minute: true
require_timezone: true
max_frequency_per_hour: 12
disallow_midnight_utc: true
EOF
```

Run it in CI:

```sh
croncheck check --from-k8s cronjobs.yaml \
  --policy croncheck.policy \
  --window 30d
```

The command exits `1` if warnings, conflicts, overlaps, or policy violations
are found.

When introducing the tool gradually, fail only on policy violations while still
printing other findings:

```sh
croncheck check --from-k8s cronjobs.yaml \
  --policy croncheck.policy \
  --window 30d \
  --fail-on policy
```

## Use Docker in CI without installing OCaml

Use the published Docker image when the CI job only needs the CLI.

```sh
docker run --rm -v "$PWD:/work" -w /work \
  pwbsladek/croncheck:latest \
  check --from-k8s cronjobs.yaml --policy croncheck.policy
```

This is useful in repositories that do not otherwise need an OCaml toolchain.
