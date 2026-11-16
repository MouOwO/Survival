"""Bounded, conservative rate-credit reservations; explicit caller opt-in only.

Caller holds the same lock as all other uses of this SQLite connection. Credits
are committed before use, and abandoned credits never return to the database.
Session authorization and business operations are outside this helper.
Init/idle O(1); consume O(1) indexed operations; space O(max_keys), at most 4096.
There is no poller, account scan, retry, connection creation or global cache.
"""
from collections import OrderedDict


class RateReservations:
    def __init__(self, *, max_keys=4096):
        if type(max_keys) is not int or not 1 <= max_keys <= 4096:
            raise ValueError("rate_reservation_budget_invalid")
        self._entries = OrderedDict()
        self._max_keys = max_keys
        self._highest_bucket = None

    def consume(self, db, key, bucket, maximum, *, batch):
        """Use one prepaid credit, or atomically reserve a bounded new batch.

        Return False on an exhausted or backwards-clock bucket. SQLite errors
        propagate and leave no usable new credits. BEGIN IMMEDIATE makes the
        read/update atomic across independent connections and processes.
        A policy change discards existing credits for that key, conservatively.
        """
        if (type(key) is not str or len(key) != 64
                or any(c not in "0123456789abcdef" for c in key)
                or type(bucket) is not int or bucket < 0
                or type(maximum) is not int or not 1 <= maximum <= 120000
                or type(batch) is not int or not 1 <= batch <= 64):
            raise ValueError("rate_reservation_input_invalid")
        if db.in_transaction:
            raise ValueError("rate_reservation_requires_idle_connection")
        if self._highest_bucket is not None and bucket < self._highest_bucket:
            return False
        self._highest_bucket = bucket
        cached = self._entries.get(key)
        if cached is not None:
            saved_bucket, saved_maximum, credits = cached
            if saved_bucket == bucket and saved_maximum == maximum and credits:
                self._entries[key] = (bucket, maximum, credits - 1)
                self._entries.move_to_end(key)
                return True
            del self._entries[key]
        reserved = 0
        with db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT count FROM limits WHERE key=? AND bucket=?", (key, bucket)).fetchone()
            count = 0 if row is None else row[0]
            if type(count) is not int or count < 0:
                raise ValueError("rate_reservation_counter_invalid")
            reserved = min(batch, max(0, maximum - count))
            if reserved:
                db.execute("INSERT INTO limits VALUES(?,?,?) ON CONFLICT(key,bucket) DO UPDATE SET count=count+excluded.count", (key, bucket, reserved))
        # No cache publication occurs until successful COMMIT. Eviction merely
        # wastes reserved credits; it cannot manufacture capacity after restart.
        if not reserved:
            return False
        if len(self._entries) == self._max_keys:
            self._entries.popitem(last=False)
        self._entries[key] = (bucket, maximum, reserved - 1)
        return True
