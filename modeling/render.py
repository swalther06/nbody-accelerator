import csv
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import imageio.v2 as imageio


class FrameState:
    def __init__(self, rx, ry, m):
        self.rx = rx
        self.ry = ry
        self.m = m


def load_states_csv(path):
    """Read a states CSV (as written by export.py / bitlevel_model.c) back
    into a list of per-step FrameState objects, ordered by step then particle."""
    steps = {}
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            steps.setdefault(int(row["step"]), []).append(row)

    states = []
    for step in sorted(steps):
        rows = sorted(steps[step], key=lambda r: int(r["particle"]))
        rx = np.array([float(r["rx"]) for r in rows])
        ry = np.array([float(r["ry"]) for r in rows])
        m = np.array([float(r["m"]) for r in rows])
        states.append(FrameState(rx, ry, m))
    return states


def render_video(states, path, fps=30, stride=10):
    all_x = np.concatenate([s.rx for s in states])
    all_y = np.concatenate([s.ry for s in states])
    all_m = np.concatenate([s.m for s in states])
    massive = all_m > 0
    all_x = all_x[massive]
    all_y = all_y[massive]
    margin = 0.1 * max(all_x.max() - all_x.min(), all_y.max() - all_y.min(), 1e-9)
    xlim = (all_x.min() - margin, all_x.max() + margin)
    ylim = (all_y.min() - margin, all_y.max() + margin)

    states = states[::stride]

    fig, ax = plt.subplots()
    writer = imageio.get_writer(path, fps=fps)
    try:
        for state in states:
            ax.clear()
            ax.set_xlim(xlim)
            ax.set_ylim(ylim)
            ax.set_aspect("equal")
            ax.scatter(state.rx, state.ry, s=20 * state.m)
            fig.canvas.draw()
            frame = np.asarray(fig.canvas.buffer_rgba())[:, :, :3]
            writer.append_data(frame)
    finally:
        writer.close()
        plt.close(fig)

    return path


def main():
    output_dir = os.path.join(os.path.dirname(__file__), "..", "output")
    states = load_states_csv(os.path.join(output_dir, "states.csv"))
    render_video(states, os.path.join(output_dir, "orbit.mp4"), fps=60, stride=1)


if __name__ == "__main__":
    main()
