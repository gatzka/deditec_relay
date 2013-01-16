local deditec_relays = require "deditec_relays"
local socket = require "socket"

local relays = deditec_relays.get_relays()

for i,relay in ipairs(relays) do
    relay:attach()
	print("now opening")
	relay:open_switch(1)
	socket.sleep(5)
	print("now closing")
	relay:close_switch(1)
--    relay:close_all()
--	relay:read_switches()
--    socket.sleep(10)
--	print("now opening")
--    relay:open_all()
--	relay:read_switches()
--    socket.sleep(10)
    relay:detach()
end

