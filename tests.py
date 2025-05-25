# mypy: disable-error-code="no-untyped-call"
import time

import pytest
from cryptography.fernet import Fernet
from flask.testing import FlaskClient
from freezegun import freeze_time
from peewee import SqliteDatabase
from werkzeug.exceptions import BadRequest

import snapbin.main as snap
from snapbin.models.secret import Secret


def test_get_password(memory_db: SqliteDatabase) -> None:
    _ = memory_db
    password = "melatonin overdose 1337!$"
    key = snap.set_password(password, 30)
    assert password == snap.get_password(key), "passwords do not match"
    assert snap.get_password(key) is None, "password should be expired"


def test_password_is_not_stored_in_plaintext(memory_db: SqliteDatabase) -> None:
    _ = memory_db
    password = "trustno1"
    token = snap.set_password(password, 30)
    redis_key = token.split(snap.TOKEN_SEPARATOR, maxsplit=1)[0]
    stored_password_text = Secret.get(Secret.storage_key == redis_key).value
    assert stored_password_text not in password


def test_returned_token_format(memory_db: SqliteDatabase) -> None:
    _ = memory_db
    password = "trustsome1"
    token = snap.set_password(password, 30)
    token_fragments = token.split(snap.TOKEN_SEPARATOR)
    assert 2 == len(token_fragments)
    storage_key, encryption_key = token_fragments
    assert 32 == len(storage_key)
    try:
        Fernet(encryption_key.encode("utf-8"))
    except ValueError:
        assert False, "the encryption key is not valid"


def test_encryption_key_is_returned(memory_db: SqliteDatabase) -> None:
    _ = memory_db
    password = "trustany1"
    token = snap.set_password(password, 30)
    token_fragments = token.split(snap.TOKEN_SEPARATOR)
    storage_key, encryption_key = token_fragments
    stored_password = Secret.get(storage_key=storage_key).value
    fernet = Fernet(encryption_key.encode("utf-8"))
    decrypted_password = fernet.decrypt(stored_password).decode("utf-8")
    assert password == decrypted_password


def test_password_is_decoded(memory_db: SqliteDatabase) -> None:
    _ = memory_db
    password = "correct horse battery staple"
    key = snap.set_password(password, 30)
    assert not isinstance(snap.get_password(key), bytes)


def test_clean_input(memory_db: SqliteDatabase) -> None:
    _ = memory_db
    # Test Bad Data
    with snap.app.test_request_context(
        "/", data={"password": "foo", "ttl": "bar"}, method="POST"
    ):
        with pytest.raises(BadRequest):
            snap.clean_input()

    # No Password
    with snap.app.test_request_context("/", method="POST"):
        with pytest.raises(BadRequest):
            snap.clean_input()

    # No TTL
    with snap.app.test_request_context(
        "/", data={"password": "foo", "ttl": ""}, method="POST"
    ):
        assert (604800, "foo") == snap.clean_input()

    with snap.app.test_request_context(
        "/", data={"password": "foo", "ttl": 3600}, method="POST"
    ):
        assert (3600, "foo") == snap.clean_input()


def test_password_before_expiration(memory_db: SqliteDatabase) -> None:
    _ = memory_db
    password = "fidelio"
    key = snap.set_password(password, 1)
    assert password == snap.get_password(key)


def test_password_after_expiration(memory_db: SqliteDatabase) -> None:
    _ = memory_db
    password = "open sesame"
    key = snap.set_password(password, 1)
    time.sleep(2)
    assert snap.get_password(key) is None


def test_preview_password(app: FlaskClient) -> None:
    password = "I like novelty kitten statues!"
    key = snap.set_password(password, 30)
    rv = app.get(f"/{key}")
    assert password not in rv.get_data(as_text=True)


def test_show_password(app: FlaskClient) -> None:
    password = "I like novelty kitten statues!"
    key = snap.set_password(password, 30)
    rv = app.post("/get-secret", data={"key": key})
    assert password in rv.get_data(as_text=True)


def test_set_password_json(app: FlaskClient) -> None:
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
        assert snap.get_password(key) == password

        frozen_time.move_to("2020-05-22 12:00:00")
        assert snap.get_password(key) is None
