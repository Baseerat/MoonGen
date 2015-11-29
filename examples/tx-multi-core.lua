local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"

local ffi	= require "ffi"

function master(...)
	local txPort, cores, rate = tonumberall(...)
	if not txPort or not cores then
		return print("usage: txPort cores [rate]")
	end
	rate = rate or nil
	local rxMempool = memory.createMemPool()
	local txDev
	txDev = device.config(txPort, rxMempool, 1, cores)
	txDev:wait()
	for i = 0, cores - 1 do
		if rate then
			txDev:getTxQueue(i):setRate(rate / cores)
		end
		dpdk.launchLua("loadSlave", txPort, i)
	end
	dpdk.waitForSlaves()
end

function loadSlave(port, queue)
	local core = queue
	local queue = device.get(port):getTxQueue(queue)
	local mem = memory.createMemPool(function(buf)
		local data = ffi.cast("uint8_t*", buf:getData())
		-- src/dst mac
		for i = 0, 11 do
			data[i] = i
		end
		-- eth type
		data[12] = 0x12
		data[13] = 0x34
	end)
	local MAX_BURST_SIZE = 31
	local lastPrint = dpdk.getTime()
	local totalSent = 0
	local lastTotal = 0
	local lastSent = 0
	local bufs = mem:bufArray(MAX_BURST_SIZE)
	while dpdk.running() do
		bufs:alloc(60)
		totalSent = totalSent + queue:send(bufs)
		local time = dpdk.getTime()
		if time - lastPrint > 1 then
			local mpps = (totalSent - lastTotal) / (time - lastPrint) / 10^6
			printf("[Queue %d] Sent %d packets, current rate %.2f Mpps, %.2f MBit/s, %.2f MBit/s wire rate", core, totalSent, mpps, mpps * 64 * 8, mpps * 84 * 8)
			lastTotal = totalSent
			lastPrint = time
		end
	end
	printf("[Queue %d] Sent %d packets", core, totalSent)
end

