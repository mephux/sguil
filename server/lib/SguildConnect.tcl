# $Id: SguildConnect.tcl,v 1.12 2005/10/14 21:21:04 bamm Exp $

#
# ClientConnect: Sets up comms for client/server
#
proc ClientConnect { socketID IPAddr port } {
  global socketInfo VERSION
  global OPENSSL KEY PEM

  LogMessage "Client Connect: $IPAddr $port $socketID"
  
  # Check the client access list
  if { ![ValidateClientAccess $IPAddr] } {
    SendSocket $socketID "Connection Refused."
    catch {close $socketID} tmpError
    LogMessage "Invalid access attempt from $IPAddr"
    return
  }
  LogMessage "Valid client access: $IPAddr"
  set socketInfo($socketID) "$IPAddr $port"
  fconfigure $socketID -buffering line
  # Do version checks
  if [catch {SendSocket $socketID "$VERSION"} sendError ] {
    return
  }
  if [catch {gets $socketID} clientVersion] {
    LogMessage "ERROR: $clientVersion"
    return
  }
  if { $clientVersion != $VERSION } {
    catch {close $socketID} tmpError
    LogMessage "ERROR: Client connect denied - mismatched versions"
    LogMessage "CLIENT VERSION: $clientVersion"
    LogMessage "SERVER VERSION: $VERSION"
    ClientExitClose $socketID
    return
  }
  if {$OPENSSL} {
    tls::import $socketID -server true -keyfile $KEY -certfile $PEM
    fileevent $socketID readable [list HandShake $socketID ClientCmdRcvd]
  } else {
    fileevent $socketID readable [list ClientCmdRcvd $socketID]
  }
}

proc SensorConnect { socketID IPAddr port } {

  LogMessage "Connect from $IPAddr:$port $socketID"
  # Check the client access list
  if { ![ValidateSensorAccess $IPAddr] } {
    SendSocket $socketID "Connection Refused."
    catch {close $socketID} tmpError
    LogMessage "Invalid access attempt from $IPAddr"
    return
  }
  LogMessage "ALLOWED"
  fconfigure $socketID -buffering line -blocking 0
  fileevent $socketID readable [list SensorCmdRcvd $socketID]
}

proc SensorAgentInit { socketID sensorName barnyardStatus} {

    global connectedAgents agentSocketArray agentSensorNameArray
    global sensorStatusArray

    lappend connectedAgents $sensorName
    set agentSocketArray($sensorName) $socketID
    set agentSensorNameArray($socketID) $sensorName
    set sensorID [GetSensorID $sensorName]

    if { $sensorID == "" } {

        LogMessage "New sensor. Adding sensor $sensorName to the DB."
        # We have a new sensor
        set sensorName $agentSensorNameArray($socketID)

        set tmpQuery "INSERT INTO sensor (hostname) VALUES ('$sensorName')"

        if [catch {SafeMysqlExec $tmpQuery} tmpError] {
            # Insert failed
            ErrorMessage "ERROR from mysqld: $tmpError :\nQuery => $tmpQuery"
            ErrorMessage "ERROR: Unable to add new sensors."
            return
        }

        set sensorID [GetSensorID $sensorName]

    }

    SendSystemInfoMsg $sensorName "Agent connected."
    SendSensorAgent $socketID [list SensorID $sensorID]

    if { [info exists sensorStatusArray($sensorName)] } {

        set sensorStatusArray($sensorName) [lreplace $sensorStatusArray($sensorName) 2 3 1 $barnyardStatus]

    } else { 

        # TEMPORARY
        set sensorStatusArray($sensorName) [list $sensorID Unknown 1 $barnyardStatus None]

    }


    SendAllSensorStatusInfo

}

proc CleanUpDisconnectedAgent { socketID } {

    global connectedAgents agentSocketArray agentSensorNameArray
    global sensorStatusArray
 
    if [info exists agentSensorNameArray($socketID)] { 

        set connectedAgents [ldelete $connectedAgents $agentSensorNameArray($socketID)]
        set sensorName $agentSensorNameArray($socketID)

        if [info exists agentSocketArray($sensorName)] {

            unset agentSocketArray($sensorName)

        }

        if [info exists sensorStatusArray($sensorName)] {

            set sensorStatusArray($sensorName) [lreplace $sensorStatusArray($sensorName) 2 3 0 0]
 
        }

        unset agentSensorNameArray($socketID)


    } 

    SendAllSensorStatusInfo

}

proc HandShake { socketID cmd } {
  if {[eof $socketID]} {
    close $socketID
    ClientExitClose socketID
  } elseif { [catch {tls::handshake $socketID} results] } {
    LogMessage "ERROR: $results"
    close $socketID
    ClientExitClose socketID
  } elseif {$results == 1} {
    InfoMessage "Handshake complete for $socketID"
    fileevent $socketID readable [list $cmd $socketID]
  }
}



