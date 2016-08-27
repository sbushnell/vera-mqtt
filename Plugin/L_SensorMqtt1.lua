module("L_SensorMqtt1", package.seeall)

-- Service ID strings used by this device.
SERVICE_ID = "urn:upnp-sensor-mqtt-se:serviceId:SensorMqtt1"
SENSOR_MQTT_LOG_NAME = "SensorMqtt plugin: "

local DEBUG = true
local DEVICE_ID
local HANDLERS = {}
local ITEMS_NEEDED = 0
local WATCH = {}

local mqttServerIp = nil
local mqttServerPort = 0
local mqttServerConnected = "0"
local mqttWatches = "{}"
local mqttAlias = "{}"
local mqttLastMessage = ""

local watches = {}
local alias = {}

local index=1
local configMonitors = {}

mqttClient = nil
package.loaded.MQTT = nil
MQTT = require("mqtt_library")
--_G["MQTT"] = MQTT

json = nil

-- ------------------------------------------------------------------
-- Callback Watch Configured Sensor Variables
-- ------------------------------------------------------------------
function watchSensorVariable(lul_device, lul_service, lul_variable, lul_value_old, lul_value_new)
	if (DEBUG) then
		luup.log(SENSOR_MQTT_LOG_NAME .. "Device: " .. lul_device .. " Variable: " .. lul_variable .. " Value " .. tostring(lul_value_old) .. " => " .. tostring(lul_value_new), 1)
	end

	local variableUpdate = {}
	variableUpdate.Time = os.time()
	variableUpdate.DeviceId = lul_device
        variableUpdate.DeviceName = luup.devices[lul_device].description
        variableUpdate.DeviceType = luup.devices[lul_device].device_type
        variableUpdate.RoomId = luup.devices[lul_device].room_num
        variableUpdate.RoomName = luup.rooms[variableUpdate.RoomId] or "No Room"
	variableUpdate[watches[lul_service][lul_variable]] = lul_value_new
	variableUpdate["Old" .. watches[lul_service][lul_variable]] = lul_value_old

	local payload = json:encode(variableUpdate)
	local topic = ""

	if (alias[tostring(lul_device)]) then
		topic = mqttVeraIdentifier.."/Events/"..alias[tostring(lul_device)]
	else
		topic = mqttVeraIdentifier.."/Events/"..lul_device
	end

	publishMessage(topic, payload)

	local lastMessage = {}
	lastMessage.Topic = topic
	lastMessage.Payload = variableUpdate

	luup.variable_set(SERVICE_ID, "mqttLastMessage", json:encode(lastMessage), DEVICE_ID)

end

-- ------------------------------------------------------------------
-- 
-- ------------------------------------------------------------------
local function debug(s)
	if (DEBUG) then
		luup.log(SENSOR_MQTT_LOG_NAME .. " " .. s, 1)
	end
end

-- ------------------------------------------------------------------
-- 
-- ------------------------------------------------------------------
local function log(text, level)
	luup.log(SENSOR_MQTT_LOG_NAME .. " " .. text, (level or 50))
end

-- ------------------------------------------------------------------
-- 
-- ------------------------------------------------------------------

function registerWatches()

	watches = json:decode(mqttWatches)
	alias = json:decode(mqttAlias)

	debug("************************************************ MQTT Settings ************************************************")
	debug(mqttWatches)

	for service,variables in pairs(watches) do
		for varName, label in pairs(variables) do
			debug("Watching ".. service .." on variable " .. varName .. " with label " .. label )
			luup.variable_watch("watchSensorVariable", tostring(service), tostring(varName), nil)
		end
	end

end

-- ------------------------------------------------------------------
-- Connect to MQTT
-- ------------------------------------------------------------------
function connectToMqtt()
	luup.log(SENSOR_MQTT_LOG_NAME .. "Connect to MQTT", 1)
	-- TODO: Add checks for IP and Port	
	mqttServerPort = tonumber(mqttServerPort)
	mqttClient = MQTT.client.create(mqttServerIp, mqttServerPort)
	mqttClient.KEEP_ALIVE_TIME = 3600
--	local result = mqttClient:connect("VeraController")
	local result = mqttClient:connect(mqttVeraIdentifier, "Will_Topic/", 2, 1, "testament_msg")
	if (result ~=nil and result == "client:connect(): Couldn't open MQTT broker connection") then
		luup.log(result)
		setConnectionStatus(false)
		luup.call_delay('connectToMqtt', 10, "")
	else
		setConnectionStatus(true)
	end
end

-- ------------------------------------------------------------------
-- 
-- ------------------------------------------------------------------
function setConnectionStatus(connected)
	if(connected) then
		mqttServerConnected = "1"
		luup.log(SENSOR_MQTT_LOG_NAME .. "MQTT Status: Connected", 1)
		luup.variable_set(SERVICE_ID, "mqttServerStatus", "Connected", DEVICE_ID)
		luup.variable_set(SERVICE_ID, "mqttServerConnected", mqttServerConnected, DEVICE_ID)
	else
		mqttServerConnected = "0"
		luup.log(SENSOR_MQTT_LOG_NAME .. "MQTT Status: Disconnected", 1)
		luup.variable_set(SERVICE_ID, "mqttServerStatus", "Disconnected", DEVICE_ID)
		luup.variable_set(SERVICE_ID, "mqttServerConnected", mqttServerConnected, DEVICE_ID)
	end
end

-- ------------------------------------------------------------------
-- Publish a message
-- ------------------------------------------------------------------
function publishMessage(topic, payload)
	local result = mqttClient:publish(topic, "" .. payload)
	if (result ~= nil) then
		connectToMqtt()
		-- Retry to publish
		mqttClient:publish(topic, "" .. payload)
	end
	if (DEBUG) then
		luup.log(SENSOR_MQTT_LOG_NAME .. "Publish MQTT message on topic: "..topic.." with value:"..payload , 1)
	end
end
-- ------------------------------------------------------------------
--
-- ------------------------------------------------------------------
function publishPing()
	if (DEBUG) then
		luup.log(SENSOR_MQTT_LOG_NAME .. "Publish MQTT ping message", 1)
	end
	local result = mqttClient:handler()
	if (result ~= nil) then
		connectToMqtt()
		-- Retry to ping again
		mqttClient:handler()
	end
	luup.call_delay('publishPing', 30, "", false)
end

-- ------------------------------------------------------------------
-- Get the name of device
-- ------------------------------------------------------------------
function getDeviceName(deviceId)
	local deviceName = luup.attr_get('name', deviceId)
	return deviceName
end

function getXMLTime()
	local a,b = math.modf(os.clock())
	if b==0 then 
		b='000' 
	else 
		b=tostring(b):sub(3,5) 
	end
	local tf = os.date('%Y-%m-%dT%H:%M:%S.'..b, os.time())
	return tf
end

function startup(lul_device)
	DEVICE_ID = lul_device
	
	_G.watchSensorVariable = watchSensorVariable
	_G.publishPing = publishPing
	_G.connectToMqtt = connectToMqtt
	
	log("Initialising SensorMqtt", 1)

	package.loaded.JSON = nil
	json = require("JSON")
	--_G["JSON"] = JSON

	-- "Generic I/O" device http://wiki.micasaverde.com/index.php/Luup_Device_Categories 
	luup.attr_set("category_num", 3, DEVICE_ID)

	--Reading variables
	mqttServerIp = luup.variable_get(SERVICE_ID, "mqttServerIp", DEVICE_ID)
	if(mqttServerIp == nil) then
		mqttServerIp = "0.0.0.0"
		luup.variable_set(SERVICE_ID, "mqttServerIp", mqttServerIp, DEVICE_ID)
	end
	
	mqttServerPort = luup.variable_get(SERVICE_ID, "mqttServerPort", DEVICE_ID)
	if(mqttServerPort == nil) then
		mqttServerPort = "0"
		luup.variable_set(SERVICE_ID, "mqttServerPort", mqttServerPort, DEVICE_ID)
	end

	mqttWatches = luup.variable_get(SERVICE_ID, "mqttWatches", DEVICE_ID)
	if(mqttWatches == nil) then
		mqttWatches = "{}"
		luup.variable_set(SERVICE_ID, "mqttWatches", mqttWatches, DEVICE_ID)
	end

	mqttAlias = luup.variable_get(SERVICE_ID, "mqttAlias", DEVICE_ID)
	if(mqttAlias == nil) then
		mqttAlias = "{}"
		luup.variable_set(SERVICE_ID, "mqttAlias", mqttAlias, DEVICE_ID)
	end

	mqttServerConnected = luup.variable_get(SERVICE_ID, "mqttServerConnected", DEVICE_ID)
	if(mqttServerConnected == nil) then
		mqttServerConnected = "0"
		luup.variable_set(SERVICE_ID, "mqttServerConnected", mqttServerConnected, DEVICE_ID)
	end

	mqttLastMessage = luup.variable_get(SERVICE_ID, "mqttLastMessage", DEVICE_ID)
	if(mqttLastMessage == nil) then
		mqttLastMessage = ""
		luup.variable_set(SERVICE_ID, "mqttLastMessage", mqttLastMessage, DEVICE_ID)
	end
	
	mqttVeraIdentifier = luup.variable_get(SERVICE_ID, "mqttVeraIdentifier", DEVICE_ID)
	if(mqttVeraIdentifier == nil) then
		mqttVeraIdentifier = "Vera"
		luup.variable_set(SERVICE_ID, "mqttVeraIdentifier", mqttVeraIdentifier, DEVICE_ID)
	end

	if (mqttServerIp ~= "0.0.0.0") then
		connectToMqtt()
		luup.call_delay('publishPing', 15, "", false)
	end
	
	if (mqttServerConnected == "1") then
		registerWatches()
	end
end
