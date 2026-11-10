# Release bundle contract

The foundation provides a portable way to collect **already-built** files into a
bundle with a version, source-commit identifier, file sizes, and SHA-256 hashes.
It does not choose a release trigger, build a distributable, sign it, upload it,
or deploy it. A specialized template supplies those parts.

A NuGet template may put packages and their SBOMs in the input directory. A
command-line template may put platform archives there. A service template may
instead bundle manifests and immutable container-image references; the image
itself then needs separate verification using its registry digest. The input
must contain only the files intended for this release bundle.

```sh
make release-bundle RELEASE_INPUT=path/to/finished/files \
  RELEASE_VERSION=1.2.3 RELEASE_COMMIT="$(git rev-parse HEAD)"
make release-bundle-verify
```

The default output is `artifacts/release-bundle`; set `RELEASE_OUTPUT` to choose
another path. Creation fails if the destination already exists. Preserve the
bundle as an immutable artifact and promote that same bundle rather than
rebuilding it. The tool rejects empty inputs and symbolic links. Verification
checks the complete payload file list, sizes, and hashes against `manifest.json`.
It does not validate empty directories, executable permission bits, or external
container images.

The manifest is **not a signature or provenance attestation**. An attacker able
to replace both the payload and the manifest can make verification pass. The
version and source commit are caller-supplied claims: the script does not prove
which source produced the files. A release workflow must validate the source
and version, run appropriate checks, and protect or attest the bundle before
trusting or promoting it. Ensure retries reuse the original artifact and fail
on conflicting existing releases rather than replacing already-published bytes.

The specialized templates must also decide how to generate and attach SBOMs,
verify provenance, manage credentials, and handle destinations that transform
artifacts. For example, nuget.org's repository signature changes package bytes
on upload, so the served file's digest differs from the built file's digest.

`eng/scripts/release_bundle.py` is a local building block. There is no active
release workflow, remote publishing, or automatic template synchronization in
this foundation yet.
