# EKS Setup Notes

This folder contains setup notes and focused troubleshooting entries.

## Troubleshooting journal

- [EKS node creation failure](./troubleshooting-journal/node-creation-failure.md)
- [VPC CNI not ready](./troubleshooting-journal/vpc-cni-not-ready.md)
- [EBS CSI controller unhealthy](./troubleshooting-journal/ebs-csi-controller-unhealthy.md)

## Working guidelines

- Keep one incident or problem per journal file.
- Record exact symptoms, evidence, root cause, remediation, and validation.
- Do not store access keys, secret keys, session tokens, passwords, or other
  credentials in documentation.
- Prefer commands that can be rerun and redact sensitive output before saving it.

## New incident template

Create `troubleshooting-journal/<short-problem-name>.md` with:

```markdown
# <Problem title>

**Date:** YYYY-MM-DD
**Environment:** account / region / service

## Symptom

## Scope

## Investigation

```bash
# Reproducible diagnostic commands
```

## Evidence

## Root cause

## Remediation

## Validation

- [ ] Health check
- [ ] Functional check
- [ ] Cleanup or follow-up

## Lessons learned
```
