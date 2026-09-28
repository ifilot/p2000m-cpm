# External programs

Some programs on the SD image are developed in their own repositories. They
are pinned in [`games.lock.toml`](../games.lock.toml) and installed by
`tools/build.py`:

| Program | Repository | Drive |
| --- | --- | --- |
| Othello | [ifilot/p2000m-othello](https://github.com/ifilot/p2000m-othello) | J: GAMES |

Each entry names the release tag, its commit, the target drive, and every
installed file with its GitHub release-asset URL and SHA-256 digest. The build
downloads each asset once, rejects it unless the digest matches, and caches the
verified copy under `build/external/<id>/<version>/`. It then copies the file
to `build/` and installs it on the drive. `build-info.json` records the
repository, version, commit and digests under `external_programs`.

Building therefore needs network access once, but no Docker or Z88DK: the
programs are compiled and released by their own repositories' CI.

## Updating a program

1. Tag and release the new version in the program's repository.
2. Update `version`, `commit`, `release_url` and `sha256` in the lock. The
   digest of a release asset can be computed with

   ```sh
   curl -sL <release_url> | sha256sum
   ```

3. Run `python3 tools/build.py` and the complete test suite.
   `tests/othello_ui.cpp` plays the installed game on the emulated machine and
   checks the version shown on its help screen, so update that string as well.

The lock format follows the P2000C ZuluBlaster distribution, restricted to
release assets. `tools/games.py` validates it strictly: unknown keys, non-8.3
filenames, drives outside A-K, duplicate files, and URLs that do not belong to
the locked tag are all rejected.
