"""Player-state seed helper for the Nimeoniter Robot Framework tests.

Writes a known game state for a test user directly into the TEST database, so
building, world-change and World Complete tests don't need hundreds of
completed tasks. This is part of the test suite, not the application.

Safety: the helper refuses to run unless the database name in
TEST_MONGODB_URI contains "test", so it can never touch the real database.
"""

import sys
from pathlib import Path

from pymongo import MongoClient
from robot.api.deco import keyword, library

# settings.py is in the same folder as this file
sys.path.insert(0, str(Path(__file__).resolve().parent))
from settings import TEST_MONGODB_URI  # noqa: E402

# Mongoose stores the PlayerState model in the "playerstates" collection
COLLECTION = "playerstates"

# The same defaults as backend/models/PlayerState.js
DEFAULT_STATE = {
    "totalXp": 0,
    "resources": {"wood": 0, "stone": 0, "food": 0},
    "baseStageIndex": -1,
    "missions": [],
    "streak": 0,
    "lastActiveDate": None,
    "chatHistory": [],
    "unlockedAchievements": [],
}


@library(scope="GLOBAL")
class PlayerStateSeed:
    def __init__(self):
        self._client = None
        self._db = None

    def _collection(self):
        if self._db is None:
            self._client = MongoClient(TEST_MONGODB_URI, serverSelectionTimeoutMS=10000)
            db = self._client.get_default_database()
            if "test" not in db.name.lower():
                raise RuntimeError(
                    f"TEST_MONGODB_URI points to database '{db.name}'. The seed "
                    "helper only runs against a database whose name contains 'test'."
                )
            self._db = db
        return self._db[COLLECTION]

    @keyword
    def reset_player_state(self, user_id):
        """Resets the user's game state to a fresh player (creates it if missing)."""
        self._collection().update_one(
            {"clerkUserId": user_id},
            {"$set": DEFAULT_STATE, "$setOnInsert": {"clerkUserId": user_id}},
            upsert=True,
        )

    @keyword
    def seed_player_state(self, user_id, **fields):
        """Starts from a fresh player and sets the given fields.

        Example: ``Seed Player State    ${user_id}    totalXp=${300}    baseStageIndex=${0}``
        Nested values (resources, missions, chatHistory) are passed as
        dictionaries and lists.
        """
        state = dict(DEFAULT_STATE)
        state.update(fields)
        self._collection().update_one(
            {"clerkUserId": user_id},
            {"$set": state, "$setOnInsert": {"clerkUserId": user_id}},
            upsert=True,
        )

    @keyword
    def get_player_state_from_database(self, user_id):
        """Returns the user's game state document, or None if there is none."""
        doc = self._collection().find_one({"clerkUserId": user_id}, {"_id": 0})
        return doc

    @keyword
    def count_player_states(self, user_id):
        """Returns how many game state documents the user has (should be 0 or 1)."""
        return self._collection().count_documents({"clerkUserId": user_id})

    @keyword
    def delete_player_state(self, user_id):
        """Deletes the user's game state. Used for cleanup if a test fails."""
        self._collection().delete_one({"clerkUserId": user_id})

    @keyword
    def player_state_should_not_exist(self, user_id):
        """Fails if the user still has a game state in the test database."""
        count = self.count_player_states(user_id)
        if count:
            raise AssertionError(f"Game state for {user_id} still exists in the test database")