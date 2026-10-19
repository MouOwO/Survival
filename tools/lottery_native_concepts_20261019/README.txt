Five offline Dota 2 lottery UI concepts

Review: docs/design/lottery_native_concepts_20261019/index.html

From the addon root:
  node tools/lottery_native_concepts_20261019/export.cjs
  node tools/lottery_native_concepts_20261019/build.cjs
  node tools/lottery_native_concepts_20261019/capture.cjs

The exporter reads installed Valve VPK files and verifies the selected texture hashes.
If decoding is needed, set SOURCE2VIEWER_CLI to a local Source2Viewer-CLI.exe.
The capture helper requires local Chrome and a loopback DevTools connection.
Use a writable D: TEMP/TMP folder if the system drive is full.
All reward, ticket and scene art is existing addon content; balances are review fixtures.
No game controller, account, purchase or draw requests are loaded.
These screenshots are design concepts, not in-game captures.
