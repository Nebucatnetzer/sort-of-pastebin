from peewee import CharField
from peewee import IntegerField
from snapbin.models import BaseModel


class Secret(BaseModel):
    storage_key = CharField(max_length=32, primary_key=True)
    ttl = IntegerField()
    value = CharField()
