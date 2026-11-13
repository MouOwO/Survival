"""One fixed SQL-only candidate; no skipped predicates or authorization cache."""
import ast,hashlib
PARENTS=frozenset(('15efa09cc9297ff065d56067570ba001ae3c4700db62df6e4cd159e5f1e0a966','fde92f0b97b31769d6e42e0f76fc81db6a30db68c4f5536ab4c89bb8008fa7a8'))
PREFIX="""WITH guard_namespaces AS MATERIALIZED (
 SELECT oid FROM pg_namespace
 WHERE nspname !~ '^pg_' AND nspname <> 'information_schema'
), guard_relations AS MATERIALIZED (
 SELECT c.oid,c.relowner,c.relkind FROM pg_class c
 JOIN guard_namespaces n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p','v','m','f','S')
), guard_functions AS MATERIALIZED (
 SELECT p.oid,p.proowner,p.pronamespace FROM pg_proc p
 JOIN guard_namespaces n ON n.oid=p.pronamespace
)
"""
def optimize_runtime(sql):
 old="FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace\n               WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'\n               AND c.relkind"
 if sql.count(old)!=2:raise ValueError('filtered_role_relation_anchor_changed')
 result=sql.replace(old,'FROM guard_relations c\n               WHERE c.relkind')
 old="FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace\n               WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'\n               AND (p.proowner"
 if result.count(old)!=1:raise ValueError('filtered_role_function_anchor_changed')
 result=result.replace(old,'FROM guard_functions p\n               WHERE (p.proowner',1)
 if result.count("has_schema_privilege(n.oid, 'USAGE')")!=1:raise ValueError('filtered_role_usage_anchor_changed')
 result=result.replace("has_schema_privilege(n.oid, 'USAGE')","has_schema_privilege(p.pronamespace, 'USAGE')",1)
 return PREFIX+result.lstrip()
def patch_postgres(source):
 if hashlib.sha256(source.encode()).hexdigest() not in PARENTS:raise ValueError('filtered_role_parent_changed')
 tree=ast.parse(source);node=next(n for n in tree.body if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id=='_RUNTIME_CHECK')
 original=ast.get_source_segment(source,node);result=source.replace(original,'_RUNTIME_CHECK = '+repr(optimize_runtime(ast.literal_eval(node.value))),1)
 compile(result,'<filtered-role-v1>','exec')
 other=ast.parse(result)
 for t in (tree,other):
  for n in t.body:
   if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id=='_RUNTIME_CHECK':n.value=ast.Constant(value='ONLY_RUNTIME_SQL_MAY_CHANGE')
 if ast.dump(tree,include_attributes=False)!=ast.dump(other,include_attributes=False):raise ValueError('filtered_role_ast_delta_changed')
 return result
