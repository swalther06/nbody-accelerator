import os
import sys

import numpy as np
from export import write_states_csv
from orbits import CONFIGS

EPS_SQUARED = 1e-5 ** 2
G = 6.67430e-11
WIDTH = 10

class State:
    def __init__(self, N):
        self.rx = np.zeros(N)
        self.ry = np.zeros(N)
        self.rz = np.zeros(N)
        self.vx = np.zeros(N)
        self.vy = np.zeros(N)
        self.vz = np.zeros(N)
        self.ax = np.zeros(N)
        self.ay = np.zeros(N)
        self.az = np.zeros(N)
        self.m = np.zeros(N)
    
    def copy(self, other_state):
        self.rx = np.copy(other_state.rx)
        self.ry = np.copy(other_state.ry)
        self.rz = np.copy(other_state.rz)
        self.vx = np.copy(other_state.vx)
        self.vy = np.copy(other_state.vy)
        self.vz = np.copy(other_state.vz)
        self.ax = np.copy(other_state.ax)
        self.ay = np.copy(other_state.ay)
        self.az = np.copy(other_state.az)
        self.m = np.copy(other_state.m)


def calc_scaled_gravitational_acceleration(x_i, y_i, z_i, x_j, y_j, z_j, m_j):
    # don't multiply by G 
    dx = x_j - x_i
    dy = y_j - y_i
    dz = z_j - z_i
    denominator = (dx**2 + dy**2 + dz**2 + EPS_SQUARED) ** (3/2) 

    return (m_j * dx / denominator), (m_j * dy / denominator), (m_j * dz / denominator)


def create_particle(state, i, rx=0, ry=0, rz=0, vx=0, vy=0, vz=0, m=1):
    state.rx[i] = rx
    state.ry[i] = ry
    state.rz[i] = rz
    state.vx[i] = vx
    state.vy[i] = vy
    state.vz[i] = vz
    state.m[i]  = m


def accumulate_accelerations(ax, ay, az):
    return np.sum(ax), np.sum(ay), np.sum(az)


def calculate_particle_acceleration(i, rx, ry, rz, m, N):
    ax_reg, ay_reg, az_reg = 0, 0, 0
    num_cycles = np.ceil(N / WIDTH)

    for cycles in range(int(num_cycles)):
        ax_wire = np.zeros(WIDTH)
        ay_wire = np.zeros(WIDTH)
        az_wire = np.zeros(WIDTH)

        for j in range(WIDTH):
            ax_wire[j], ay_wire[j], az_wire[j] = calc_scaled_gravitational_acceleration(rx[i], ry[i], rz[i], rx[cycles * WIDTH + j], ry[cycles * WIDTH + j], rz[cycles * WIDTH + j], m[cycles * WIDTH + j])
        ax, ay, az = accumulate_accelerations(ax_wire, ay_wire, az_wire)
        ax_reg += ax
        ay_reg += ay
        az_reg += az

    return ax_reg, ay_reg, az_reg


def calculate_new_positions(rx, ry, rz, vx, vy, vz, ax, ay, az, dt):
    vx_half = vx + ax * (dt / 2)
    vy_half = vy + ay * (dt / 2)
    vz_half = vz + az * (dt / 2)

    rx_new = rx + vx_half * dt
    ry_new = ry + vy_half * dt
    rz_new = rz + vz_half * dt

    return rx_new, ry_new, rz_new, vx_half, vy_half, vz_half


def calculate_new_velocity(vx_half, vy_half, vz_half, ax_new, ay_new, az_new, dt):
    vx_new = vx_half + ax_new * (dt / 2)
    vy_new = vy_half + ay_new * (dt / 2)
    vz_new = vz_half + az_new * (dt / 2)

    return vx_new, vy_new, vz_new


def load_config(name, state, N):
    """Populate `state` (size N) with the named orbit configuration.
    Returns the config's suggested dt. Unused slots stay mass 0."""
    if name not in CONFIGS:
        raise ValueError(f"unknown config '{name}'. options: {list(CONFIGS)}")
    cfg = CONFIGS[name]()
    if cfg["n"] > N:
        raise ValueError(f"config '{name}' needs {cfg['n']} bodies but N={N}")
    for i, p in enumerate(cfg["particles"]):
        create_particle(state, i,
                        rx=p.get("rx",0.0), ry=p.get("ry",0.0), rz=p.get("rz",0.0),
                        vx=p.get("vx",0.0), vy=p.get("vy",0.0), vz=p.get("vz",0.0),
                        m=p["m"])
    return cfg["dt"]


def seed_accelerations(state, N):
    for i in range(N):
        state.ax[i], state.ay[i], state.az[i] = \
            calculate_particle_acceleration(i, state.rx, state.ry, state.rz, state.m, N)


def calculate_total_energy(state, N):
    kinetic = 0.5 * np.sum(state.m * (state.vx**2 + state.vy**2 + state.vz**2))

    potential = 0.0
    for i in range(N):
        for j in range(i + 1, N):
            dx = state.rx[j] - state.rx[i]
            dy = state.ry[j] - state.ry[i]
            dz = state.rz[j] - state.rz[i]
            r = np.sqrt(dx**2 + dy**2 + dz**2 + EPS_SQUARED)
            potential -= state.m[i] * state.m[j] / r

    return kinetic + potential


def main(orbit_type="figure8"):
    N = 10

    t = 0
    t_end = 10

    state = State(N)
    dt = load_config(orbit_type, state, N)

    seed_accelerations(state, N)
    states = [state]
    energies = [calculate_total_energy(state, N)]
    while (t < t_end):
        new_state = State(N)
        new_state.copy(state)

        vx_half = np.zeros(N)
        vy_half = np.zeros(N)
        vz_half = np.zeros(N)

        for i in range(N):
            new_state.rx[i], new_state.ry[i], new_state.rz[i], vx_half[i], vy_half[i], vz_half[i] = \
            calculate_new_positions(state.rx[i], state.ry[i], state.rz[i], state.vx[i], state.vy[i], state.vz[i], state.ax[i], state.ay[i], state.az[i], dt)

        for i in range(N):
            new_state.ax[i], new_state.ay[i], new_state.az[i] = calculate_particle_acceleration(i, new_state.rx, new_state.ry, new_state.rz, state.m, N)

        for i in range(N):
            new_state.vx[i], new_state.vy[i], new_state.vz[i] = \
            calculate_new_velocity(vx_half[i], vy_half[i], vz_half[i], new_state.ax[i], new_state.ay[i], new_state.az[i], dt)

        state = new_state
        t += dt
        states.append(state)
        energies.append(calculate_total_energy(state, N))

    drift = (energies[-1] - energies[0]) / abs(energies[0])
    print(f"Initial energy: {energies[0]:.6f}")
    print(f"Final energy:   {energies[-1]:.6f}")
    print(f"Relative drift: {drift:.3%}")

    output_dir = os.path.join(os.path.dirname(__file__), "output")
    os.makedirs(output_dir, exist_ok=True)
    write_states_csv(states, os.path.join(output_dir, "states.csv"), dt)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "figure8")
