# Package metadata and SBOM adoption

- For each NuGet package, declare its package ID, author, description, license,
  readme, and project and repository URLs in the packable project. The example
  project shows the layout. Verify the metadata in the built package before
  release. Set repository-wide values in your own shared props where appropriate.
- Select one finished deliverable and its resolved project graph before
  generating an SBOM. For NuGet, select one package and its symbol package.
  For a command-line application, select its publish output for the intended
  runtime. For an Aspire service, inventory each deployable image and associate
  its inventory with the registry digest used for promotion.
- Set the version to the one embedded in that deliverable. Keep the SBOM with
  the candidate and verify it refers to the artifact selected for promotion.
  Use a separate output directory for each deliverable.

```sh
make sbom SBOM_BUILD_DROP=artifacts/package/my-library \
  SBOM_PROJECT=my-library SBOM_PACKAGE_NAME=My.Library \
  SBOM_PACKAGE_VERSION=1.2.3 SBOM_PACKAGE_SUPPLIER=my-organization \
  SBOM_NAMESPACE_BASE=https://github.com/my-organization/my-library \
  SBOM_DIR=artifacts/sbom/my-library
```

`SBOM_PROJECT` selects a project under `artifacts/obj`. Use
`SBOM_COMPONENT_PATH` to pass a different directory containing that project's
`project.assets.json`. The SPDX document includes the resolved build graph,
which can contain analyzers and other build-time dependencies. Use an
image-aware inventory for the runtime contents of a container.
