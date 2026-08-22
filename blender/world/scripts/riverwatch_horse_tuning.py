VERSION = "V89"

# ============================================================
# RIVERWATCH HORSE V89
#
# LIMB ANATOMY + HEAD REFINEMENT PASS
#
# Anatomy-only checkpoint.
#
# X = left/right
# Y = front/rear
# negative Y = horse faces forward
# Z = height
#
# V89 priorities:
# - preserve the compact medieval courser body that is working
# - reduce the separate "pod" look of the upper hind limb
# - make the hind leg read thigh -> stifle -> gaskin -> hock -> cannon
# - break the front leg out of the straight-post silhouette
# - keep the head large enough in side view while narrowing it in front
# - strengthen cheek-to-muzzle taper
# - keep a powerful neck root but slim the middle neck
# - give hooves a more substantial vertical/forward read
# - make mane slightly more visible without returning to a flat slab
# ============================================================


COAT = (
    0.205,
    0.052,
    0.017,
    1.0
)

DARK = (
    0.026,
    0.017,
    0.014,
    1.0
)

HOOF = (
    0.046,
    0.039,
    0.035,
    1.0
)

MUZZLE = (
    0.105,
    0.058,
    0.048,
    1.0
)

EYE = (
    0.005,
    0.004,
    0.003,
    1.0
)

EYE_HIGHLIGHT = (
    0.75,
    0.70,
    0.58,
    1.0
)


# ============================================================
# BODY
#
# rear -> front
#
# y,
# center_z,
# half_width,
# top_depth,
# belly_depth,
# upper_width_factor,
# lower_width_factor
#
# V89 leaves the successful V88 rib cage largely alone.
# The rear stations are trimmed only slightly so the croup stays
# rounded without exaggerating the separate hind-thigh pod.
# ============================================================

BODY_STATIONS = [

    (
        1.115,
        1.410,
        0.205,
        0.155,
        0.190,
        0.87,
        0.79
    ),

    (
        1.020,
        1.468,
        0.335,
        0.275,
        0.290,
        0.99,
        0.90
    ),

    (
        0.880,
        1.515,
        0.418,
        0.355,
        0.365,
        1.05,
        0.96
    ),

    (
        0.705,
        1.505,
        0.448,
        0.375,
        0.390,
        1.06,
        0.99
    ),

    (
        0.500,
        1.465,
        0.448,
        0.338,
        0.392,
        1.03,
        0.97
    ),

    (
        0.285,
        1.425,
        0.442,
        0.302,
        0.410,
        1.00,
        0.95
    ),

    (
        0.070,
        1.408,
        0.438,
        0.294,
        0.452,
        1.00,
        0.96
    ),

    (
        -0.135,
        1.420,
        0.426,
        0.320,
        0.485,
        1.02,
        0.98
    ),

    (
        -0.315,
        1.458,
        0.402,
        0.390,
        0.468,
        1.05,
        0.97
    ),

    (
        -0.475,
        1.508,
        0.350,
        0.460,
        0.420,
        1.04,
        0.93
    ),

    (
        -0.610,
        1.485,
        0.295,
        0.425,
        0.365,
        0.98,
        0.88
    ),

    (
        -0.720,
        1.420,
        0.242,
        0.320,
        0.320,
        0.91,
        0.82
    ),
]


# ============================================================
# NECK
#
# V89:
#
# - strong root remains buried in the shoulder
# - middle third becomes slightly narrower
# - crest keeps a clean forward sweep
# - poll stays narrow enough to meet the head cleanly
# ============================================================

NECK_STATIONS = [

    (
        0.0,
        -0.365,
        1.550,
        0.315,
        0.262,
        0.315,
        1.00,
        0.94
    ),

    (
        0.0,
        -0.455,
        1.655,
        0.302,
        0.272,
        0.286,
        1.00,
        0.93
    ),

    (
        0.0,
        -0.565,
        1.765,
        0.280,
        0.275,
        0.252,
        1.00,
        0.92
    ),

    (
        0.0,
        -0.680,
        1.870,
        0.252,
        0.263,
        0.220,
        0.99,
        0.91
    ),

    (
        0.0,
        -0.800,
        1.960,
        0.220,
        0.238,
        0.190,
        0.98,
        0.90
    ),

    (
        0.0,
        -0.915,
        2.025,
        0.196,
        0.212,
        0.172,
        0.97,
        0.89
    ),

    (
        0.0,
        -1.008,
        2.058,
        0.180,
        0.188,
        0.158,
        0.96,
        0.88
    ),

    (
        0.0,
        -1.072,
        2.060,
        0.170,
        0.174,
        0.150,
        0.95,
        0.88
    ),
]


# ============================================================
# HEAD
#
# V89 keeps the improved V88 side length, but specifically
# narrows the head in X so the front view stops reading as a
# broad round mask. The cheek remains the widest point and the
# final muzzle tapers distinctly.
# ============================================================

HEAD_STATIONS = [

    (
        0.0,
        -1.045,
        2.045,
        0.178,
        0.175,
        0.172,
        1.00,
        1.00
    ),

    (
        0.0,
        -1.145,
        2.060,
        0.238,
        0.220,
        0.238,
        1.00,
        1.04
    ),

    (
        0.0,
        -1.265,
        2.040,
        0.280,
        0.250,
        0.290,
        1.00,
        1.08
    ),

    (
        0.0,
        -1.385,
        1.992,
        0.272,
        0.230,
        0.265,
        0.99,
        1.07
    ),

    (
        0.0,
        -1.515,
        1.925,
        0.235,
        0.188,
        0.215,
        0.98,
        1.04
    ),

    (
        0.0,
        -1.645,
        1.855,
        0.195,
        0.145,
        0.165,
        0.97,
        1.01
    ),

    (
        0.0,
        -1.765,
        1.795,
        0.158,
        0.112,
        0.132,
        0.96,
        0.99
    ),

    (
        0.0,
        -1.875,
        1.755,
        0.128,
        0.085,
        0.100,
        0.95,
        0.97
    ),
]


# ============================================================
# FRONT LEGS
#
# V89 gives the upper forelimb a visible rearward sweep before
# the lower limb returns forward toward the hoof. The knee stays
# broader than the cannon, and fetlock/pastern remain distinct.
# ============================================================

FRONT_LEG_STATIONS = [

    (
        -0.470,
        1.445,
        0.172,
        0.198
    ),

    (
        -0.445,
        1.275,
        0.165,
        0.185
    ),

    (
        -0.410,
        1.095,
        0.152,
        0.168
    ),

    (
        -0.380,
        0.915,
        0.138,
        0.148
    ),

    (
        -0.390,
        0.740,
        0.146,
        0.132
    ),

    (
        -0.420,
        0.595,
        0.110,
        0.100
    ),

    (
        -0.450,
        0.445,
        0.078,
        0.070
    ),

    (
        -0.475,
        0.305,
        0.071,
        0.064
    ),

    (
        -0.505,
        0.195,
        0.090,
        0.078
    ),

    (
        -0.540,
        0.105,
        0.074,
        0.062
    ),
]


# ============================================================
# HIND LEGS
#
# V89 is a deliberate anti-pod pass:
#
# - upper thigh radii are smaller
# - stifle moves clearly forward but is not a giant bulb
# - gaskin travels rearward into a readable hock
# - hock is high and broader than the cannon
# - lower cannon is close to vertical
# - pastern returns slightly forward into the hoof
# ============================================================

HIND_LEG_STATIONS = [

    (
        0.780,
        1.500,
        0.250,
        0.270
    ),

    (
        0.700,
        1.360,
        0.242,
        0.258
    ),

    (
        0.600,
        1.205,
        0.225,
        0.240
    ),

    (
        0.505,
        1.045,
        0.205,
        0.215
    ),

    (
        0.450,
        0.895,
        0.185,
        0.190
    ),

    (
        0.500,
        0.755,
        0.165,
        0.168
    ),

    (
        0.590,
        0.620,
        0.148,
        0.145
    ),

    (
        0.665,
        0.505,
        0.128,
        0.118
    ),

    (
        0.695,
        0.390,
        0.100,
        0.090
    ),

    (
        0.692,
        0.260,
        0.078,
        0.069
    ),

    (
        0.680,
        0.165,
        0.090,
        0.078
    ),

    (
        0.650,
        0.100,
        0.076,
        0.063
    ),
]


# ============================================================
# STANCE
# ============================================================

FRONT_LEG_X = 0.245
HIND_LEG_X = 0.290


# ============================================================
# HOOVES
#
# V89 restores a little height and adds toe length so the feet
# read as weight-bearing hooves instead of thin floor plates.
# ============================================================

FRONT_HOOF = {
    "center_y": -0.565,
    "width": 0.215,
    "length": 0.350,
    "height": 0.150,
}

HIND_HOOF = {
    "center_y": 0.650,
    "width": 0.220,
    "length": 0.360,
    "height": 0.150,
}


# ============================================================
# MANE
#
# Keep one continuous mane. V89 lowers the hanging edge enough
# to read at review distance while staying clear of the old slab.
# ============================================================

MANE_ROOT = [

    (
        -0.025,
        -0.405,
        1.830
    ),

    (
        -0.027,
        -0.495,
        1.925
    ),

    (
        -0.029,
        -0.590,
        2.010
    ),

    (
        -0.031,
        -0.690,
        2.080
    ),

    (
        -0.033,
        -0.790,
        2.135
    ),

    (
        -0.035,
        -0.885,
        2.175
    ),

    (
        -0.037,
        -0.965,
        2.195
    ),
]


MANE_DROP = [

    (
        -0.130,
        -0.295,
        1.575
    ),

    (
        -0.145,
        -0.380,
        1.645
    ),

    (
        -0.158,
        -0.470,
        1.720
    ),

    (
        -0.165,
        -0.565,
        1.790
    ),

    (
        -0.165,
        -0.665,
        1.850
    ),

    (
        -0.155,
        -0.765,
        1.905
    ),

    (
        -0.135,
        -0.860,
        1.965
    ),
]


# ============================================================
# TAIL
#
# Preserve the V88 continuous tail for this anatomy-focused pass.
# ============================================================

TAIL_STATIONS = [

    (
        0.0,
        1.020,
        1.540,
        0.090,
        0.095,
        0.095,
        1.0,
        1.0
    ),

    (
        0.0,
        1.125,
        1.425,
        0.115,
        0.120,
        0.120,
        1.0,
        1.0
    ),

    (
        0.0,
        1.215,
        1.280,
        0.140,
        0.145,
        0.145,
        1.0,
        1.0
    ),

    (
        0.0,
        1.285,
        1.100,
        0.155,
        0.160,
        0.160,
        1.0,
        1.0
    ),

    (
        0.0,
        1.320,
        0.900,
        0.160,
        0.165,
        0.165,
        1.0,
        1.0
    ),

    (
        0.0,
        1.320,
        0.695,
        0.148,
        0.153,
        0.153,
        1.0,
        1.0
    ),

    (
        0.0,
        1.300,
        0.500,
        0.120,
        0.125,
        0.125,
        1.0,
        1.0
    ),

    (
        0.0,
        1.265,
        0.330,
        0.090,
        0.095,
        0.095,
        1.0,
        1.0
    ),

    (
        0.0,
        1.220,
        0.190,
        0.058,
        0.062,
        0.062,
        1.0,
        1.0
    ),

    (
        0.0,
        1.175,
        0.090,
        0.028,
        0.031,
        0.031,
        1.0,
        1.0
    ),
]
