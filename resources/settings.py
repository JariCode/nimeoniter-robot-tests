import os
from pathlib import Path
from dotenv import load_dotenv

# .env is in the test suite root, one level up from this file
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

# Application addresses. APP_URL is the production build served by vite
# preview (sub-path included). RENDER_BACKEND_URL is only needed by the
# webhook test (TC11-003).
APP_URL = os.getenv("APP_URL", "")
BACKEND_URL = os.getenv("BACKEND_URL", "").rstrip("/")
RENDER_BACKEND_URL = os.getenv("RENDER_BACKEND_URL", "").rstrip("/")

# Standard test account and the new password for the password-change test
TEST_EMAIL = os.getenv("TEST_EMAIL", "")
TEST_PASSWORD = os.getenv("TEST_PASSWORD", "")
NEW_PASSWORD = os.getenv("NEW_PASSWORD", "")

# Clerk development instance test settings
CLERK_TEST_CODE = os.getenv("CLERK_TEST_CODE", "")
TEST_EMAIL_PREFIX = os.getenv("TEST_EMAIL_PREFIX", "")
TEST_EMAIL_DOMAIN = os.getenv("TEST_EMAIL_DOMAIN", "")

# Test database for the player-state seed helper. Never the real database.
TEST_MONGODB_URI = os.getenv("TEST_MONGODB_URI", "")


# Frontend build folder (frontend/dist) for the .htaccess test (TC13-003).
# Optional: only that test needs it.
FRONTEND_DIST = os.getenv("FRONTEND_DIST", "").rstrip("/\\")

# Browser: chromium, firefox or webkit. HEADLESS=true hides the browser,
# SLOWMO slows down every action.
BROWSER = os.getenv("BROWSER", "")
HEADLESS_TEXT = os.getenv("HEADLESS", "")
SLOWMO_TEXT = os.getenv("SLOWMO", "")

# Stop immediately if a required value is missing, instead of running tests
# with empty values
REQUIRED = {
    "APP_URL": APP_URL,
    "BACKEND_URL": BACKEND_URL,
    "TEST_EMAIL": TEST_EMAIL,
    "TEST_PASSWORD": TEST_PASSWORD,
    "NEW_PASSWORD": NEW_PASSWORD,
    "CLERK_TEST_CODE": CLERK_TEST_CODE,
    "TEST_EMAIL_PREFIX": TEST_EMAIL_PREFIX,
    "TEST_EMAIL_DOMAIN": TEST_EMAIL_DOMAIN,
    "TEST_MONGODB_URI": TEST_MONGODB_URI,
    "BROWSER": BROWSER,
    "HEADLESS": HEADLESS_TEXT,
    "SLOWMO": SLOWMO_TEXT,
}
MISSING = [name for name, value in REQUIRED.items() if not value]
if MISSING:
    raise RuntimeError("These values are missing from the .env file: " + ", ".join(MISSING))

if BROWSER not in ("chromium", "firefox", "webkit"):
    raise RuntimeError("BROWSER must be chromium, firefox or webkit")

# Convert the browser settings to the format Robot needs
HEADLESS = HEADLESS_TEXT.strip().lower() == "true"
SLOWMO = f"{float(SLOWMO_TEXT)}s"