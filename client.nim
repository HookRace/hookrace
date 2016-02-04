import logger, config, network, msgs, rawsockets, os

var socket = newUDPClient()
var data: array[maxPacketSize, byte]
var sockAddress: Sockaddr_in
var addrLen = sizeof(sockAddress).SockLen

sockAddress.sin_family = AF_INET.toInt
sockAddress.sin_port = 4004.htons
sockAddress.sin_addr.s_addr = 16777343 # localhost

var state = disconnected

proc run =
  while true:
    if state == disconnected:
      let size = data.pack initSyn(clientVersion = CharArray(16, "foo"),
        playerID = 12345, clientToken = 666)

      discard socket.sendto(addr data, size, 0, cast[ptr SockAddr](addr sockAddress), addrLen)
      state = connecting

    if socket.wait(1_000_000):
      let bytes = socket.recvfrom(addr data, maxPacketSize, 0, cast[ptr SockAddr](addr sockAddress), addr addrLen)

      if bytes <= 0:
        break

      echo "Received packet from ", sockAddress

      caseMsg data:
      of synack:
        if state != connecting: continue
        echo msg
        let size = data.pack initAck(serverToken = msg.serverToken)
        discard socket.sendto(addr data, size, 0, cast[ptr SockAddr](addr sockAddress), addrLen)
      else:
        echo "Unknown packet received"

#run()
#close socket

proc main =
  addLogger stdout
  addLogger open("client.log", fmWrite)

  echo gConfig.inp.mousesens
  gConfig.inp.mousesens = 150
  echo gConfig.player.name
  gConfig.player.name = "foobaraskdjalsdjkasjdsa"
  echo gConfig.player.name

main()
