"""elmulator — a scriptable Bluetooth + TCP OBD2 (ELM327) adapter emulator.

The Python package provides the language-neutral TCP server and the scenario
validator. See the `elmulator` console command (`elmulator --help`).
"""

from .server import EngineState, Scenario, normalize, serve, self_test

__all__ = ["Scenario", "EngineState", "normalize", "serve", "self_test", "__version__"]

__version__ = "0.2.0"
