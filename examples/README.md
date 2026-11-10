# Historical NuGet workflow

`nuget-publish.yml.reference` preserves the former tag-triggered workflow for
the future NuGet-specific template. It is outside `.github/workflows/` and is
not active. It refers to the former example project and release setup; do not
copy it unchanged into a production repository. Its release-source validation,
retry behavior, and artifact handling need to be redesigned around the release
contract before use.

`legacy-readme.txt` preserves the previous detailed documentation as historical
context. Its workflow and CI descriptions no longer describe this branch.
