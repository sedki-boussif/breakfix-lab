"""Settings, and the three checks that refuse to start this app in production
with a dangerous one.

Deliberately dependency-free: it imports nothing but os, so the refusal rules
can be tested without installing anything, and so a bad setting fails at import
rather than on the first request.
"""
import os

# The value shipped in .env.example. It is not a secret, it is a placeholder,
# and starting in production while it is still in place is a hard failure.
DEFAULT_JWT_SECRET = "change-me-before-production"
MIN_JWT_SECRET_LEN = 32


class ConfigError(RuntimeError):
    """Raised at import time. The app must not start."""


def _as_bool(value, default=False):
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


class Settings:
    def __init__(self, env=None):
        env = os.environ if env is None else env
        self.app_env = env.get("APP_ENV", "development").strip().lower()
        self.debug = _as_bool(env.get("DEBUG"), default=False)
        self.jwt_secret = (env.get("JWT_SECRET") or "").strip()
        self.forwarded_allow_ips = (env.get("FORWARDED_ALLOW_IPS") or "").strip()
        self.database_url = (env.get("DATABASE_URL") or "").strip()
        self.uploads_dir = env.get("UPLOADS_DIR", "/app/uploads")

    @property
    def is_production(self):
        return self.app_env == "production"

    def problems(self):
        """Every reason this configuration must not start, not just the first."""
        found = []
        if not self.database_url:
            found.append("DATABASE_URL is empty; there is nothing to connect to.")
        if not self.is_production:
            return found
        if not self.jwt_secret or self.jwt_secret == DEFAULT_JWT_SECRET:
            found.append(
                "JWT_SECRET is still the placeholder from .env.example. "
                "Generate one: openssl rand -hex 32"
            )
        elif len(self.jwt_secret) < MIN_JWT_SECRET_LEN:
            found.append(
                f"JWT_SECRET is {len(self.jwt_secret)} characters; "
                f"at least {MIN_JWT_SECRET_LEN} are required in production."
            )
        if not self.forwarded_allow_ips:
            found.append(
                "FORWARDED_ALLOW_IPS is empty. Behind a proxy that means every "
                "client IP in the logs is the proxy's, and rate limits and audit "
                "entries become useless. Set it to the proxy's address."
            )
        if self.debug:
            found.append("DEBUG=true in production leaks tracebacks to clients.")
        return found

    def validate(self):
        found = self.problems()
        if found:
            raise ConfigError(
                "refusing to start in %s:\n  - %s" % (self.app_env, "\n  - ".join(found))
            )
        return self


def load():
    return Settings().validate()
