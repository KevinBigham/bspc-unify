# Node runtime decision

- Date: 2026-07-12
- Status: implemented
- Decision: pin Node 22 across both app roots, Coach Functions, the parent portal, local version files, and CI.

## Evidence

- Node 20 reached end of life on 2026-03-24 and no longer receives security fixes: https://nodejs.org/en/about/eol
- Node 22 remains an LTS line, while Node 24 is the current latest LTS: https://nodejs.org/en/about/previous-releases
- Firebase Cloud Functions currently supports Node 22 and Node 20, but not Node 24: https://firebase.google.com/docs/functions/manage-functions#set_node.js_version
- Expo SDK 54 requires Node 20.19.x or newer: https://docs.expo.dev/versions/v54.0.0/

## Rationale

Node 22 is the supported intersection for Expo SDK 54 development and the Firebase Functions runtime. Node 20 is rejected because it is end-of-life; Node 24 is rejected for now because Firebase Functions does not list it as a supported runtime. Revisit when Firebase supports Node 24 or the schedulers leave Firebase.

## Verification

Run clean installs plus all app, Functions, portal, and build bars under Node 22. CI is the authoritative enforcement surface.
