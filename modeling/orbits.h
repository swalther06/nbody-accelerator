#ifndef ORBITS_H
#define ORBITS_H

#include "state.h"

// Zeros `state` and populates it with the named orbit configuration,
// converting real-valued positions/velocities/masses into Q(FRAC_BITS)
// fixed point. Returns the config's suggested dt as a real (non-fixed)
// value; the caller is responsible for converting it to fixed point.
// Exits the process if the name is unknown or needs more than N bodies.
double load_orbit_config(const char *name, State *state);

#endif // ORBITS_H
