"""Felix environment settings, with compatibility for existing deployments."""
import os


def brand_env(name: str, default=None):
    """Prefer FELIX_* settings; accept legacy deployment variables as a fallback."""
    legacy_name = "LUMIS_" + name.removeprefix("FELIX_")
    return os.getenv(name, os.getenv(legacy_name, default))
