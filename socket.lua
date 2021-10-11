-- mock `socket` implementation
local m = {}
-- the control handle for an individual mocked socket
local mockhandle = {}

-- the mock remote end of a stream socket, enabled with `mockremote` option
local streamremote = {}
-- the mock remote end of a datagram socket, enabled with `mockremote` option
local datagramremote = {}

-- Parameter Verification Helpers

function domain_or_ip(val)
  return type(val) == "string" -- do more validation later?
end

function u16(val)
  return type(val) == "number" and val > 0 and val < 2^16
end

function number(val)
  return type(val) == "number"
end

function str(val)
  return type(val) == "string"
end

function mode(mode)
  return function(self)
    if type(self) ~= "table" then
      return false, string.format("expected socket, got %s", type(self))
    elseif type(mode) == "table" then
      for m in mode do if self.mode == m then return true end end
      return false
    else
      if self.mode == mode then
        return true
      else
        return false, string.format("expected %s socket, got %s socket", mode, self.mode)
      end
    end
  end
end

function any(val)
  return val ~= nil
end

function optional(verify)
  return function(val)
    return val == nil or verify(val)
  end
end

-- Socket Profiles
--
-- Each profile is of the format
-- {
--   kind = "stream" | "datagram",
--   allowedmethods = {
--     args = { function(param) -> is_valid: bool, err: string (optional), ... }, -- validate each argument
--     argnames = { arg_name: string, ... } (optional), -- names of arguments, for error messages, if omitted shows numerical position
--     always = function(...) (optional) -- is always run after success of main handler, useful for required state changes,
--     default = function(...) -> ... (optional) -- the default handler, overrideable, usually returns success response,
--  }
--}

local profiles = {
  tcp = {
    kind = "stream",
    allowedmethods = {
      accept = {
        args = { mode("server") },
        argnames = { "self" },
        always = nil,
        default = nil,
      },
      bind =  {
        args = { mode("master") },
        argnames = { "self" },
        always = function(self) self.mode = "client" end,
        default = nil,
      },
      close =  {
        args = { any },
        argnames = { "self" },
        always = nil,
        default = function() return 1.0 end,
      },
      connect =  {
        args = { mode("master"), domain_or_ip, u16 },
	argnames = { "self", "host", "port" },
        always = function(self) self.mode = "client" end,
        default = function() return 1.0 end,
      },
      getpeername =  {
        args = { mode("client") },
        argnames = { "self" },
        always = nil,
        default = nil,
      },
      getsockname =  {
        args = { any },
        argnames = { "self" },
        always = nil,
        default = nil,
      },
      getstats =  {
        args = { any },
        argnames = { "self" },
        always = nil,
        default = nil,
      },
      listen =  {
        args = { mode("master"), optional(number) },
        argnames = { "self", "backlog" },
        always = nil,
        default = nil,
      },
      receive =  {
        args = { mode("client"), optional(any), optional(any) },
        argnames = { "self", "pattern", "prefix" },
        always = nil,
        default = nil,
      },
      send =  {
        args = { mode("client"), any, optional(any), optional(any) },
	argnames = { "self", "data", "i", "j" },
        always = nil,
        default = function(self) return 1.0 end,
      },
      setoption =  {
        args = { mode({"client", "server"}), str, any },
        argnames = { "self", "option", "value" },
        always = nil,
        default = nil,
      },
      setstats =  {
        args = { any, number, number, number },
        argnames = { "self", "received", "sent", "age" },
        always = nil,
        default = nil,
      },
      settimeout =  {
        args = { any, number, optional(str) },
        argnames = { "self", "value", "mode" },
        always = nil,
        default = function(self, timeout, mode)
          assert(mode == nil or mode == "b", "total timeout mode not supported")
          self.timeout = timeout
	  return 1.0
        end,
      },
      shutdown =  {
        args = { mode("client"), optional(str) },
        argnames = { "self", "mode" },
        always = nil,
        default = nil,
      },
    }
  },
  udp = {
    kind = "datagram",
    allowedmethods = {
      close = {
        args = { any },
        argnames = { "self" },
        always = nil,
        default = function(self) return 1.0 end,
      },
      getpeername = {
        args = { mode("connected") },
        argnames = { "self" },
        always = nil,
        default = nil,
      },
      getsockname = {
        argnames = { "self" },
        args = { any },
        always = nil,
        default = nil,
      },
      receive = {
        args = { any, optional(number) },
        argnames = { "self", "size" },
        always = nil,
        default = nil,
      },
      receivefrom = {
        args = { mode("unconnected"), optional(number) },
        argnames = { "self", "size" },
        always = nil,
        default = nil,
      },
      send = {
        args = { mode("connected"), any },
        argnames = { "self", "datagram" },
        always = nil,
        default = nil,
      },
      sendto = {
        args = { mode("unconnected"), str, domain_or_ip, u16 },
        argnames = { "self", "datagram", "ip", "port" },
        always = nil,
        default = nil,
      },
      setpeername = {
        args = { any, str, optional(u16) },
        argnames = { "self", "address", "port" },
        always = function(self) if address == "*" then self.mode = "unconnected" else self.mode = "connected" end end,
        default = function(self, address, port)
          if type(self.peer) == "table" and self.peer.address ~= address then
            return nil, "Invalid argument"
          end
          if addresss == "*" then
            self.peer = nil
          else
            self.peer = {address = address, port = port}
          end
          return 1.0
        end,
      },
      setsockname = {
        args = { mode("unconnected"), str, u16 },
        argnames = { "self", "address", "port" },
        always = nil,
        default = function(self, host, port)
          if self.sockname then return nil, "Invalid argument" end
          return 1.0
        end,
      },
      setoption = {
        args = { any, str, optional(any) },
        argnames = { "self", "option", "value" },
        always = nil,
        default = nil,
      },
      settimeout = {
        args = { any, number },
        argnames = { "self", "value" },
        always = nil,
        default = function(self, timeout) self.timeout = timeout; return 1.0 end,
      }
    }
  },
  zigbee = {
    -- TODO: we probably need to mock send, do we need to mock receive?
    kind = "datagram",
    allowedmethods = {
      receive = {
        args = { any },
        argnames = { "self" },
        always = nil,
        default = nil,
      },
      send = {
        args = { mode("connected"), any },
        argnames = { "self", "message" },
        always = nil,
        default = nil,
      },
      settimeout = {
        args = { any, number },
        argnames = { "self", "value" },
        always = nil,
        default = function(self, timeout) self.timeout = timeout; return 1.0 end,
      }
    }
  },
  zwave = {
      receive = {
        args = { any },
        argnames = { "self" },
        always = nil,
        default = nil,
      },
      send = {
        args = { any, any, any, any, any, any, any },
        argnames = { "self", "encap", "command class", "command code",
	             "payload", "source channel", "destination channels" },
        always = nil,
        default = nil,
      },
      settimeout = {
        args = { any, number },
        argnames = { "self", "value" },
        always = nil,
        default = function(self, timeout) self.timeout = timeout; return 1.0 end,
      }
  }
}

-- default mock socket handler that acts based on one of the above profiles
function profilehandler(profile)
  return function(self, key, ...)

    local method = profile.allowedmethods[key]
    if not method then error("unsupported method: "..tostring(key)) end

    local args = {...}

    for i, arg in ipairs(args) do
      if not (method.args[i] and method.args[i](arg)) then
        local _, reason = method.args[i](arg)
        local argname = (method.argnames or {})[i] or string.format("#%i", i)
        error(string.format("bad argument %s to '%s': %s", argname, key, reason))
      end
    end

    local ret
    if type(self.customhandlers[key]) == "function" then
      ret = {self.customhandlers[key](...)}
    elseif method.default then
      ret = {method.default(...)}
    else
      error(string.format("no handler set for %s", key))
    end

    if ret[1] and method.always then
      method.always(...)
    end

    return table.unpack(ret)
  end
end

-- internal joiner function to merge mt lookup args with actual function call args
function socket_call(self, key)
  return function(...)
    return self.handler(self, key, ...)
  end
end

function m.new(profile)
  local handler = profilehandler(profile)
  assert(handler, "handler required")
  assert(type(handler) == "function", "handler must be a function")
  return setmetatable({handler = handler, kind = profile.kind}, { __index = socket_call})
end

function m.tcp(opt)
  if type(opt) ~= "table" then opt = {} end
  local sock, handle =  m.new(profiles.tcp)

  sock.mode = "master"
  sock.customhandlers = {}

  local handle = setmetatable({socket = sock}, {__index = mockhandle})

  if opt.mockremote then
    handle:enableremote()
  end

  return sock, handle
end

function m.udp(opt)
  if type(opt) ~= "table" then opt = {} end
  local sock, handle =  m.new(profiles.udp)

  sock.mode = "unconnected"
  sock.customhandlers = {}

  local handle = setmetatable({socket = sock}, {__index = mockhandle})

  if opt.mockremote then
    handle:enableremote()
  end

  return sock, handle
end

function m.zigbee(opt)
  if type(opt) ~= "table" then opt = {} end
  local sock, handle =  m.new(profiles.zigbee)

  sock.mode = "connected" -- zigbee has a single "connection" to the radio
  sock.customhandlers = {}

  local handle = setmetatable({socket = sock}, {__index = mockhandle})

  if opt.mockremote then
    handle:enableremote()
  end

  return sock, handle
end

function m.zwave(opt)
  if type(opt) ~= "table" then opt = {} end
  local sock, handle =  m.new(profiles.zwave)

  sock.mode = "connected" -- zwave has a single "connection" to the radio
  sock.customhandlers = {}

  local handle = setmetatable({socket = sock}, {__index = mockhandle})

  if opt.mockremote then
    handle:enableremote()
  end

  return sock, handle
end

function mockhandle:sethandler(method, handler)
  self.socket.customhandlers[method] = handler
end

function mockhandle:enableremote()
  if self.socket.kind == "stream" then
    self.remote = setmetatable({socket = self.socket}, { __index = streamremote })
    self.socket.sendqueue = ""
    self.socket.receivequeue = ""
    self:sethandler("receive", mockstreamrecievehandlerforremote)
    self:sethandler("send", mockstreamsendhandlerforremote)
  elseif self.socket.kind == "datagram" then
    self.remote = setmetatable({socket = self.socket}, { __index = datagramremote })
    self.socket.sendqueue = {}
    self.socket.receivequeue = {}
    self:sethandler("receive", mockdatagramrecievehandlerforremote)
    self:sethandler("receivefrom", mockdatagramrecievefromhandlerforremote)
    self:sethandler("send", mockdatagramsendhandlerforremote)
    self:sethandler("sendto", mockdatagramsendtohandlerforremote)
  else
    error("unknown socket kind: "..tostring(self.socket.kind))
  end
end

-- handler for `receive` on stream type sockets, enabled with `mockremote` option
function mockstreamrecievehandlerforremote(self, pattern, prefix)
  if pattern == nil or pattern == "*l" then
    local pos = string.find(self.receivequeue, "\n", nil, true)
    if pos then
      local bytes = string.sub(self.receivequeue, 1, pos-1)
      self.receivequeue = string.sub(self.receivequeue, pos+1)
      return bytes
    else
      error("mock remote receive would block, no full lines and no timeout set")
    end
  elseif pattern == "*a" then
    error("*a pattern not currently supported")
  elseif type(pattern) == "number" then
    if #self.receivequeue < pattern then
      local bytes = string.sub(self.receivequeue, 1, pattern-1)
      self.receivequeue = string.sub(self.receivequeue, pattern+1)
      return bytes
    elseif self.socket.timeout then
      return nil, "timeout"
    else
      error("mock remote receive would block, not enough data and no timeout set")
    end
  else
    error("invalid receive pattern")
  end
end

-- handler for `send` on stream type sockets, enabled with `mockremote` option
function mockstreamsendhandlerforremote(self, data, i, j)
  data = string.sub(data, i or 1)
  self.sendqueue = self.sendqueue..data
  return 1.0
end

function streamremote:receive(pattern, prefix)
  if pattern == nil or pattern == "*l" then
    local pos = string.find(self.socket.sendqueue, "\n", nil, true)
    if pos then
      local bytes = string.sub(self.socket.sendqueue, 1, pos-1)
      self.socket.sendqueue = string.sub(self.socket.sendqueue, pos+1)
      return bytes
    else
      error("mock remote receive would block, no full lines and no timeout set")
    end
  elseif pattern == "*a" then
    error("*a pattern not currently supported")
  elseif type(pattern) == "number" then
    if #self.socket.sendqueue < pattern then
      local bytes = string.sub(self.socket.sendqueue, 1, pattern-1)
      self.socket.sendqueue = string.sub(self.socket.sendqueue, pattern+1)
      return bytes
    elseif self.socket.timeout then
      return nil, "timeout"
    else
      error("mock remote receive would block, not enough data and no timeout set")
    end
  else
    error("invalid receive pattern")
  end
end

function streamremote:send(data, i, j)
  data = string.sub(data, i or 1)
  self.socket.receivequeue = self.socket.receivequeue..data
  return 1.0
end

-- handler for `receive` on datagram type sockets, enabled with `mockremote` option
function mockdatagramrecievefromhandlerforremote(self, size)
  if #self.receivequeue > 0 then
    local msg = table.remove(self.receivequeue, 1)
    return string.sub(msg.data, 1, size), msg.ip, msg.port
  elseif self.timeout then
    return nil, "timeout"
  else
    error("mock remote would block, no datagrams available and no timeout set")
  end
end

-- handler for `receive` on datagram type sockets, enabled with `mockremote` option
function mockdatagramrecievehandlerforremote(self, size)
  if #self.receivequeue > 0 then
    local msg = table.remove(self.receivequeue, 1)
    return string.sub(msg.data, 1, size)
  elseif self.timeout then
    return nil, "timeout"
  else
    error("mock remote would block, no datagrams available and no timeout set")
  end
end

-- handler for `send` on unconnected datagram type sockets, enabled with `mockremote` option
function mockdatagramsendtohandlerforremote(self, data, ip, port)
  table.insert(self.sendqueue, {data = data, ip = ip, port = port})
  return 1.0
end

-- handler for `send` on connected datagram type sockets, enabled with `mockremote` option
function mockdatagramsendhandlerforremote(self, data)
  assert(self.mode == "connected", "call to send on unconnected socket")
  local address = assert(self.peer.address, "no peer ip on connected socket")
  local port = assert(self.peer.port, "no peer port on connected socket")
  table.insert(self.sendqueue, {data = data, ip = ip, port = port})
  return 1.0
end

-- the mock remote end of an unconnected datagram socket, enabled with `mockremote` option
function datagramremote:receiveto(size)
  if #self.socket.sendqueue > 0 then
    local msg = table.remove(self.socket.sendqueue, 1)
    return string.sub(msg.data, 1, size), msg.ip, msg.port
  elseif self.socket.timeout then
    return nil, "timeout"
  else
    error("mock remote would block, no datagrams available and no timeout set")
  end
end

-- the mock remote end of a connected datagram socket, enabled with `mockremote` option
function datagramremote:receive(size)
  assert(self.socket.mode == "connected", "call to receive on unconnected socket")
  local data = self:receiveto(size) -- drop ip, port
  return data
end

-- the mock remote end of an unconnected datagram socket, enabled with `mockremote` option
function datagramremote:sendfrom(datagram, ip, port)
  assert(ip, "no ip")
  assert(port, "no port")

  table.insert(self.socket.receivequeue, {data = datagram, ip = ip, port = port})
  return 1.0
end

-- the mock remote end of a connected datagram socket, enabled with `mockremote` option
function datagramremote:send(datagram)
  assert(self.socket.mode == "connected", "send can only be used on connected socket, connect or use sendfrom")
  local ip = assert(self.socket.ip, "internal: connected socket with no remote ip")
  local port = assert(self.socket.port, "internal: connected socket with no remote port")
  return self:sendfrom(datagram, ip, port)
end

--
--
-- Everything below here is for example only.
--
--

-- demonstration of the "mock remote" interface
function test()
  -- TCP example
  local t, h = m.tcp({mockremote = true})

  assert(t:connect("127.0.0.1", 80), "failed to connect")
  assert(t:send("hello, world\n"), "failed to send")

  local recv, err = h.remote:receive()
  assert(recv, "failed to receive: "..tostring(err))
  assert(recv == "hello, world", "receieved unexpected msg: "..tostring(recv))

  assert(h.remote:send("hello, back\n"), "failed to send from remote")

  local recv, err = t:receive()
  assert(recv, "failed to receive: "..tostring(err))
  assert(recv == "hello, back", "receieved unexpected msg: "..tostring(recv))

  -- UDP(connected) example
  local t, h = m.udp({mockremote = true})

  assert(t:setpeername("127.0.0.1", 80), "failed to connect")
  assert(t:send("hello, world"), "failed to send")

  local recv, err = h.remote:receive()
  assert(recv, "failed to receive: "..tostring(err))
  assert(recv == "hello, world", "receieved unexpected msg: "..tostring(recv))

  assert(h.remote:send("hello, back"), "failed to send from remote")

  local recv, err = t:receive()
  assert(recv, "failed to receive: "..tostring(err))
  assert(recv == "hello, back", "receieved unexpected msg: "..tostring(recv))

  -- UDP(unconnected) example
  local t, h = m.udp({mockremote = true})

  assert(t:sendto("hello, world", "127.0.0.1", 80), "failed to send")

  local recv, err_or_ip, port = h.remote:receiveto()
  assert(recv, "failed to receive: "..tostring(err_or_ip))
  local ip = err_or_ip
  assert(recv == "hello, world", "receieved unexpected msg: "..tostring(recv))
  assert(ip == "127.0.0.1", "received at wrong remote ip")
  assert(port == 80, "received at wrong remote port: "..tostring(port))

  assert(h.remote:sendfrom("hello, back", "127.0.0.1", 80), "failed to send from remote")

  local recv, err_or_ip, port = t:receivefrom()
  assert(recv, "failed to receive: "..tostring(err_or_ip))
  local ip = err_or_ip
  assert(recv == "hello, back", "receieved unexpected msg: "..tostring(recv))
  assert(ip == "127.0.0.1", "received from wrong remote ip")
  assert(port == 80, "received from wrong remote port: "..tostring(port))
end

-- demonstration of the basic interface (also showing how I expect tests for capability events would be written)
function testtest()
  -- create mock already connected socket (and handle to control mock)
  local sock, mockhandle = m.tcp()
  sock:connect("192.0.2.37", 80)

  -- create mock device
  local device = {
    connection = sock,
    ip = "10.0.0.37",
    port = 80,
  }

  -- tell mock what to return when `receive` is called
  mockhandle:sethandler("receive", function(self, patern, prefix)
    assert(pattern == "*l" or pattern == nil)
    assert(prefix == nil)
    return "ok"
  end)

  -- note: all other socket calls use default "success" response or are left
  -- unimplemented and would fail if called

  -- call function under test
  fakeswitchonhandler(nil, device, args)
end

-- a fake capability handler for above example test
function fakeswitchonhandler(driver, device, args)
  if not device.connection then
    local t = socket.tcp()
    if not t:connect(device.ip, device.port) then return false end
    device.connection = t
  end

  if not device.connection:send("on\n") then
    print("failed to send")
    device.connection = nil
    return false
  end
  local resp, err = device.connection:receive()

  if not resp then
    print("failed to receive response: "..tostring(msg))
    device.connection = nil
    return false
  elseif resp == "ok" then
    -- TODO: emit event
    return true
  elseif resp == "err" then
    return false
  else
    print("bad response:", resp)
    device.connection = nil
    return false
  end
end


test()
testtest()

return m
