# Contributing to qr-pipeline

Thank you for contributing to QuantumRishi's shared pipeline infrastructure!

## Guidelines

### Workflow Changes

1. **All actions must be SHA-pinned**
   ```yaml
   # ✅ Good
   uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332 # v4.1.7
   
   # ❌ Bad
   uses: actions/checkout@v4
   ```

2. **Include harden-runner in all jobs**
   ```yaml
   - name: Harden Runner
     uses: step-security/harden-runner@17d0e2bd7d51742c71671bd19fa12bdc9d40a3d6
     with:
       egress-policy: audit
   ```

3. **Document all inputs and secrets**

### Testing

- Test workflows locally with [act](https://github.com/nektos/act)
- Verify SHA pins: `./scripts/verify-pins.sh`

### Pull Requests

1. Reference any related issues
2. Update docs/action-shas.yml if updating versions
3. Wait for CODEOWNERS review

## Questions?

Open a discussion or reach out to @QuantumRishi/devops
