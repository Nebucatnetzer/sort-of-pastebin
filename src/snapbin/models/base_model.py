from peewee import Model

from snapbin.database import db


# pylint: disable=too-few-public-methods
class BaseModel(Model):
    class Meta:
        database = db
