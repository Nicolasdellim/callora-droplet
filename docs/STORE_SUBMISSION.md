# Preparing Droplet Store review

GitHub is the source repository. The Store is the independent GitLab repository at https://gitlab.com/droppyformac1/droplets. No Store merge request or terms acceptance was performed in this task.

The current Store accepts `droplet.json`, `Package.swift`, `Sources/`, `Assets/`, `CHANGELOG.md` and `README.md`; it rejects test targets, scripts and extra documentation. Keep those in GitHub. Create a separate staging checkout, copy allowed files, remove the `.testTarget` from its Package.swift, and adapt documentation so it has no links to omitted files. Validate the staged package with `droppykit validate` (without `--no-submission`).

The current Store policy says Jordy supplies the final Icon Composer icon. Exclude `Callora.icon` and custom icon exports from the submission. Include a concept description: "A dark island capsule above a detached silver glass video rectangle, with a restrained cool-white docking accent." The repository's custom `.icon` remains development artwork. Do not rename a PNG to `.icon`.

Before submission, obtain the actual creator's GitLab identity and approved creator avatar, complete the real-call validation gates, and check the permanent `callora` id is available. This repository uses the authenticated GitHub account as attribution and an original neutral creator mark, not a claimed personal portrait or GitLab identity.

The Store's developer terms are at https://getdroppy.app/droplet-developer-terms. Once the owner accepts those terms and authorizes submission, use the official `droppykit submit --print` to review the GitLab publication plan, then the normal fork/merge-request flow. A successful local `--no-submission` validation says nothing about Store acceptance.

Signing and notarization are handled by Store publication after review. Local bundles are development builds without a distribution signature and require host approval in Droppy. No certificate, signature or published release has been fabricated.
