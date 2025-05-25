import os
from typing import Generator

import pytest
from flask.testing import FlaskClient
from peewee import SqliteDatabase
from py.path import local  # type: ignore

os.environ["SNAPBIN_TESTING"] = "true"
# pylint: disable=wrong-import-position
from snapbin import database
from snapbin import main
from snapbin.models.secret import Secret


@pytest.fixture(scope="function")
def memory_db() -> Generator[SqliteDatabase, None, None]:
    database.db.init(":memory:")
    database.db.connect()
    database.db.create_tables([Secret])
    yield database.db
    database.db.close()


@pytest.fixture()
def app(tmpdir: local) -> FlaskClient:
    temp_directory = tmpdir.mkdir("db")
    main.initialize_db(db_path=f"{temp_directory}/test.db")
    main.app.config["TESTING"] = True
    return main.app.test_client()
