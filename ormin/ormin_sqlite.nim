
{.deadCodeElim: on.}

import strutils, sqlite3, json

import db_common
export db_common

type
  DbConn* = PSqlite3  ## encapsulates a database connection
  varchar* = string
  integer* = int
  timestamp* = string

#[
int sqlite3_bind_blob(sqlite3_stmt*, int, const void*, int n, void(*)(void*));
int sqlite3_bind_blob64(sqlite3_stmt*, int, const void*, sqlite3_uint64,
                        void(*)(void*));
int sqlite3_bind_double(sqlite3_stmt*, int, double);
int sqlite3_bind_int(sqlite3_stmt*, int, int);
int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64);
int sqlite3_bind_null(sqlite3_stmt*, int);
int sqlite3_bind_text(sqlite3_stmt*,int,const char*,int,void(*)(void*));
int sqlite3_bind_text16(sqlite3_stmt*, int, const void*, int, void(*)(void*));
int sqlite3_bind_text64(sqlite3_stmt*, int, const char*, sqlite3_uint64,
                        void(*)(void*), unsigned char encoding);
int sqlite3_bind_value(sqlite3_stmt*, int, const sqlite3_value*);
int sqlite3_bind_pointer(sqlite3_stmt*, int, void*, const char*,void(*)(void*));
int sqlite3_bind_zeroblob(sqlite3_stmt*, int, int n);
int sqlite3_bind_zeroblob64(sqlite3_stmt*, int, sqlite3_uint64);

const void *sqlite3_column_blob(sqlite3_stmt*, int iCol);
double sqlite3_column_double(sqlite3_stmt*, int iCol);
int sqlite3_column_int(sqlite3_stmt*, int iCol);
sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int iCol);
const unsigned char *sqlite3_column_text(sqlite3_stmt*, int iCol);
const void *sqlite3_column_text16(sqlite3_stmt*, int iCol);
sqlite3_value *sqlite3_column_value(sqlite3_stmt*, int iCol);
int sqlite3_column_bytes(sqlite3_stmt*, int iCol);
int sqlite3_column_type(sqlite3_stmt*, int iCol);

const void *sqlite3_column_blob(sqlite3_stmt*, int iCol);
int sqlite3_column_int(sqlite3_stmt*, int iCol);
sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int iCol);
const unsigned char *sqlite3_column_text(sqlite3_stmt*, int iCol);
const void *sqlite3_column_text16(sqlite3_stmt*, int iCol);
sqlite3_value *sqlite3_column_value(sqlite3_stmt*, int iCol);
int sqlite3_column_bytes(sqlite3_stmt*, int iCol);
int sqlite3_column_type(sqlite3_stmt*, int iCol);
]#

proc dbError*(db: DbConn) {.noreturn.} =
  ## raises a DbError exception.
  var e: ref DbError
  new(e)
  e.msg = $sqlite3.errmsg(db)
  raise e

proc prepareStmt*(db: DbConn; q: string): PStmt =
  if prepare_v2(db, q, q.len.cint, result, nil) != SQLITE_OK:
    dbError(db)

template startBindings*(n: int) {.dirty.} = discard "nothing to do"

template bindParam*(db: DbConn; s: PStmt; idx: int; x: int; t: untyped) =
  if bind_int64(s, idx.cint, x.int64) != SQLITE_OK:
    dbError(db)

template bindParam*(db: DbConn; s: PStmt; idx: int; x: int64; t: untyped) =
  if bind_int64(s, idx.cint, x) != SQLITE_OK:
    dbError(db)

template bindParam*(db: DbConn; s: PStmt; idx: int; x: string; t: untyped) =
  if bind_blob(s, idx.cint, cstring(x), x.len.cint, SQLITE_STATIC) != SQLITE_OK:
    dbError(db)

template bindParam*(db: DbConn; s: PStmt; idx: int; x: float64; t: untyped) =
  if bind_double(s, idx.cint, x) != SQLITE_OK:
    dbError(db)

template bindParamJson*(db: DbConn; s: PStmt; idx: int; xx: JsonNode;
                        t: typedesc) =
  let x = xx
  if x.kind == JNull:
    if bind_null(s, idx.cint) != SQLITE_OK: dbError(db)
  else:
    when t is string:
      doAssert x.kind == JString
      let xs = x.str
      bindParam(db, s, idx, xs, t)
    elif (t is int) or (t is int64):
      doAssert x.kind == JInt
      let xi = x.num
      bindParam(db, s, idx, xi, t)
    elif t is float64:
      doAssert x.kind == JFloat
      let xf = x.fnum
      bindParam(db, s, idx, xf, t)
    else:
      {.error: "invalid type for JSON object".}

template bindResult*(db: DbConn; s: PStmt; idx: int; dest: int;
                     t: typedesc; name: string) =
  dest = int column_int64(s, idx.cint)

template bindResult*(db: DbConn; s: PStmt; idx: int; dest: int64;
                     t: typedesc; name: string) =
  dest = column_int64(s, idx.cint)

proc fillString(dest: var string; src: cstring; srcLen: int) =
  if dest.isNil: dest = newString(srcLen)
  else: setLen(dest, srcLen)
  copyMem(unsafeAddr(dest[0]), src, srcLen)
  dest[srcLen] = '\0'

template bindResult*(db: DbConn; s: PStmt; idx: int; dest: var string;
                     t: typedesc; name: string) =
  let srcLen = column_bytes(s, idx.cint)
  let src = column_text(s, idx.cint)
  fillString(dest, src, srcLen)

template bindResult*(db: DbConn; s: PStmt; idx: int; dest: float64;
                     t: typedesc; name: string) =
  dest = column_double(s, idx.cint)

template createJObject*(): untyped = newJObject()
template createJArray*(): untyped = newJArray()

template bindResultJson*(db: DbConn; s: PStmt; idx: int; obj: JsonNode;
                         t: typedesc; name: string) =
  let x = obj
  doAssert x.kind == JObject
  if column_type(s, idx.cint) == SQLITE_NULL:
    x[name] = newJNull()
  else:
    when t is string:
      doAssert x.kind == JString
      let dest = newJString(nil)
      let srcLen = column_bytes(s, idx.cint)
      let src = column_text(s, idx.cint)
      fillString(dest.str, src, srcLen)
      x[name] = dest
    elif (t is int) or (t is int64):
      x[name] = newJInt(column_int64(s, idx.cint))
    elif t is float64:
      x[name] = newJFloat(column_double(s, idx.cint))
    else:
      {.error: "invalid type for JSON object".}

template startQuery*(db: DbConn; s: PStmt) = discard "nothing to do"

template stopQuery*(db: DbConn; s: PStmt) =
  if finalize(s) != SQLITE_OK: dbError(db)

template stepQuery*(db: DbConn; s: PStmt): bool =
  step(s) == SQLITE_ROW

template getLastId*(db: DbConn; s: PStmt): int =
  int(last_insert_rowid(db))

template getAffectedRows*(db: DbConn; s: PStmt): int =
  int(changes(db))

proc close*(db: DbConn) =
  ## closes the database connection.
  if sqlite3.close(db) != SQLITE_OK: dbError(db)

proc open*(connection, user, password, database: string): DbConn =
  ## opens a database connection. Raises `EDb` if the connection could not
  ## be established. Only the ``connection`` parameter is used for ``sqlite``.
  if sqlite3.open(connection, result) != SQLITE_OK:
    dbError(result)
