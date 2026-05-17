import logging
import sys

_FMT = "%(asctime)s.%(msecs)03d %(levelname)-7s %(name)s :: %(message)s"
_DATEFMT = "%Y-%m-%d %H:%M:%S"


def setup(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter(_FMT, datefmt=_DATEFMT))
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(getattr(logging, level.upper(), logging.INFO))


def get(name: str) -> logging.Logger:
    return logging.getLogger(name)
