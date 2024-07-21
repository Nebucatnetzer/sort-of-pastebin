import time
import uuid

import pytest

from cryptography.fernet import Fernet
from freezegun import freeze_time
from werkzeug.exceptions import BadRequest

# noinspection PyPep8Naming
import snapbin.main as snapbin


def test_get_password(memory_db):
    password = "melatonin overdose 1337!$"
    key = snapbin.set_password(password, 30)
    assert password == snapbin.get_password(key)
    # Assert that we can't look this up a second time.
    assert snapbin.get_password(key) == None


def test_password_is_not_stored_in_plaintext():
    password = "trustno1"
    token = snapbin.set_password(password, 30)
    redis_key = token.split(snapbin.TOKEN_SEPARATOR)[0]
    stored_password_text = snapbin.redis_client.get(redis_key).decode("utf-8")
    assert stored_password_text not in password


def test_returned_token_format():
    password = "trustsome1"
    token = snapbin.set_password(password, 30)
    token_fragments = token.split(snapbin.TOKEN_SEPARATOR)
    assert 2 == len(token_fragments)
    redis_key, encryption_key = token_fragments
    assert (32 + len(snapbin.REDIS_PREFIX)) == len(redis_key)
    try:
        Fernet(encryption_key.encode("utf-8"))
    except ValueError:
        assert False, "the encryption key is not valid"


def test_encryption_key_is_returned():
    password = "trustany1"
    token = snapbin.set_password(password, 30)
    token_fragments = token.split(snapbin.TOKEN_SEPARATOR)
    redis_key, encryption_key = token_fragments
    stored_password = snapbin.redis_client.get(redis_key)
    fernet = Fernet(encryption_key.encode("utf-8"))
    decrypted_password = fernet.decrypt(stored_password).decode("utf-8")
    assert password == decrypted_password


def test_unencrypted_passwords_still_work():
    unencrypted_password = "trustevery1"
    storage_key = uuid.uuid4().hex
    snapbin.redis_client.setex(storage_key, 30, unencrypted_password)
    retrieved_password = snapbin.get_password(storage_key)
    assert unencrypted_password == retrieved_password


def test_password_is_decoded():
    password = "correct horse battery staple"
    key = snapbin.set_password(password, 30)
    assert not isinstance(snapbin.get_password(key), bytes)


def test_clean_input():
    # Test Bad Data
    with snapbin.app.test_request_context(
        "/", data={"password": "foo", "ttl": "bar"}, method="POST"
    ):
        with pytest.raises(BadRequest):
            snapbin.clean_input()

    # No Password
    with snapbin.app.test_request_context("/", method="POST"):
        with pytest.raises(BadRequest):
            snapbin.clean_input()

    # No TTL
    with snapbin.app.test_request_context(
        "/", data={"password": "foo", "ttl": ""}, method="POST"
    ):
        assert (604800, "foo") == snapbin.clean_input()

    with snapbin.app.test_request_context(
        "/", data={"password": "foo", "ttl": 3600}, method="POST"
    ):
        assert (3600, "foo") == snapbin.clean_input()


def test_password_before_expiration():
    password = "fidelio"
    key = snapbin.set_password(password, 1)
    assert password == snapbin.get_password(key)


def test_password_after_expiration():
    password = "open sesame"
    key = snapbin.set_password(password, 1)
    time.sleep(1.5)
    assert snapbin.get_password(key) == None


def test_preview_password(app):
    password = "I like novelty kitten statues!"
    key = snapbin.set_password(password, 30)
    rv = app.get("/{0}".format(key))
    assert password not in rv.get_data(as_text=True)


def test_show_password(app):
    password = "I like novelty kitten statues!"
    key = snapbin.set_password(password, 30)
    rv = app.post("/get-secret", data={"key": key})
    assert password in rv.get_data(as_text=True)


def test_set_password_json(app):
    with freeze_time("2020-05-08 12:00:00") as frozen_time:
        password = "my name is my passport. verify me."
        rv = app.post(
            "/",
            headers={"Accept": "application/json"},
            data={"password": password, "ttl": 3000},
        )

        json_content = rv.get_json()
        key = json_content["key"]

        frozen_time.move_to("2020-05-22 11:59:59")
        assert snapbin.get_password(key) == password

        frozen_time.move_to("2020-05-22 12:00:00")
        assert snapbin.get_password(key) == None
