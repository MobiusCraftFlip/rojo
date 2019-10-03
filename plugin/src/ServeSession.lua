local t = require(script.Parent.Parent.t)

local strict = require(script.Parent.strict)

local Status = strict("Session.Status", {
	NotStarted = "NotStarted",
	Connecting = "Connecting",
	Connected = "Connected",
	Disconnected = "Disconnected",
})

local function DEBUG_printPatch(patch)
	local HttpService = game:GetService("HttpService")


	for removed in ipairs(patch.removed) do
		print("Remove:", removed)
	end

	for id, added in pairs(patch.added) do
		print("Add:", id, HttpService:JSONEncode(added))
	end

	for updated in ipairs(patch.updated) do
		print("Update:", HttpService:JSONEncode(updated))
	end
end

local ServeSession = {}
ServeSession.__index = ServeSession

ServeSession.Status = Status

local validateServeOptions = t.strictInterface({
	apiContext = t.table,
	reconciler = t.table,
})

function ServeSession.new(options)
	assert(validateServeOptions(options))

	local self = {
		__status = Status.NotStarted,
		__apiContext = options.apiContext,
		__reconciler = options.reconciler,
		__statusChangedCallback = nil,
	}

	setmetatable(self, ServeSession)

	return self
end

function ServeSession:onStatusChanged(callback)
	self.__statusChangedCallback = callback
end

function ServeSession:start()
	self:__setStatus(Status.Connecting)

	self.__apiContext:connect()
		:andThen(function(serverInfo)
			self:__setStatus(Status.Connected)

			local rootInstanceId = serverInfo.rootInstanceId

			return self.__apiContext:read({ rootInstanceId })
				:andThen(function(readResponseBody)
					local hydratePatch = self.__reconciler:hydrate(
						readResponseBody.instances,
						rootInstanceId,
						game
					)

					DEBUG_printPatch(hydratePatch)

					-- TODO: Apply the patch generated by hydration. We should
					-- eventually prompt the user about this since it's a
					-- conflict between Rojo and their current place state.
				end)
		end)
		:catch(function(err)
			self:__setStatus(Status.Disconnected, err)
		end)
end

function ServeSession:stop()
	self:__setStatus(Status.Disconnected)
end

function ServeSession:__setStatus(status, detail)
	self.__status = status

	if self.__statusChangedCallback ~= nil then
		self.__statusChangedCallback(status, detail)
	end
end

return ServeSession