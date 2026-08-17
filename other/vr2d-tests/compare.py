#!/usr/bin/env python3
"""Angular error between two renders of the same view.

Both images come from a pattern whose red and green channels encode the source
pixel's own longitude and latitude, so every output pixel says which direction
on the sphere it sampled. Comparing those directions gives the error in degrees,
which is what actually matters and is comparable across projections.

PSNR is a poor substitute here: it is dominated by the graticule, which is
deliberately high-frequency, and it blows up near the poles where a half-pixel
difference is a large change in longitude but a negligible change in direction.

    compare.py <a.rgb> <b.rgb> <width> <height>

prints the median and 95th-percentile angular error in degrees.
"""

import math
import sys


def directions(path, width, height):
    data = open(path, "rb").read()
    out = []
    for i in range(0, width * height * 3, 3):
        r, g, b = data[i], data[i + 1], data[i + 2]
        if r == 0 and g == 0 and b == 0:
            out.append(None)  # outside what the source covers; both should agree
            continue
        lon = (r / 255 * 360 - 180) * math.pi / 180
        lat = (90 - g / 255 * 180) * math.pi / 180
        out.append((math.cos(lat) * math.sin(lon),
                    math.sin(lat),
                    -math.cos(lat) * math.cos(lon)))
    return out


def main():
    a_path, b_path, width, height = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    a, b = directions(a_path, width, height), directions(b_path, width, height)

    errors = []
    mismatched_void = 0
    for va, vb in zip(a, b):
        if va is None or vb is None:
            if (va is None) != (vb is None):
                mismatched_void += 1
            continue
        dot = max(-1.0, min(1.0, va[0] * vb[0] + va[1] * vb[1] + va[2] * vb[2]))
        errors.append(math.acos(dot) * 180 / math.pi)

    if not errors:
        print("0 0 100 100")
        return
    errors.sort()
    median = errors[len(errors) // 2]
    p95 = errors[int(len(errors) * 0.95)]
    void = mismatched_void / max(1, len(a)) * 100
    print(f"{median:.3f} {p95:.3f} {void:.2f} {blue_difference(a_path, b_path):.2f}")


def blue_difference(a_path, b_path):
    """How far apart the two images are in blue, as a percentage.

    The two eyes of the stereo fixtures hold the same picture, differing only in
    a blue tint, so the angular error above — which reads only red and green —
    cannot tell them apart. This can: pick the wrong eye and the mean blue is
    out by tens of percent.
    """
    means = []
    for path in (a_path, b_path):
        data = open(path, "rb").read()
        blue = data[2::3]
        means.append(sum(blue) / max(1, len(blue)))
    reference = max(means[1], 1.0)
    return abs(means[0] - means[1]) / reference * 100


if __name__ == "__main__":
    main()
