#ifndef REFERENCE_SIM_H
#define REFERENCE_SIM_H

// Optimized software software n-body - baseline for accelerator speedup numbers.

// Physics matches float64_model.py and bitlevel_model.c: G=1 units,
// a_i = sum_j m_j * dr_ij / (|dr_ij|^2 + eps^2)^(3/2), Stormer-Verlet
// (kick-drift-kick), softening eps^2 = 1e-6.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

#include "definitions.h"
#include "state.h"

#define EPS2 1e-6 

typedef struct {
    int n;
    double *rx, *ry, *rz;
    double *vx, *vy, *vz;
    double *ax, *ay, *az;
    double *vhx, *vhy, *vhz;   // half-step velocities
    double *m;
} Sim;

// Returns double* (not void*) and casts internally, so this header parses as
// both C and C++. C allows an implicit void*->double* conversion and C++ does
// not, and editors commonly language-server a bare .h as C++, which would
// otherwise flag every assignment in sim_alloc below.
static inline double *alloc_doubles(int n) {
    double *p = (double *)malloc((size_t)n * sizeof(double));
    if (!p) { fprintf(stderr, "out of memory\n"); exit(1); }
    return p;
}

static inline void sim_alloc(Sim *s, int n) {
    s->n = n;
    s->rx  = alloc_doubles(n); s->ry  = alloc_doubles(n); s->rz  = alloc_doubles(n);
    s->vx  = alloc_doubles(n); s->vy  = alloc_doubles(n); s->vz  = alloc_doubles(n);
    s->ax  = alloc_doubles(n); s->ay  = alloc_doubles(n); s->az  = alloc_doubles(n);
    s->vhx = alloc_doubles(n); s->vhy = alloc_doubles(n); s->vhz = alloc_doubles(n);
    s->m   = alloc_doubles(n);
}

static inline void sim_free(Sim *s) {
    free(s->rx);  free(s->ry);  free(s->rz);
    free(s->vx);  free(s->vy);  free(s->vz);
    free(s->ax);  free(s->ay);  free(s->az);
    free(s->vhx); free(s->vhy); free(s->vhz);
    free(s->m);
}

static inline void sim_copy(Sim *dst, const Sim *src) {
    size_t sz = (size_t)src->n * sizeof(double);
    memcpy(dst->rx, src->rx, sz); memcpy(dst->ry, src->ry, sz); memcpy(dst->rz, src->rz, sz);
    memcpy(dst->vx, src->vx, sz); memcpy(dst->vy, src->vy, sz); memcpy(dst->vz, src->vz, sz);
    memcpy(dst->ax, src->ax, sz); memcpy(dst->ay, src->ay, sz); memcpy(dst->az, src->az, sz);
    memcpy(dst->m,  src->m,  sz);
}

static inline void forces_full(Sim *s) {
    const int n = s->n;
    for (int i = 0; i < n; i++) {
        const double rxi = s->rx[i], ryi = s->ry[i], rzi = s->rz[i];
        double axi = 0.0, ayi = 0.0, azi = 0.0;
        for (int j = 0; j < n; j++) {
            if (j == i) continue;
            const double dx = s->rx[j] - rxi;
            const double dy = s->ry[j] - ryi;
            const double dz = s->rz[j] - rzi;
            const double r2  = dx*dx + dy*dy + dz*dz + EPS2;
            const double inv = 1.0 / sqrt(r2);
            const double f   = s->m[j] * inv * inv * inv;
            axi += f * dx; ayi += f * dy; azi += f * dz;
        }
        s->ax[i] = axi; s->ay[i] = ayi; s->az[i] = azi;
    }
}

static inline void forces_sym(Sim *s) {
    const int n = s->n;
    for (int i = 0; i < n; i++) { s->ax[i] = 0.0; s->ay[i] = 0.0; s->az[i] = 0.0; }
    for (int i = 0; i < n; i++) {
        const double rxi = s->rx[i], ryi = s->ry[i], rzi = s->rz[i];
        double axi = 0.0, ayi = 0.0, azi = 0.0;
        for (int j = i + 1; j < n; j++) {
            const double dx = s->rx[j] - rxi;
            const double dy = s->ry[j] - ryi;
            const double dz = s->rz[j] - rzi;
            const double r2   = dx*dx + dy*dy + dz*dz + EPS2;
            const double inv  = 1.0 / sqrt(r2);
            const double inv3 = inv * inv * inv;
            const double fi = s->m[j] * inv3;
            const double fj = s->m[i] * inv3;
            axi += fi * dx; ayi += fi * dy; azi += fi * dz;
            s->ax[j] -= fj * dx; s->ay[j] -= fj * dy; s->az[j] -= fj * dz;
        }
        s->ax[i] += axi; s->ay[i] += ayi; s->az[i] += azi;
    }
}

// Stormer-Verlet, same structure as bitlevel_model.c's main loop:
// half kick -> drift -> recompute forces -> half kick.
static inline void step(Sim *s, double dt, void (*forces)(Sim *)) {
    const int n = s->n;
    const double hdt = 0.5 * dt;
    for (int i = 0; i < n; i++) {
        s->vhx[i] = s->vx[i] + s->ax[i] * hdt;
        s->vhy[i] = s->vy[i] + s->ay[i] * hdt;
        s->vhz[i] = s->vz[i] + s->az[i] * hdt;
        s->rx[i] += s->vhx[i] * dt;
        s->ry[i] += s->vhy[i] * dt;
        s->rz[i] += s->vhz[i] * dt;
    }
    forces(s);
    for (int i = 0; i < n; i++) {
        s->vx[i] = s->vhx[i] + s->ax[i] * hdt;
        s->vy[i] = s->vhy[i] + s->ay[i] * hdt;
        s->vz[i] = s->vhz[i] + s->az[i] * hdt;
    }
}

static inline double total_energy(const Sim *s) {
    double ke = 0.0, pe = 0.0;
    for (int i = 0; i < s->n; i++)
        ke += 0.5 * s->m[i] * (s->vx[i]*s->vx[i] + s->vy[i]*s->vy[i] + s->vz[i]*s->vz[i]);
    for (int i = 0; i < s->n; i++)
        for (int j = i + 1; j < s->n; j++) {
            const double dx = s->rx[j] - s->rx[i];
            const double dy = s->ry[j] - s->ry[i];
            const double dz = s->rz[j] - s->rz[i];
            pe -= s->m[i] * s->m[j] / sqrt(dx*dx + dy*dy + dz*dz + EPS2);
        }
    return ke + pe;
}

static inline double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + 1e-9 * (double)ts.tv_nsec;
}

#endif
