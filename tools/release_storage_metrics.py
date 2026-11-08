"""Read-only, single-pass Windows file-storage metadata provider.

The caller owns directory traversal, parent/reparse checks and exclusions. This
module never reads file contents, scans directories, follows links intentionally,
changes files/ACLs, or estimates deletion savings. Import has no Win32 side effect.

Per ordinary file: one attribute-only handle, four metadata queries, close (six
primary Win32 calls). A new compressed/sparse identity adds two size queries;
another hardlink reuses that measurement after its own identity/state queries.
O(1) work per path, O(U) cache for U distinct observed file identities. Cache
entries change only on actual identity/metadata changes; there is no timer.
"""
from collections import Counter
import ctypes
import ntpath
import os
import stat


REPARSE = 0x400
DIRECTORY = 0x10
SPARSE = 0x200
COMPRESSED = 0x800


class _Basic(ctypes.Structure):
    _fields_ = [(name, ctypes.c_int64) for name in
                ("creation", "access", "write", "change")] + [("attributes", ctypes.c_uint32)]


class _Standard(ctypes.Structure):
    _fields_ = [("allocation", ctypes.c_int64), ("size", ctypes.c_int64),
                ("links", ctypes.c_uint32), ("delete_pending", ctypes.c_ubyte),
                ("directory", ctypes.c_ubyte)]


class _Id(ctypes.Structure):
    _fields_ = [("volume", ctypes.c_uint64), ("identifier", ctypes.c_ubyte * 16)]


class _Compression(ctypes.Structure):
    _fields_ = [("size", ctypes.c_int64), ("format", ctypes.c_uint16),
                ("unit_shift", ctypes.c_ubyte), ("chunk_shift", ctypes.c_ubyte),
                ("cluster_shift", ctypes.c_ubyte), ("reserved", ctypes.c_ubyte * 3)]


class _Win32Metadata:
    """Only metadata APIs. No FILE_READ_DATA/GENERIC_READ permission is requested."""
    def __init__(self):
        if os.name != "nt":
            raise OSError("WINDOWS_METADATA_UNAVAILABLE")
        from ctypes import wintypes
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD,
            wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        self.kernel.CreateFileW.restype = wintypes.HANDLE
        self.kernel.GetFileInformationByHandleEx.argtypes = [wintypes.HANDLE,
            ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        self.kernel.GetFileInformationByHandleEx.restype = wintypes.BOOL
        self.kernel.GetCompressedFileSizeW.argtypes = [wintypes.LPCWSTR,
            ctypes.POINTER(wintypes.DWORD)]
        self.kernel.GetCompressedFileSizeW.restype = wintypes.DWORD
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.kernel.CloseHandle.restype = wintypes.BOOL

    @staticmethod
    def _native_path(path):
        path = ntpath.normpath(path)
        if path.startswith("\\\\?\\"):
            return path
        if path.startswith("\\\\"):
            return "\\\\?\\UNC\\" + path[2:]
        return "\\\\?\\" + path

    def open(self, path):
        # READ_ATTRIBUTES, SHARE_READ|WRITE|DELETE, OPEN_EXISTING,
        # OPEN_REPARSE_POINT|BACKUP_SEMANTICS. Directories/reparse are rejected.
        handle = self.kernel.CreateFileW(self._native_path(path), 0x80, 7, None, 3, 0x02200000, None)
        if handle == ctypes.c_void_p(-1).value:
            raise ctypes.WinError(ctypes.get_last_error())
        return handle

    def _query(self, handle, info_class, structure):
        value = structure()
        if not self.kernel.GetFileInformationByHandleEx(handle, info_class,
                                                       ctypes.byref(value), ctypes.sizeof(value)):
            raise ctypes.WinError(ctypes.get_last_error())
        return value

    def basic(self, handle):
        value = self._query(handle, 0, _Basic)
        return dict(attributes=int(value.attributes), write=int(value.write), change=int(value.change))

    def standard(self, handle):
        value = self._query(handle, 1, _Standard)
        return dict(allocation=int(value.allocation), size=int(value.size), links=int(value.links),
                    directory=bool(value.directory), delete_pending=bool(value.delete_pending))

    def identity(self, handle):
        value = self._query(handle, 18, _Id)
        return dict(volume=f"{value.volume:016x}", file_id=bytes(value.identifier).hex())

    def compression(self, handle):
        value = self._query(handle, 8, _Compression)
        return int(value.size)

    def compressed_size(self, path):
        high = ctypes.c_uint32()
        ctypes.set_last_error(0)
        low = self.kernel.GetCompressedFileSizeW(self._native_path(path), ctypes.byref(high))
        if low == 0xFFFFFFFF and ctypes.get_last_error():
            raise ctypes.WinError(ctypes.get_last_error())
        return (high.value << 32) | low

    def close(self, handle):
        if not self.kernel.CloseHandle(handle):
            raise ctypes.WinError(ctypes.get_last_error())


class MetadataProvider:
    """Reuse one instance per scan; ``backend`` injection is for pure tests only.

    inspect_file returns measured fields or None, plus structured errors. identity
    is ``volume_serial:file_id_128``. storage_bytes is the measured data allocation,
    NOT exclusive ownership or reclaimable space (hardlinks/open handles remain).
    The supplied stat_result must come from lstat/stat(follow_symlinks=False).
    A partial/error row must not be counted as a complete physical measurement.
    """
    def __init__(self, backend=None):
        self.backend = backend
        self.metrics = Counter()
        self._physical = {}

    def _call(self, method, *args):
        self.metrics["native_calls"] += 1
        self.metrics["native_" + method] += 1
        return getattr(self.backend, method)(*args)

    def inspect_file(self, path, stat_result=None):
        self.metrics["files_inspected"] += 1
        path = os.fsdecode(os.fspath(path))
        row = dict(path=path, status="ERROR", logical_bytes=None, volume_serial=None,
            file_id_128=None, identity=None, number_of_links=None, allocation_bytes=None,
            compressed_storage_bytes=None, storage_bytes=None, storage_basis=None,
            file_attributes=None, compressed=None, sparse=None, reparse=None,
            storage_cache_hit=False, reclaimable_bytes=None, errors=[])

        def error(operation, code, exception=None):
            row["errors"].append(dict(operation=operation, code=code,
                winerror=getattr(exception, "winerror", None) if exception else None))
            self.metrics["errors"] += 1

        if not ntpath.isabs(path) or "\x00" in path:
            error("path", "ABSOLUTE_REGULAR_FILE_PATH_REQUIRED")
            return row
        try:
            if stat_result is None:
                self.metrics["lstat_calls"] += 1
                stat_result = os.lstat(path)
            attributes = getattr(stat_result, "st_file_attributes", 0)
            row["file_attributes"] = attributes
            row["reparse"] = bool(attributes & REPARSE) or stat.S_ISLNK(stat_result.st_mode)
            if row["reparse"] or not stat.S_ISREG(stat_result.st_mode):
                row["status"] = "REJECTED"
                error("lstat", "REPARSE_REJECTED" if row["reparse"] else "NOT_REGULAR_FILE")
                return row
            row["logical_bytes"] = int(stat_result.st_size)
        except OSError as exc:
            error("lstat", "STAT_FAILED", exc)
            return row

        handle = None
        stage = "backend"
        try:
            if self.backend is None:
                self.backend = _Win32Metadata()
            stage = "open"
            handle = self._call("open", path)
            stage = "basic"
            before = self._call("basic", handle)
            attrs = before["attributes"]
            row.update(file_attributes=attrs, compressed=bool(attrs & COMPRESSED),
                       sparse=bool(attrs & SPARSE), reparse=bool(attrs & REPARSE))
            if attrs & (REPARSE | DIRECTORY):
                row["status"] = "REJECTED"
                error(stage, "REPARSE_REJECTED" if attrs & REPARSE else "NOT_REGULAR_FILE")
                return row
            stage = "standard"
            info = self._call("standard", handle)
            if info["directory"] or info["delete_pending"]:
                row["status"] = "REJECTED"
                error(stage, "DIRECTORY_OR_DELETE_PENDING")
                return row
            if min(info["size"], info["allocation"], info["links"]) < 0 or info["links"] == 0:
                error(stage, "INVALID_NATIVE_SIZE_OR_LINK_COUNT")
                return row
            row.update(logical_bytes=info["size"], allocation_bytes=info["allocation"],
                       number_of_links=info["links"])
            stage = "identity"
            identity = self._call("identity", handle)
            row.update(volume_serial=identity["volume"], file_id_128=identity["file_id"],
                       identity=identity["volume"] + ":" + identity["file_id"])
            fingerprint = (info["size"], info["allocation"], attrs, before["write"], before["change"])
            cached = self._physical.get(row["identity"])
            if cached is not None and cached[0] == fingerprint:
                storage, compressed, basis = cached[1:]
                row["storage_cache_hit"] = True
                self.metrics["physical_cache_hits"] += 1
            elif attrs & (COMPRESSED | SPARSE):
                # The path API follows links. Compare to metadata from our already
                # opened non-reparse handle; never cache a substituted path's size.
                stage = "compressed_size"
                compressed = self._call("compressed_size", path)
                stage = "compression"
                by_handle = self._call("compression", handle)
                if compressed != by_handle or compressed < 0:
                    error(stage, "PATH_HANDLE_STORAGE_MISMATCH")
                    return row
                storage = compressed
                basis = "COMPRESSED_OR_SPARSE_PATH_AND_HANDLE_METADATA"
            else:
                compressed = None
                storage = info["allocation"]
                basis = "FILE_STANDARD_INFO_ALLOCATION_SIZE"
            stage = "basic_after"
            after = self._call("basic", handle)
            if before != after or info["size"] != stat_result.st_size:
                error(stage, "FILE_CHANGED_DURING_METADATA_OBSERVATION")
                self._physical.pop(row["identity"], None)
                return row
            self._physical[row["identity"]] = (fingerprint, storage, compressed, basis)
            self.metrics["unique_physical_records"] = len(self._physical)
            row.update(status="MEASURED", storage_bytes=storage,
                       compressed_storage_bytes=compressed, storage_basis=basis)
        except (OSError, ValueError, OverflowError) as exc:
            error(stage, "NATIVE_METADATA_FAILED", exc)
        finally:
            if handle is not None:
                try:
                    self._call("close", handle)
                except OSError as exc:
                    error("close", "HANDLE_CLOSE_FAILED", exc)
                    row["status"] = "ERROR"
                    row["storage_bytes"] = None
        return row


def inspect_file(path, stat_result=None):
    """Convenience single-file call; scans should reuse MetadataProvider."""
    return MetadataProvider().inspect_file(path, stat_result)
