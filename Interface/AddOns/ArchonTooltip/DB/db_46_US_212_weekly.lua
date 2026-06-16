local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Mage-Frost','Warrior-Protection','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Holy','Druid-Restoration','Druid-Guardian','Hunter-BeastMastery','DemonHunter-Havoc','Hunter-Survival','DemonHunter-Devourer','Shaman-Restoration','Evoker-Preservation','Monk-Mistweaver','Hunter-Marksmanship','Warlock-Destruction','Warrior-Arms','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Rogue-Subtlety','Warlock-Demonology',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=46,date='2026-06-14',data={Ab='Abuna:BAABLgAECn8hAAIBAAkJ4hKPYgCqAQABAAkJ4hKPYgCqAQAAAA==.',
Ad='Adreni:BAAALgADCgUJBQAAAA==.',
Ae='Aelzia:BAAALgAECgMJBwAAAA==.Aennivan:BAAALgADCgcJBwABLgAECgUJEQACAAAAAA==.Aestia:BAAALgAECgUJEAAAAA==.',
Al='Alfarin:BAAALgAECgEJAQAAAA==.Aljern:BAAALgAECgkJCwAAAA==.Alpha:BAAALgAECgYJBwAAAA==.Alysra:BAAALgADCgUJBQABLgAFFAgJIAADADsfAA==.',
Am='Ammogal:BAAALgAECgYJCQAAAA==.',
An='Anakin:BAAALgAECgMJAwAAAA==.Andyson:BAAALgAECgMJCAAAAA==.Antandra:BAAALgAECgYJEwAAAA==.Anwen:BAABLgAECn8nAAIEAAkJiRfgNABDAgAEAAkJiRfgNABDAgAAAA==.',
Ar='Arawen:BAAALgAECgQJBgABLgAECgkJJwAEAIkXAA==.Arkol:BAAALgADCgYJCAAAAA==.Artinash:BAAALgAECgUJBQAAAA==.',
As='Asha:BAABLgAFFH8FAAIFAAUJYwhPGwC3AAAFAAUJYwhPGwC3AAAAAA==.',
Av='Avadrea:BAAALgADCgEJAQAAAA==.Aválánche:BAAALgADCgEJAQAAAA==.',
Ay='Ayanea:BAABLgAECn8oAAQGAAkJVCL5CgC/AgAGAAkJOiH5CgC/AgAHAAIJvCRzWwDGAAAIAAQJTw+uXgCaAAAAAA==.Aysá:BAAALgADCgMJBQAAAA==.',
Ba='Baberaham:BAABLgAECn8nAAQJAAcJpQVaIQDBAAAKAAcJogMf5wDJAAAJAAYJUgZaIQDBAAALAAEJhATQYgAiAAAAAA==.Baiford:BAABLgAECn8pAAMMAAkJIRGpJwDMAQAMAAkJIRGpJwDMAQABAAkJGgrJfABzAQAAAA==.Baldie:BAAALgADCgEJAQAAAA==.Batteries:BAABLgAECn8WAAIBAAYJ0QOqEQGhAAABAAYJ0QOqEQGhAAAAAA==.',
Be='Bearitto:BAABLgAECn83AAINAAgJmSJJCwAIAwANAAgJmSJJCwAIAwAAAA==.',
Bi='Bigpony:BAAALgADCgYJCAAAAA==.',
Bl='Bloodrain:BAAALgADCgYJBgAAAA==.',
Bo='Bobsan:BAAALgAECgQJBAAAAA==.',
Br='Breyvarian:BAAALgADCgUJBQAAAA==.Broland:BAABLgAECn8YAAIIAAkJTAkbNABIAQAIAAkJTAkbNABIAQAAAA==.',
Bu='Burningvoker:BAAALgADCgYJBgAAAA==.',
['Bå']='Bånduri:BAAALgADCgQJBAAAAA==.',
Ca='Caitycat:BAABLgAECn8gAAINAAkJdBSgJAAkAgANAAkJdBSgJAAkAgAAAA==.Calliopê:BAABLgAECn8gAAINAAgJ5BngHQBVAgANAAgJ5BngHQBVAgAAAA==.Candycane:BAAALgADCgQJBAAAAA==.Carabina:BAAALgADCgYJBQAAAA==.Casseopea:BAAALgADCgYJCQABLgAECgMJDAACAAAAAA==.Cathelsun:BAAALgAECgYJDQAAAA==.Catherinn:BAAALgAECgUJBQAAAA==.Cattlock:BAAALgAECgQJDwAAAA==.',
Ch='Chaltin:BAAALgAECgMJAwAAAA==.Chillhunt:BAAALgADCgIJAgAAAA==.',
Cl='Clyysa:BAAALgAECgEJAQAAAA==.',
Co='Coldhand:BAAALgAECgkJBgAAAA==.Colë:BAABLgAECn8jAAIOAAkJQReVDQAGAgAOAAkJQReVDQAGAgAAAA==.Conocobhar:BAABLgAECn8hAAIPAAkJ7xzyHwBlAgAPAAkJ7xzyHwBlAgAAAA==.',
['Cæ']='Cærus:BAAALgAECgYJBgABLgAFFAgJHQAIAFgUAA==.',
Da='Daedrina:BAAALgADCgMJAwAAAA==.Dajoji:BAAALgAECgEJAgAAAA==.Dalkrim:BAABLgAECn8mAAILAAkJAyClCACIAgALAAkJAyClCACIAgAAAA==.',
De='Deadblanchy:BAAALgADCgIJAgAAAA==.Debboi:BAAALgADCgUJBQAAAA==.Deluthor:BAAALgAECgEJAQAAAA==.Demondány:BAAALgADCgEJAQAAAA==.Denzel:BAAALgAECgYJBQAAAA==.Derrick:BAABLgAECn8XAAIQAAcJ+gm8MgDzAAAQAAcJ+gm8MgDzAAAAAA==.Desol:BAAALgADCgEJAQAAAA==.Destrya:BAABLgAECn8oAAIFAAkJDiFJBgCnAgAFAAkJDiFJBgCnAgAAAA==.',
Di='Diamondhoof:BAAALgADCgcJCQAAAA==.Dibbsette:BAABLgAECn8mAAMGAAkJBh61HQDfAQAGAAkJBh61HQDfAQAIAAkJIA+xIgCyAQAAAA==.Dibbsonious:BAAALgADCgQJBAAAAA==.',
Do='Douber:BAAALgADCgYJCAAAAA==.',
Dr='Drosera:BAAALgADCgcJCQAAAA==.',
Ds='Dshiznit:BAAALgAECgcJCwABLgAECggJIAANAOQZAA==.',
Dw='Dwamli:BAAALgAECgUJEQAAAA==.',
Dy='Dynamitedave:BAAALgAECgUJDAABLgAECgYJFwARAJ0YAA==.',
['Dø']='Dømino:BAABLgAECn8oAAIRAAYJFhfEJgBpAQARAAYJFhfEJgBpAQAAAA==.',
Eb='Ebolabeef:BAABLgAECn8hAAIKAAgJPCW/HgCOAgAKAAgJPCW/HgCOAgAAAA==.',
Ei='Eirlys:BAAALgAECggJEgAAAA==.',
El='Elky:BAAALgADCgkJHAABLgAECgUJEwACAAAAAA==.Elìyon:BAABLgAECn9BAAMSAAkJwhSiMAABAgASAAkJwhSiMAABAgAQAAEJoQExfQAiAAAAAA==.',
Es='Espyvon:BAAALgADCgQJBAAAAA==.',
Et='Eternalay:BAAALgAECgYJDAAAAA==.Eternalist:BAAALgAECgMJBAAAAA==.Eternshot:BAAALgADCgEJAQAAAA==.Eternsword:BAAALgADCgYJBgAAAA==.',
Ev='Evelanara:BAAALgADCgUJBQAAAA==.Evelinnia:BAAALgADCgMJBQAAAA==.Evilmurkii:BAAALgAECgEJBgABLgAFFAIJBgABAHUUAA==.Evilssoul:BAAALgAECgQJBAAAAA==.',
Fe='Feltsmer:BAAALgADCgYJCQAAAA==.Fenira:BAAALgAECgEJAQAAAA==.',
Fo='Foscora:BAAALgAECgEJAQAAAA==.',
Fr='Frushy:BAAALgAECgEJAQAAAA==.',
Fu='Fugu:BAAALgADCggJEQAAAA==.',
Ga='Gannicûs:BAAALgAECgYJBwAAAA==.Garlando:BAAALgAECgEJAQAAAA==.',
Gi='Girly:BAAALgAECgEJAQABLgAECgUJEwACAAAAAA==.',
Go='Goatmommy:BAABLgAECn8eAAITAAYJEBWaUQBpAQATAAYJEBWaUQBpAQAAAA==.Goph:BAAALgADCgMJBQAAAA==.Goremnar:BAAALgADCgYJBgAAAA==.',
Gr='Grimmfury:BAAALgAECgMJDAAAAA==.Grimmtide:BAAALgADCgYJBgAAAA==.Grolgor:BAAALgADCgQJBAAAAA==.Grïffïth:BAACLgAFFH8hAAMBAAgJexhiAwC/AQABAAcJShZiAwC/AQAMAAEJ2ADBHABGAAAuAAQKfy4AAwEACQmOIRoPABUDAAEACQmOIRoPABUDAAwABglLD2lHAFoBAAAA.',
Gu='Gunjir:BAAALgAECgQJCwAAAA==.',
Gw='Gwyneira:BAAALgAECgYJDwABLgAECggJEgACAAAAAA==.',
Ha='Haranbush:BAAALgADCgYJBgAAAA==.Hazellok:BAAALgAECgMJAwAAAA==.',
He='Helloween:BAAALgAECgMJAQAAAA==.',
Hi='Hipidipi:BAAALgADCgUJBQAAAA==.',
Ho='Honeysuckles:BAAALgAECgQJBQAAAA==.',
Hu='Hucklebeary:BAAALgAECgQJCgAAAA==.Hugcubs:BAAALgADCgUJBQAAAA==.',
['Hí']='Hítgirl:BAAALgAECgUJDAAAAA==.',
Ic='Icylilith:BAAALgADCgYJCQAAAA==.',
Im='Imugi:BAABLgAECn8mAAIUAAkJ7AeKFwBVAQAUAAkJ7AeKFwBVAQAAAA==.',
Ir='Irithia:BAAALgAECgEJAQAAAA==.',
Is='Ishamael:BAAALgAECgMJAwABLgAECgcJKAAVAOMhAA==.Issavanos:BAAALgAECgYJEAAAAA==.',
Ja='Japopo:BAAALgAECgMJAwABLgAECgUJEQACAAAAAA==.Jazmane:BAAALgADCgYJBgAAAA==.',
Je='Jendruid:BAAALgADCgcJBwAAAA==.Jenhoney:BAAALgAECgMJDAAAAA==.Jes:BAAALgADCgEJAQAAAA==.Jessdarklord:BAAALgAECgQJAwAAAA==.',
Jo='Josh:BAAALgAECgYJCQABLgAFFAYJDAAWAOcTAA==.',
Ka='Kaliya:BAAALgAECgQJCQAAAA==.Kashar:BAAALgADCgQJBAAAAA==.',
Ke='Keltro:BAAALgADCgcJBwABLgAECgUJEwACAAAAAA==.Ketna:BAAALgAECgMJAwAAAA==.Kevdog:BAABLgAECn8hAAIXAAkJZRE4CgCeAQAXAAkJZRE4CgCeAQAAAA==.',
Kh='Khelemarth:BAAALgAECgEJBwAAAA==.',
Ki='Kire:BAABLgAECn83AAMFAAkJKyIZBADoAgAFAAkJKyIZBADoAgAYAAEJ0Q7MQAA3AAAAAA==.Kirohan:BAABLgAECn8YAAIBAAcJihLOhABkAQABAAcJihLOhABkAQAAAA==.',
Ko='Kobellr:BAAALgADCgUJBQAAAA==.Koldov:BAAALgAECgEJAQAAAA==.Kosmik:BAAALgADCgcJCwAAAA==.',
Kr='Kremm:BAAALgADCgMJBQABLgAECgMJAwACAAAAAA==.Krimzin:BAAALgAFFAEJAQABLgAFFAUJGgAPADAhAA==.',
Ku='Kuiu:BAAALgADCgEJAQAAAA==.Kulnurayne:BAAALgADCgcJDAAAAA==.Kuna:BAAALgAECgYJDQAAAA==.Kushta:BAABLgAECn8YAAIBAAgJix0NGQDTAgABAAgJix0NGQDTAgAAAA==.',
La='Lackjaw:BAABLgAECn8aAAIXAAgJUA73EQC8AQAXAAgJUA73EQC8AQAAAA==.Landrick:BAACLgAFFH8eAAILAAUJqBKQHQD2AAALAAUJqBKQHQD2AAAuAAQKfzYAAgsACQlJGvUQAPoBAAsACQlJGvUQAPoBAAAA.Lanejack:BAAALgADCgUJCAAAAA==.Larissah:BAEBLgAECn8gAAIIAAkJqhMAHADkAQAIAAkJqhMAHADkAQAAAA==.Lava:BAAALgAECggJDwAAAA==.',
Lg='Lgang:BAABLgAECn8VAAIQAAYJ5gqIPAANAQAQAAYJ5gqIPAANAQAAAA==.',
Li='Lifeblõõm:BAABLgAECn8aAAMNAAkJPB+WCgARAwANAAkJPB+WCgARAwADAAIJjA6xjgAvAAAAAA==.Lilium:BAAALgAECgYJBgAAAA==.',
Ll='Llau:BAABLgAECn9GAAMVAAkJZyLWAwB4AwAVAAkJZyLWAwB4AwAZAAEJpAYorwAlAAAAAA==.',
Lo='Longbow:BAAALgAFFAIJAgAAAA==.Losia:BAAALgAECgUJEwAAAA==.Loveinvain:BAAALgAECgMJAgAAAA==.',
Lu='Lunabun:BAAALgADCgcJEwAAAA==.',
['Lû']='Lûffy:BAAALgAECgkJCQAAAA==.',
Ma='Mahina:BAAALgAECgUJCgAAAA==.Malorn:BAABLgAECn82AAQZAAkJFR7sBwDHAgAZAAkJFR7sBwDHAgAVAAYJIROIQABmAQAaAAgJvhHdQAD1AAAAAA==.Manaaddict:BAAALgAECgYJBgAAAA==.Manbeerpig:BAAALgAECgEJAQAAAA==.Matore:BAAALgAECgYJBwAAAA==.Mavimus:BAAALgAECgEJAQAAAA==.',
Mi='Midníght:BAAALgAECgIJAgABLgAECgUJEwACAAAAAA==.',
Mo='Moltencarl:BAAALgAECgEJAgAAAA==.',
My='Myrna:BAAALgAECgMJAwAAAA==.',
Na='Naranir:BAAALgAECgEJAQAAAA==.Nasher:BAAALgAECgEJAQAAAA==.',
Ni='Niege:BAAALgAECgYJDwAAAA==.Niiso:BAAALgAECgMJAwAAAA==.Nivas:BAAALgADCgIJAgABLgAECgkJNgAZABUeAA==.Nivina:BAAALgADCgcJBwAAAA==.',
Nk='Nkagnyto:BAABLgAECn8VAAMaAAUJCBCoUQC6AAAaAAUJCBCoUQC6AAAZAAQJxwwcaACCAAAAAA==.Nkanue:BAAALgADCgIJAgABLgAECgUJFQAaAAgQAA==.',
No='Noonstalker:BAAALgAECgYJEQAAAA==.',
Nu='Nuadi:BAAALgADCgcJDQAAAA==.',
Or='Oric:BAAALgADCgMJAwABLgAECggJIAAbAD4PAA==.Orintaar:BAAALgADCgMJAwAAAA==.Ormac:BAAALgAECgYJEwAAAA==.Ororoe:BAACLgAFFH8MAAMaAAMJIxMHNQDQAAAaAAMJIxMHNQDQAAAZAAEJCAgLRQAzAAAuAAQKfykAAxoACQk4GmsUAGsCABoACAnNGmsUAGsCABkACQkOEj8eALkBAAAA.Orphancalf:BAAALgAECgIJAgAAAA==.',
Ow='Owlmel:BAAALgAECgYJBgAAAA==.',
Pa='Palapo:BAAALgAECgUJEQAAAA==.Panrocktar:BAAALgADCgEJAQAAAA==.Paudrig:BAABLgAECn8lAAMMAAYJoBjoLwCZAQAMAAYJoBjoLwCZAQABAAYJHguV0QDvAAAAAA==.Pawdrig:BAAALgAECggJDAAAAA==.',
Pe='Penicilin:BAAALgAECgUJBQAAAA==.Perfect:BAAALgAECgQJBgAAAA==.',
Ph='Phagetouched:BAAALgAECgYJDQAAAA==.Phaydre:BAAALgAECgYJEgABLgAFFAYJDgAUAGcOAA==.',
Pi='Picklenick:BAABLgAECn8lAAIcAAkJ4BS/EwADAgAcAAkJ4BS/EwADAgAAAA==.',
Po='Ponyhunts:BAAALgAECgQJBAAAAA==.Ponytree:BAABLgAECn8aAAQNAAkJbAS9dADVAAANAAkJbAS9dADVAAADAAEJzwEijwAdAAAOAAIJkAJ5NgAcAAAAAA==.Porani:BAAALgAECgQJBQAAAA==.',
Pr='Primal:BAAALgAECgEJAQAAAA==.Prismo:BAAALgAFFAIJBAAAAA==.Prognosis:BAAALgADCgcJBwAAAA==.',
Ps='Psychlonem:BAAALgAECgIJAQAAAA==.',
Pw='Pwnbuggy:BAABLgAECn8gAAIKAAgJEhiQVwC9AQAKAAgJEhiQVwC9AQAAAA==.',
Qa='Qartoga:BAAALgAECgUJBgABLgAECgYJDQACAAAAAA==.',
Ql='Qlue:BAAALgAECgEJAQAAAA==.',
Qu='Quiin:BAAALgADCgQJBQAAAA==.',
Ra='Rabellious:BAAALgAECgQJBQAAAA==.Rabin:BAAALgADCgIJAgAAAA==.Racistgreen:BAAALgAECgIJAgAAAA==.Raethys:BAAALgADCgUJBQAAAA==.Rafikibull:BAAALgAECgIJBQAAAA==.Raindrop:BAABLgAECn8sAAINAAkJbhjdGgBsAgANAAkJbhjdGgBsAgAAAA==.Ramah:BAAALgAECgUJEwAAAA==.Ramen:BAAALgADCgEJAQAAAA==.',
Re='Reignstorm:BAABLgAECn8hAAIJAAkJfgu5EwA+AQAJAAkJfgu5EwA+AQAAAA==.Reivax:BAABLgAECn9CAAIPAAkJABiuJQBIAgAPAAkJABiuJQBIAgAAAA==.Renjiyomo:BAAALgAECgYJBgAAAA==.Rethelm:BAAALgAECgYJEwAAAA==.Retreats:BAAALgADCgUJBQAAAA==.Retsella:BAAALgADCgkJIgAAAA==.Reveum:BAABLgAECn8+AAMFAAgJlw0nHgBBAQAFAAgJlw0nHgBBAQAYAAYJXwtKOgDYAAAAAA==.Revân:BAAALgAECggJDQAAAA==.',
Rh='Rhaegár:BAABLgAECn8ZAAISAAYJFhS3eAAsAQASAAYJFhS3eAAsAQAAAA==.',
Ro='Robyerto:BAAALgADCgMJAwAAAA==.Rogl:BAACLgAFFH8QAAINAAcJHCF3BgCXAgANAAcJHCF3BgCXAgAuAAQKfx0AAg0ABwkbIFEcAFoCAA0ABwkbIFEcAFoCAAAA.Rosgard:BAAALgADCggJCAAAAA==.',
Ru='Ruffruff:BAAALgAECgkJBgAAAA==.Ruhll:BAAALgAECgQJBwAAAA==.Ruminate:BAAALgADCggJDgABLgAECgUJEwACAAAAAA==.Rustychi:BAABLgAECn8VAAIZAAYJdw1ERQDoAAAZAAYJdw1ERQDoAAAAAA==.',
['Rá']='Rámpapi:BAABLgAECn8eAAIaAAYJQhyHIQCaAQAaAAYJQhyHIQCaAQAAAA==.',
Sa='Sammaile:BAABLgAECn8oAAIVAAcJ4yEOEgCLAgAVAAcJ4yEOEgCLAgAAAA==.Sarahsmith:BAABLgAECn8eAAIdAAcJWgTQugDUAAAdAAcJWgTQugDUAAAAAA==.Saucypeach:BAAALgAECgYJDQAAAA==.',
Sc='Scamander:BAABLgAECn8WAAIPAAkJDxYTJgAiAgAPAAkJDxYTJgAiAgAAAA==.Scarmouse:BAAALgAECgEJAQAAAA==.',
Se='Seifer:BAAALgADCgkJJQAAAA==.Semnickmonk:BAAALgAECgMJBAAAAA==.Senjosaku:BAABLgAECn8YAAIBAAgJCSRLFgC8AgABAAgJCSRLFgC8AgABLgAFFAUJGQAEAGIcAA==.Serigo:BAABLgAECn8ZAAIEAAYJtw0IwAAHAQAEAAYJtw0IwAAHAQAAAA==.Serral:BAAALgAFFAEJAQAAAA==.',
Sh='Shaxx:BAAALgAECgIJAgABLgAECgYJGQAEALcNAA==.Shellshocked:BAAALgADCgkJDwAAAA==.',
Sk='Skayley:BAAALgADCgUJBQAAAA==.',
Sm='Smoochy:BAAALgAECgEJAQAAAA==.',
Sn='Sneknyto:BAAALgAECgMJAwAAAA==.',
So='Solysz:BAAALgAECgYJEwAAAA==.Sophietheone:BAAALgADCgIJAgAAAA==.Soten:BAAALgAECgMJAwABLgAECgUJEwACAAAAAA==.Soß:BAACLgAFFH8VAAIEAAQJKRuJQQBrAQAEAAQJKRuJQQBrAQAuAAQKfyEAAgQABwnPIZxSAEACAAQABwnPIZxSAEACAAAA.',
Sp='Spongébob:BAAALgAECgIJAgAAAA==.Spork:BAAALgAECgUJEwAAAA==.',
St='Stimcheck:BAAALgADCgcJBwABLgADCggJCAACAAAAAA==.Stmary:BAAALgADCgQJBAAAAA==.Stormm:BAAALgAECgYJBgAAAA==.Størmzmisery:BAAALgAECgcJCAAAAA==.',
Su='Subzéro:BAABLgAECn8lAAIEAAgJqwwwhgBoAQAEAAgJqwwwhgBoAQAAAA==.',
Sw='Sweetwhisper:BAABLgAECn8YAAMNAAkJThG6MgDSAQANAAkJThG6MgDSAQADAAMJZAjLaQB1AAAAAA==.',
Sy='Sylitae:BAAALgAECgEJAQAAAA==.',
['Så']='Såbëtha:BAAALgADCgMJBQAAAA==.',
Ta='Tahuu:BAAALgADCgUJBAABLgAECgYJFQAMAIUUAA==.Tazzen:BAAALgAECgQJBQAAAA==.',
Te='Teletern:BAAALgADCgUJBwAAAA==.Tempeststørm:BAAALgAECgUJBwAAAA==.Terabythia:BAAALgAECgIJAgAAAA==.',
Th='Thaunelian:BAAALgAECgcJEwABLgAECgkJNgAZABUeAA==.Theblueguy:BAAALgADCgMJAwAAAA==.Theweirdo:BAAALgADCgYJBgAAAA==.Thoristain:BAABLgAECn8gAAIbAAgJPg/SGQBIAQAbAAgJPg/SGQBIAQAAAA==.Thorshman:BAAALgAECgMJAwABLgAECggJIAAbAD4PAA==.Thrain:BAABLgAECn8uAAIBAAkJiQ0gawCXAQABAAkJiQ0gawCXAQAAAA==.Threefive:BAAALgAECgQJBQAAAA==.Thrusher:BAAALgADCgIJAgAAAA==.',
To='Torture:BAAALgAECgEJAQAAAA==.Torvar:BAAALgADCgEJAgAAAA==.Totemíc:BAAALgAECgQJBQAAAA==.',
Tp='Tpops:BAAALgADCgQJBAAAAA==.',
Tr='Trilràq:BAAALgAECgYJBQAAAA==.',
Tu='Tulku:BAAALgADCgIJBAAAAA==.',
Ty='Tyrdrea:BAAALgADCgkJCQAAAA==.',
Va='Vallak:BAAALgAECgQJBAAAAA==.Vaqine:BAAALgAECgMJAwABLgAECgUJEwACAAAAAA==.',
Ve='Velarion:BAAALgAECgEJAQAAAA==.Veryundead:BAABLgAECn9FAAIXAAkJChjSAwBNAgAXAAkJChjSAwBNAgAAAA==.',
Vi='Viscor:BAAALgADCgEJAQAAAA==.',
Vo='Void:BAABLgAECn8aAAIQAAcJ3hZCHwB8AQAQAAcJ3hZCHwB8AQAAAA==.Voidmara:BAAALgAECgEJAwAAAA==.Voíd:BAAALgAECgEJAQAAAA==.',
Vr='Vrylykos:BAAALgAECgYJDwAAAA==.',
Vy='Vygil:BAAALgADCgQJAwAAAA==.Vyneda:BAAALgADCgUJBQABLgAECgYJFQAMAIUUAA==.',
Wa='Waddlez:BAAALgAECgEJAQAAAA==.Wardawg:BAAALgADCgEJAQABLgAECgkJKAAGAFQiAA==.Wargrylls:BAAALgADCgcJBwAAAA==.',
We='Wendrin:BAAALgAECgYJEQAAAA==.',
Wh='White:BAAALgAECgQJBwAAAA==.',
Wo='Wolvynlyfe:BAAALgADCgIJAgAAAA==.',
Xa='Xanarine:BAABLgAECn8VAAMMAAYJhRQvRABnAQAMAAYJhRQvRABnAQABAAIJtQdHIQFbAAAAAA==.Xavíous:BAAALgADCgYJBgAAAA==.',
Xe='Xeeva:BAABLgAECn8YAAITAAYJzxWrTwBwAQATAAYJzxWrTwBwAQAAAA==.',
Xu='Xuralxia:BAAALgAECgEJBgAAAA==.',
Yz='Yzinia:BAAALgADCgMJAwAAAA==.',
Zi='Zink:BAAALgAECgEJAQAAAA==.Ziyad:BAABLgAECn8aAAQDAAkJdhEbJACmAQADAAkJnA8bJACmAQAOAAMJwxMIIQCWAAANAAEJLgei6AAjAAAAAA==.',
Zy='Zyla:BAAALgAECgUJBQAAAA==.Zyn:BAAALgAECgUJEAAAAA==.',
['Zè']='Zèró:BAABLgAECn8WAAMbAAYJnBwkGABaAQAbAAYJnBwkGABaAQABAAIJPxBKOQFvAAAAAA==.',
['Ðü']='Ðüß:BAAALgADCgIJAgABLgAECgMJAwACAAAAAA==.',
['Ön']='Öna:BAABLgAECn89AAIPAAkJ8BpKGgCEAgAPAAkJ8BpKGgCEAgAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
