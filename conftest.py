import os

import pytest

os.environ["MOCK_DB"] = "1"
from snapbin import main
from snapbin.database import db
from snapbin.models import Secret


@pytest.fixture(scope="function")
def memory_db():
    db.connect()
    db.create_tables([Secret])
    yield db
    db.close()


@pytest.fixture()
def app(memory_db):
    _ = memory_db
    main.app.config["TESTING"] = True
    return main.app.test_client()
