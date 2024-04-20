import pytest

import snapbin.main as snapbin


@pytest.fixture()
def app():
    snapbin.app.config["TESTING"] = True
    return snapbin.app.test_client()
