# Integration, acceptance, and release baseline

## Intended flow

1. Open a pull request from a short-lived branch into `develop`. Require the
   `ci` check and review according to the repository's ruleset. A direct push
   to `develop` is blocked by the shipped policy.
2. A push to `develop`, including a merged pull request, runs `acceptance` on
   that exact commit. Initially `make acceptance` runs `make ci`; projects can
   extend it with a broader suite. A later push must not cancel an earlier
   acceptance run if that commit could become a release candidate.
3. Select an accepted `develop` commit, assign the candidate an immutable
   version and build its release artifact once. Record the source commit,
   version, artifact digests and build provenance. Keep the artifact and its
   evidence in durable storage with an explicit retention and access policy.
4. Test that exact candidate and retain a verdict tied to its commit and
   artifact digest. Release creation must require successful acceptance for the
   selected commit and candidate; a green run for a different commit or a
   rebuilt artifact is insufficient. A failed or incomplete gate must not
   silently produce a successful release.
5. Create the release from that accepted candidate. A release is a golden
   build: it has passed every required test and analysis and is eligible for
   production. Promotion publishes or deploys the same verified artifact,
   rather than rebuilding it. Only after a
   successful promotion and destination-specific verification should `main`
   advance to the source commit represented by the promoted artifact.

The .NET foundation implements steps 1 and 2 only. It does not ship a product,
create candidates or releases, publish packages, deploy services, or advance
`main`. A derived project must implement steps 3–5 and explicitly connect each
gate. Neither a `develop` push nor a green acceptance result is a release.

A candidate may be stored in a draft release or another durable candidate
store while testing. The chosen mechanism must prevent mutation or detect and
reject it; draft status alone does not guarantee immutability. Publish the
release only after acceptance succeeds. Promotion must verify the acceptance
evidence and provenance for the exact artifact it is about to publish or
deploy. Manual approval can add a gate but does not replace that verification.

A release may include several accepted pull requests, and `develop` can advance
while a candidate is being tested. Select and verify the immutable commit and
artifact, rather than assuming the latest branch tip is still the candidate.
Do not use hashes alone as proof of origin: a manifest and its contents can be
replaced together. Verify an attestation or another trusted provenance record.

Retries must reuse the accepted artifact or fail on a conflict; do not overwrite
already-released bytes with a rebuild. NuGet registries and other destinations
may transform artifacts, so document which digest is verified at each boundary.
Promotion and recording `main` are separate operations: if promotion succeeds
and recording fails, report the actual deployed or published version and repair
the record without publishing again.

A rollback is also a promotion. A protected `main` that only fast-forwards
cannot point back to an older deployed commit. The deployment or publication
record must remain the source of truth when a rollback or partial failure means
`main` cannot represent the active version; changing that policy needs an
explicit decision. Concurrent promotions must not let an older run overwrite a
newer one accidentally.

## Standard phase names

These names are the shared contract for Make targets and the corresponding
pipeline phases. A project may have multiple jobs within a phase; the name alone
is not evidence of a passed gate.

| Target | Responsibility |
| --- | --- |
| `ci` | Validate a pull request into the integration branch. |
| `acceptance` | Validate the integrated `develop` commit, initially with the same checks as `ci`. |
| `candidate` | Build once and store a versioned candidate and provenance for an accepted commit. |
| `candidate-acceptance` | Test that exact candidate and record results bound to its identity and digest. |
| `release` | Verify required results and publish the golden release without rebuilding. |
| `publish` | Promote the verified release to the destination, such as a package registry or production environment. |
| `record-release` | After successful promotion, record the released source on `main` or report why recording failed. |

`ci` and `acceptance` are implemented in this foundation. The remaining targets
are reserved placeholders that fail with a clear message until a downstream
project replaces their recipes; they must never report an unimplemented phase
as successful. The placeholders do not trigger or chain release operations.
Downstream implementations and pipeline jobs must explicitly connect and
verify the relevant commit, version, artifact digest, provenance, and results.
A failure or skipped required check must block release or promotion.

## What is shared and what varies

| Shared baseline | Project-specific implementation |
| --- | --- |
| PR validation, post-integration acceptance, and separate entry points | Test commands, toolchain, runtime, and acceptance depth |
| Candidate identified by source commit, version, and artifact digest | Package, executable, site archive, container image, or other output |
| Evidence and provenance checked before release and promotion | SBOM generator, signing service, registry, deployment environment, and credentials |
| Promote tested bytes and record the successfully promoted source | Destination-specific verification, rollback, and authorization |
| Read-only PR jobs and minimal rights in trusted jobs | Availability of scanning, attestations, and branch policy on the hosting account |

The homepage is a useful example of protected integration, one packaged artifact,
attestation, test deployment, manual production promotion, and a post-promotion
`main` update. Its current ordering differs from the target: release-please
publishes a GitHub Release before the package is built and tested; the
post-merge `develop` checks run separately and do not directly gate that
publication. Production promotion verifies the package but does not explicitly
require the matching test-deployment run to have succeeded. On rollback, its
fast-forward-only `main` intentionally stays at the newer commit. These are
follow-up alignment items, not guarantees supplied by this foundation.

## Adoption and branch protection

Create `develop` and ensure the CI workflow runs for a PR to it before applying
`develop-protection`. The shipped rulesets require one review and `ci` on both
protected branches. An admin can bypass them during a pull request, including a
red check; this is not a hard approval boundary for a sole maintainer.

The shipped `main` ruleset has no automation bypass. A project that needs an
automated post-promotion update must explicitly provision a narrowly scoped
identity and configure its ruleset bypass, or use a reviewed alternative. A
bypass can skip other rules too, so document the actual authority and verify
provenance and promotion before invoking it. Do not copy the homepage's
account-specific App ID into a general template.

`make rulesets-apply` changes live GitHub configuration and is never run by the
CI workflow. Review the repository's existing rules and merge settings before
applying it. A required check must run on every PR into a protected branch;
otherwise it can block all merges or provide no real gate.

Security scanning, dependency updates, and Actions dependency pinning are part
of the baseline alignment work still to be specified and validated against each
repository's hosting and dependency ecosystem. This file does not claim those
checks or a release pipeline are already implemented.
