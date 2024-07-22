import os
import uuid

from cryptography.fernet import Fernet
from flask import abort, Flask, request, jsonify
from peewee import DoesNotExist
from peewee import OperationalError

from snapbin.database import db
from snapbin.models import Secret
from snapbin.utils import strtobool

NO_SSL = bool(strtobool(os.environ.get("NO_SSL", "False")))
HOST_OVERRIDE = os.environ.get("HOST_OVERRIDE", None)
TOKEN_SEPARATOR = "~"


# Initialize Flask Application
app = Flask(__name__)
if os.environ.get("DEBUG"):
    app.debug = True
app.secret_key = os.environ.get("SECRET_KEY", "Secret Key")
app.config.update({"STATIC_URL": os.environ.get("STATIC_URL", "static")})


def initialize_db(db_path):
    if not os.path.exists(db_path):
        db.init(db_path)
        db.connect()
        db.create_tables([Secret])
        db.close()


@app.before_request
def before_request():
    try:
        db.connect()
    except OperationalError:
        return


@app.after_request
def after_request(response):
    db.close()
    return response


def encrypt(password):
    """
    Take a password string, encrypt it with Fernet symmetric encryption,
    and return the result (bytes), with the decryption key (bytes)
    """
    encryption_key = Fernet.generate_key()
    fernet = Fernet(encryption_key)
    encrypted_password = fernet.encrypt(password.encode("utf-8"))
    return encrypted_password, encryption_key


def decrypt(password, decryption_key):
    """
    Decrypt a password (bytes) using the provided key (bytes),
    and return the plain-text password (bytes).
    """
    fernet = Fernet(decryption_key)
    return fernet.decrypt(password)


def parse_token(token):
    token_fragments = token.split(TOKEN_SEPARATOR, 1)  # Split once, not more.
    storage_key = token_fragments[0]

    try:
        decryption_key = token_fragments[1].encode("utf-8")
    except IndexError:
        decryption_key = None

    return storage_key, decryption_key


def set_password(password, ttl):
    """
    Encrypt and store the password for the specified lifetime.

    Returns a token comprised of the key where the encrypted password
    is stored, and the decryption key.
    """
    storage_key = uuid.uuid4().hex
    encrypted_password, encryption_key = encrypt(password)
    Secret.create(storage_key=storage_key, ttl=ttl, value=encrypted_password)
    encryption_key = encryption_key.decode("utf-8")
    token = TOKEN_SEPARATOR.join([storage_key, encryption_key])
    return token


def get_password(token):
    """
    From a given token, return the initial password.

    If the token is tilde-separated, we decrypt the password fetched from Redis.
    If not, the password is simply returned as is.
    """
    try:
        storage_key, decryption_key = parse_token(token)
        secret = Secret.get_by_id(storage_key)
        if secret.is_expired():
            secret.delete_instance()
            return None

        password = secret.value
        secret.delete_instance()

        if password is not None:
            if decryption_key is not None:
                password = decrypt(password, decryption_key)
                return password.decode("utf-8")
        return None
    except DoesNotExist:
        return None


def empty(value):
    if not value:
        return True
    return None


def _clean_ttl(ttl_request):
    if not ttl_request.form.get("ttl"):
        return 604800

    try:
        time_period = int(ttl_request.form.get("ttl"))
    except ValueError:
        abort(400, "TTL must be an integer")

    if time_period > 2419200:
        abort(400, "TTL must be less than 2419200 seconds (4 weeks)")
    return time_period


def clean_input():
    """
    Make sure we're not getting bad data from the front end,
    format data to be machine readable
    """
    if empty(request.form.get("password", "")):
        abort(400)

    time_period = _clean_ttl(request)
    return time_period, request.form["password"]


@app.route("/", methods=["POST"])
def handle_password():
    if request.is_json:
        request.form = request.get_json()
    ttl, password = clean_input()
    token = set_password(password, ttl)
    return jsonify(key=token)


@app.route("/get-secret", methods=["POST"])
def show_password():
    if request.is_json:
        request.form = request.get_json()
    if empty(request.form.get("key", "")):
        abort(400)
    password_key = request.form["key"]
    password = get_password(password_key)
    if not password:
        return abort(404)
    return jsonify(password=password)


def main():
    db_path = os.environ.get("DB_PATH", "snapbin.db")
    initialize_db(db_path=db_path)
    app.run(host="0.0.0.0")


if __name__ == "__main__":
    main()
