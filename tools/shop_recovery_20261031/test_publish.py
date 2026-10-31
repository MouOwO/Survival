"""Admission rejects stale releases, copied player data, or missing preservation."""
import copy
import unittest
import publish as p


def fixture():
    package={'content_sha256':'a'*64}
    native=dict(status='PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY',release_sequence=p.b.SEQUENCE,
        content_sha256=package['content_sha256'],signed_resources_verified=6917,protected_modules_verified=184,
        cheats=False,normal_default_verified=True,redemption_resources_verified=True,
        markers={key:True for key in ('signed_addon','server_activated','initialized','layout_ready','no_script_error')})
    plan=dict(authorized_scope='WS4_3_TABLES_2_RPCS_EXISTING_128_DEFINITIONS',
        release='20261031-redemption-ws4-123456789abc',registry_count=128)
    clone=dict(ok=True,checks=dict(ok=True,clone_only=True,actual_app_transport_ready=True,
        real_lua_reducer=True,checks=sorted(p.CHECKS),real_player_redemption=False),
        production_player_data_copied=False,real_code_definitions_copied_to_clone=False,codes_registered=0)
    backup=dict(bytes=100,sha256='b'*64)
    protected=dict(encrypted_verified=True,sha256=backup['sha256'])
    active=dict(ok=True,status='WS4_REDEMPTION_ACTIVATED',release=plan['release'],bundle=p.BUNDLE,
        payment_untouched=True,codes_registered=128,old_business_tables_unchanged=31,existing_functions_and_acls_unchanged=True)
    verified=dict(ok=True,status='WS4_REDEMPTION_VERIFIED',bundle=p.BUNDLE,codes=128,payment_untouched=True,
        synthetic_schema_validation=True,real_player_redemption=False)
    return [package,native,plan,clone,backup,protected,active,verified]


class AdmissionTests(unittest.TestCase):
    def test_complete_scoped_proof(self):p.validate_receipts(*fixture())

    def test_stale_native_or_partial_proof(self):
        for key,value in [('release_sequence',2026103101),('normal_default_verified',False),('cheats',True),('markers',{})]:
            args=fixture();args[1][key]=value
            with self.assertRaises(ValueError):p.validate_receipts(*args)

    def test_real_data_or_missing_lua_rejected(self):
        for field in ('production_player_data_copied','real_code_definitions_copied_to_clone'):
            args=fixture();args[3][field]=True
            with self.assertRaises(ValueError):p.validate_receipts(*args)
        args=fixture();args[3]['checks']['real_lua_reducer']=False
        with self.assertRaises(ValueError):p.validate_receipts(*args)

    def test_backup_scope_and_preservation_rejected(self):
        for index,key,value in [(2,'registry_count',129),(5,'encrypted_verified',False),
            (6,'existing_functions_and_acls_unchanged',False),(7,'payment_untouched',False),
            (7,'real_player_redemption',True)]:
            args=copy.deepcopy(fixture());args[index][key]=value
            with self.assertRaises(ValueError):p.validate_receipts(*args)


if __name__=='__main__':unittest.main()
