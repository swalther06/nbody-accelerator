import numpy as np

# Each config is a function returning a list of particle dicts.
# Functions (not static data) because most need computed velocities (sqrt, etc.).

def _figure8():
    x1, y1   =  0.97000436, -0.24308753
    vx3, vy3 = -0.93240737, -0.86473146
    return {
        "n": 3,
        "dt": 0.01,
        "particles": [
            dict(rx=+x1, ry=+y1, vx=-vx3/2, vy=-vy3/2, m=1.0),
            dict(rx=-x1, ry=-y1, vx=-vx3/2, vy=-vy3/2, m=1.0),
            dict(rx=0.0, ry=0.0, vx=+vx3,   vy=+vy3,   m=1.0),
        ],
    }

def _three_body_chaotic():
    return {
        "n": 3,
        "dt": 0.01,
        "particles": [
            dict(rx=-1.0, ry=0.0, vx=0.0,  vy=-0.4, m=1.0),
            dict(rx=+1.0, ry=0.0, vx=0.0,  vy=+0.4, m=1.0),
            dict(rx=0.0,  ry=0.8, vx=0.35, vy=0.0,  m=1.0),
        ],
    }

def _four_ring():
    M, R = 1.0, 1.0
    v = np.sqrt(M / R * (1/4) * (1 + 2*np.sqrt(2)) / np.sqrt(2))
    return {
        "n": 4,
        "dt": 0.01,
        "particles": [
            dict(rx=+R, ry=0.0, vx=0.0, vy=+v, m=M),
            dict(rx=0.0, ry=+R, vx=-v, vy=0.0, m=M),
            dict(rx=-R, ry=0.0, vx=0.0, vy=-v, m=M),
            dict(rx=0.0, ry=-R, vx=+v, vy=0.0, m=M),
        ],
    }

def _two_body_barycentric():
    M = m = 1.0
    d = 2.0
    r = d / 2
    v = 0.5 * np.sqrt((M + m) / d)
    return {
        "n": 2,
        "dt": 0.01,
        "particles": [
            dict(rx=-r, ry=0.0, vx=0.0, vy=-v, m=M),
            dict(rx=+r, ry=0.0, vx=0.0, vy=+v, m=m),
        ],
    }

def _two_body_circular(M=100.0, m=1.0, r0=1.0):
    mu = M + m
    v = np.sqrt(mu / r0)                      # circular: exactly circular speed
    return {
        "n": 2,
        "dt": 0.01,
        "particles": [
            dict(rx=-(m/(M+m))*r0, ry=0.0, vx=0.0, vy=+(m/(M+m))*v, m=M),
            dict(rx=+(M/(M+m))*r0, ry=0.0, vx=0.0, vy=-(M/(M+m))*v, m=m),
        ],
    }

def _two_body_elliptical(M=500.0, m=1.0, r0=12.0, ecc=0.6):
    mu = M + m
    v = np.sqrt(mu / r0) * np.sqrt(1 + ecc)  # >circular -> ellipse, start = perihelion
    return {
        "n": 2,
        "dt": 0.01,
        "particles": [
            dict(rx=-(m/(M+m))*r0, ry=0.0, vx=0.0, vy=+(m/(M+m))*v, m=M),
            dict(rx=+(M/(M+m))*r0, ry=0.0, vx=0.0, vy=-(M/(M+m))*v, m=m),
        ],
    }

CONFIGS = {
    "figure8":            _figure8,
    "three_chaotic":      _three_body_chaotic,
    "four_ring":          _four_ring,
    "two_barycentric":    _two_body_barycentric,
    "two_circular":       _two_body_circular,
    "two_elliptical":     _two_body_elliptical,
}