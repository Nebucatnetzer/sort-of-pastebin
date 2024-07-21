import os

from peewee import SqliteDatabase

# Initialize DB
if os.environ.get("MOCK_DB"):
    db = SqliteDatabase(":memory:", pragmas={"journal_mode": "wal"})
else:
    db = SqliteDatabase("snapbin.db", pragmas={"journal_mode": "wal"})
