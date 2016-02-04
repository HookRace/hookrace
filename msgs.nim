import macros, strutils

import network

# Helpers
template addUint8(x) {.immediate.} =
  raw[result] = uint8(x)
  inc result

template addUint16(x) {.immediate.} =
  addUint8(uint16(x) shr 8)
  addUint8(uint16(x))

template addUint32(x) {.immediate.} =
  addUint16(uint32(x) shr 16)
  addUint16(uint32(x))

template addCharArray(xs) {.immediate.} =
  for x in xs:
    addUint8(x)

template getUint8: uint8 {.immediate.} =
  let x = raw[i]
  inc i
  x

template getUint16: uint16 {.immediate.} =
  let hi = getUint8()
  let lo = getUint8()
  (uint16(hi) shl 8) or lo

template getUint32: uint32 {.immediate.} =
  let hi = getUint16()
  let lo = getUint16()
  (uint32(hi) shl 16) or lo

template getCharArray(xs) {.immediate.} =
  for x in xs.mitems:
    x = char(getUint8())

# Create the msgs code
macro msgDefinitions(x): stmt =
  let
    netmsg = quote do:
      type NetMsg* {.inject, pure.} = enum
        null = 0'u8

    netmsgElems = netmsg[0][0][2]

    objects, packProcs, unpackProcs, createProcs = newStmtList()

  x.expectKind nnkStmtList
  x.expectMinLen 1

  for y in x: # Messags
    y.expectKind nnkCall
    y.expectLen 2

    y[0].expectKind nnkIdent
    netmsgElems.add y[0]
    let netmsgName = $y[0]
    let msgName = ident(capitalize($y[0]))

    objects.add quote do:
      type `msgName`* {.inject.} = object
    objects.last[0][0][2][2] = newNimNode(nnkRecList)
    let objectElems = objects.last[0][0][2][2]

    var packProc = """
proc pack*(raw: var array[maxPacketSize, byte], msg: $#): int =
  result = 0
  addUint8 NetMsg.$#
""" % [$msgName, netmsgName]

    var unpackProc = """
proc unpack$1*(raw: array[maxPacketSize, byte]): $1 {.inject.} =
  var i = 0
  doAssert getUint8() == uint8(NetMsg.$2)
""" % [$msgName, netmsgName]

    var createArgs = ""
    var createAssigns = ""

    y[1].expectKind nnkStmtList
    y[1].expectMinLen 1

    for z in y[1]: # Values in the msgs
      z.expectKind nnkCall
      z.expectLen 2

      z[0].expectKind nnkIdent
      z[1].expectKind nnkStmtList
      z[1].expectLen 1

      let
        fieldName = $z[0]
        typ = z[1][0]

      if createArgs.len > 0:
        createArgs.add ", "
      createArgs.add fieldName & ": " & typ.repr

      createAssigns.add "  result.$1 = $1\n" % fieldName

      case typ.kind
      of nnkIdent:
        case $typ.ident
        of "uint8":
          packProc.add "  addUint8 msg.$#\n" % fieldName
          unpackProc.add "  result.$# = getUint8()\n" % fieldName
        of "uint16":
          packProc.add "  addUint16 msg.$#\n" % fieldName
          unpackProc.add "  result.$# = getUint16()\n" % fieldName
        of "uint32":
          packProc.add "  addUint32 msg.$#\n" % fieldName
          unpackProc.add "  result.$# = getUint32()\n" % fieldName
        else: raise newException(ValueError, "Unknown field type: " & $typ.ident)
      of nnkBracketExpr:
        typ.expectLen 3
        typ[0].expectKind nnkIdent
        typ[1].expectKind nnkIntLit
        typ[2].expectKind nnkIdent
        #echo typ.repr
        packProc.add "  addCharArray msg.$#\n" % fieldName
        unpackProc.add "  result.$#.getCharArray()\n" % fieldName
      else: raise newException(ValueError, "Unknown field type: " & $typ)

      objectElems.add newIdentDefs(newNimNode(nnkPostfix).add(ident("*")).add(z[0]), z[1][0])

    packProcs.add parseStmt(packProc)
    unpackProcs.add parseStmt(unpackProc)
    createProcs.add parseStmt("proc init$1*($2): $1 = \n$3" % [$msgName, createArgs, createAssigns])

  result = newStmtList(netmsg, objects, packProcs, unpackProcs, createProcs)
  #echo result.repr

macro caseMsg*(x, ys): stmt =
  result = newNimNode(nnkCaseStmt).add(quote do: NetMsg(`x`[0]))

  ys.expectKind nnkStmtList
  ys.expectMinLen 1

  for y in ys:
    case y.kind
    of nnkOfBranch:
      y[0].expectKind nnkIdent
      let id = y[0]
      let name = capitalize($y[0].ident)
      y[0] = quote do: NetMsg.`id`

      y[1].expectKind nnkStmtList
      let msgAssign = parseStmt "let msg = unpack$#($#)" % [name, $x]
      y[1].insert(0, msgAssign)

    of nnkElse:
      y[0].expectKind nnkStmtList

    else: raise newException(ValueError, "Unhandled kind: " & $y.kind)
    result.add y

macro CharArray*(x, ys): expr =
  result = newNimNode(nnkBracket)

  x.expectKind({nnkCharLit..nnkInt64Lit})
  ys.expectKind({nnkStrLit..nnkTripleStrLit})

  if ys.strVal.len > x.intVal:
    raise newException(ValueError, "String too long: " & $ys)

  for i, y in ys.strVal:
    let z = newNimNode(nnkCharLit)
    z.intVal = int(y)
    result.add z
  for i in BiggestInt(ys.strVal.len) ..< x.intVal:
    result.add newNimNode(nnkCharLit)

# The actual network msg definitions
msgDefinitions:
  syn: # Client -> Server
    clientVersion: array[16, char]
    playerID: uint32 # Unique worldwide player ID from account server
    clientToken: uint16 # Random token to verify that server is not spoofed

  synack: # Server -> Client
    playerID: uint32 # Same player number back as token
    ingameID: uint16 # New player ID on the server, position in players array
    clientToken: uint16 # Same token back
    serverToken: uint16 # Random token to verify that client is not spoofed

  ack: # Client -> Server
    serverToken: uint16 # Same token back
