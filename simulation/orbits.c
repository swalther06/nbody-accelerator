#include <string.h>
#include <stdlib.h>

#include "orbits.h"

// Mirrors orbits.py: each config is a function returning particle data
// (not static tables) because most need computed velocities (sqrt, etc.).

typedef struct {
    double rx, ry, rz;
    double vx, vy, vz;
    double m;
} OrbitParticle;

typedef struct {
    int n;
    double dt;
    OrbitParticle particles[N];
} OrbitSpec;

static OrbitSpec figure8_spec(void) {
    double x1 = 0.97000436, y1 = -0.24308753;
    double vx3 = -0.93240737, vy3 = -0.86473146;
    OrbitSpec spec = {
        .n = 3,
        .dt = 0.01,
        .particles = {
            { .rx = +x1, .ry = +y1, .vx = -vx3/2, .vy = -vy3/2, .m = 1.0 },
            { .rx = -x1, .ry = -y1, .vx = -vx3/2, .vy = -vy3/2, .m = 1.0 },
            { .rx = 0.0, .ry = 0.0, .vx = +vx3,   .vy = +vy3,   .m = 1.0 },
        },
    };
    return spec;
}

static OrbitSpec three_body_chaotic_spec(void) {
    OrbitSpec spec = {
        .n = 3,
        .dt = 0.01,
        .particles = {
            { .rx = -1.0, .ry = 0.0, .vx = 0.0,  .vy = -0.4, .m = 1.0 },
            { .rx = +1.0, .ry = 0.0, .vx = 0.0,  .vy = +0.4, .m = 1.0 },
            { .rx = 0.0,  .ry = 0.8, .vx = 0.35, .vy = 0.0,  .m = 1.0 },
        },
    };
    return spec;
}

static OrbitSpec four_ring_spec(void) {
    double M = 1.0, R = 1.0;
    double v = sqrt(M / R * (1.0/4.0) * (1 + 2*sqrt(2)) / sqrt(2));
    OrbitSpec spec = {
        .n = 4,
        .dt = 0.01,
        .particles = {
            { .rx = +R,  .ry = 0.0, .vx = 0.0, .vy = +v,  .m = M },
            { .rx = 0.0, .ry = +R,  .vx = -v,  .vy = 0.0, .m = M },
            { .rx = -R,  .ry = 0.0, .vx = 0.0, .vy = -v,  .m = M },
            { .rx = 0.0, .ry = -R,  .vx = +v,  .vy = 0.0, .m = M },
        },
    };
    return spec;
}

static OrbitSpec two_body_barycentric_spec(void) {
    double M = 1.0, m = 1.0;
    double d = 2.0;
    double r = d / 2;
    double v = 0.5 * sqrt((M + m) / d);
    OrbitSpec spec = {
        .n = 2,
        .dt = 0.01,
        .particles = {
            { .rx = -r, .ry = 0.0, .vx = 0.0, .vy = -v, .m = M },
            { .rx = +r, .ry = 0.0, .vx = 0.0, .vy = +v, .m = m },
        },
    };
    return spec;
}

static OrbitSpec two_body_circular_spec(void) {
    double M = 100.0, m = 1.0, r0 = 1.0;
    double mu = M + m;
    double v = sqrt(mu / r0);
    OrbitSpec spec = {
        .n = 2,
        .dt = 0.01,
        .particles = {
            { .rx = -(m/(M+m))*r0, .ry = 0.0, .vx = 0.0, .vy = +(m/(M+m))*v, .m = M },
            { .rx = +(M/(M+m))*r0, .ry = 0.0, .vx = 0.0, .vy = -(M/(M+m))*v, .m = m },
        },
    };
    return spec;
}

static OrbitSpec two_body_elliptical_spec(void) {
    double M = 500.0, m = 1.0, r0 = 12.0, ecc = 0.6;
    double mu = M + m;
    double v = sqrt(mu / r0) * sqrt(1 + ecc);
    OrbitSpec spec = {
        .n = 2,
        .dt = 0.01,
        .particles = {
            { .rx = -(m/(M+m))*r0, .ry = 0.0, .vx = 0.0, .vy = +(m/(M+m))*v, .m = M },
            { .rx = +(M/(M+m))*r0, .ry = 0.0, .vx = 0.0, .vy = -(M/(M+m))*v, .m = m },
        },
    };
    return spec;
}

typedef OrbitSpec (*OrbitSpecFn)(void);

typedef struct {
    const char *name;
    OrbitSpecFn fn;
} OrbitEntry;

static const OrbitEntry ORBIT_CONFIGS[] = {
    { "figure8",         figure8_spec },
    { "three_chaotic",   three_body_chaotic_spec },
    { "four_ring",       four_ring_spec },
    { "two_barycentric", two_body_barycentric_spec },
    { "two_circular",    two_body_circular_spec },
    { "two_elliptical",  two_body_elliptical_spec },
};

static inline int32_t to_fixed(double x) {
    return (int32_t)llround(x * (double)FRAC_SCALE);
}

double load_orbit_config(const char *name, State *state) {
    int num_configs = sizeof(ORBIT_CONFIGS) / sizeof(ORBIT_CONFIGS[0]);
    for (int c = 0; c < num_configs; ++c) {
        if (strcmp(ORBIT_CONFIGS[c].name, name) != 0) continue;

        OrbitSpec spec = ORBIT_CONFIGS[c].fn();
        if (spec.n > N) {
            fprintf(stderr, "orbit '%s' needs %d bodies but N=%d\n", name, spec.n, N);
            exit(1);
        }

        memset(state, 0, sizeof(*state));
        for (int i = 0; i < spec.n; ++i) {
            const OrbitParticle *p = &spec.particles[i];
            state->rx[i] = to_fixed(p->rx);
            state->ry[i] = to_fixed(p->ry);
            state->rz[i] = to_fixed(p->rz);
            state->vx[i] = to_fixed(p->vx);
            state->vy[i] = to_fixed(p->vy);
            state->vz[i] = to_fixed(p->vz);
            state->m[i]  = to_fixed(p->m);
        }

        return spec.dt;
    }

    fprintf(stderr, "unknown orbit '%s'\n", name);
    exit(1);
}
