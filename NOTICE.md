# Notices and attribution

This repository is an **unofficial, community-maintained build toolkit**. It is
not affiliated with, endorsed by, or published by DeepSeek.

## DeepSeek Harness

- Upstream: <https://github.com/deepseek-ai/deepseek-harness>
- License: MIT (see the upstream repository)
- Copyright: DeepSeek and upstream contributors

`patches/linux-x64-support.patch` contains a small diff against upstream source
files (`apps/desktop/...`) and is provided under the same MIT terms. The scripts
here do not redistribute the upstream source; they operate on a checkout that
the user obtains directly from upstream.

## Icons

`assets/icons/*.png` are hicolor renditions of the DeepSeek Harness desktop
application icon. They are included only so that electron-builder can produce a
locally installable package with a correct desktop icon. DeepSeek Harness and
its marks belong to DeepSeek; do not use these assets to imply endorsement or
to redistribute the application.

If you prefer not to include them, delete `assets/icons/` and drop a matching
`apps/desktop/resources/icons/` directory (16–512 px PNGs) into your upstream
checkout before building.

## dsh-purge compatibility note

`plugin-patch/` documents a local compatibility fix for the third-party
`dsh-purge-community` plugin (MIT, <https://github.com/kingcharleslzy-ai/dsh-purge>).
It edits only the installed plugin's patch table; no plugin source is
redistributed here.
