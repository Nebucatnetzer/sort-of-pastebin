import datetime

from peewee import CharField
from peewee import DateTimeField
from peewee import IntegerField
from snapbin.models.base_model import BaseModel


# pylint: disable=too-few-public-methods
class Secret(BaseModel):
    creation_date = DateTimeField(default=datetime.datetime.now())
    storage_key = CharField(max_length=32, primary_key=True)
    ttl = IntegerField()
    value = CharField()

    def is_expired(self) -> bool:
        """Returns false when the creation date is older than the ttl (time to live)"""
        now = datetime.datetime.now()
        difference = int((now - self.creation_date).total_seconds())  # type: ignore
        if difference > self.ttl:
            return True
        return False
