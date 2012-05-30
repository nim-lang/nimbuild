import htmlgen, times, irc, marshal, streams, strutils, os

type
  TLogger = object # Items get erased when new day starts.
    startTime: TTimeInfo
    items: seq[tuple[time: TTime, msg: TIRCEvent]]
  PLogger* = ref TLogger

# TODO: Current implementation writes whole files, every message. Not really
# sure how else to approach this.

const logFilepath = "/home/nimrod/irclogs/"

proc loadLogger(f: string): PLogger =
  load(newFilestream(f, fmRead), result)

proc newLogger*(): PLogger =
  new(result)
  result.startTime = getTime().getGMTime()
  result.items = @[]
  let log = logFilepath / result.startTime.format("dd'-'MM'-'yyyy'.json'")
  if existsFile(log):
    result = loadLogger(log)

proc renderItems(logger: PLogger): string =
  result = ""
  for i in logger.items:
    var c = ""
    case i.msg.cmd
    of MJoin:
      c = "join"
    of MPart:
      c = "part"
    of MNick:
      c = "nick"
    of MQuit:
      c = "quit"
    else:
      nil
    var message = i.msg.params[i.msg.params.len-1]
    if message.startswith("\x01ACTION "):
      c = "action"
      message = message[8 .. -2]
    
    if c == "":
      result.add(tr(td(i.time.getGMTime().format("HH':'mm':'ss")),
                    td(class="nick", i.msg.nick),
                    td(class="msg", message)))
    else:
      case c
      of "join":
        message = i.msg.nick & " joined " & i.msg.origin
      of "part":
        message = i.msg.nick & " left " & i.msg.origin & " (" & message & ")"
      of "nick":
        message = i.msg.nick & " is now known as " & message
      of "quit":
        message = i.msg.nick & " quit (" & message & ")"
      of "action":
        message = i.msg.nick & " " & message
      else: assert(false)
      result.add(tr(class=c,
                    td(i.time.getGMTime().format("HH':'mm':'ss")),
                    td(class="nick", "*"),
                    td(class="msg", message)))

proc renderHtml(logger: PLogger, index = false): string =
  let previousDay = logger.startTime - (newInterval(days=1))
  let nextDay     = logger.startTime + (newInterval(days=1))
  let nextUrl     = if index: "" else: nextDay.format("dd'-'MM'-'yyyy'.html'")
  result = 
    html(
      head(title("#nimrod logs for " & logger.startTime.format("dd'-'MM'-'yyyy")),
           link(rel="stylesheet", href="static/css/boilerplate.css"),
           link(rel="stylesheet", href="static/css/log.css")
      ),
      body(
        htmlgen.`div`(id="controls",
            a(href=previousDay.format("dd'-'MM'-'yyyy'.html'"), "<<"),
            span(logger.startTime.format("dd'-'MM'-'yyyy")),
            (if nextUrl == "": span(">>") else: a(href=nextUrl, ">>"))
        ),
        hr(),
        table(
          renderItems(logger)
        )
      )
    )

proc save(logger: PLogger, filename: string, index = false) =
  writeFile(filename, renderHtml(logger, index))
  if not index:
    writeFile(filename.changeFileExt("json"), $$logger)

proc log*(logger: PLogger, msg: TIRCEvent) =
  if getTime().getGMTime().yearday != logger.startTime.yearday:
    # Time to cycle to next day.
    # Reset logger.
    logger.startTime = getTime().getGMTime()
    logger.items = @[]
    
  case msg.cmd
  of MPrivMsg, MJoin, MPart, MNick, MQuit: # TODO: MTopic? MKick?
    logger.items.add((getTime(), msg))
    logger.save(logFilepath / "index.html", true)
    # This is saved so that it can be reloaded later, if NimBot crashes for example.
    logger.save(logFilepath / logger.startTime.format("dd'-'MM'-'yyyy'.html'"))
  else: nil


  