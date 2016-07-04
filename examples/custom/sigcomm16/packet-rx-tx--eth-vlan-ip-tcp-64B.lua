local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local timer		= require "timer"
local ffi       = require "ffi"

--memory.enableCache()

PKT_SIZE = 64
RX_RUN_TIME = 30
RX_DELAY = 5
TX_RUN_TIME = RX_RUN_TIME + RX_DELAY + 5

-- TODO: this
function master(port1, port2, port3)
	if not port1 then
		return print("Usage: port1 [port2 [port3]]")
	end
	local dev1 = device.config(port1)
	local dev2
	if port2 then
		dev2 = device.config(port2)
	end
	local dev3
	if port3 then
		dev3 = device.config(port3)
	end
	device.waitForLinks()
	local tx_task, rx_task
	if port1 and port2 and port3 then
	  tx_task = dpdk.launchLua("txSlave3", dev1:getTxQueue(0), dev2:getTxQueue(0), dev3:getTxQueue(0))
	  dpdk.sleepMillis(RX_DELAY*1000) -- wait few ms to ensure rx threads are running
    rx_task = dpdk.launchLua("rxSlave3", dev1:getRxQueue(0), dev2:getRxQueue(0), dev3:getRxQueue(0))
	elseif port1 and port2 then
	  tx_task = dpdk.launchLua("txSlave2", dev1:getTxQueue(0), dev2:getTxQueue(0))
	  dpdk.sleepMillis(RX_DELAY*1000) -- wait few ms to ensure rx threads are running
	  rx_task = dpdk.launchLua("rxSlave2", dev1:getRxQueue(0), dev2:getRxQueue(0))
	else
	  tx_task = dpdk.launchLua("txSlave1", dev1:getTxQueue(0))
	  dpdk.sleepMillis(RX_DELAY*1000) -- wait few ms to ensure rx threads are running
	  rx_task = dpdk.launchLua("rxSlave1", dev1:getRxQueue(0))
	end
	local avg = rx_task:wait()
	      avg = tx_task:wait()
	dpdk.waitForSlaves()
end

local function fillPacket(buf)
  local data = ffi.cast("uint8_t*", buf:getData())
  local vlan_pkt = {0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x10, 0x11, 0x12, 0x13, 0x14, 0x14, 0x08, 0x00, 0x45, 0x00,
					0x00, 0x28, 0x00, 0x01, 0x00, 0x00, 0x40, 0x06, 0x66, 0xB3, 0x0A, 0x00, 0x00, 0x0E, 0x0A, 0x00,
					0x00, 0x0F, 0x1F, 0x90, 0x00, 0x50, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x50, 0x02,
  					0x20, 0x00, 0x5B, 0xE6, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}
    for i = 0, PKT_SIZE-1 do
      data[i] = vlan_pkt[i+1]
    end
end

function rxSlave1(queue1)
  local bufs = memory.bufArray()
  local ctr1 = stats:newDevRxCounter(queue1.dev, "plain")
  local runtime = timer:new(RX_RUN_TIME)
  while runtime:running() and dpdk.running() do
    queue1:tryRecv(bufs, 10)
    bufs:freeAll()
    ctr1:update()
  end
  ctr1:finalize()
  printf("Total Rx Mpps: %s (avg.), %s (stddev.)\r\nTotal Rx Mbps: %s (avg.), %s (stddev.)", ctr1.mpps.avg, ctr1.mpps.stdDev,
    ctr1.wireMbit.avg, ctr1.wireMbit.stdDev)
  return nil -- TODO
end

function txSlave1(queue1)
	local mem = memory.createMemPool(function(buf)
		fillPacket(buf)
	end)
	bufs = mem:bufArray()
	bufs:alloc(PKT_SIZE)
	bufs:offloadIPChecksums()
	local ctr1 = stats:newDevTxCounter(queue1.dev, "plain")
	local runtime = timer:new(TX_RUN_TIME)
	while runtime:running() and dpdk.running() do
		queue1:send(bufs)
		ctr1:update()
	end
	ctr1:finalize()
	printf("Total Tx Mpps: %s (avg.), %s (stddev.)\r\nTotal Tx Mbps: %s (avg.), %s (stddev.)", ctr1.mpps.avg, ctr1.mpps.stdDev,
		ctr1.wireMbit.avg, ctr1.wireMbit.stdDev)
	return nil -- TODO
end

function rxSlave2(queue1, queue2)
  local bufs = memory.bufArray()
  local ctr1 = stats:newDevRxCounter(queue1.dev, "plain")
  local ctr2 = stats:newDevRxCounter(queue2.dev, "plain")
  local runtime = timer:new(RX_RUN_TIME)
  while runtime:running() and dpdk.running() do
    queue1:tryRecv(bufs, 10)
    bufs:freeAll()
    ctr1:update()
    queue2:tryRecv(bufs, 10)
    bufs:freeAll()
    ctr2:update()
  end
  ctr1:finalize()
  ctr2:finalize()
  printf("Total Rx Mpps: %s (avg.), %s (stddev.)\r\nTotal Rx Mbps: %s (avg.), %s (stddev.)",
    ctr1.mpps.avg + ctr2.mpps.avg, ctr1.mpps.stdDev + ctr2.mpps.stdDev,
    ctr1.wireMbit.avg + ctr2.wireMbit.avg, ctr1.wireMbit.stdDev + ctr2.wireMbit.stdDev)
  return nil -- TODO
end

function txSlave2(queue1, queue2)
	local mem1 = memory.createMemPool(function(buf)
    fillPacket(buf)
	end)
	local mem2 = memory.createMemPool(function(buf)
    fillPacket(buf)
	end)
	bufs1 = mem1:bufArray()
	bufs1:alloc(PKT_SIZE)
	bufs1:offloadIPChecksums()
	bufs2 = mem2:bufArray()
	bufs2:alloc(PKT_SIZE)
	bufs2:offloadIPChecksums()
	local ctr1 = stats:newDevTxCounter(queue1.dev, "plain")
	local ctr2 = stats:newDevTxCounter(queue2.dev, "plain")
	local runtime = timer:new(TX_RUN_TIME)
	while runtime:running() and dpdk.running() do
		queue1:send(bufs1)
		ctr1:update()
		queue2:send(bufs2)
		ctr2:update()
	end
	ctr1:finalize()
	ctr2:finalize()
	printf("Total Tx Mpps: %s (avg.), %s (stddev.)\r\nTotal Tx Mbps: %s (avg.), %s (stddev.)",
		ctr1.mpps.avg + ctr2.mpps.avg, ctr1.mpps.stdDev + ctr2.mpps.stdDev,
		ctr1.wireMbit.avg + ctr2.wireMbit.avg, ctr1.wireMbit.stdDev + ctr2.wireMbit.stdDev)
	return nil -- TODO
end

function rxSlave3(queue1, queue2, queue3)
  local bufs = memory.bufArray()
  local ctr1 = stats:newDevRxCounter(queue1.dev, "plain")
  local ctr2 = stats:newDevRxCounter(queue2.dev, "plain")
  local ctr3 = stats:newDevRxCounter(queue3.dev, "plain")
  local runtime = timer:new(RX_RUN_TIME)
  while runtime:running() and dpdk.running() do
    queue1:tryRecv(bufs, 10)
    bufs:freeAll()
    ctr1:update()
    queue2:tryRecv(bufs, 10)
    bufs:freeAll()
    ctr2:update()
    queue3:tryRecv(bufs, 10)
    bufs:freeAll()
    ctr3:update()
  end
  ctr1:finalize()
  ctr2:finalize()
  ctr3:finalize()
  printf("Total Rx Mpps: %s (avg.), %s (stddev.)\r\nTotal Rx Mbps: %s (avg.), %s (stddev.)",
    ctr1.mpps.avg + ctr2.mpps.avg + ctr3.mpps.avg, ctr1.mpps.stdDev + ctr2.mpps.stdDev + ctr3.mpps.stdDev,
    ctr1.wireMbit.avg + ctr2.wireMbit.avg + ctr3.wireMbit.avg, ctr1.wireMbit.stdDev + ctr2.wireMbit.stdDev + ctr3.wireMbit.stdDev)
  return nil -- TODO
end

function txSlave3(queue1, queue2, queue3)
	local mem1 = memory.createMemPool(function(buf)
    fillPacket(buf)
	end)
	local mem2 = memory.createMemPool(function(buf)
    fillPacket(buf)
	end)
	local mem3 = memory.createMemPool(function(buf)
    fillPacket(buf)
	end)

	bufs1 = mem1:bufArray()
	bufs1:alloc(PKT_SIZE)
	bufs1:offloadIPChecksums()
	bufs2 = mem2:bufArray()
	bufs2:alloc(PKT_SIZE)
	bufs2:offloadIPChecksums()
	bufs3 = mem3:bufArray()
	bufs3:alloc(PKT_SIZE)
	bufs3:offloadIPChecksums()
	local ctr1 = stats:newDevTxCounter(queue1.dev, "plain")
	local ctr2 = stats:newDevTxCounter(queue2.dev, "plain")
	local ctr3 = stats:newDevTxCounter(queue3.dev, "plain")
	local runtime = timer:new(TX_RUN_TIME)
	while runtime:running() and dpdk.running() do
		queue1:send(bufs1)
		ctr1:update()
		queue2:send(bufs2)
		ctr2:update()
		queue3:send(bufs3)
		ctr3:update()
	end
	ctr1:finalize()
	ctr2:finalize()
	ctr3:finalize()
	printf("Total Tx Mpps: %s (avg.), %s (stddev.)\r\nTotal Tx Mbps: %s (avg.), %s (stddev.)",
		ctr1.mpps.avg + ctr2.mpps.avg + ctr3.mpps.avg, ctr1.mpps.stdDev + ctr2.mpps.stdDev + ctr3.mpps.stdDev,
		ctr1.wireMbit.avg + ctr2.wireMbit.avg + ctr3.wireMbit.avg, ctr1.wireMbit.stdDev + ctr2.wireMbit.stdDev + ctr3.wireMbit.stdDev)
	return nil -- TODO
end

