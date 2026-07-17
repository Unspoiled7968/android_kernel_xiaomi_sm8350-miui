# Build workflows

This branch holds only the GitHub Actions workflows. There's no kernel source
here on purpose — the source lives on `hyper-17`, and every workflow checks it
out at build time with `actions/checkout` set to `ref: hyper-17`.

Splitting CI off the source branch keeps things clean: editing a workflow no
longer shows up in kernel history, and pushing to `hyper-17` doesn't trigger a
pile of builds you didn't ask for.

## Running a build

Actions tab → pick a workflow on the left → **Run workflow** → set the branch
dropdown to **build** → fill in the inputs → run.

That dropdown only decides which *workflow* runs. The kernel source is always
pulled from `hyper-17` regardless of what you pick there.

## What each workflow builds

| File | Result |
|------|--------|
| `clean_build.yml` | Plain kernel, no root |
| `resukisu_build.yml` | ReSukiSU + SUSFS (inline hook) |
| `sukisu.yml` | SukiSU Ultra |
| `sukisu_test.yml` | SukiSU Ultra, testing config |
| `ksunext_build.yml` | KernelSU-Next + SUSFS |
| `KageSU.yml` | KageSU |
| `all.yml` | Any of the above — pick the KSU variant as an input |
| `show.yml` | Dumps the KSU Makefile. Debug helper, doesn't build a kernel |

`star` (Mi 11 Ultra) is the default target on every workflow; some also offer
`mars`, `venus`, or `renoir`.

## BPF backport

The 5.10 BPF backport is **not** part of the kernel source. It lives here as a
set of patches under `patches/bpf/`, and every kernel build workflow has an
`enable_bpf` toggle (**on by default**). When it's on, the workflow pulls the
patches from this branch and applies them, in filename order, to the
checked-out source before building. Turn it off to build the plain kernel
without the backport.

The patches are split only so each one stays viewable on GitHub (a single 1.2M
patch won't render); together they're one feature and are always applied as a
set:

```
patches/bpf/
  01-bpf-uapi.patch          uapi headers + tools mirror
  02-bpf-headers.patch       kernel-internal bpf/btf/filter headers
  03-bpf-verifier.patch      kernel/bpf/verifier.c
  04-bpf-core.patch          the rest of kernel/bpf
  05-rcu-tasks-trace.patch   SRCU-backed tasks-trace RCU (sched.h, rcu, init)
  06-integration-misc.patch  net, security, cgroup, config, misc glue
```

Keeping BPF as patches means `hyper-17` stays clean, and you can build with or
without the backport from the same source — handy for narrowing down whether a
problem comes from BPF or from the base kernel.

To refresh the patches after changing the backport on `hyper-17`, regenerate
them against the LTS-merge base (see the split by path in the file list above).

## Telegram notifications

On success the build workflows send the finished zip to Telegram; on failure
they send the build log. For that the repo needs a secret `TELEGRAM_BOT_TOKEN`
and a variable `CHAT_ID`. Leave them unset and the build still runs — only the
last notification step fails.

## Building from a different branch

The source branch is hardcoded to `hyper-17`. To build from somewhere else,
change `ref:` in the Checkout step of whichever workflow you're running.
