"""
Pytest configuration for backend E2E tests.
Set DATABASE_NAME before main is imported so tests use a separate DB (default: gym_db_test).
"""
import os

# Use test DB so we don't touch production. Override with env DATABASE_NAME if needed.
os.environ.setdefault("DATABASE_NAME", "gym_db_test")
