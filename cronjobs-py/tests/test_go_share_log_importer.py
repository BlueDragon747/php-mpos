from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


def load_importer():
    path = (
        Path(__file__).resolve().parents[1]
        / ".."
        / "deploy-bundle"
        / "scripts"
        / "go-share-log-importer.py"
    ).resolve()
    spec = importlib.util.spec_from_file_location("go_share_log_importer", path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_worker_lookup_keeps_exact_workers():
    importer = load_importer()

    lookup = importer.build_worker_lookup(["admin.rig1", "rig1"])

    assert lookup["admin.rig1"] == "admin.rig1"
    assert lookup["rig1"] == "rig1"


def test_worker_lookup_accepts_unique_bare_suffix():
    importer = load_importer()

    lookup = importer.build_worker_lookup(["admin.rig1", "admin.rig2"])

    assert lookup["rig1"] == "admin.rig1"
    assert lookup["rig2"] == "admin.rig2"


def test_worker_lookup_can_disable_bare_suffixes():
    importer = load_importer()

    lookup = importer.build_worker_lookup(
        ["admin.rig1"],
        allow_bare_suffixes=False,
    )

    assert lookup["admin.rig1"] == "admin.rig1"
    assert "rig1" not in lookup


def test_worker_lookup_rejects_ambiguous_bare_suffix():
    importer = load_importer()

    lookup = importer.build_worker_lookup(["admin.rig1", "other.rig1"])

    assert lookup["admin.rig1"] == "admin.rig1"
    assert lookup["other.rig1"] == "other.rig1"
    assert "rig1" not in lookup


def test_worker_lookup_accepts_unique_dotted_suffix():
    importer = load_importer()

    lookup = importer.build_worker_lookup(["admin.rig-1.foo"])

    assert lookup["rig-1.foo"] == "admin.rig-1.foo"
