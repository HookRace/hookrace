import rawsockets, os, parseutils, typetraits

when defined(Windows):
  from winlean import TFdSet, FD_ZERO, FD_SET, Timeval, select
else:
  from posix import TFdSet, FD_ZERO, FD_SET, Timeval, select

export Port, recvFrom, send, sendTo, close, select

const
  defaultPort* = 4004
  maxPacketSize* = 1400

type ClientState* = enum disconnected, connecting, connected

proc newUDPServer*(port: Port): SocketHandle =
  result = newRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  result.setSockOptInt(SOL_SOCKET, SO_REUSEADDR, 1)

  var name: Sockaddr_in
  name.sin_family = AF_INET.toInt
  name.sin_port = port.int16.htons
  name.sin_addr.s_addr = INADDR_ANY.htonl

  if result.bindAddr(cast[ptr SockAddr](addr(name)), sizeof(name).SockLen) < 0:
    raiseOSError(osLastError())

  result.setBlocking(false)

proc newUDPClient*: SocketHandle =
  result = newRawSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  result.setBlocking(false)

proc wait*(socket: SocketHandle, time: int): bool =
  var rd: TFdSet
  FD_ZERO(rd)
  FD_SET(socket, rd)

  var tv: Timeval
  var tp: ptr Timeval

  if time >= 0:
    tv.tv_sec = time div 1000000
    tv.tv_usec = time mod 1000000
    tp = addr tv

  let ret = select(socket.cint + 1, addr rd, nil, nil, tp)
  result = ret > 0

type NetAddr* = object
  typ*: Domain
  ip*: array[16, uint8]
  port*: Port

proc `$`*(x: NetAddr): string =
  case x.typ
  of AF_INET: result = $x.ip[0] & '.' & $x.ip[1] & '.' & $x.ip[2] & '.' & $x.ip[3] & ':' & $x.port
  of AF_INET6: discard # TODO
  else: discard

proc toNetAddr*(s: ptr SockAddr): NetAddr =
  result.typ = AF_INET
  result.port = Port htons(cast[ptr SockAddr_in](s).sin_port)
  copyMem(addr result.ip, addr cast[ptr SockAddr_in](s).sin_addr.s_addr, 4)

proc toSockAddrIn*(n: NetAddr): Sockaddr_in =
  result.sin_family = AF_INET.toInt
  result.sin_port = n.port.int16.htons
  echo result.sin_addr.s_addr.type.name
  copyMem(addr result.sin_addr.s_addr, unsafeAddr n.ip, 4)

proc splitHostPort*(s: string): tuple[host: string, port: Port] =
  var i = 0
  if s[0] == '[':
    discard # TODO: ipv6
  else:
    i = s.parseUntil(result.host, ':')
    var port: int
    i = s.parseInt(port, i+1)
    result.port = Port port
    if not i == s.len:
      raise newException(ValueError, "Can't split into host and port: " & s)

proc lookup*(hostname: string): NetAddr =
  let (host, port) = splitHostPort(hostname)
  var addrInfo = getAddrInfo(host, port, AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  result = toNetAddr(addrInfo.ai_addr)
  result.port = port
  dealloc addrInfo

#var n = lookup("localhost:4004")
#echo n
#var s = toSockAddrIn(n)
#echo s
