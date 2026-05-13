--- Common utility functions (2026 update: improved with better type safety)

--- Gets a handle from coordinates (creates a consistent hash)
function GetHandleFromCoords(coords)
	if not coords then return nil end
	return GetHashKey(string.format("%d_%d_%d", math.floor(coords.x * 10), math.floor(coords.y * 10), math.floor(coords.z * 10)))
end

--- Clamps a value between min and max (2026 update: better nil handling)
function Clamp(val, min, max, def)
	if not val then
		return def
	elseif val < min then
		return min
	elseif val > max then
		return max
	else
		return val
	end
end

--- Converts a table to vector3 (2026 update: added nil check)
function ToVector3(t)
	if not t then return vector3(0, 0, 0) end
	return vector3(t.x or 0, t.y or 0, t.z or 0)
end

--- Checks if two coordinates are the same entity location
function IsSameEntity(coords1, coords2)
	if not coords1 or not coords2 then return false end
	return #(coords1 - coords2) < 0.001
end

--- Gets the default media player from a list by coordinates
function GetDefaultMediaPlayer(list, coords)
	if not list or not coords then return nil end
	for _, mediaPlayer in ipairs(list) do
		if mediaPlayer and mediaPlayer.position and IsSameEntity(coords, mediaPlayer.position) then
			return mediaPlayer
		end
	end
	return nil
end
