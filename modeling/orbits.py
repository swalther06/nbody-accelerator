import csv
import os

# Orbit configs live in orbits.csv (shared with orbits.c), not here -- add a
# new orbit by appending rows there (same name on each of its particle rows),
# not by editing this file.
_CSV_PATH = os.path.join(os.path.dirname(__file__), "orbits.csv")


def _load_configs():
    configs = {}
    with open(_CSV_PATH, newline="") as f:
        for row in csv.DictReader(f):
            cfg = configs.setdefault(row["name"], {"n": 0, "dt": float(row["dt"]), "particles": []})
            cfg["particles"].append({k: float(row[k]) for k in ("rx", "ry", "rz", "vx", "vy", "vz", "m")})
            cfg["n"] = len(cfg["particles"])
    return configs


_configs = _load_configs()
# CONFIGS[name] is a zero-arg callable (not the dict directly) to match the
# pre-CSV interface, where each entry computed its particle data on call.
CONFIGS = {name: (lambda cfg=cfg: cfg) for name, cfg in _configs.items()}
