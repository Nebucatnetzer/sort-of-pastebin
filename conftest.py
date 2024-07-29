import os
import pytest

os.environ["SNAPBIN_TESTING"] = "true"
# pylint: disable=wrong-import-position
from snapbin import main
from snapbin.models.secret import Secret


@pytest.fixture(scope="function")
def memory_db():
    main.db.init(":memory:")
    main.db.connect()
    main.db.create_tables([Secret])
    yield main.db
    main.db.close()


@pytest.fixture()
def app(tmpdir):
    temp_directory = tmpdir.mkdir("db")
    main.initialize_db(db_path=f"{temp_directory}/test.db")
    main.app.config["TESTING"] = True
    return main.app.test_client()
