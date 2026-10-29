// Real isolated PostgreSQL/WASM execution, no network/database credentials.
// Usage: node this.cjs <directory containing temporary node_modules> <bootstrap.json>
const fs=require('fs'),path=require('path'),assert=require('assert');
const {createRequire}=require('module');
const [dependencyRoot,bootstrapFile]=process.argv.slice(2);
if(!dependencyRoot||!bootstrapFile) throw Error('usage: <pglite dependency directory> <bootstrap SQL file list>');
const localRequire=createRequire(path.join(path.resolve(dependencyRoot),'package.json'));
const {PGlite}=localRequire('@electric-sql/pglite');
const {pgcrypto}=localRequire('@electric-sql/pglite/contrib/pgcrypto');
const bootstrap=JSON.parse(fs.readFileSync(bootstrapFile,'utf8'));
assert(Array.isArray(bootstrap)&&bootstrap.length>=20,'explicit real migration chain required');
(async()=>{
  const pg=new PGlite({extensions:{pgcrypto}});
  let current='bootstrap roles';
  try {
    await pg.exec(`
      CREATE ROLE goufayu_owner NOLOGIN;
      CREATE ROLE goufayu_app NOLOGIN;
      CREATE ROLE anon NOLOGIN;
      CREATE ROLE authenticated NOLOGIN;
      CREATE ROLE service_role NOLOGIN;
      CREATE SCHEMA extensions AUTHORIZATION goufayu_owner;
      CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
      GRANT USAGE,CREATE ON SCHEMA public TO goufayu_owner;
      GRANT USAGE ON SCHEMA extensions TO goufayu_owner,goufayu_app;
      SET ROLE goufayu_owner;
    `);
    const files=[];
    for(const filename of bootstrap){
      current=filename;
      await pg.exec(fs.readFileSync(filename,'utf8').replace(/^\uFEFF/,''));
      files.push(path.basename(filename));
    }
    current='real receipt transaction assertions';
    const testPath='server/tests/archive_challenge_receipts_database.sql';
    await pg.exec(fs.readFileSync(testPath,'utf8').replace(/^\uFEFF/,''));
    const leftovers=await pg.query(`SELECT count(*)::int count FROM public.archive_operations
      WHERE operation_id LIKE 'challenge-probe:%'`);
    assert.strictEqual(leftovers.rows[0].count,0,'transaction test must leave no receipt fixtures');
    const trigger=await pg.query(`SELECT count(*)::int count FROM pg_trigger
      WHERE tgname='archive_challenge_receipt_probe_failure'`);
    assert.strictEqual(trigger.rows[0].count,0,'injected rollback trigger must not survive');
    const version=(await pg.query('SELECT version() version')).rows[0].version;
    console.log(JSON.stringify({status:'PASS',engine:version,bootstrap_files:files,
      test:testPath,atomic_commit_and_response:true,lost_response_replay:true,revision_conflict:true,
      rollback_on_response_write_error:true,legacy_null_receipts_unchanged:true,inventory_preserved:true,
      least_privilege_checked:true,fixtures_rolled_back:true,external_database_connections:0}));
  } catch(error){
    console.error(JSON.stringify({status:'FAIL',stage:current,error:error.message,code:error.code}));
    process.exitCode=1;
  } finally{await pg.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
