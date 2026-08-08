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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Hunter-BeastMastery','Druid-Balance','Mage-Frost','Warrior-Protection','Monk-Mistweaver','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Holy','Warrior-Arms','Druid-Restoration','Druid-Guardian','DemonHunter-Havoc','Hunter-Survival','Shaman-Restoration','DemonHunter-Devourer','Evoker-Preservation','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','Monk-Windwalker','Monk-Brewmaster','Rogue-Subtlety','Warlock-Demonology',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abuna:BAABLgAECn8hAAIBAAkJ4hJiYwCpAQABAAkJ4hJiYwCpAQAAAA==.',
Ac='Acidia:BAAALgAECgcJCQAAAA==.',
Ad='Adreni:BAAALgADCgUJBQAAAA==.',
Ae='Aelzia:BAAALgAECgMJBwAAAA==.Aennivan:BAAALgADCgcJBwABLgAECgcJEwACAAAAAA==.Aestia:BAABLgAECn8aAAIDAAcJxQkmIQDQAAADAAcJxQkmIQDQAAAAAA==.',
Al='Alfarin:BAAALgAECgEJAQAAAA==.Aljern:BAAALgAECgkJCwAAAA==.Alpha:BAAALgAECgYJBwAAAA==.Alysra:BAAALgADCgUJBQABLgAFFAkJMQAEAFkhAA==.',
Am='Ammogal:BAAALgAECgYJCQAAAA==.',
An='Anakin:BAAALgAECgYJCQAAAA==.Andyson:BAAALgAECgMJCAAAAA==.Angrymonk:BAAALgADCgMJAwAAAA==.Antandra:BAAALgAECgYJEwAAAA==.Anwen:BAABLgAECn8nAAIFAAkJiRdyNQBDAgAFAAkJiRdyNQBDAgAAAA==.',
Ar='Arawen:BAAALgAECgQJBgABLgAECgkJJwAFAIkXAA==.Arkol:BAAALgADCgYJCAAAAA==.Artinash:BAAALgAECgUJBQAAAA==.',
As='Asha:BAABLgAFFH8OAAIGAAgJMAo6CABPAQAGAAgJMAo6CABPAQAAAA==.Asmodean:BAAALgADCgMJAwABLgAECggJNwAHAL8hAA==.',
Av='Avadrea:BAAALgADCgEJAQAAAA==.Aválánche:BAAALgADCgEJAQAAAA==.',
Ay='Ayanea:BAABLgAECn8oAAQIAAkJVCIbCwC9AgAIAAkJOiEbCwC9AgAJAAIJvCRzWwDGAAAKAAQJTw/HXwCZAAAAAA==.Aysá:BAAALgADCgMJBQAAAA==.',
Ba='Baberaham:BAABLgAECn8nAAQLAAcJpQUGIgC+AAAMAAcJogMd6gDIAAALAAYJUgYGIgC+AAANAAEJhATLYwAiAAAAAA==.Baiford:BAABLgAECn8pAAMOAAkJIRFCKADJAQAOAAkJIRFCKADJAQABAAkJGgo8fwBwAQAAAA==.Baldie:BAAALgADCgEJAQAAAA==.Batteries:BAABLgAECn8pAAIBAAYJdQhpKgCiAAABAAYJdQhpKgCiAAAAAA==.',
Be='Bear:BAABLgAFFH8IAAIPAAUJnxhOCAA4AQAPAAUJnxhOCAA4AQAAAA==.Bearitto:BAABLgAECn83AAIQAAgJmSJcFACnAgAQAAgJmSJcFACnAgAAAA==.',
Bi='Bibbly:BAAALgADCgIJAgAAAA==.Bigpony:BAAALgADCgYJCAAAAA==.',
Bl='Blightmaker:BAAALgAECgEJAQAAAA==.Bloodrain:BAAALgADCgYJBgAAAA==.',
Bo='Bobsan:BAAALgAECgQJBAAAAA==.',
Br='Breyvarian:BAAALgADCgUJBQAAAA==.Broland:BAABLgAECn8YAAIKAAkJTAlUNQBCAQAKAAkJTAlUNQBCAQAAAA==.Brugarin:BAAALgAECgMJBAAAAA==.Brôski:BAAALgAECgEJAQABLgAECgcJCAACAAAAAA==.',
Bu='Burningvoker:BAAALgADCgYJBgAAAA==.',
['Bå']='Bånduri:BAAALgADCgQJBAAAAA==.',
Ca='Caitycat:BAABLgAECn8gAAIQAAkJdBTuJAAlAgAQAAkJdBTuJAAlAgAAAA==.Calliopê:BAABLgAECn8rAAIQAAkJJBuqAgBQAgAQAAkJJBuqAgBQAgAAAA==.Candycane:BAAALgADCgQJBAAAAA==.Capn:BAAALgAECgEJAQAAAA==.Carabina:BAAALgADCgYJBQAAAA==.Casseopea:BAAALgADCgYJCQABLgAECgMJDAACAAAAAA==.Cathelsun:BAAALgAECgYJDQAAAA==.Catherinn:BAAALgAECgUJBQAAAA==.Cattlock:BAAALgAECgQJEQAAAA==.',
Ch='Chadwick:BAAALgAECgkJAgAAAA==.Chaltin:BAAALgAECgMJAwAAAA==.Chillhunt:BAAALgADCgIJAgAAAA==.',
Cl='Clyysa:BAAALgAECgEJAQAAAA==.',
Co='Coldknights:BAAALgAECgEJAQAAAA==.Colë:BAABLgAECn8kAAIRAAkJQRfJDQAGAgARAAkJQRfJDQAGAgAAAA==.Conocobhar:BAABLgAECn8hAAIDAAkJ7xyRIABkAgADAAkJ7xyRIABkAgAAAA==.',
['Cæ']='Cærus:BAAALgAECgYJBgABLgAFFAkJIgAKAA8WAA==.',
Da='Daedrina:BAAALgADCgMJAwAAAA==.Dajoji:BAAALgAECgEJAgAAAA==.Dalkrim:BAABLgAECn8mAAINAAkJAyDPCACHAgANAAkJAyDPCACHAgAAAA==.',
De='Deadblanchy:BAAALgADCgIJAgAAAA==.Debboi:BAAALgADCgUJBQAAAA==.Deluthor:BAAALgAECgEJAQAAAA==.Demondány:BAAALgADCgEJAQAAAA==.Denzel:BAAALgAECgYJBQAAAA==.Derrick:BAABLgAECn8XAAISAAcJ+gmFMwDzAAASAAcJ+gmFMwDzAAAAAA==.Desol:BAAALgADCgEJAQAAAA==.Destrya:BAABLgAECn8oAAIGAAkJDiFjBgCmAgAGAAkJDiFjBgCmAgAAAA==.',
Di='Diamondhoof:BAAALgADCgcJCQAAAA==.Dibbsette:BAABLgAECn8mAAMIAAkJBh7mHQDeAQAIAAkJBh7mHQDeAQAKAAkJIA9+IwCtAQAAAA==.Dibbsonious:BAAALgADCgQJBAAAAA==.',
Do='Douber:BAAALgADCgYJCAAAAA==.',
Dr='Dractruckz:BAAALgAECgkJDwABLgAFFAMJCQADAIMPAA==.Drosera:BAAALgADCgcJCQAAAA==.',
Ds='Dshiznit:BAAALgAECgcJDAABLgAECgkJKwAQACQbAA==.',
Dw='Dwamli:BAAALgAECgUJEQAAAA==.',
Dy='Dynamitedave:BAAALgAECggJDwAAAA==.',
['Dø']='Dømino:BAABLgAECn8sAAITAAYJIheWBgDfAAATAAYJIheWBgDfAAAAAA==.',
Eb='Ebolabeef:BAABLgAECn8hAAIMAAgJPCUqHwCNAgAMAAgJPCUqHwCNAgAAAA==.',
Ei='Eirlys:BAABLgAECn8aAAIFAAkJIQ/bDwBeAQAFAAkJIQ/bDwBeAQAAAA==.',
El='Elky:BAAALgADCgkJHAABLgAECgkJKAAUADEaAA==.Elìyon:BAABLgAECn9BAAMVAAkJwhQeMQACAgAVAAkJwhQeMQACAgASAAEJoQExfQAiAAAAAA==.',
Es='Espyvon:BAAALgADCgQJBAAAAA==.',
Et='Eternalay:BAAALgAECgYJDAAAAA==.Eternalist:BAAALgAECgMJBAAAAA==.Eternshot:BAAALgADCgEJAQAAAA==.Eternsword:BAAALgADCgYJBgAAAA==.',
Ev='Evelanara:BAAALgADCgUJBQAAAA==.Evelinnia:BAAALgADCgMJBQAAAA==.Evilmurkii:BAAALgAECgEJBgABLgAFFAIJBwABAHUUAA==.Evilssoul:BAAALgAECgQJBAAAAA==.',
Fa='Fatalstørm:BAAALgAECgUJBQAAAA==.',
Fe='Feltsmer:BAAALgADCgYJCQAAAA==.Fenira:BAAALgAECgEJAQAAAA==.',
Fo='Foscora:BAAALgAECgEJAQAAAA==.',
Fr='Frushy:BAAALgAECgEJAQAAAA==.Frynn:BAAALgADCgMJAwAAAA==.',
Fu='Fugu:BAAALgADCggJEQAAAA==.',
Ga='Gannicûs:BAAALgAECgcJCAAAAA==.Garlando:BAAALgAECgYJBwAAAA==.',
Gi='Girly:BAAALgAECgMJAwABLgAECgkJKAAUADEaAA==.',
Go='Goatmommy:BAABLgAECn8jAAIUAAYJDRkGDQBNAQAUAAYJDRkGDQBNAQAAAA==.Goph:BAAALgADCgMJBQAAAA==.Goregrind:BAAALgADCgUJBQAAAA==.Goremnar:BAAALgADCgYJBgAAAA==.',
Gr='Grimmfury:BAAALgAECgMJDAAAAA==.Grimmtide:BAAALgADCgYJBgAAAA==.Grolgor:BAAALgADCgQJBAAAAA==.Grïffïth:BAACLgAFFH8wAAMBAAkJhRdiAwC/AQABAAkJhRdiAwC/AQAOAAEJ2ADBHABGAAAuAAQKfy4AAwEACQmOIRoPABUDAAEACQmOIRoPABUDAA4ABglLD2lHAFoBAAAA.',
Gu='Gunjir:BAAALgAECgQJCwAAAA==.',
Gw='Gwyneira:BAABLgAECn8YAAIFAAYJ9ArzJgCzAAAFAAYJ9ArzJgCzAAABLgAECgkJGgAFACEPAA==.',
Ha='Haranbush:BAAALgADCgYJBgAAAA==.Hazellok:BAAALgAECgMJBAAAAA==.Hazzyylock:BAAALgAECgEJAQAAAA==.',
He='Helloween:BAAALgAECgMJAQAAAA==.',
Hi='Hipidipi:BAAALgADCgUJBQAAAA==.',
Ho='Holybush:BAAALgADCgQJAwAAAA==.Honeysuckles:BAAALgAECgQJCAAAAA==.',
Hu='Hucklebeary:BAAALgAECgQJCgAAAA==.Hugcubs:BAAALgADCgUJBQAAAA==.',
['Hí']='Hítgirl:BAABLgAECn8cAAIDAAgJ+RxaBQBTAgADAAgJ+RxaBQBTAgAAAA==.',
Ia='Ianuvyen:BAAALgAECgUJAQAAAA==.',
Ic='Icylilith:BAAALgADCgYJCQAAAA==.',
Il='Illadane:BAAALgAECgEJAQAAAA==.',
Im='Imugi:BAABLgAECn8nAAIWAAkJPAi8FwBVAQAWAAkJPAi8FwBVAQAAAA==.',
Ir='Irithia:BAAALgAECgEJAQAAAA==.Iroc:BAAALgAECgEJAQAAAA==.',
Is='Ishamael:BAAALgAECgUJCgABLgAECggJNwAHAL8hAA==.Issavanos:BAAALgAECgYJEAAAAA==.',
Ja='Japopo:BAAALgAECgMJAwABLgAECgcJEwACAAAAAA==.Jazmane:BAAALgADCgYJBgAAAA==.',
Je='Jendruid:BAAALgADCgcJBwAAAA==.Jenhoney:BAAALgAECgMJDAAAAA==.Jes:BAAALgADCgEJAQAAAA==.Jessdarklord:BAAALgAECgQJAwAAAA==.',
Jo='Joespally:BAAALgADCgYJBgAAAA==.Josh:BAAALgAECgYJCQABLgAFFAYJDAAXAOcTAA==.',
Ka='Kaliya:BAAALgAECgQJCQAAAA==.Kalliana:BAAALgADCgEJAQAAAA==.Kashar:BAAALgADCgQJBAAAAA==.',
Ke='Keltro:BAAALgADCgcJBwABLgAECgcJIQAGAMsaAA==.Ketna:BAAALgAECgMJAwAAAA==.Kevdog:BAABLgAECn8hAAIYAAkJZRFwCgCdAQAYAAkJZRFwCgCdAQAAAA==.',
Kh='Khelemarth:BAAALgAECgYJDQAAAA==.',
Ki='Killa:BAAALgAECgYJAgAAAA==.Killaelf:BAAALgAECgEJAQAAAA==.Kire:BAABLgAECn83AAMGAAkJKyIrBADnAgAGAAkJKyIrBADnAgAPAAEJ0Q7MQAA3AAAAAA==.Kirohan:BAABLgAECn8hAAMBAAcJoxVpGwD0AAABAAcJoxVpGwD0AAAZAAEJ0ALrHAATAAAAAA==.Kittzz:BAAALgADCgMJAwAAAA==.',
Ko='Kobellr:BAAALgADCgUJBQAAAA==.Koldov:BAAALgAECgEJAQAAAA==.Kosmik:BAAALgADCgcJCwAAAA==.',
Kr='Kravann:BAAALgAECgEJAQAAAA==.Kremm:BAAALgADCgMJBQABLgAECgYJCAACAAAAAA==.Krimzin:BAAALgAFFAEJAQABLgAFFAUJGwADADAhAA==.',
Ku='Kuiu:BAAALgAECgEJAQAAAA==.Kulnurayne:BAAALgADCgcJDAAAAA==.Kuna:BAAALgAECgYJDgAAAA==.Kushta:BAABLgAECn8YAAIBAAgJix0NGQDTAgABAAgJix0NGQDTAgAAAA==.',
La='Lackjaw:BAABLgAECn8aAAIYAAgJUA73EQC8AQAYAAgJUA73EQC8AQAAAA==.Landrick:BAACLgAFFH8kAAINAAYJ8BHDDwDtAAANAAYJ8BHDDwDtAAAuAAQKfzYAAg0ACQlJGkMRAPgBAA0ACQlJGkMRAPgBAAAA.Lanejack:BAAALgADCgUJCAAAAA==.Larissah:BAECLgAFFH8FAAIKAAQJPQnJMACDAAAKAAQJPQnJMACDAAAuAAQKfyAAAgoACQmqE10cAOIBAAoACQmqE10cAOIBAAEuAAUUBQkFAAMArQMA.Lava:BAABLgAECn8VAAISAAkJ5x3FAgASAgASAAkJ5x3FAgASAgAAAA==.',
Lg='Lgang:BAABLgAECn8VAAISAAYJ5gqIPAANAQASAAYJ5gqIPAANAQAAAA==.',
Li='Lichgore:BAAALgAECgEJAQAAAA==.Lifeblõõm:BAABLgAECn8aAAMQAAkJPB/ACgARAwAQAAkJPB/ACgARAwAEAAIJjA6HkAAvAAAAAA==.Lilium:BAAALgAECgYJBgAAAA==.',
Ll='Llau:BAACLgAFFH8NAAIHAAMJ3R0gHADjAAAHAAMJ3R0gHADjAAAuAAQKf2cAAwcACQk6JKkAAKQDAAcACQk6JKkAAKQDABoAAQmkBkKxACUAAAAA.',
Lo='Longbow:BAAALgAFFAIJAgAAAA==.Losia:BAABLgAECn8bAAIIAAcJ0A/HCQA4AQAIAAcJ0A/HCQA4AQAAAA==.Lottashocks:BAABLgAFFH8FAAIUAAMJWxk1GwDwAAAUAAMJWxk1GwDwAAAAAA==.Loveinvain:BAAALgAECgMJAgAAAA==.',
Lu='Lunabun:BAAALgADCgcJEwAAAA==.',
['Lû']='Lûffy:BAAALgAECgkJCQAAAA==.',
Ma='Mahina:BAAALgAECgUJCgAAAA==.Malorn:BAABLgAECn82AAQaAAkJFR4PCADGAgAaAAkJFR4PCADGAgAHAAYJIROsQQBnAQAbAAgJvhFXQQD1AAAAAA==.Manaaddict:BAAALgAECgYJBgAAAA==.Manbeerpig:BAAALgAECgEJAQAAAA==.Matore:BAAALgAECgcJEQAAAA==.Mavimus:BAAALgAECgEJAQAAAA==.',
Mi='Midníght:BAAALgAECgYJCQABLgAECgkJKAAUADEaAA==.',
Mo='Molanar:BAAALgAECgEJAQAAAA==.Moltencarl:BAAALgAECgEJAgAAAA==.',
My='Myrna:BAAALgAECgMJAwAAAA==.',
['Må']='Målåchi:BAAALgAECgYJCAAAAA==.',
Na='Naranir:BAAALgAECgEJAQAAAA==.Nasher:BAAALgAECgEJAQAAAA==.',
Ni='Niege:BAABLgAECn8YAAIEAAYJkgPvGwBTAAAEAAYJkgPvGwBTAAAAAA==.Niiso:BAAALgAECgYJCAAAAA==.Nivas:BAAALgADCgIJAgABLgAECgkJNgAaABUeAA==.Nivina:BAAALgADCgcJBwAAAA==.',
Nk='Nkag:BAAALgAECgEJAQABLgAECgUJFQAbAAgQAA==.Nkagnyto:BAABLgAECn8VAAMbAAUJCBA7UgC6AAAbAAUJCBA7UgC6AAAaAAQJxwz1aQCAAAAAAA==.Nkanue:BAAALgAECgIJAgABLgAECgUJFQAbAAgQAA==.',
No='Noonstalker:BAAALgAECgYJEQAAAA==.',
Nu='Nuadi:BAAALgADCgcJFAAAAA==.',
Or='Oric:BAAALgADCgMJAwABLgAECgkJKgAZAH4WAA==.Orintaar:BAAALgADCgMJAwAAAA==.Ormac:BAAALgAECgYJEwAAAA==.Ororoe:BAACLgAFFH8ZAAMbAAQJrhVWJwALAQAbAAQJVRRWJwALAQAaAAQJLwqGEACtAAAuAAQKfykAAxsACQk4GmsUAGsCABsACAnNGmsUAGsCABoACQkOEs0eALYBAAAA.Orphancalf:BAAALgAECgIJAgAAAA==.',
Ow='Owlmel:BAAALgAECgYJBgAAAA==.',
Pa='Palapo:BAAALgAECgcJEwAAAA==.Panrocktar:BAAALgADCgEJAQAAAA==.Papaheals:BAAALgADCgQJBAAAAA==.Paudrig:BAABLgAECn8mAAMOAAYJoBg/MACZAQAOAAYJoBg/MACZAQABAAYJrQtz1QDsAAAAAA==.Pawdrig:BAABLgAECn8UAAMMAAkJkRVLEgAbAQAMAAkJWBJLEgAbAQANAAQJKg/iDACRAAAAAA==.',
Pe='Penicilin:BAAALgAECgUJBQAAAA==.Perfect:BAAALgAECgQJBgAAAA==.',
Ph='Phagetouched:BAAALgAECgYJDQAAAA==.Phaydre:BAAALgAECgYJEgABLgAFFAgJEQAWAFwLAA==.',
Pi='Picklenick:BAABLgAECn8lAAIcAAkJ4BQEFAADAgAcAAkJ4BQEFAADAgAAAA==.',
Po='Ponyhunts:BAAALgAECgQJCAAAAA==.Ponytree:BAABLgAECn8aAAQQAAkJbARrdQDVAAAQAAkJbARrdQDVAAAEAAEJzwEijwAdAAARAAIJkAJ5NgAcAAAAAA==.Porani:BAAALgAECgQJBgAAAA==.',
Pr='Predatore:BAAALgAECgYJBgAAAA==.Primal:BAAALgAECgEJAgAAAA==.Prismo:BAAALgAFFAIJBAAAAA==.Prognosis:BAAALgADCgcJBwAAAA==.',
Ps='Psychlonem:BAAALgAECgMJAwAAAA==.',
Pw='Pwnbuggy:BAABLgAECn8gAAIMAAgJEhgSWQC7AQAMAAgJEhgSWQC7AQAAAA==.',
Qa='Qartoga:BAAALgAECgUJCwABLgAECgYJDgACAAAAAA==.',
Ql='Qlue:BAAALgAECgEJAQAAAA==.',
Qu='Quiin:BAAALgAECgYJCgAAAA==.',
Ra='Rabellious:BAAALgAECgQJCgAAAA==.Rabin:BAAALgADCgIJAgAAAA==.Racistgreen:BAAALgAECgIJAgAAAA==.Raethys:BAAALgADCgUJBQAAAA==.Rafikibull:BAAALgAECgIJBQAAAA==.Raindrop:BAABLgAECn8sAAIQAAkJbhgsGwBsAgAQAAkJbhgsGwBsAgAAAA==.Ramah:BAABLgAECn8hAAIGAAcJyxrAAwB9AQAGAAcJyxrAAwB9AQAAAA==.Ramen:BAAALgADCgEJAQAAAA==.',
Re='Reignstorm:BAABLgAECn8hAAILAAkJfgtQFAA6AQALAAkJfgtQFAA6AQAAAA==.Reivax:BAABLgAECn9FAAIDAAkJ3hhNJgBIAgADAAkJ3hhNJgBIAgAAAA==.Renjiyomo:BAAALgAECgYJBgAAAA==.Rethelm:BAAALgAECgYJEwAAAA==.Retreats:BAAALgADCgUJBQAAAA==.Retsella:BAAALgADCgkJIgAAAA==.Reveum:BAABLgAECn8+AAMGAAgJlw1yHgBAAQAGAAgJlw1yHgBAAQAPAAYJXwtFOwDYAAAAAA==.Revân:BAABLgAECn8XAAMNAAkJ6BNgAwDYAQANAAkJ6BNgAwDYAQAMAAEJlwqqhgErAAAAAA==.',
Rh='Rhaegár:BAABLgAECn8ZAAIVAAYJFhTWeQAtAQAVAAYJFhTWeQAtAQAAAA==.',
Ro='Robyerto:BAAALgADCgMJAwAAAA==.Rogl:BAACLgAFFH8RAAIQAAcJHCH3BgCWAgAQAAcJHCH3BgCWAgAuAAQKfx0AAhAABwkbIFEcAFoCABAABwkbIFEcAFoCAAAA.Rohaka:BAAALgADCgEJAQABLgAECgcJIQAGAMsaAA==.Rosgard:BAAALgADCggJCAAAAA==.',
Ru='Ruhll:BAAALgAECgQJBwAAAA==.Ruminate:BAAALgADCggJDgABLgAECgkJKAAUADEaAA==.Rustychi:BAABLgAECn8VAAIaAAYJdw0lRgDnAAAaAAYJdw0lRgDnAAAAAA==.',
['Rá']='Rámpapi:BAABLgAECn8jAAIbAAYJmxzSIQCaAQAbAAYJmxzSIQCaAQAAAA==.',
Sa='Sammaile:BAABLgAECn83AAIHAAgJvyHbAQDAAgAHAAgJvyHbAQDAAgAAAA==.Sapient:BAAALgAECggJEwABLgAECgkJKAAUADEaAA==.Sarahsmith:BAABLgAECn8lAAIdAAcJTwgEFQDEAAAdAAcJTwgEFQDEAAAAAA==.Saucypeach:BAAALgAECgYJDQAAAA==.',
Sc='Scamander:BAABLgAECn8WAAIDAAkJDxYTJgAiAgADAAkJDxYTJgAiAgAAAA==.Scarmouse:BAAALgAECgEJAQAAAA==.',
Se='Seifer:BAAALgADCgkJJQAAAA==.Semnickmonk:BAAALgAECgMJBAAAAA==.Senjosako:BAAALgAECgYJBgABLgAFFAUJGgAFAGIcAA==.Senjosaku:BAACLgAFFH8HAAMBAAQJFRIXNgC9AAABAAQJFRIXNgC9AAAOAAEJ1whxKAAtAAAuAAQKfxgAAgEACAkJJLcWALoCAAEACAkJJLcWALoCAAEuAAUUBQkaAAUAYhwA.Serigo:BAABLgAECn8ZAAIFAAYJtw2dwQAHAQAFAAYJtw2dwQAHAQAAAA==.Serral:BAAALgAFFAEJAQAAAA==.',
Sh='Sharpen:BAAALgAECgEJAQAAAA==.Shaxx:BAAALgAECgIJAgABLgAECgYJGQAFALcNAA==.Shellshocked:BAAALgAECgEJAQAAAA==.',
Sk='Skayley:BAAALgADCgUJBQAAAA==.',
Sm='Smoochy:BAAALgAECgEJAQAAAA==.',
Sn='Sneknyto:BAAALgAECgMJAwAAAA==.',
So='Solysz:BAAALgAECgYJEwAAAA==.Sophietheone:BAAALgADCgIJAgAAAA==.Soten:BAAALgAECgQJBAABLgAECgcJIQAGAMsaAA==.Soß:BAACLgAFFH8VAAIFAAQJKRt8QgBmAQAFAAQJKRt8QgBmAQAuAAQKfyQAAgUABwnVIZxSAEACAAUABwnVIZxSAEACAAAA.',
Sp='Spongébob:BAAALgAECgIJAwAAAA==.Spork:BAABLgAECn8oAAIUAAkJMRryBAAiAgAUAAkJMRryBAAiAgAAAA==.',
St='Stimcheck:BAAALgADCgcJBwABLgADCggJCAACAAAAAA==.Stmary:BAAALgADCgQJBAAAAA==.Stormm:BAAALgAECgYJBgAAAA==.Størmzmisery:BAAALgAECgcJCAAAAA==.',
Su='Subzéro:BAABLgAECn8lAAIFAAgJqwx0hwBoAQAFAAgJqwx0hwBoAQAAAA==.',
Sw='Sweetwhisper:BAABLgAECn8bAAMQAAkJpxEDMwDSAQAQAAkJpxEDMwDSAQAEAAMJZAgIawB1AAAAAA==.',
Sy='Sylitae:BAAALgAECgEJAQAAAA==.',
['Så']='Såbëtha:BAAALgADCgMJBQAAAA==.',
Ta='Tahuu:BAAALgADCgUJBAABLgAECgYJFQAOAIUUAA==.Tazzen:BAAALgAECgQJBQAAAA==.',
Te='Teletern:BAAALgADCgUJBwAAAA==.Tempeststørm:BAAALgAECgUJBwAAAA==.Terabythia:BAAALgAECgIJAgAAAA==.',
Th='Thaunelian:BAAALgAECgcJEwABLgAECgkJNgAaABUeAA==.Theblueguy:BAAALgADCgMJAwAAAA==.Theweirdo:BAAALgADCgYJBgAAAA==.Thoristain:BAABLgAECn8qAAIZAAkJfhbmAQAOAgAZAAkJfhbmAQAOAgAAAA==.Thorshman:BAAALgAECgMJAwABLgAECgkJKgAZAH4WAA==.Thrain:BAABLgAECn8uAAIBAAkJiQ1ebQCTAQABAAkJiQ1ebQCTAQAAAA==.Threefive:BAAALgAECgQJBQAAAA==.Thrusher:BAAALgADCgIJAgAAAA==.',
To='Torture:BAAALgAECgEJAQAAAA==.Torvar:BAAALgADCgEJAgAAAA==.Totemíc:BAAALgAECgUJBgAAAA==.',
Tp='Tpops:BAAALgADCgQJBAAAAA==.',
Tr='Trident:BAAALgAECgUJBQAAAA==.Trilràq:BAAALgAECggJBQAAAA==.',
Tu='Tulku:BAAALgADCgIJBAAAAA==.',
Ty='Tyrdrea:BAAALgADCgkJCQAAAA==.',
Up='Upondeath:BAAALgAECgcJBwAAAA==.',
Va='Vallak:BAAALgAECgQJBAAAAA==.Vaqine:BAAALgAECgMJBgABLgAECgkJKAAUADEaAA==.',
Ve='Velarion:BAAALgAECgEJAQAAAA==.Veryundead:BAABLgAECn9OAAIYAAkJDhnvAwBMAgAYAAkJDhnvAwBMAgAAAA==.',
Vi='Viscor:BAAALgAECgEJAQAAAA==.',
Vo='Void:BAABLgAECn8aAAISAAcJ3ha2HwB8AQASAAcJ3ha2HwB8AQAAAA==.Voidmara:BAAALgAECgEJAwAAAA==.Voíd:BAAALgAECgEJAQAAAA==.',
Vr='Vrylykos:BAABLgAECn8gAAMMAAgJJRQqDABpAQAMAAgJGhAqDABpAQANAAYJNxUeBwATAQAAAA==.',
Vy='Vygil:BAAALgADCgQJAwAAAA==.Vyneda:BAAALgADCgUJBQABLgAECgYJFQAOAIUUAA==.',
Wa='Waddlez:BAAALgAECgEJAQAAAA==.Wardawg:BAAALgADCgEJAQABLgAECgkJKAAIAFQiAA==.Wargrylls:BAAALgADCgcJBwAAAA==.',
We='Wendrin:BAABLgAECn8aAAIIAAYJ3gOZFACRAAAIAAYJ3gOZFACRAAAAAA==.',
Wh='White:BAAALgAECgQJBwAAAA==.',
Wo='Wolvynlyfe:BAAALgADCgIJAgAAAA==.',
Xa='Xanarine:BAABLgAECn8VAAMOAAYJhRQvRABnAQAOAAYJhRQvRABnAQABAAIJtQdHIQFbAAAAAA==.Xavíous:BAAALgADCgYJBgAAAA==.',
Xe='Xeeva:BAABLgAECn8bAAIUAAcJCRSWUABwAQAUAAcJCRSWUABwAQAAAA==.',
Xu='Xuralxia:BAAALgAECgEJBgAAAA==.',
Ya='Yassa:BAAALgADCgEJAQAAAA==.',
Yz='Yzinia:BAAALgADCgMJAwAAAA==.',
Zi='Zink:BAAALgAECgEJAQAAAA==.Ziyad:BAABLgAECn8aAAQEAAkJdhGFJACnAQAEAAkJnA+FJACnAQARAAMJwxMIIQCWAAAQAAEJLgde6gAjAAAAAA==.',
Zy='Zyla:BAAALgAECgYJBgAAAA==.Zyn:BAABLgAECn8cAAIZAAcJGg3WBwDjAAAZAAcJGg3WBwDjAAAAAA==.',
['Zè']='Zèró:BAABLgAECn8WAAMZAAYJnBxdGABaAQAZAAYJnBxdGABaAQABAAIJPxCpPAFvAAAAAA==.',
['Ðü']='Ðüß:BAAALgADCgIJAgABLgAECgYJCAACAAAAAA==.',
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
