# ACARS + CPDLC For FlightGear Aircraft

## Introduction

This is an ACARS and CPDLC system, intended for FlightGear aircraft developers
to include in aircraft models. It provides the entire logic necessary for a
working ACARS + CPDLC system, but there is no user interface - you will have to
add this yourself, typically by interfacing this system with your aircraft's
FMS.

If you are *not* developing aircraft models for FlightGear, then this package
will be useless to you - this is *not* an addon, it is not a patch that will
magically add ACARS and CPDLC to any aircraft.

## Installation / Adding To An Aircraft

1. Copy all the Nasal files in `./Nasal` into your aircraft directory, under
   `./Nasal`.
2. Open the `aircraft-common-dist.xml` file, and add its contents to your
   aircraft `-set.xml`.
3. Write code to interface with the ACARS and CPDLC systems. See below.
4. Document things.

## Transport Backends

ACARS and CPDLC cover a range of services, and to implement these, this
simulation supports multiple data sources for each of them.

### CPDLC Backends

- `HOPPIE`: uses the Hoppie ACARS plugin, if installed, available from
  https://github.com/tdammers/fg-hoppie-acars. The minimum supported version is
  0.2.0. This will connect to [Hoppie's ACARS
  system](http://www.hoppie.nl/acars/), the ACARS system used by VATSIM and
  other online environments.
- `FGMP`: uses the IRC CPDLC implementation built into FG Core. Note that this
  backend does not provide MIN/MRN, so replies are linked to requests based on
  a very simple heuristic; it is recommended to avoid having more than one
  dialog open at any time, as the system may otherwise match replies to the
  wrong requests.
- `NONE`: disable CPDLC functionality.

### TELEX Backends

- `HOPPIE`: use the Hoppie ACARS plugin for TELEX and PDC messages.
- `NONE`: disable TELEX and PDC.

### Weather Backends (METAR, TAF, SHORTTAF)

- `HOPPIE`: use the Hoppie ACARS plugin to fetch VATSIM weather.
- `NOAA`: fetch weather information over HTTP from noaa.gov (this is the same
  source from which FG itself pulls live weather)
- `NONE`: disable weather information
- `AUTO`: use the `HOPPIE` backend if available, `NOAA` otherwise.

### ATIS Weather Backends

- `HOPPIE`: use the Hoppie ACARS plugin to fetch ATIS for an active airport on
  VATSIM (`vatatis` message type). This will only work if a controller is
  providing ATIS services on VATSIM for the selected airport.
- `DATIS`: use the FAA's D-ATIS service to fetch ATIS for one of the supported
  US airports. D-ATIS provides no information for non-US airports. Note that
  these are real-world ATIS information, so if you want to fly on VATSIM, use
  with care (and especially note that the ATIS letters will not match those on
  VATSIM).
- `NONE`: disable ATIS information
- `AUTO`: use the `HOPPIE` backend if available, `DATIS` otherwise.

## API Documentation

### Property Interface

#### The `/acars` subtree

##### `/acars/telex/sent`, `/acars/telex/received`

*readonly*

History of sent and received messages. Each message is stored under a
property node named by the unique message ID (`"m" ~ serial`, see below); its
children are:

- `type` - one of `TELEX`, `ATIS`, `METAR`, `TAF`, `SHORTTAF`.
- `serial` - the raw message serial.
- `from` - the sender of the message (received messages only)
- `to` - the recipient of the message (sent messages only)
- `text` - message text
- `timestamp` - sent/received timestamp in `YYYYMMDDTHHMMSS` format
- `status` - textual status of the message

##### `/acars/telex/unread`

*readonly*

Total number of unread TELEX messages.

##### `/acars/telex/newest-unread`

*readonly*

Serial (not message ID!) of the newest unread TELEX message.

##### `/acars/pdc-dialog`

Fields used for sending PDC messages (Pre-Departure Clearance):

- `facility` - the code of the recipient (usually the 4-letter ICAO code of the
  airport you are departing from)
- `origin` - departure airport (pre-filled to departure airport of current
  flightplan, or current location if no flightplan was loaded)
- `destination` - arrival airport (pre-filled to destination airport of current
  flightplan, if any)
- `fltID` - callsign (pre-filled from `sim/multiplay/callsign`)
- `acType` - aircraft type
- `atis` - ATIS letter; optional
- `gate` - current parking position; optional


##### `/acars/telex-dialog`

Fields used for sending TELEX messages:

- `to` - the code of the recipient. This can be an aircraft callsign, a ground
  station code, a 3-letter ICAO airline code, etc.
- `text` - plain text to be sent. Realistically, this should only contain
  characters specified in the TELEX standard, though no validation is performed
  to this extent.

##### `/acars/inforeq-dialog`

Fields used for sending information requests (ATIS, METAR, TAF, SHORTTAF):

- `station` - the code of the station to query (usually the 4-letter ICAO
  airport code)

##### `/acars/availability/telex`, `/acars/availability/atis`, `/acars/availability/weather`

*readonly*

Boolean fields that indicate whether the corresponding ACARS service is
currently available. You may want to use these to turn menu items on the CDU on
or off according to their availability.

#### The `/cpdlc` subtree

##### `datalink-status`

*readonly*

Status of the datalink connection. 1 = datalink up, 0 = datalink down or not
available.

##### `logon-status`

*readonly*

Logon status. Constants are defined for these in Nasal:

- `LOGON_NO_LINK` = -4 (Transport is not available, cannot logon)
- `LOGON_NO_LOGON_STATION` = -5 (No logon station selected, can't logon)
- `LOGON_FAILED` = -2 (Last logon attempt did not succeed)
- `LOGON_NOT_CONNECTED` = -1 (Currently disconnected, connecting possible)
- `LOGON_OK` = 0 (Logged on successfully)
- `LOGON_ACCEPTED` = 2 (Logon accepted, wait for CURRENT DATA AUTHORITY message)
- `LOGON_SENT` = 1 (Logon request sent, no reply received)

##### `connected`

*readonly*

Boolean, for convenience: reflects active datalink and valid logon, i.e.
`logon-status` == `LOGON_OK`. You can use this to show or hide CPDLC
functionality on the CDU.

##### `current-station`

*readonly*

The current data authority, i.e., the station that you are logged on to.

##### `logon-station`

The station to log on to. You would normally set this before requesting a
logon; once the logon succeeds, the logon-station becomes the current-station.

##### `next-station`

*readonly*

The station that the CPDLC is currently attempting to log on to during a
handover. Once the logon succeeds, the next-station becomes the
current-station. Handovers are always triggered by ATC.

##### `history`

*readonly*

List of message IDs, both uplinks and downlinks, ordered by timestamp. Message
IDs reference messages in the `messages` subtree.

##### `messages`

*readonly*

The actual messages as they have been sent / received.

##### `unread`

*readonly*

Number of unread uplinks.

##### `newest-unread`

*readonly*

Message ID of the newest unread uplink.

##### `incoming`

*readonly*

Signal property; this will flip to 1 for 100 milliseconds when a new uplink
arrives. Useful for triggering alert sounds.

##### `driver`

*readonly*

String representation of the currently selected CPDLC driver.

### Nasal APIs

#### The `cpdlc` Namespace

##### The `cpdlc.system` Object

###### Fields

- `driver` - the currently selected driver object, or `nil` if no driver is
  currently active. You should not normally need to use this directly.

###### Methods

- `setDriver(driver)` - select the `driver` (see above).
- `getDriver()` - return the currently selected driver name
- `listDrivers()` - return a vector of available driver names
- `updateDatalinkStatus()` - test the datalink, and set the
  `/cpdlc/datalink-status` property accordingly.
- `connect(logonStation=nil)` - send a logon request to the specified
  `logonStation`, or the station in `/cpdlc/logon-station` if unspecified.
- `disconnect()` - send a logoff message.
- `send(msg)` - send a CPDLC message (see below)
- `markMessageRead(messageID)` - marks an uplink message as read
- `clearHistory` - empty the entire message history

##### The `cpdlc.Message` class

###### Fields

- `timestamp` (string): time sent/received, UTC, in HHMM format
- `min` (int): Message Identification Number. Generated by the CPDLC system for
  downlinks, parsed from uplink messages.
- `mrn` (int): Message Reference Number. Points to the MIN of the message that
  this message is a reply to. `nil` if message is not a reply.
- `parts` (vector): individual message parts. Each part has the following
  fields:
  - `type` (string): one of the CPDLC message codes documented in ICAO 4444
    (see `message-types.nas` for a list of supported codes and suggested
    formattings)
    `args` (vector): list of string arguments. The required arguments depend on
    the message type.
- `to` (string): message recipient
- `from` (string): message sender
- `dir` (string): 'up' (uplink, ATC to aircraft), 'down' (downlink, aircraft to
  ATC), or 'pseudo' (system-generated events that are not actual CPDLC
  messages).
- `valid` (bool): whether the message is valid (all required arguments
  present).
- `status` (string): one of:
  - 'NEW': this is an unread message that may or may not require a reply.
  - 'OLD': this is a message that has been read and does not require a reply.
  - 'SENDING': this message is currently being sent.
  - 'RESPONSE RECVD': this is a downlink message for which a response has been
    received.
  - 'OPEN': this is a message that requires a reply, but hasn't been replied
    to.
  - 'RESPONDED': this is an uplink message that requires a non-specific or
    yes/no reply (RA = Y or AN), and a reply has been sent.
  - 'REJECTED': this is an uplink message that requires a specific reply (RA =
    WU or R), and a negative reply ("UNABLE") has been sent.
  - 'ACCEPTED': this is an uplink message that requires a specific reply (RA =
    WU or RA = R), and a positive reply ("ROGER" or "WILCO") has been sent.

###### Methods

- `toNode(node=nil)` (Node): convert message to a property node. If no property
  node is given, create and return a new one, otherwise, overwrite argument.
- `fromNode(node)` (Message): construct a new message object from a property
  node.
- `getMessageType(partIndex=0)` (hash): Look up the message type for the
  specified `partIndex`. (See `Nasal/cpdlc/message-types.nas` for message type
  definitions).
- `getRA()` (string): find the effective RA for the message.
- `getMID()` (string): get the message ID for this message.

Note that MessageID is not the same as MIN: the MIN is just a number, while the
MessageID also contains the *direction* of the message (uplink, downlink, or
pseudo). MessageID's are used for referencing messages internally within the
local system; MIN's and MRN's are used to cross-reference messages on the
CPDPLC network.

##### The `acars.system` object

###### Methods


- `isAvailable()` (bool): whether the currently selected TELEX backend is up.
- `isAtisAvailable()` (bool): whether the currently selected ATIS backend is
  up.
- `isWeatherAvailable()` (bool): whether the currently selected weather backend
  (METAR, TAF, SHORTTAF) is up.
- `updateAvailabilities()` (void): check current backend availabilities and
  update properties.
- `receive(msg=nil)` (void): process an incoming message. This method is used
  internally to automatically process messages from the backend, so you don't
  normally have to call it yourself, but if you wish to inject "fake" messages
  into the ACARS system, you can use this method.
- `sendTelex(to=nil, txt=nil)` (bool): send a TELEX message to recipient `to`,
  with text content `txt`.
  If not given `to` and/or `txt` are read from the corresponding properties in
  `/acars/telex-dialog/`.
- `sendInfoRequest(what, station=nil)` (bool): send an information request.
  `what` determines the type of request: `atis`, `metar`, `taf`, or `shorttaf`.
- `injectSystemMessage(from, packet)` (void): create and inject a "system"
  message.
- `clearTelexDialog()` (void): clear out the `/acars/telex-dialog` fields.
- `completePDC(pdc)` (PDC): given a PDC hash, complete the missing fields from
  the corresponding properties in `/acars/pdc-dialog`.
- `pdcValid(pdc)` (bool): check whether a PDC hash is valid (all required
  fields given).
- `validatePDC(pdc=nil)`: sets the `/acars/pdc-dialog/valid` property based on
  the validity of the provided PDC, and/or properties in `/acars/pdc-dialog`.
- `sendPDC(pdc=nil)` (bool): sends a PDC (Pre-Departure Clearance) request by
  TELEX. Missing fields are read from `/acars/pdc-dialog`. If no PDC object is
  given, *all* fields are read from `/acars/pdc-dialog`.
- `clearHistory()`: deletes everything in the TELEX history.
