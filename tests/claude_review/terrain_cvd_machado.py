"""Machado/Oliveira/Fernandes (2009), severity 1.0, linear-sRGB matrices.

Coefficients are numerical data from the authors' supplementary matrix table.
The C9 acceptance thresholds are a project decision, not claims of the paper.
"""
from __future__ import annotations

import numpy as np


SOURCE = "https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html"
MATRICES = {
    "protanopia": np.array([[0.152286, 1.052583, -0.204868],
                            [0.114503, 0.786281, 0.099216],
                            [-0.003882, -0.048116, 1.051998]]),
    "deuteranopia": np.array([[0.367322, 0.860646, -0.227968],
                              [0.280085, 0.672501, 0.047413],
                              [-0.011820, 0.042940, 0.968881]]),
}


def simulate(rgb: np.ndarray, mode: str) -> np.ndarray:
    """Input/output encoded sRGB in 0..255; output floats avoid 8-bit rounding."""
    if (rgb.ndim < 2 or rgb.shape[-1] != 3 or not np.isfinite(rgb).all()
            or np.any(rgb < 0) or np.any(rgb > 255)):
        raise ValueError("expected finite encoded sRGB values in 0..255")
    if mode not in MATRICES:
        raise ValueError("unsupported severity-1.0 C9 mode")
    encoded = rgb.astype(np.float64) / 255.0
    linear = np.where(encoded <= .04045, encoded / 12.92,
                      ((encoded + .055) / 1.055) ** 2.4)
    # RGB row vectors need the transposed matrix. Clip out-of-gamut linear RGB
    # before applying the display encoding, without changing source pixels.
    projected = np.clip(linear @ MATRICES[mode].T, 0, 1)
    encoded = np.where(projected <= .0031308, projected * 12.92,
                       1.055 * projected ** (1/2.4) - .055)
    return np.clip(encoded, 0, 1) * 255.0
