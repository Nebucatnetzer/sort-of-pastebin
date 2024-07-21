from peewee import Model

from snapbin.database import db


class BaseModel(Model):
    class Meta:
        database = db
