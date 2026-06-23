import csv


def write_states_csv(states, path, dt):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["step", "t", "particle", "rx", "ry", "rz", "vx", "vy", "vz", "ax", "ay", "az", "m"])
        for step, state in enumerate(states):
            t = step * dt
            for i in range(len(state.rx)):
                writer.writerow([
                    step, t, i,
                    state.rx[i], state.ry[i], state.rz[i],
                    state.vx[i], state.vy[i], state.vz[i],
                    state.ax[i], state.ay[i], state.az[i],
                    state.m[i],
                ])

    return path
