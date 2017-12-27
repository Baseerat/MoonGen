local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local timer		= require "timer"

--memory.enableCache()

PKT_SIZE = 64
TX_RUN_TIME = 60

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
	local tx_task
	if port1 and port2 and port3 then
	  tx_task = dpdk.launchLua("txSlave3", dev1:getTxQueue(0), dev2:getTxQueue(0), dev3:getTxQueue(0))
	elseif port1 and port2 then
	  tx_task = dpdk.launchLua("txSlave2", dev1:getTxQueue(0), dev2:getTxQueue(0))
	else
	  tx_task = dpdk.launchLua("txSlave1", dev1:getTxQueue(0))
	end
	local avg = tx_task:wait()
	dpdk.waitForSlaves()
end

local function fillPacket1(buf)
  buf:getUdpPacket():fill{
    pktLength = PKT_SIZE,
    ethSrc = "10:11:12:13:14:14",
    ethDst = "10:11:12:13:14:15",
    ip4Src = "10.0.0.14",
    ip4Dst = "10.0.0.15",
    udpSrc = 54321,
    udpDst = 12345,
  }
end

local function fillPacket2(buf)
  buf:getUdpPacket():fill{
    pktLength = PKT_SIZE,
    ethSrc = "10:11:12:13:14:16",
    ethDst = "10:11:12:13:14:17",
    ip4Src = "20.0.0.16",
    ip4Dst = "20.0.0.17",
    udpSrc = 54322,
    udpDst = 12345,
  }
end

local function fillPacket3(buf)
  buf:getUdpPacket():fill{
    pktLength = PKT_SIZE,
    ethSrc = "10:11:12:13:14:18",
    ethDst = "10:11:12:13:14:19",
    ip4Src = "30.0.0.18",
    ip4Dst = "30.0.0.19",
    udpSrc = 54323,
    udpDst = 12345,
  }
end


function txSlave1(queue1)
	local mem = memory.createMemPool(function(buf)
		fillPacket1(buf)
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

function txSlave2(queue1, queue2)
	local mem1 = memory.createMemPool(function(buf)
    fillPacket1(buf)
	end)
	local mem2 = memory.createMemPool(function(buf)
    fillPacket2(buf)
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

function txSlave3(queue1, queue2, queue3)
	local mem1 = memory.createMemPool(function(buf)
    fillPacket1(buf)
	end)
	local mem2 = memory.createMemPool(function(buf)
    fillPacket2(buf)
	end)
	local mem3 = memory.createMemPool(function(buf)
    fillPacket3(buf)
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