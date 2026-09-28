#!/usr/bin/env python3
"""Fetch and verify the locked external programs installed on the SD image."""
from dataclasses import dataclass
from hashlib import sha256
import os
from pathlib import Path
import re
import tempfile
import tomllib
from urllib.request import Request, urlopen

from sd_image import SD_DRIVES, disk_name

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'games.lock.toml'
CACHE = ROOT / 'build/external'
LOCK_SCHEMA = 1
SHA256_RE = re.compile(r'[0-9a-f]{64}\Z')
COMMIT_RE = re.compile(r'[0-9a-f]{40}\Z')
VERSION_RE = re.compile(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z')
REPOSITORY_RE = re.compile(r'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z')


@dataclass(frozen=True)
class Artifact:
    """One CP/M file published as a release asset of a locked program."""
    name: str
    sha256: str
    release_url: str


@dataclass(frozen=True)
class LockedGame:
    """An external program pinned to one tagged release and commit."""
    identifier: str
    repository: str
    version: str
    commit: str
    drive: int
    artifacts: tuple


def _string(table, key, context):
    value = table.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f'{context}.{key} must be a non-empty string')
    return value


def load_lock(path=LOCK):
    """Load and validate the lock file; return its programs in order."""
    try:
        document = tomllib.loads(Path(path).read_text(encoding='utf-8'))
    except tomllib.TOMLDecodeError as error:
        raise ValueError(f'Invalid game lock TOML: {error}') from error
    if document.get('schema') != LOCK_SCHEMA or set(document) - {'schema', 'games'}:
        raise ValueError('Unsupported game lock schema')
    raw_games = document.get('games')
    if not isinstance(raw_games, list) or not raw_games:
        raise ValueError('The game lock must contain at least one game')
    games, identifiers, targets = [], set(), set()
    for index, raw in enumerate(raw_games, 1):
        context = f'games[{index}]'
        if not isinstance(raw, dict):
            raise ValueError(f'{context} must be a table')
        unknown = set(raw) - {'id', 'repository', 'version', 'commit', 'drive', 'user', 'artifacts'}
        if unknown:
            raise ValueError(f'Unknown key in {context}: {sorted(unknown)[0]}')
        identifier = _string(raw, 'id', context)
        if not re.fullmatch(r'[a-z0-9-]+', identifier) or identifier in identifiers:
            raise ValueError(f'{context}.id must be unique lowercase text')
        identifiers.add(identifier)
        repository = _string(raw, 'repository', context)
        if not REPOSITORY_RE.fullmatch(repository):
            raise ValueError(f'{context}.repository must be a GitHub repository URL')
        version = _string(raw, 'version', context)
        if not VERSION_RE.fullmatch(version):
            raise ValueError(f'{context}.version must be vMAJOR.MINOR.PATCH')
        commit = _string(raw, 'commit', context).lower()
        if not COMMIT_RE.fullmatch(commit):
            raise ValueError(f'{context}.commit must be a 40-character commit ID')
        letter = _string(raw, 'drive', context).upper()
        drive = ord(letter) - ord('A') if len(letter) == 1 else -1
        if not 0 <= drive < SD_DRIVES:
            raise ValueError(f'{context}.drive must be an SD drive A-K')
        if raw.get('user') != 0:
            raise ValueError(f'{context}.user must be 0; the image tool writes user 0')
        raw_artifacts = raw.get('artifacts')
        if not isinstance(raw_artifacts, list) or not raw_artifacts:
            raise ValueError(f'{context}.artifacts must be a non-empty list')
        artifacts = []
        for artifact_index, item in enumerate(raw_artifacts, 1):
            item_context = f'{context}.artifacts[{artifact_index}]'
            if not isinstance(item, dict) or set(item) != {'path', 'sha256', 'release_url'}:
                raise ValueError(f'{item_context} must contain path, sha256 and release_url')
            name = _string(item, 'path', item_context)
            disk_name(name)  # rejects anything that is not a CP/M 8.3 filename
            digest = _string(item, 'sha256', item_context).lower()
            if not SHA256_RE.fullmatch(digest):
                raise ValueError(f'{item_context}.sha256 must be a SHA-256 digest')
            url = _string(item, 'release_url', item_context)
            if url != f'{repository}/releases/download/{version}/{name}':
                raise ValueError(f'{item_context}.release_url must be the {version} asset {name}')
            if (drive, name.upper()) in targets:
                raise ValueError(f'Duplicate installed file {name} on drive {chr(65 + drive)}:')
            targets.add((drive, name.upper()))
            artifacts.append(Artifact(name, digest, url))
        games.append(LockedGame(identifier, repository, version, commit, drive, tuple(artifacts)))
    return tuple(games)


def _download(url):
    request = Request(url, headers={'User-Agent': 'p2000m-cpm-build'})
    try:
        with urlopen(request, timeout=60) as response:
            return response.read()
    except OSError as error:
        raise ValueError(f'Could not download {url}: {error}') from error


def _write_atomically(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        temporary.write(data)
    os.replace(temporary.name, path)


def fetch(game, artifact, cache=CACHE, download=_download):
    """Return a verified artifact, reusing a matching cached copy when present."""
    cached = Path(cache) / game.identifier / game.version / artifact.name
    if cached.is_file() and sha256(cached.read_bytes()).hexdigest() == artifact.sha256:
        return cached.read_bytes()
    data = download(artifact.release_url)
    actual = sha256(data).hexdigest()
    if actual != artifact.sha256:
        raise ValueError(f'{game.identifier} {game.version} {artifact.name}: '
                         f'SHA-256 {actual} does not match the lock')
    _write_atomically(cached, data)
    return data


def install(destination, games=None, cache=CACHE, download=_download):
    """Write every verified artifact to destination; return {drive: [paths]}."""
    games = load_lock() if games is None else games
    by_drive = {}
    for game in games:
        for artifact in game.artifacts:
            target = Path(destination) / artifact.name
            _write_atomically(target, fetch(game, artifact, cache, download))
            by_drive.setdefault(game.drive, []).append(target)
    return by_drive


def manifest(games):
    """Describe the locked programs for build-info.json."""
    return {game.identifier: {
        'repository': game.repository, 'version': game.version, 'commit': game.commit,
        'drive': chr(65 + game.drive),
        'files': {artifact.name: artifact.sha256 for artifact in game.artifacts},
    } for game in games}
