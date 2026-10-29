"""Narrow source hooks; callers pin and preserve the actual remote baseline."""
import ast

COMMAND = '''        if kind == "redemption_redeem":
            from .redemption_codes import command as redeem
            try:
                return redeem(self, payload)
            except ValueError as error:
                raise ArchiveError(str(error)) from error
'''
FINISH = '''        if prepared.get("command", {}).get("kind") == "redemption_redeem":
            from .redemption_codes import finish as finish_redemption
            return finish_redemption(self, account, operation_id, prepared)
'''
RPC = '''    # BEGIN SURVIVAL_REDEMPTION_RPC_V1
    "redemption_prepare": _params(
        ("p_account", "text", "hash"), ("p_session", "text", "request_id"),
        ("p_code_hash", "text", "hash"), ("p_request", "text", "request_id"),
        ("p_hash", "text", "hash")),
    "redemption_commit": _params(
        ("p_account", "text", "hash"), ("p_id", "text", "archive_id"),
        ("p_revision", "bigint", "revision"), ("p_archive", "jsonb", "object"),
        ("p_deltas", "jsonb", "object"), ("p_inventory", "jsonb", "object"),
        ("p_response", "jsonb", "object")),
    # END SURVIVAL_REDEMPTION_RPC_V1
'''


def patch(raw, kind):
    text = raw.decode("utf-8")
    newline = "\r\n" if "\r\n" in text else "\n"
    changes = ([('        # Account tutorial metadata', COMMAND),
                ('        for _ in range(4):\n            if not prepared.get("ok")', FINISH)]
               if kind == "service" else [('}\nRUNTIME_ROLE =', RPC)])
    for anchor, insertion in changes:
        anchor, insertion = anchor.replace("\n", newline), insertion.replace("\n", newline)
        if insertion in text:
            continue
        if text.count(anchor) != 1:
            raise ValueError("redeem_backend_patch_context_changed")
        text = text.replace(anchor, insertion + anchor, 1)
    ast.parse(text)
    return text.encode("utf-8")
