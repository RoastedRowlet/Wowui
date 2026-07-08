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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Hunter-BeastMastery','Druid-Balance','Mage-Frost','Warrior-Protection','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Holy','Warrior-Arms','Druid-Restoration','Druid-Guardian','DemonHunter-Havoc','Hunter-Survival','Shaman-Restoration','DemonHunter-Devourer','Evoker-Preservation','Monk-Mistweaver','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','Monk-Windwalker','Monk-Brewmaster','Rogue-Subtlety','Warlock-Demonology',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abuna:BAABLgAECn8hAAIBAAkJ4hJiYwCpAQABAAkJ4hJiYwCpAQAAAA==.',
Ac='Acidia:BAAALgAECgQJBAAAAA==.',
Ad='Adreni:BAAALgADCgUJBQAAAA==.',
Ae='Aelzia:BAAALgAECgMJBwAAAA==.Aennivan:BAAALgADCgcJBwABLgAECgcJEwACAAAAAA==.Aestia:BAABLgAECn8WAAIDAAcJpgmsFQDKAAADAAcJpgmsFQDKAAAAAA==.',
Al='Alfarin:BAAALgAECgEJAQAAAA==.Aljern:BAAALgAECgkJCwAAAA==.Alpha:BAAALgAECgYJBwAAAA==.Alysra:BAAALgADCgUJBQABLgAFFAkJJQAEAAgeAA==.',
Am='Ammogal:BAAALgAECgYJCQAAAA==.',
An='Anakin:BAAALgAECgQJBAAAAA==.Andyson:BAAALgAECgMJCAAAAA==.Antandra:BAAALgAECgYJEwAAAA==.Anwen:BAABLgAECn8nAAIFAAkJiRdyNQBDAgAFAAkJiRdyNQBDAgAAAA==.',
Ar='Arawen:BAAALgAECgQJBgABLgAECgkJJwAFAIkXAA==.Arkol:BAAALgADCgYJCAAAAA==.Artinash:BAAALgAECgUJBQAAAA==.',
As='Asha:BAABLgAFFH8GAAIGAAYJAAcOHAC3AAAGAAYJAAcOHAC3AAAAAA==.',
Av='Avadrea:BAAALgADCgEJAQAAAA==.Aválánche:BAAALgADCgEJAQAAAA==.',
Ay='Ayanea:BAABLgAECn8oAAQHAAkJVCIbCwC9AgAHAAkJOiEbCwC9AgAIAAIJvCRzWwDGAAAJAAQJTw/HXwCZAAAAAA==.Aysá:BAAALgADCgMJBQAAAA==.',
Ba='Baberaham:BAABLgAECn8nAAQKAAcJpQUGIgC+AAALAAcJogMd6gDIAAAKAAYJUgYGIgC+AAAMAAEJhATLYwAiAAAAAA==.Baiford:BAABLgAECn8pAAMNAAkJIRFCKADJAQANAAkJIRFCKADJAQABAAkJGgo8fwBwAQAAAA==.Baldie:BAAALgADCgEJAQAAAA==.Batteries:BAABLgAECn8dAAIBAAYJ1gRPIAB5AAABAAYJ1gRPIAB5AAAAAA==.',
Be='Bear:BAABLgAFFH8IAAIOAAUJnxjhBABQAQAOAAUJnxjhBABQAQAAAA==.Bearitto:BAABLgAECn83AAIPAAgJmSJcFACnAgAPAAgJmSJcFACnAgAAAA==.',
Bi='Bibbly:BAAALgADCgIJAgAAAA==.Bigpony:BAAALgADCgYJCAAAAA==.',
Bl='Blightmaker:BAAALgAECgEJAQAAAA==.Bloodrain:BAAALgADCgYJBgAAAA==.',
Bo='Bobsan:BAAALgAECgQJBAAAAA==.',
Br='Breyvarian:BAAALgADCgUJBQAAAA==.Broland:BAABLgAECn8YAAIJAAkJTAlUNQBCAQAJAAkJTAlUNQBCAQAAAA==.',
Bu='Burningvoker:BAAALgADCgYJBgAAAA==.',
['Bå']='Bånduri:BAAALgADCgQJBAAAAA==.',
Ca='Caitycat:BAABLgAECn8gAAIPAAkJdBTuJAAlAgAPAAkJdBTuJAAlAgAAAA==.Calliopê:BAABLgAECn8iAAIPAAkJbRknHgBVAgAPAAkJbRknHgBVAgAAAA==.Candycane:BAAALgADCgQJBAAAAA==.Carabina:BAAALgADCgYJBQAAAA==.Casseopea:BAAALgADCgYJCQABLgAECgMJDAACAAAAAA==.Cathelsun:BAAALgAECgYJDQAAAA==.Catherinn:BAAALgAECgUJBQAAAA==.Cattlock:BAAALgAECgQJEQAAAA==.',
Ch='Chadwick:BAAALgAECgkJAgAAAA==.Chaltin:BAAALgAECgMJAwAAAA==.Chillhunt:BAAALgADCgIJAgAAAA==.',
Cl='Clyysa:BAAALgAECgEJAQAAAA==.',
Co='Colë:BAABLgAECn8kAAIQAAkJQRfJDQAGAgAQAAkJQRfJDQAGAgAAAA==.Conocobhar:BAABLgAECn8hAAIDAAkJ7xyRIABkAgADAAkJ7xyRIABkAgAAAA==.',
['Cæ']='Cærus:BAAALgAECgYJBgABLgAFFAgJIQAJAFgUAA==.',
Da='Daedrina:BAAALgADCgMJAwAAAA==.Dajoji:BAAALgAECgEJAgAAAA==.Dalkrim:BAABLgAECn8mAAIMAAkJAyDPCACHAgAMAAkJAyDPCACHAgAAAA==.',
De='Deadblanchy:BAAALgADCgIJAgAAAA==.Debboi:BAAALgADCgUJBQAAAA==.Deluthor:BAAALgAECgEJAQAAAA==.Demondány:BAAALgADCgEJAQAAAA==.Denzel:BAAALgAECgYJBQAAAA==.Derrick:BAABLgAECn8XAAIRAAcJ+gmFMwDzAAARAAcJ+gmFMwDzAAAAAA==.Desol:BAAALgADCgEJAQAAAA==.Destrya:BAABLgAECn8oAAIGAAkJDiFjBgCmAgAGAAkJDiFjBgCmAgAAAA==.',
Di='Diamondhoof:BAAALgADCgcJCQAAAA==.Dibbsette:BAABLgAECn8mAAMHAAkJBh7mHQDeAQAHAAkJBh7mHQDeAQAJAAkJIA9+IwCtAQAAAA==.Dibbsonious:BAAALgADCgQJBAAAAA==.',
Do='Douber:BAAALgADCgYJCAAAAA==.',
Dr='Drosera:BAAALgADCgcJCQAAAA==.',
Ds='Dshiznit:BAAALgAECgcJDAABLgAECgkJIgAPAG0ZAA==.',
Dw='Dwamli:BAAALgAECgUJEQAAAA==.',
Dy='Dynamitedave:BAAALgAECggJDwAAAA==.',
['Dø']='Dømino:BAABLgAECn8sAAISAAYJIhe+AwD5AAASAAYJIhe+AwD5AAAAAA==.',
Eb='Ebolabeef:BAABLgAECn8hAAILAAgJPCUqHwCNAgALAAgJPCUqHwCNAgAAAA==.',
Ei='Eirlys:BAABLgAECn8aAAIFAAkJIQ+mCABnAQAFAAkJIQ+mCABnAQAAAA==.',
El='Elky:BAAALgADCgkJHAABLgAECgYJGAATAE8ZAA==.Elìyon:BAABLgAECn9BAAMUAAkJwhQeMQACAgAUAAkJwhQeMQACAgARAAEJoQExfQAiAAAAAA==.',
Es='Espyvon:BAAALgADCgQJBAAAAA==.',
Et='Eternalay:BAAALgAECgYJDAAAAA==.Eternalist:BAAALgAECgMJBAAAAA==.Eternshot:BAAALgADCgEJAQAAAA==.Eternsword:BAAALgADCgYJBgAAAA==.',
Ev='Evelanara:BAAALgADCgUJBQAAAA==.Evelinnia:BAAALgADCgMJBQAAAA==.Evilmurkii:BAAALgAECgEJBgABLgAFFAIJBwABAHUUAA==.Evilssoul:BAAALgAECgQJBAAAAA==.',
Fe='Feltsmer:BAAALgADCgYJCQAAAA==.Fenira:BAAALgAECgEJAQAAAA==.',
Fo='Foscora:BAAALgAECgEJAQAAAA==.',
Fr='Frushy:BAAALgAECgEJAQAAAA==.',
Fu='Fugu:BAAALgADCggJEQAAAA==.',
Ga='Gannicûs:BAAALgAECgYJBwAAAA==.Garlando:BAAALgAECgEJAQAAAA==.',
Gi='Girly:BAAALgAECgEJAQABLgAECgYJGAATAE8ZAA==.',
Go='Goatmommy:BAABLgAECn8jAAITAAYJDRn/BgBSAQATAAYJDRn/BgBSAQAAAA==.Goph:BAAALgADCgMJBQAAAA==.Goregrind:BAAALgADCgUJBQAAAA==.Goremnar:BAAALgADCgYJBgAAAA==.',
Gr='Grimmfury:BAAALgAECgMJDAAAAA==.Grimmtide:BAAALgADCgYJBgAAAA==.Grolgor:BAAALgADCgQJBAAAAA==.Grïffïth:BAACLgAFFH8kAAMBAAkJHhdiAwC/AQABAAgJChViAwC/AQANAAEJ2ADBHABGAAAuAAQKfy4AAwEACQmOIRoPABUDAAEACQmOIRoPABUDAA0ABglLD2lHAFoBAAAA.',
Gu='Gunjir:BAAALgAECgQJCwAAAA==.',
Gw='Gwyneira:BAABLgAECn8YAAIFAAYJ9AonFgDBAAAFAAYJ9AonFgDBAAABLgAECgkJGgAFACEPAA==.',
Ha='Haranbush:BAAALgADCgYJBgAAAA==.Hazellok:BAAALgAECgMJBAAAAA==.',
He='Helloween:BAAALgAECgMJAQAAAA==.',
Hi='Hipidipi:BAAALgADCgUJBQAAAA==.',
Ho='Honeysuckles:BAAALgAECgQJBgAAAA==.',
Hu='Hucklebeary:BAAALgAECgQJCgAAAA==.Hugcubs:BAAALgADCgUJBQAAAA==.',
['Hí']='Hítgirl:BAAALgAECgUJDAAAAA==.',
Ic='Icylilith:BAAALgADCgYJCQAAAA==.',
Im='Imugi:BAABLgAECn8nAAIVAAkJPAi8FwBVAQAVAAkJPAi8FwBVAQAAAA==.',
Ir='Irithia:BAAALgAECgEJAQAAAA==.Iroc:BAAALgAECgEJAQAAAA==.',
Is='Ishamael:BAAALgAECgUJBgABLgAECgcJNgAWAKAjAA==.Issavanos:BAAALgAECgYJEAAAAA==.',
Ja='Japopo:BAAALgAECgMJAwABLgAECgcJEwACAAAAAA==.Jazmane:BAAALgADCgYJBgAAAA==.',
Je='Jendruid:BAAALgADCgcJBwAAAA==.Jenhoney:BAAALgAECgMJDAAAAA==.Jes:BAAALgADCgEJAQAAAA==.Jessdarklord:BAAALgAECgQJAwAAAA==.',
Jo='Josh:BAAALgAECgYJCQABLgAFFAYJDAAXAOcTAA==.',
Ka='Kaliya:BAAALgAECgQJCQAAAA==.Kashar:BAAALgADCgQJBAAAAA==.',
Ke='Keltro:BAAALgADCgcJBwABLgAECgcJGwAGAEMaAA==.Ketna:BAAALgAECgMJAwAAAA==.Kevdog:BAABLgAECn8hAAIYAAkJZRFwCgCdAQAYAAkJZRFwCgCdAQAAAA==.',
Kh='Khelemarth:BAAALgAECgYJDQAAAA==.',
Ki='Killa:BAAALgAECgYJAgAAAA==.Kire:BAABLgAECn83AAMGAAkJKyIrBADnAgAGAAkJKyIrBADnAgAOAAEJ0Q7MQAA3AAAAAA==.Kirohan:BAABLgAECn8iAAMBAAcJ6xXTCQBMAQABAAcJ6xXTCQBMAQAZAAEJ0AL7EAAUAAAAAA==.',
Ko='Kobellr:BAAALgADCgUJBQAAAA==.Koldov:BAAALgAECgEJAQAAAA==.Kosmik:BAAALgADCgcJCwAAAA==.',
Kr='Kravann:BAAALgAECgEJAQAAAA==.Kremm:BAAALgADCgMJBQABLgAECgMJAwACAAAAAA==.Krimzin:BAAALgAFFAEJAQABLgAFFAUJGwADADAhAA==.',
Ku='Kuiu:BAAALgAECgEJAQAAAA==.Kulnurayne:BAAALgADCgcJDAAAAA==.Kuna:BAAALgAECgYJDQAAAA==.Kushta:BAABLgAECn8YAAIBAAgJix0NGQDTAgABAAgJix0NGQDTAgAAAA==.',
La='Lackjaw:BAABLgAECn8aAAIYAAgJUA73EQC8AQAYAAgJUA73EQC8AQAAAA==.Landrick:BAACLgAFFH8jAAIMAAUJuxTMHgDwAAAMAAUJuxTMHgDwAAAuAAQKfzYAAgwACQlJGkMRAPgBAAwACQlJGkMRAPgBAAAA.Lanejack:BAAALgADCgUJCAAAAA==.Larissah:BAECLgAFFH8FAAIJAAQJPQnJMACDAAAJAAQJPQnJMACDAAAuAAQKfyAAAgkACQmqE10cAOIBAAkACQmqE10cAOIBAAEuAAUUBQkJAAkArg0A.Lava:BAAALgAECggJDwAAAA==.',
Lg='Lgang:BAABLgAECn8VAAIRAAYJ5gqIPAANAQARAAYJ5gqIPAANAQAAAA==.',
Li='Lichgore:BAAALgAECgEJAQAAAA==.Lifeblõõm:BAABLgAECn8aAAMPAAkJPB/ACgARAwAPAAkJPB/ACgARAwAEAAIJjA6HkAAvAAAAAA==.Lilium:BAAALgAECgYJBgAAAA==.',
Ll='Llau:BAACLgAFFH8NAAIWAAMJ3R1AEwDxAAAWAAMJ3R1AEwDxAAAuAAQKf1UAAxYACQleI74AAAcDABYACQleI74AAAcDABoAAQmkBkKxACUAAAAA.',
Lo='Longbow:BAAALgAFFAIJAgAAAA==.Losia:BAABLgAECn8XAAIHAAcJbAwqSADlAAAHAAcJbAwqSADlAAAAAA==.Lottashocks:BAAALgAECgUJBQABLgAECggJNwAPAJkiAA==.Loveinvain:BAAALgAECgMJAgAAAA==.',
Lu='Lunabun:BAAALgADCgcJEwAAAA==.',
['Lû']='Lûffy:BAAALgAECgkJCQAAAA==.',
Ma='Mahina:BAAALgAECgUJCgAAAA==.Malorn:BAABLgAECn82AAQaAAkJFR4PCADGAgAaAAkJFR4PCADGAgAWAAYJIROsQQBnAQAbAAgJvhFXQQD1AAAAAA==.Manaaddict:BAAALgAECgYJBgAAAA==.Manbeerpig:BAAALgAECgEJAQAAAA==.Matore:BAAALgAECgYJDgAAAA==.Mavimus:BAAALgAECgEJAQAAAA==.',
Mi='Midníght:BAAALgAECgYJBwABLgAECgYJGAATAE8ZAA==.',
Mo='Moltencarl:BAAALgAECgEJAgAAAA==.',
My='Myrna:BAAALgAECgMJAwAAAA==.',
['Må']='Målåchi:BAAALgAECgQJBAAAAA==.',
Na='Naranir:BAAALgAECgEJAQAAAA==.Nasher:BAAALgAECgEJAQAAAA==.',
Ni='Niege:BAABLgAECn8YAAIEAAYJkgOKDgBeAAAEAAYJkgOKDgBeAAAAAA==.Niiso:BAAALgAECgMJAwAAAA==.Nivas:BAAALgADCgIJAgABLgAECgkJNgAaABUeAA==.Nivina:BAAALgADCgcJBwAAAA==.',
Nk='Nkag:BAAALgAECgEJAQABLgAECgUJFQAbAAgQAA==.Nkagnyto:BAABLgAECn8VAAMbAAUJCBA7UgC6AAAbAAUJCBA7UgC6AAAaAAQJxwz1aQCAAAAAAA==.Nkanue:BAAALgADCgIJAgABLgAECgUJFQAbAAgQAA==.',
No='Noonstalker:BAAALgAECgYJEQAAAA==.',
Nu='Nuadi:BAAALgADCgcJFAAAAA==.',
Or='Oric:BAAALgADCgMJAwABLgAECgkJIQAZAKcPAA==.Orintaar:BAAALgADCgMJAwAAAA==.Ormac:BAAALgAECgYJEwAAAA==.Ororoe:BAACLgAFFH8XAAMaAAQJ7hKXCgC3AAAbAAQJlRFWJwALAQAaAAQJLwqXCgC3AAAuAAQKfykAAxsACQk4GmsUAGsCABsACAnNGmsUAGsCABoACQkOEs0eALYBAAAA.Orphancalf:BAAALgAECgIJAgAAAA==.',
Ow='Owlmel:BAAALgAECgYJBgAAAA==.',
Pa='Palapo:BAAALgAECgcJEwAAAA==.Panrocktar:BAAALgADCgEJAQAAAA==.Papaheals:BAAALgADCgQJBAAAAA==.Paudrig:BAABLgAECn8lAAMNAAYJoBg/MACZAQANAAYJoBg/MACZAQABAAYJHgtz1QDsAAAAAA==.Pawdrig:BAAALgAECgkJEAAAAA==.',
Pe='Penicilin:BAAALgAECgUJBQAAAA==.Perfect:BAAALgAECgQJBgAAAA==.',
Ph='Phagetouched:BAAALgAECgYJDQAAAA==.Phaydre:BAAALgAECgYJEgABLgAFFAcJEAAVAMQMAA==.',
Pi='Picklenick:BAABLgAECn8lAAIcAAkJ4BQEFAADAgAcAAkJ4BQEFAADAgAAAA==.',
Po='Ponyhunts:BAAALgAECgQJBgAAAA==.Ponytree:BAABLgAECn8aAAQPAAkJbARrdQDVAAAPAAkJbARrdQDVAAAEAAEJzwEijwAdAAAQAAIJkAJ5NgAcAAAAAA==.Porani:BAAALgAECgQJBgAAAA==.',
Pr='Predatore:BAAALgAECgYJBgAAAA==.Primal:BAAALgAECgEJAgAAAA==.Prismo:BAAALgAFFAIJBAAAAA==.Prognosis:BAAALgADCgcJBwAAAA==.',
Ps='Psychlonem:BAAALgAECgMJAwAAAA==.',
Pw='Pwnbuggy:BAABLgAECn8gAAILAAgJEhgSWQC7AQALAAgJEhgSWQC7AQAAAA==.',
Qa='Qartoga:BAAALgAECgUJBgABLgAECgYJDQACAAAAAA==.',
Ql='Qlue:BAAALgAECgEJAQAAAA==.',
Qu='Quiin:BAAALgAECgYJCQAAAA==.',
Ra='Rabellious:BAAALgAECgQJCAAAAA==.Rabin:BAAALgADCgIJAgAAAA==.Racistgreen:BAAALgAECgIJAgAAAA==.Raethys:BAAALgADCgUJBQAAAA==.Rafikibull:BAAALgAECgIJBQAAAA==.Raindrop:BAABLgAECn8sAAIPAAkJbhgsGwBsAgAPAAkJbhgsGwBsAgAAAA==.Ramah:BAABLgAECn8bAAIGAAcJQxqUAgBLAQAGAAcJQxqUAgBLAQAAAA==.Ramen:BAAALgADCgEJAQAAAA==.',
Re='Reignstorm:BAABLgAECn8hAAIKAAkJfgtQFAA6AQAKAAkJfgtQFAA6AQAAAA==.Reivax:BAABLgAECn9FAAIDAAkJ3hhNJgBIAgADAAkJ3hhNJgBIAgAAAA==.Renjiyomo:BAAALgAECgYJBgAAAA==.Rethelm:BAAALgAECgYJEwAAAA==.Retreats:BAAALgADCgUJBQAAAA==.Retsella:BAAALgADCgkJIgAAAA==.Reveum:BAABLgAECn8+AAMGAAgJlw1yHgBAAQAGAAgJlw1yHgBAAQAOAAYJXwtFOwDYAAAAAA==.Revân:BAAALgAECgkJDgAAAA==.',
Rh='Rhaegár:BAABLgAECn8ZAAIUAAYJFhTWeQAtAQAUAAYJFhTWeQAtAQAAAA==.',
Ro='Robyerto:BAAALgADCgMJAwAAAA==.Rogl:BAACLgAFFH8RAAIPAAcJHCH3BgCWAgAPAAcJHCH3BgCWAgAuAAQKfx0AAg8ABwkbIFEcAFoCAA8ABwkbIFEcAFoCAAAA.Rosgard:BAAALgADCggJCAAAAA==.',
Ru='Ruhll:BAAALgAECgQJBwAAAA==.Ruminate:BAAALgADCggJDgABLgAECgYJGAATAE8ZAA==.Rustychi:BAABLgAECn8VAAIaAAYJdw0lRgDnAAAaAAYJdw0lRgDnAAAAAA==.',
['Rá']='Rámpapi:BAABLgAECn8jAAIbAAYJmxzjAgAgAQAbAAYJmxzjAgAgAQAAAA==.',
Sa='Sammaile:BAABLgAECn82AAIWAAcJoCNOAQCEAgAWAAcJoCNOAQCEAgAAAA==.Sapient:BAAALgADCgcJDAABLgAECgYJGAATAE8ZAA==.Sarahsmith:BAABLgAECn8eAAIdAAcJWgQFvADSAAAdAAcJWgQFvADSAAAAAA==.Saucypeach:BAAALgAECgYJDQAAAA==.',
Sc='Scamander:BAABLgAECn8WAAIDAAkJDxYTJgAiAgADAAkJDxYTJgAiAgAAAA==.Scarmouse:BAAALgAECgEJAQAAAA==.',
Se='Seifer:BAAALgADCgkJJQAAAA==.Semnickmonk:BAAALgAECgMJBAAAAA==.Senjosaku:BAABLgAECn8YAAIBAAgJCSS3FgC6AgABAAgJCSS3FgC6AgABLgAFFAUJGgAFAGIcAA==.Serigo:BAABLgAECn8ZAAIFAAYJtw2dwQAHAQAFAAYJtw2dwQAHAQAAAA==.Serral:BAAALgAFFAEJAQAAAA==.',
Sh='Shaxx:BAAALgAECgIJAgABLgAECgYJGQAFALcNAA==.Shellshocked:BAAALgADCgkJDwAAAA==.',
Sk='Skayley:BAAALgADCgUJBQAAAA==.',
Sm='Smoochy:BAAALgAECgEJAQAAAA==.',
Sn='Sneknyto:BAAALgAECgMJAwAAAA==.',
So='Solysz:BAAALgAECgYJEwAAAA==.Sophietheone:BAAALgADCgIJAgAAAA==.Soten:BAAALgAECgQJBAABLgAECgcJGwAGAEMaAA==.Soß:BAACLgAFFH8VAAIFAAQJKRt8QgBmAQAFAAQJKRt8QgBmAQAuAAQKfyQAAgUABwnVITwLADoBAAUABwnVITwLADoBAAAA.',
Sp='Spongébob:BAAALgAECgIJAwAAAA==.Spork:BAABLgAECn8YAAITAAYJTxkWRgCWAQATAAYJTxkWRgCWAQAAAA==.',
St='Stimcheck:BAAALgADCgcJBwABLgADCggJCAACAAAAAA==.Stmary:BAAALgADCgQJBAAAAA==.Stormm:BAAALgAECgYJBgAAAA==.Størmzmisery:BAAALgAECgcJCAAAAA==.',
Su='Subzéro:BAABLgAECn8lAAIFAAgJqwx0hwBoAQAFAAgJqwx0hwBoAQAAAA==.',
Sw='Sweetwhisper:BAABLgAECn8YAAMPAAkJThEDMwDSAQAPAAkJThEDMwDSAQAEAAMJZAgIawB1AAAAAA==.',
Sy='Sylitae:BAAALgAECgEJAQAAAA==.',
['Så']='Såbëtha:BAAALgADCgMJBQAAAA==.',
Ta='Tahuu:BAAALgADCgUJBAABLgAECgYJFQANAIUUAA==.Tazzen:BAAALgAECgQJBQAAAA==.',
Te='Teletern:BAAALgADCgUJBwAAAA==.Tempeststørm:BAAALgAECgUJBwAAAA==.Terabythia:BAAALgAECgIJAgAAAA==.',
Th='Thaunelian:BAAALgAECgcJEwABLgAECgkJNgAaABUeAA==.Theblueguy:BAAALgADCgMJAwAAAA==.Theweirdo:BAAALgADCgYJBgAAAA==.Thoristain:BAABLgAECn8hAAIZAAkJpw8MGgBIAQAZAAkJpw8MGgBIAQAAAA==.Thorshman:BAAALgAECgMJAwABLgAECgkJIQAZAKcPAA==.Thrain:BAABLgAECn8uAAIBAAkJiQ1ebQCTAQABAAkJiQ1ebQCTAQAAAA==.Threefive:BAAALgAECgQJBQAAAA==.Thrusher:BAAALgADCgIJAgAAAA==.',
To='Torture:BAAALgAECgEJAQAAAA==.Torvar:BAAALgADCgEJAgAAAA==.Totemíc:BAAALgAECgQJBQAAAA==.',
Tp='Tpops:BAAALgADCgQJBAAAAA==.',
Tr='Trilràq:BAAALgAECgcJBQAAAA==.',
Tu='Tulku:BAAALgADCgIJBAAAAA==.',
Ty='Tyrdrea:BAAALgADCgkJCQAAAA==.',
Va='Vallak:BAAALgAECgQJBAAAAA==.Vaqine:BAAALgAECgMJAwABLgAECgYJGAATAE8ZAA==.',
Ve='Velarion:BAAALgAECgEJAQAAAA==.Veryundead:BAABLgAECn9OAAIYAAkJDhnvAwBMAgAYAAkJDhnvAwBMAgAAAA==.',
Vi='Viscor:BAAALgAECgEJAQAAAA==.',
Vo='Void:BAABLgAECn8aAAIRAAcJ3ha2HwB8AQARAAcJ3ha2HwB8AQAAAA==.Voidmara:BAAALgAECgEJAwAAAA==.Voíd:BAAALgAECgEJAQAAAA==.',
Vr='Vrylykos:BAABLgAECn8YAAIMAAYJNxXqAwAaAQAMAAYJNxXqAwAaAQAAAA==.',
Vy='Vygil:BAAALgADCgQJAwAAAA==.Vyneda:BAAALgADCgUJBQABLgAECgYJFQANAIUUAA==.',
Wa='Waddlez:BAAALgAECgEJAQAAAA==.Wardawg:BAAALgADCgEJAQABLgAECgkJKAAHAFQiAA==.Wargrylls:BAAALgADCgcJBwAAAA==.',
We='Wendrin:BAABLgAECn8aAAIHAAYJ3gN5CwCZAAAHAAYJ3gN5CwCZAAAAAA==.',
Wh='White:BAAALgAECgQJBwAAAA==.',
Wo='Wolvynlyfe:BAAALgADCgIJAgAAAA==.',
Xa='Xanarine:BAABLgAECn8VAAMNAAYJhRQvRABnAQANAAYJhRQvRABnAQABAAIJtQdHIQFbAAAAAA==.Xavíous:BAAALgADCgYJBgAAAA==.',
Xe='Xeeva:BAABLgAECn8ZAAITAAcJCRSWUABwAQATAAcJCRSWUABwAQAAAA==.',
Xu='Xuralxia:BAAALgAECgEJBgAAAA==.',
Yz='Yzinia:BAAALgADCgMJAwAAAA==.',
Zi='Zink:BAAALgAECgEJAQAAAA==.Ziyad:BAABLgAECn8aAAQEAAkJdhGFJACnAQAEAAkJnA+FJACnAQAQAAMJwxMIIQCWAAAPAAEJLgde6gAjAAAAAA==.',
Zy='Zyla:BAAALgAECgYJBgAAAA==.Zyn:BAABLgAECn8YAAIZAAcJdwyXBADYAAAZAAcJdwyXBADYAAAAAA==.',
['Zè']='Zèró:BAABLgAECn8WAAMZAAYJnBxdGABaAQAZAAYJnBxdGABaAQABAAIJPxCpPAFvAAAAAA==.',
['Ðü']='Ðüß:BAAALgADCgIJAgABLgAECgMJAwACAAAAAA==.',
['Ön']='Öna:BAABLgAECn9BAAIDAAkJ8Br2GgCDAgADAAkJ8Br2GgCDAgAAAA==.',
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
