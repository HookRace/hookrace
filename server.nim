import network, msgs, rawsockets

var socket = newUDPServer(Port 4004)
var data: array[maxPacketSize, byte]
var sockAddress: Sockaddr_in
var addrLen = sizeof(sockAddress).SockLen

type Client = object
  sockAddress: Sockaddr_in
  state: ClientState

var clients = newSeq[Client]()

proc run =
  while true:
    if socket.wait(1_000_000):
      let bytes = socket.recvfrom(addr data, maxPacketSize, 0, cast[ptr SockAddr](addr sockAddress), addr addrLen)

      if bytes <= 0:
        break

      echo "received packet from ", sockAddress

      caseMsg data:
      of syn:
        echo "new client"
        echo msg

        let size = data.pack initSynAck(playerID = msg.playerID,
          ingameID = 64, clientToken = msg.clientToken, serverToken = 9999)

        discard socket.sendto(addr data, size, 0, cast[ptr SockAddr](addr sockAddress), addrLen)
        clients.add Client(sockAddress: sockAddress, state: connecting)
      of ack:
        echo msg
        for client in clients.mitems:
          if sockAddress == client.sockAddress:
            echo "client finished connection process"
            client.state = connected
            break
      else: echo "Unknown packet received"

run()
close socket
