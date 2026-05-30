import pytest

from cronjobs_py.errors import Fatal
from cronjobs_py.settings import slot_int


def test_slot_int_uses_parent_value_for_parent_slot() -> None:
    assert (
        slot_int({"confirmations": 120, "confirmations_mm3": 460}, "confirmations", "", 100)
        == 120
    )


def test_slot_int_uses_slot_value_for_aux_slot() -> None:
    assert (
        slot_int({"confirmations": 120, "confirmations_mm3": 460}, "confirmations", "mm3", 100)
        == 460
    )


def test_slot_int_falls_back_to_parent_value_for_missing_aux_slot() -> None:
    assert slot_int({"confirmations": 120}, "confirmations", "mm5", 100) == 120


def test_slot_int_falls_back_to_default_when_no_value_exists() -> None:
    assert slot_int({}, "confirmations", "mm5", 100) == 100


def test_slot_int_raises_clear_fatal_for_bad_slot_value() -> None:
    with pytest.raises(Fatal, match="confirmations_mm3"):
        slot_int(
            {"confirmations": 120, "confirmations_mm3": "bad"},
            "confirmations",
            "mm3",
            100,
        )


def test_slot_int_raises_clear_fatal_for_bad_parent_value() -> None:
    with pytest.raises(Fatal, match="confirmations"):
        slot_int({"confirmations": ""}, "confirmations", "mm5", 100)
