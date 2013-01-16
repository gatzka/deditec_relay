local bit = require "bit"
local usb = require "libusb1"
local socket = require "socket"

local error = error
local ipairs = ipairs
local print = print
local string = string
local tostring = tostring
local table = table

module("deditec_relays")

local function sleep(sec)
	socket.select(nil, nil, sec)
end

local function send_command(handle, job_id, command, be, bytes)
	local header = string.char(0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0xff)
	local cmd = header..string.char(job_id)..command..
		string.char(0x00, 0x00, 0x00, 0x00)..string.char(be)
	if bytes then
		cmd = cmd..bytes
	end
	local length, timedout = usb.bulk_transfer(handle, 0x02, cmd, 1000)
	if timedout then
		error("Timeout while sending command!")
	end
end


local function ftdi_read(handle, count)
	local received = 0
	local cnt = count - received + 2
	local tries = 0
	local buffer = ""
	while tries ~= 10 do
		local ret, timedout = usb.bulk_transfer(handle, 0x81, cnt, 1000)
		if timedout then
			print("timedout!");
			return nil
		end
		buffer = buffer..ret:sub(3)
		if buffer:len() >= count then
			return buffer
		end
		cnt = cnt - ret:len() + 2
		tries = tries + 1
		sleep(0.01)
	end
	print("to much tries!")
end

local GET_8_BYTES = 0x34
local SEND_8_BYTES = 0x23

function deditec_close_all(relay)
	relay.job_id = relay.job_id + 1
	send_command(relay.handle, relay.job_id, string.char(SEND_8_BYTES), 1,
		string.char(0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
	local ret = ftdi_read(relay.handle, 3)
	if ret:byte(1) ~= 0x1a or ret:byte(2) ~= relay.job_id or ret:byte(ret:len()) ~= 0x4f then
		print("Ack for close_all not correct!")
	end
end

function deditec_open_all(relay)
	relay.job_id = relay.job_id + 1
	send_command(relay.handle, relay.job_id, string.char(SEND_8_BYTES), 1,
		string.char(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
	local ret = ftdi_read(relay.handle, 3)
	if ret:byte(1) ~= 0x1a or ret:byte(2) ~= relay.job_id or ret:byte(ret:len()) ~= 0x4f then
		print("Ack for open_all not correct!")
	end
end

function deditec_get_switches(handle, job_id)
	send_command(handle, job_id, string.char(GET_8_BYTES), 15, nil)
	local ret = ftdi_read(handle, 11)
	if ret:byte(1) ~= 0x1a or ret:byte(2) ~= job_id or ret:byte(ret:len()) ~= 0x4f then
		print("Ack for get_switches not correct!")
		return nil
	end
	return ret:byte(3)
end

function deditec_close_switch(relay, number)
	local bit_pos = bit.lshift(1, number - 1) 
	relay.job_id = relay.job_id + 1
	local actual = deditec_get_switches(relay.handle, relay.job_id)
	local new = bit.bor(actual, bit_pos) 
	relay.job_id = relay.job_id + 1
	send_command(relay.handle, relay.job_id, string.char(SEND_8_BYTES), 1,
		string.char(new, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
	local ret = ftdi_read(relay.handle, 3)
	if ret:byte(1) ~= 0x1a or ret:byte(2) ~= relay.job_id or ret:byte(ret:len()) ~= 0x4f then
		print("Ack for close_switch not correct!")
	end
	relay.job_id = relay.job_id + 1
	actual = deditec_get_switches(relay.handle, relay.job_id)
end

function deditec_open_switch(relay, number)
	local bit_pos = bit.lshift(1, number - 1) 
	relay.job_id = relay.job_id + 1
	local actual = deditec_get_switches(relay.handle, relay.job_id)
	local new = bit.band(actual, bit.bnot(bit_pos)) 
	relay.job_id = relay.job_id + 1
	send_command(relay.handle, relay.job_id, string.char(SEND_8_BYTES), 1,
		string.char(new, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
	local ret = ftdi_read(relay.handle, 3)
	if ret:byte(1) ~= 0x1a or ret:byte(2) ~= relay.job_id or ret:byte(ret:len()) ~= 0x4f then
		print("Ack for open_switch not correct!")
	end
	relay.job_id = relay.job_id + 1
	actual = deditec_get_switches(relay.handle, relay.job_id)
end

function get_relays()
	local relay_table = {}

	local context = usb.init()
	local usb_devices = usb.get_device_list(context)
	for i,usb_device in ipairs(usb_devices) do
		local device_desc = usb.get_device_descriptor(usb_device)
		if device_desc.idVendor == 0x0403 and device_desc.idProduct == 0x6001 then
			if device_desc.iSerialNumber > 0 then
				local handle, err = usb.open(usb_device)
				if handle ~= nil then
					local serial_number = usb.get_string_descriptor_utf8(handle, device_desc.iSerialNumber)
					if serial_number == "DT000014" then
						local relay = {}
						relay.usb_device = usb_device
						relay.job_id = 0x7

						relay.attach = function(self)
							local handle = usb.open(self.usb_device)
							usb.reset_device(handle)
							if usb.kernel_driver_active(handle, 0) then
								usb.detach_kernel_driver(handle, 0)
							end
							if usb.claim_interface(handle, 0) == nil then
								error("Could not claim interface!")
							end

							local SIO_RESET_REQUEST = 0
							local SIO_RESET_SIO = 0
							local SIO_SET_BAUDRATE_REQUEST = 3
							local SIO_SET_LATENCY_TIMER_REQUEST = 9
							local SIO_BAUDRATE_9600 = 0x4138
							local SIO_BAUDRATE_150060 = 0x0014
						
							local request_type = usb.LIBUSB_RECIPIENT_DEVICE + usb.LIBUSB_ENDPOINT_OUT +
								usb.LIBUSB_REQUEST_TYPE_VENDOR
							local length, timedout = usb.control_transfer(handle, request_type, SIO_RESET_REQUEST,
								SIO_RESET_SIO, 0, "", 100)
							if timedout then
								error("Could not reset relais card!")
							end
							length, timedout = usb.control_transfer(handle, request_type, SIO_SET_BAUDRATE_REQUEST,
								SIO_BAUDRATE_9600, 0, "", 100)
							if timedout then
								error("Could not set baudrate!")
							end
							length, timedout = usb.control_transfer(handle, request_type, SIO_SET_BAUDRATE_REQUEST,
								SIO_BAUDRATE_150060, 0, "", 100)
							if timedout then
								error("Could not set baudrate!")
							end
							length, timedout = usb.control_transfer(handle,	request_type,
								SIO_SET_LATENCY_TIMER_REQUEST, 0x000a, 0, "", 100)
							if timedout then
								error("Could not set baudrate!")
							end
							self.handle = handle
						end
							
						relay.detach = function(self)
							usb.release_interface(self.handle, 0)
							usb.close(self.handle)
							self.handle = nil
						end

						relay.close_all = function(self)
							deditec_close_all(self)
						end

						relay.open_all = function(self)
							deditec_open_all(self)
						end

						relay.close_switch = function(self, number)
							deditec_close_switch(self, number)
						end

						relay.open_switch = function(self, number)
							deditec_open_switch(self, number)
						end

						table.insert(relay_table, relay);
					end
					usb.close(handle)
				end
			end
		end
	end

	return relay_table
end
return {get_relays=get_relays}

