--- Class factory function
local Class = {}

setmetatable(Class, {
	__call = function(self)
		self.__call = getmetatable(self).__call
		self.__index = self
		return setmetatable({}, self)
	end
})

function Class:new()
	return self()
end

DuiBrowser = Class()

DuiBrowser.initQueue = {}
DuiBrowser.pool = {}
DuiBrowser.renderTargets = {}
DuiBrowser.scaleforms = {}

--- Creates a named rendertarget for a model (2026 update: modernized)
function DuiBrowser:createNamedRendertargetForModel(model, name)
	local handle = 0

	if not IsNamedRendertargetRegistered(name) then
		RegisterNamedRendertarget(name, 0)
	end
	if not IsNamedRendertargetLinked(model) then
		LinkNamedRendertarget(model)
	end
	if IsNamedRendertargetRegistered(name) then
		handle = GetNamedRendertargetRenderId(name)
	end

	return handle
end

--- Waits for DUI browser connection with timeout (2026 update: improved error handling)
function DuiBrowser:waitForConnection()
	self.initDone = false

	DuiBrowser.initQueue[self.mediaPlayerHandle] = self

	local timeout = GetGameTimer() + Config.dui.timeout

	while not DuiBrowser.initQueue[self.mediaPlayerHandle].initDone and GetGameTimer() < timeout do
		self:sendMessage({type = "DuiBrowser:init", handle = self.mediaPlayerHandle})
		Wait(100)  -- 2026: Use Wait() instead of Citizen.Wait()
	end

	DuiBrowser.initQueue[self.mediaPlayerHandle] = nil

	if self.initDone then
		return true
	else
		print(("^1[PMMS ERROR]^7 Failed to initialize DUI browser: Could not connect to %s within %d ms"):format(self.duiUrl, Config.dui.timeout))
		return false
	end
end

--- Enables the rendertarget for video display
function DuiBrowser:enableRenderTarget()
	if not self.renderTarget then
		return
	end

	if self.renderTargetHandle then
		return
	end

	self.renderTargetHandle = self:createNamedRendertargetForModel(self.model, self.renderTarget)

	if DuiBrowser.renderTargets[self.renderTarget] then
		DuiBrowser.renderTargets[self.renderTarget].browsers[self] = true
	end
end

--- Disables the rendertarget
function DuiBrowser:disableRenderTarget()
	if not self.renderTarget then
		return
	end

	if not self.renderTargetHandle then
		return
	end

	ReleaseNamedRendertarget(self.renderTarget)

	self.renderTargetHandle = nil

	if DuiBrowser.renderTargets[self.renderTarget] then
		DuiBrowser.renderTargets[self.renderTarget].browsers[self] = nil
	end
end

--- Creates a runtime texture for DUI (2026 update: improved error handling)
function DuiBrowser:createTexture()
	self.txdName = "pmms_txd_" .. tostring(self.mediaPlayerHandle)
	self.txnName = "video"
	self.txd = CreateRuntimeTxd(self.txdName)
	
	if self.duiHandle and self.txd then
		self.txn = CreateRuntimeTextureFromDuiHandle(self.txd, self.txnName, self.duiHandle)
	end
end

--- Loads a scaleform movie with timeout (2026 update: improved robustness)
function DuiBrowser:loadScaleform()
	if not self.sfHandle then
		return false
	end

	local timeout = GetGameTimer() + 5000

	while not HasScaleformMovieLoaded(self.sfHandle) and GetGameTimer() < timeout do
		Wait(0)
	end

	return HasScaleformMovieLoaded(self.sfHandle)
end

--- Enables scaleform rendering (2026 update: better null checking)
function DuiBrowser:enableScaleform()
	if self.sfHandle then
		return
	end

	self.sfHandle = RequestScaleformMovie(self.sfName)

	if self:loadScaleform() then
		self:createTexture()

		BeginScaleformMovieMethod(self.sfHandle, "SET_TEXTURE")
		ScaleformMovieMethodAddParamTextureNameString(self.txdName)
		ScaleformMovieMethodAddParamTextureNameString(self.txnName)
		ScaleformMovieMethodAddParamInt(0)
		ScaleformMovieMethodAddParamInt(0)
		ScaleformMovieMethodAddParamInt(Config.dui.screenWidth)
		ScaleformMovieMethodAddParamInt(Config.dui.screenHeight)

		EndScaleformMovieMethod()

		if DuiBrowser.scaleforms[self.sfName] then
			DuiBrowser.scaleforms[self.sfName].browsers[self] = true
		end
	else
		print(("^1[PMMS ERROR]^7 Failed to load scaleform %s"):format(self.sfName))
	end
end

--- Disables scaleform rendering
function DuiBrowser:disableScaleform()
	if not self.sfHandle then
		return
	end

	if DuiBrowser.scaleforms[self.sfName] then
		DuiBrowser.scaleforms[self.sfName].browsers[self] = nil
	end

	SetScaleformMovieAsNoLongerNeeded(self.sfHandle)
	self.sfHandle = nil
end

--- Enables rendering based on available output (renderTarget or scaleform)
function DuiBrowser:enable()
	if self.renderTarget then
		self:enableRenderTarget()
	elseif self.scaleform then
		self:enableScaleform()
	end
end

--- Disables rendering
function DuiBrowser:disable()
	if self.renderTarget then
		self:disableRenderTarget()
	elseif self.scaleform then
		self:disableScaleform()
	end
end

--- Creates a new DUI browser instance (2026 update: improved compatibility)
function DuiBrowser:new(mediaPlayerHandle, model, renderTarget, scaleform, url)
	local self = Class.new(self)

	if DuiBrowser.initQueue[mediaPlayerHandle] then
		return DuiBrowser.initQueue[mediaPlayerHandle]
	end

	self.mediaPlayerHandle = mediaPlayerHandle
	self.model = model

	if scaleform then
		self.scaleform = scaleform
	else
		self.renderTarget = renderTarget
	end

	local thisResource = GetCurrentResourceName()

	local useHttps = url and url:sub(1, 8) == "https://" or false

	if useHttps then
		self.duiUrl = Config.dui.urls.https
	else
		if Config.dui.urls.http then
			self.duiUrl = Config.dui.urls.http
		else
			local serverEndpoint = GetCurrentServerEndpoint()
			if serverEndpoint then
				self.duiUrl = ("http://%s/%s/dui/"):format(serverEndpoint, thisResource)
			else
				self.duiUrl = ("http://localhost/%s/dui/"):format(thisResource)
			end
		end
	end

	self.duiObject = CreateDui(self.duiUrl .. "?resourceName=" .. thisResource, Config.dui.screenWidth, Config.dui.screenHeight)
	self.duiHandle = GetDuiHandle(self.duiObject)

	if self.renderTarget or self.scaleform then
		self:createTexture()

		if self.scaleform then
			self.sfName = self.scaleform.name or Config.defaultScaleformName
		end
	end

	if self:waitForConnection() then
		DuiBrowser.pool[self.mediaPlayerHandle] = self

		if self.renderTarget then
			if not DuiBrowser.renderTargets[self.renderTarget] then
				DuiBrowser.renderTargets[self.renderTarget] = {
					disabled = false,
					browsers = {}
				}
			end
		elseif self.scaleform then
			if not DuiBrowser.scaleforms[self.sfName] then
				DuiBrowser.scaleforms[self.sfName] = {
					disabled = false,
					browsers = {}
				}
			end
		end

		return self
	else
		DuiBrowser.pool[self.mediaPlayerHandle] = nil
		if self.duiObject then
			DestroyDui(self.duiObject)
		end
		return nil
	end
end

--- Renders a frame to the appropriate output
function DuiBrowser:renderFrame(drawSprite)
	if self.renderTarget then
		if DuiBrowser.renderTargets[self.renderTarget] and DuiBrowser.renderTargets[self.renderTarget].disabled then
			return
		end

		self:enableRenderTarget()

		SetTextRenderId(self.renderTargetHandle)
		Set_2dLayer(4)
		SetScriptGfxDrawBehindPausemenu(1)

		DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, 255)

		if drawSprite then
			DrawSprite(self.txdName, self.txnName, 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
		end

		SetTextRenderId(GetDefaultScriptRendertargetRenderId())
		SetScriptGfxDrawBehindPausemenu(0)
	elseif self.scaleform then
		if DuiBrowser.scaleforms[self.sfName] and DuiBrowser.scaleforms[self.sfName].disabled then
			return
		end

		self:enableScaleform()

		DrawScaleformMovie_3dSolid(self.sfHandle,
			self.scaleform.finalPosition or self.scaleform.position,
			self.scaleform.finalRotation or self.scaleform.rotation,
			2.0, 2.0, 1.0,
			self.scaleform.scale,
			2)
	end
end

--- Draws the browser frame with sprite
function DuiBrowser:draw()
	self:renderFrame(true)
end

--- Checks if a browser exists for a specific render target
function DuiBrowser:doesBrowserExistForRenderTarget(renderTarget)
	for handle, duiBrowser in pairs(DuiBrowser.pool) do
		if duiBrowser.renderTarget == renderTarget then
			return true
		end
	end

	return false
end

--- Gets a browser from the pool by handle
function DuiBrowser:getBrowserForHandle(handle)
	return DuiBrowser.pool[handle]
end

--- Sends a message to the DUI browser
function DuiBrowser:sendMessage(data)
	if self.duiObject then
		SendDuiMessage(self.duiObject, json.encode(data))
	end
end

--- Checks if the DUI is available
function DuiBrowser:isAvailable()
	return self.duiObject and IsDuiAvailable(self.duiObject)
end

--- Checks if the browser has a drawable output
function DuiBrowser:isDrawable()
	return self.renderTarget ~= nil or self.scaleform ~= nil
end

--- Gets the name of the drawable output
function DuiBrowser:getDrawableName()
	if self.renderTarget then
		return self.renderTarget
	elseif self.scaleform then
		return self.sfName
	end
end

--- Sets the scaleform for this browser
function DuiBrowser:setScaleform(scaleform)
	self.scaleform = scaleform
end

--- Resets the entire browser pool
function DuiBrowser:resetPool()
	for handle, duiBrowser in pairs(DuiBrowser.pool) do
		if duiBrowser then
			duiBrowser:delete()
		end
	end
end

--- Deletes this browser instance (2026 update: improved cleanup)
function DuiBrowser:delete()
	if not self then
		return
	end

	if self.renderTarget then
		self:renderFrame(false)
		if DuiBrowser.renderTargets[self.renderTarget] then
			DuiBrowser.renderTargets[self.renderTarget].disabled = true
		end
		Wait(50)
		if DuiBrowser.renderTargets[self.renderTarget] then
			DuiBrowser.renderTargets[self.renderTarget].disabled = false
		end
	end

	if self.mediaPlayerHandle then
		DuiBrowser.pool[self.mediaPlayerHandle] = nil
	end

	if self.duiObject then
		DestroyDui(self.duiObject)
	end

	if self.renderTarget and DuiBrowser.renderTargets[self.renderTarget] then
		for duiBrowser, _ in pairs(DuiBrowser.renderTargets[self.renderTarget].browsers) do
			if duiBrowser then
				duiBrowser:disableRenderTarget()
			end
		end
	elseif self.scaleform and DuiBrowser.scaleforms[self.sfName] then
		for duiBrowser, _ in pairs(DuiBrowser.scaleforms[self.sfName].browsers) do
			if duiBrowser then
				duiBrowser:disableScaleform()
			end
		end
	end
end

RegisterNUICallback("DuiBrowser:initDone", function(data, cb)
	if data and data.handle and DuiBrowser.initQueue[data.handle] then
		DuiBrowser.initQueue[data.handle].initDone = true
	end
	cb({})
end)
