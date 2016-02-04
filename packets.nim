type
  UncheckedArray {.unchecked.}[T] = array[0..0, T]

  Channel* {.pure.} = enum game, chat, download

  PacketFlag* {.pure.} = enum connless, compression

  Packet* = object
    flags*: set[PacketFlag]
    chunks*: seq[Chunk]

  Chunk* = object
    channel*: Channel
    sequenceNr*: int
    dataLen*: int
    data*: ptr UncheckedArray[char]

# A chunk is a packed Msg
# A packet consists of multiple chunks
