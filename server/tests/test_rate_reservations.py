import concurrent.futures
from contextlib import closing
import hashlib
from pathlib import Path
import random
import sqlite3
import tempfile
import unittest
from player_web_auth.rate_reservations import RateReservations


def key(value):
    return hashlib.sha256(str(value).encode()).hexdigest()


def connect(path=":memory:"):
    db = sqlite3.connect(path, timeout=5)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=FULL")
    db.execute("CREATE TABLE IF NOT EXISTS limits(key TEXT,bucket INTEGER,count INTEGER,PRIMARY KEY(key,bucket))")
    db.commit()
    return db


class ReservationTests(unittest.TestCase):
    def test_exact_single_owner_limit_and_tail(self):
        with closing(connect()) as db:
            r = RateReservations()
            self.assertEqual(sum(r.consume(db,key(1),10,15,batch=8) for _ in range(30)),15)
            self.assertEqual(db.execute("SELECT count FROM limits").fetchone()[0],15)

    def test_hit_has_zero_sql(self):
        with closing(connect()) as db:
            r=RateReservations();r.consume(db,key(1),10,100,batch=64)
            queries=[];db.set_trace_callback(queries.append)
            for _ in range(63):self.assertTrue(r.consume(db,key(1),10,100,batch=64))
            self.assertEqual(queries,[])

    def test_independent_owners_do_not_overadmit(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"rate.sqlite";connect(path).close()
            def run(worker):
                db=connect(path);r=RateReservations()
                try:return sum(r.consume(db,key(1),10,157,batch=8) for _ in range(100))
                finally:db.close()
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                self.assertLessEqual(sum(pool.map(run,range(8))),157)
            with closing(connect(path)) as db:self.assertEqual(db.execute("SELECT count FROM limits").fetchone()[0],157)

    def test_restart_can_only_waste_credits(self):
        with closing(connect()) as db:
            a=RateReservations();self.assertTrue(a.consume(db,key(1),10,10,batch=8))
            b=RateReservations();self.assertEqual(sum(b.consume(db,key(1),10,10,batch=8) for _ in range(12)),2)

    def test_eviction_is_bounded_and_conservative(self):
        with closing(connect()) as db:
            r=RateReservations(max_keys=1)
            self.assertTrue(r.consume(db,key(1),10,8,batch=8));r.consume(db,key(2),10,8,batch=8)
            self.assertFalse(r.consume(db,key(1),10,8,batch=8));self.assertLessEqual(len(r._entries),1)

    def test_policy_reduction_discards_old_credit(self):
        with closing(connect()) as db:
            r=RateReservations();r.consume(db,key(1),10,100,batch=64)
            self.assertFalse(r.consume(db,key(1),10,1,batch=64))
            self.assertFalse(r.consume(db,key(1),10,1,batch=64))

    def test_next_bucket_and_clock_rollback(self):
        with closing(connect()) as db:
            r=RateReservations();r.consume(db,key(1),10,100,batch=64)
            self.assertTrue(r.consume(db,key(1),11,1,batch=64))
            self.assertFalse(r.consume(db,key(1),10,100,batch=64))

    def test_uncommitted_connection_rejected_even_on_hit(self):
        with closing(connect()) as db:
            r=RateReservations();r.consume(db,key(1),10,100,batch=64)
            db.execute("INSERT INTO limits VALUES(?,?,1)",(key(2),10))
            with self.assertRaisesRegex(ValueError,"requires_idle"):r.consume(db,key(1),10,100,batch=64)
            db.rollback()

    def test_failed_commit_does_not_publish(self):
        class FailedCommit:
            in_transaction=False
            def __init__(self,db):self.db=db
            def __enter__(self):self.db.__enter__();return self
            def __exit__(self,*args):self.db.rollback();raise sqlite3.OperationalError("synthetic_commit_failure")
            def execute(self,*args):return self.db.execute(*args)
        with closing(connect()) as db:
            r=RateReservations()
            with self.assertRaises(sqlite3.Error):r.consume(FailedCommit(db),key(1),10,100,batch=64)
            self.assertEqual(len(r._entries),0)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM limits").fetchone()[0],0)

    def test_sql_failure_does_not_publish(self):
        with closing(connect()) as db:
            db.execute("DROP TABLE limits");db.commit();r=RateReservations()
            with self.assertRaises(sqlite3.Error):r.consume(db,key(1),10,100,batch=64)
            self.assertEqual(len(r._entries),0);self.assertFalse(db.in_transaction)

    def test_invalid_counter_rejected(self):
        with closing(connect()) as db:
            db.execute("INSERT INTO limits VALUES(?,?,?)",(key(1),10,-1));db.commit()
            with self.assertRaisesRegex(ValueError,"counter_invalid"):RateReservations().consume(db,key(1),10,100,batch=64)

    def test_random_owner_restart_eviction_conservation(self):
        with closing(connect()) as db:
            rng=random.Random(1516);owners=[RateReservations(max_keys=4) for _ in range(8)];accepted={}
            for _ in range(5000):
                i=rng.randrange(8);account=rng.randrange(12)
                if rng.randrange(20)==0:owners[i]=RateReservations(max_keys=4)
                if owners[i].consume(db,key(account),10,123,batch=rng.randrange(1,65)):
                    accepted[account]=accepted.get(account,0)+1
                    self.assertLessEqual(accepted[account],123)
                    persisted=db.execute("SELECT count FROM limits WHERE key=? AND bucket=10",(key(account),)).fetchone()[0]
                    self.assertLessEqual(accepted[account],persisted);self.assertLessEqual(persisted,123)

    def test_invalid_options_and_inputs(self):
        for n in (True,0,4097):
            with self.assertRaises(ValueError):RateReservations(max_keys=n)
        with closing(connect()) as db:
            for args in [(key(1),True,100,4),("g"*64,10,100,4),(key(1),10,True,4),(key(1),10,100,65)]:
                with self.assertRaises(ValueError):RateReservations().consume(db,*args[:3],batch=args[3])

if __name__=="__main__":unittest.main()
