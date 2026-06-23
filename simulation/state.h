#ifndef STATE_H
#define STATE_H

#include <stdint.h>

#include "definitions.h"

typedef struct {
    int32_t rx[N];
    int32_t ry[N];
    int32_t rz[N];
    int32_t vx[N];
    int32_t vy[N];
    int32_t vz[N];
    int32_t ax[N];
    int32_t ay[N];
    int32_t az[N];
    int32_t m[N];
} State;

#endif // STATE_H
