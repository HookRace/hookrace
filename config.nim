import macros, strutils, parseutils

type
  ConfigFlag = enum
    save, client, server

proc parseString(s: string): string =
  # TODO: Not perfect yet
  if s[0] in {'"', '\''}:
    if s[^1] != s[0]:
      raise newException(ValueError, "Invalid string: " & s)
    result = s[1..^2]
  else:
    result = s

proc newObjectDef(name: NimNode, recList: NimNode): NimNode {.compiletime.} =
  newNimNode(nnkTypeDef).add(name).add(newEmptyNode()).add(
    newNimNode(nnkObjectTy).add(newEmptyNode()).add(newEmptyNode()).add(recList))

macro config(x: stmt): stmt {.immediate.} =
  var
    typeSection = newNimNode(nnkTypeSection)
    configTypeList = newNimNode(nnkRecList)
    procs = newStmtList()
    initStmts = newStmtList()
    configIdent = ident("Config")
    execCase = newNimNode(nnkCaseStmt).add(ident("key"))

  x.expectKind(nnkStmtList)
  for g in x:
    g.expectKind(nnkCall)
    g.expectMinLen(2)

    var flags: set[ConfigFlag]
    for i in 1 .. g.len-2:
      flags.incl parseEnum[ConfigFlag]($g[i])

    g[0].expectKind(nnkIdent)
    let group = g[0]
    let groupType = ident(($group).capitalize & "Config")

    var recList = newNimNode(nnkRecList)

    g[^1].expectKind(nnkStmtList)
    for setting in g[^1]:
      setting.expectKind(nnkCommand)
      setting.expectLen(4)

      setting[0].expectKind(nnkIdent)
      let
        name    = setting[0]
        typ     = setting[1]
        default = setting[2]
        desc    = setting[3]

      when defined(server):
        if server notin flags:
          continue
      else:
        if client notin flags:
          continue

      var kind, assignOp, parseOp: NimNode
      case typ.kind
      of nnkBracketExpr:
        kind = case $typ[0]
          of "range": typ
          else: typ[0]
        if typ[0].kind == nnkIdent and $typ[0] == "string":
          # This could be optimized to prevent allocating new strings, pre-allocating string of max size beforehand and using copyMem then
          assignOp = newCall(newDotExpr(name, ident("substr")), newIntLitNode(0), typ[1])
          parseOp = newCall(ident("parseString"), ident("val"))
        else:
          assignOp = newCall(newDotExpr(name, ident("clamp")), newCall(ident("low"), newDotExpr(group, name)), newCall(ident("high"), newDotExpr(group, name)))
          parseOp = newCall(ident("parseInt"), ident("val"))
      else:
        kind = typ
        assignOp = name
        parseOp = newCall(ident("parseInt"), ident("val"))

      # Config object
      recList.add newIdentDefs(name, kind)

      # Setter proc
      let setterName = newNimNode(nnkAccQuoted).add(name, ident("="))
      procs.add newNimNode(nnkProcDef).add(
        setterName.postfix("*"),
        newEmptyNode(),
        newEmptyNode(),
        newNimNode(nnkFormalParams).add(
          newEmptyNode(),
          newIdentDefs(group, newNimNode(nnkVarTy).add(groupType)),
          newIdentDefs(name, kind, default)),
        newNimNode(nnkPragma).add(ident("inline")),
        newEmptyNode(),
        newStmtList().add(newAssignment(newDotExpr(group, name), assignOp)))

      # Accessor proc
      procs.add newNimNode(nnkTemplateDef).add(
        name.postfix("*"),
        newEmptyNode(),
        newEmptyNode(),
        newNimNode(nnkFormalParams).add(
          kind,
          newIdentDefs(group, groupType)),
        newEmptyNode(),
        newEmptyNode(),
        newStmtList().add(newDotExpr(group, name)))

      # Init proc
      #initStmts.add newAssignment(newDotExpr(newDotExpr(ident("result"), group), name), default)
      initStmts.add newCall(setterName, newDotExpr(ident("result"), group), default)

      # Exec proc
      execCase.add newNimNode(nnkOfBranch).add(newStrLitNode($group & "." & $name), newStmtList().add(
        newCall(setterName, newDotExpr(ident("config"), group), parseOp)))

    if recList.len > 0:
      typeSection.add newObjectDef(groupType.postfix("*"), recList)
      configTypeList.add newIdentDefs(group.postfix("*"), groupType)

  typeSection.add newObjectDef(configIdent.postfix("*"), configTypeList)

  procs.add newNimNode(nnkProcDef).add(
    ident("initConfig").postfix("*"),
    newEmptyNode(),
    newEmptyNode(),
    newNimNode(nnkFormalParams).add(configIdent),
    newEmptyNode(),
    newEmptyNode(),
    initStmts)

  execCase.add newNimNode(nnkElse).add(newStmtList().add(newAssignment(ident("result"), ident("false"))))
  procs.add newNimNode(nnkProcDef).add(
    ident("execConfig").postfix("*"),
    newEmptyNode(),
    newEmptyNode(),
    newNimNode(nnkFormalParams).add(
      ident("bool"),
      newIdentDefs(ident("config"), newNimNode(nnkVarTy).add(ident("Config"))),
      newIdentDefs(ident("key"), ident("string")),
      newIdentDefs(ident("val"), ident("string"))),
    newEmptyNode(),
    newEmptyNode(),
    newNimNode(nnkStmtList).add(
      newAssignment(ident("result"), ident("true")),
      execCase))

  result = newStmtList().add(typeSection).add(procs)

  echo result.repr

config:
  sv(server):
    name string[128], "My HookRace Server",
      "Server name"

  player(client, save):
    name string[16], "nameless hookie",
      "Name of the player"
    clan string[16], "",
      "Clan of the player"

  gfx(client, save):
    width Natural, 0,
      "Screen resolution width in pixels"
    height Natural, 0,
      "Screen resolution height in pixels"

  inp(client, save):
    mousesens range[1..100_000], 100,
      "Mouse sensitivity"

var gConfig* = initConfig()

proc execConfig*(config: var Config, line: string) =
  var pos = 0
  var key = ""
  pos += line.parseUntil(key, Whitespace, pos)
  pos += line.skipWhitespace(pos)
  let val = line[pos..^1]

  if not config.execConfig(key, val):
    raise newException(ValueError, "Unknown config key: " & key)

gConfig.execConfig("player.name \"zzzz\"")
