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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Mage-Frost','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Druid-Restoration','Druid-Guardian','DemonHunter-Havoc','Warrior-Protection','Hunter-Survival','DemonHunter-Devourer','Hunter-BeastMastery','Shaman-Restoration','Evoker-Preservation','Monk-Mistweaver','Hunter-Marksmanship','Warlock-Destruction','Warrior-Arms','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Rogue-Subtlety','Warlock-Demonology',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Abuna:BAABLgAECn8hAAIBAAkJ4hKiTQDCAQABAAkJ4hKiTQDCAQAAAA==.',
Ad='Adreni:BAAALgADCgUJBQAAAA==.',
Ae='Aelzia:BAAALgAECgEJBAAAAA==.Aennivan:BAAALgADCgcJBwABLgAECgUJDwACAAAAAA==.Aestia:BAAALgAECgUJCwAAAA==.',
Al='Alfarin:BAAALgAECgEJAQAAAA==.Aljern:BAAALgAECgkJCwAAAA==.Alpha:BAAALgAECgYJBwAAAA==.Alysra:BAAALgADCgUJBQABLgAFFAgJHQADANQeAA==.',
Am='Ammogal:BAAALgAECgQJBAAAAA==.',
An='Anakin:BAAALgAECgMJAwAAAA==.Andyson:BAAALgAECgMJCAAAAA==.Antandra:BAAALgAECgYJEwAAAA==.Anwen:BAABLgAECn8eAAIEAAgJQBcxTQDaAQAEAAgJQBcxTQDaAQAAAA==.',
Ar='Arawen:BAAALgAECgQJBgABLgAECggJHgAEAEAXAA==.Arkol:BAAALgADCgUJBQAAAA==.Artinash:BAAALgAECgUJBQAAAA==.',
Av='Avadrea:BAAALgADCgEJAQAAAA==.Aválánche:BAAALgADCgEJAQAAAA==.',
Ay='Ayanea:BAABLgAECn8jAAQFAAgJJCNhCgCSAgAFAAgJ5yFhCgCSAgAGAAIJvCRzWwDGAAAHAAQJTw8+TwCkAAAAAA==.Aysá:BAAALgADCgMJBQAAAA==.',
Ba='Baberaham:BAABLgAECn8lAAQIAAcJNQVjxgDNAAAIAAcJogNjxgDNAAAJAAYJBwWqHQCXAAAKAAEJhARLUwAjAAAAAA==.Baiford:BAABLgAECn8pAAMLAAkJIRHqIQDRAQALAAkJIRHqIQDRAQABAAkJGgrXYwCLAQAAAA==.Baldie:BAAALgADCgEJAQAAAA==.Batteries:BAAALgAECgMJBwAAAA==.',
Be='Bearitto:BAABLgAECn8uAAIMAAgJsiAwEQCoAgAMAAgJsiAwEQCoAgAAAA==.',
Bi='Bigpony:BAAALgADCgYJCAAAAA==.',
Bl='Bloodrain:BAAALgADCgYJBgAAAA==.',
Bo='Bobsan:BAAALgAECgQJBAAAAA==.',
Br='Breyvarian:BAAALgADCgUJBQAAAA==.Broland:BAAALgAECgYJEwAAAA==.',
Bu='Burningvoker:BAAALgADCgYJBgAAAA==.',
Ca='Caitycat:BAABLgAECn8bAAIMAAkJSRRXIAAjAgAMAAkJSRRXIAAjAgAAAA==.Calliopê:BAABLgAECn8YAAIMAAYJ5RyRKgDiAQAMAAYJ5RyRKgDiAQAAAA==.Candycane:BAAALgADCgQJBAAAAA==.Carabina:BAAALgADCgMJAgAAAA==.Casseopea:BAAALgADCgYJCQABLgAECgMJDAACAAAAAA==.Catherinn:BAAALgAECgUJBQAAAA==.Cattlock:BAAALgAECgQJDwAAAA==.',
Ch='Chaltin:BAAALgAECgMJAwAAAA==.Chillhunt:BAAALgADCgIJAgAAAA==.',
Co='Coldhand:BAAALgAECgkJBgAAAA==.Colë:BAABLgAECn8eAAINAAkJ9RRzDQDUAQANAAkJ9RRzDQDUAQAAAA==.',
['Cæ']='Cærus:BAAALgAECgYJBgABLgAFFAcJFQAHAPMVAA==.',
Da='Daedrina:BAAALgADCgMJAwAAAA==.Dalkrim:BAABLgAECn8hAAIKAAkJfR2RCwApAgAKAAkJfR2RCwApAgAAAA==.',
De='Deadblanchy:BAAALgADCgIJAgAAAA==.Debboi:BAAALgADCgUJBQAAAA==.Deluthor:BAAALgAECgEJAQAAAA==.Denzel:BAAALgAECgYJBQAAAA==.Derrick:BAABLgAECn8XAAIOAAcJ+gmwKAD+AAAOAAcJ+gmwKAD+AAAAAA==.Desol:BAAALgADCgEJAQAAAA==.Destrya:BAABLgAECn8jAAIPAAgJACHuBwBeAgAPAAgJACHuBwBeAgAAAA==.',
Di='Diamondhoof:BAAALgADCgcJBgAAAA==.Dibbsette:BAABLgAECn8iAAMFAAkJBh7FFwDsAQAFAAkJBh7FFwDsAQAHAAYJQQ0qNwATAQAAAA==.',
Do='Douber:BAAALgADCgYJCAAAAA==.',
Dr='Drosera:BAAALgADCgcJBgAAAA==.',
Ds='Dshiznit:BAAALgAECgMJBAABLgAECgYJGAAMAOUcAA==.',
Dw='Dwamli:BAAALgAECgUJEAAAAA==.',
Dy='Dynamitedave:BAAALgAECgUJDAABLgAECgYJFwAQAJ0YAA==.',
['Dø']='Dømino:BAABLgAECn8YAAIQAAQJ6BQrLgATAQAQAAQJ6BQrLgATAQAAAA==.',
Eb='Ebolabeef:BAABLgAECn8hAAIIAAgJPCXNFwCZAgAIAAgJPCXNFwCZAgAAAA==.',
Ei='Eirlys:BAAALgAECgYJEAAAAA==.',
El='Elky:BAAALgADCgkJHAABLgAECgMJBgACAAAAAA==.Elìyon:BAABLgAECn8xAAMRAAkJUg27SACMAQARAAkJUg27SACMAQAOAAEJoQExfQAiAAAAAA==.',
Es='Espyvon:BAAALgADCgQJBAAAAA==.',
Et='Eternalay:BAAALgAECgYJDAAAAA==.Eternalist:BAAALgAECgMJAwAAAA==.Eternshot:BAAALgADCgEJAQAAAA==.Eternsword:BAAALgADCgYJBgAAAA==.',
Ev='Evelanara:BAAALgADCgUJBQAAAA==.Evelinnia:BAAALgADCgMJBQAAAA==.Evilmurkii:BAAALgAECgEJBgABLgAFFAIJAwACAAAAAA==.Evilssoul:BAAALgAECgQJBAAAAA==.',
Fe='Feltsmer:BAAALgADCgYJCQAAAA==.Fenira:BAAALgAECgEJAQAAAA==.Ferguz:BAABLgAECn8cAAISAAkJ7RoPIAA9AgASAAkJ7RoPIAA9AgAAAA==.',
Fo='Foscora:BAAALgAECgEJAQAAAA==.',
Fr='Frushy:BAAALgAECgEJAQAAAA==.',
Fu='Fugu:BAAALgADCggJEQAAAA==.',
Ga='Gannicûs:BAAALgAECgYJBwAAAA==.Garlando:BAAALgAECgEJAQAAAA==.',
Go='Goatmommy:BAABLgAECn8WAAITAAQJyBdiYAAHAQATAAQJyBdiYAAHAQAAAA==.Goph:BAAALgADCgMJBQAAAA==.Goremnar:BAAALgADCgYJBgAAAA==.',
Gr='Grimmfury:BAAALgAECgMJDAAAAA==.Grimmtide:BAAALgADCgYJBgAAAA==.Grolgor:BAAALgADCgQJBAAAAA==.Grïffïth:BAACLgAFFH8hAAMBAAgJexitBwDuAQABAAcJShatBwDuAQALAAEJ2ADBHABGAAAuAAQKfy4AAwEACQmOIRoPABUDAAEACQmOIRoPABUDAAsABglLD2lHAFoBAAAA.',
Gu='Gunjir:BAAALgAECgQJCwAAAA==.',
Gw='Gwyneira:BAAALgAECgYJCgABLgAECgYJEAACAAAAAA==.',
Ha='Haranbush:BAAALgADCgYJBgAAAA==.Hazellok:BAAALgADCgYJBgAAAA==.',
He='Helloween:BAAALgAECgMJAQAAAA==.',
Hi='Hipidipi:BAAALgADCgUJBQAAAA==.',
Ho='Honeysuckles:BAAALgAECgEJAQAAAA==.',
Hu='Hucklebeary:BAAALgAECgQJCgAAAA==.Hugcubs:BAAALgADCgUJBQAAAA==.',
['Hí']='Hítgirl:BAAALgAECgUJCwAAAA==.',
Ic='Icylilith:BAAALgADCgYJCQAAAA==.',
Im='Imugi:BAABLgAECn8hAAIUAAkJ7AerFABgAQAUAAkJ7AerFABgAQAAAA==.',
Ir='Irithia:BAAALgADCgEJAQAAAA==.',
Is='Ishamael:BAAALgAECgMJAwABLgAECgYJGQAVACQhAA==.Issavanos:BAAALgAECgYJEAAAAA==.',
Ja='Jazmane:BAAALgADCgYJBgAAAA==.',
Je='Jenhoney:BAAALgAECgMJDAAAAA==.Jes:BAAALgADCgEJAQAAAA==.Jessdarklord:BAAALgAECgQJAwAAAA==.',
Jo='Josh:BAAALgAECgYJCQABLgAFFAYJDAAWAOcTAA==.',
Ka='Kaliya:BAAALgAECgQJCQAAAA==.Kashar:BAAALgADCgQJBAAAAA==.',
Ke='Ketna:BAAALgAECgMJAwAAAA==.Kevdog:BAABLgAECn8hAAIXAAkJZRG1BwCqAQAXAAkJZRG1BwCqAQAAAA==.',
Kh='Khelemarth:BAAALgAECgEJBgAAAA==.',
Ki='Kire:BAABLgAECn8rAAMPAAkJoSB2BADBAgAPAAkJoSB2BADBAgAYAAEJ0Q7MQAA3AAAAAA==.Kirohan:BAAALgAECgYJBgAAAA==.',
Ko='Kobellr:BAAALgADCgUJBQAAAA==.Koldov:BAAALgAECgEJAQAAAA==.Kosmik:BAAALgADCgcJCwAAAA==.',
Kr='Kremm:BAAALgADCgMJBAABLgAECgMJAwACAAAAAA==.Krimzin:BAAALgAFFAEJAQABLgAFFAUJFgASAHwgAA==.',
Ku='Kuiu:BAAALgADCgEJAQAAAA==.Kulnurayne:BAAALgADCgcJDAAAAA==.Kuna:BAAALgAECgQJCQABLgAECgUJBgACAAAAAA==.Kushta:BAABLgAECn8YAAIBAAgJix0NGQDTAgABAAgJix0NGQDTAgAAAA==.',
La='Lackjaw:BAABLgAECn8aAAIXAAgJUA73EQC8AQAXAAgJUA73EQC8AQAAAA==.Landrick:BAACLgAFFH8QAAIKAAQJiA2GGADqAAAKAAQJiA2GGADqAAAuAAQKfzYAAgoACQlJGg8NAA0CAAoACQlJGg8NAA0CAAAA.Lanejack:BAAALgADCgUJCAAAAA==.Larissah:BAEBLgAECn8gAAIHAAkJqhM0FwDsAQAHAAkJqhM0FwDsAQAAAA==.Lava:BAAALgAECggJDwAAAA==.',
Lg='Lgang:BAABLgAECn8VAAIOAAYJ5gqIPAANAQAOAAYJ5gqIPAANAQAAAA==.',
Li='Lifeblõõm:BAABLgAECn8VAAMMAAcJUSGvFgBxAgAMAAcJUSGvFgBxAgADAAIJjA7LeQAwAAAAAA==.Lilium:BAAALgAECgYJBgAAAA==.',
Ll='Llau:BAABLgAECn8wAAIVAAkJHR0yCADrAgAVAAkJHR0yCADrAgAAAA==.',
Lo='Lokopally:BAAALgADCgEJAQAAAA==.Losia:BAAALgAECgUJDgAAAA==.Loveinvain:BAAALgAECgMJAgAAAA==.',
Lu='Lunabun:BAAALgADCgcJEwAAAA==.',
['Lû']='Lûffy:BAAALgAECgkJCQAAAA==.',
Ma='Mahina:BAAALgADCggJCAAAAA==.Malorn:BAABLgAECn8qAAQZAAkJchcUGADLAQAZAAgJ3hYUGADLAQAVAAYJIRMCMgBkAQAaAAYJ7Q7YQwAzAQAAAA==.Manaaddict:BAAALgAECgYJBgAAAA==.Manbeerpig:BAAALgAECgEJAQAAAA==.',
Mi='Midníght:BAAALgAECgEJAQABLgAECgMJBgACAAAAAA==.',
Mo='Moltencarl:BAAALgAECgEJAgAAAA==.',
My='Myrna:BAAALgAECgMJAwAAAA==.',
Ni='Niege:BAAALgAECgYJCgAAAA==.Niiso:BAAALgAECgMJAwAAAA==.Nivas:BAAALgADCgIJAgABLgAECgkJKgAZAHIXAA==.Nivina:BAAALgADCgcJBwAAAA==.',
Nk='Nkagnyto:BAABLgAECn8VAAMaAAUJCBAuSQC+AAAaAAUJCBAuSQC+AAAZAAQJxwwWWACEAAAAAA==.Nkanue:BAAALgADCgIJAgABLgAECgUJFQAaAAgQAA==.',
No='Noonstalker:BAAALgAECgYJEQAAAA==.',
Nu='Nuadi:BAAALgADCgYJBgAAAA==.',
Or='Oric:BAAALgADCgMJAwABLgAECgYJGgAbAP4RAA==.Orintaar:BAAALgADCgMJAwAAAA==.Ormac:BAAALgAECgYJEwAAAA==.Ororoe:BAABLgAECn8mAAMaAAgJNBtrFABrAgAaAAgJzRprFABrAgAZAAcJPBHUKwA3AQAAAA==.Orphancalf:BAAALgAECgIJAgAAAA==.',
Ow='Owlmel:BAAALgAECgQJBAAAAA==.',
Pa='Palapo:BAAALgAECgUJDwAAAA==.Panrocktar:BAAALgADCgEJAQAAAA==.Paudrig:BAABLgAECn8dAAMLAAYJXBYBMAB1AQALAAYJXBYBMAB1AQABAAYJHgvEsQD8AAAAAA==.',
Pe='Perfect:BAAALgAECgQJBgAAAA==.',
Ph='Phagetouched:BAAALgAECgYJDQAAAA==.Phaydre:BAAALgAECgYJEgABLgAFFAUJDAAUANgPAA==.',
Pi='Picklenick:BAABLgAECn8gAAIcAAkJIhTiEQD1AQAcAAkJIhTiEQD1AQAAAA==.',
Po='Ponytree:BAABLgAECn8ZAAQMAAkJbAToaQDZAAAMAAkJbAToaQDZAAADAAEJzwEijwAdAAANAAIJkAJ5NgAcAAAAAA==.Porani:BAAALgAECgEJAQAAAA==.',
Pr='Prismo:BAAALgAFFAIJAgAAAA==.',
Pw='Pwnbuggy:BAABLgAECn8gAAIIAAgJEhhuSADJAQAIAAgJEhhuSADJAQAAAA==.',
Qa='Qartoga:BAAALgAECgUJBgAAAA==.',
Ql='Qlue:BAAALgAECgEJAQAAAA==.',
Ra='Rabellious:BAAALgAECgEJAQAAAA==.Rabin:BAAALgADCgIJAgAAAA==.Racistgreen:BAAALgAECgIJAgAAAA==.Raethys:BAAALgADCgUJBQAAAA==.Rafikibull:BAAALgAECgIJBQAAAA==.Raindrop:BAABLgAECn8jAAIMAAgJuRlTHQA6AgAMAAgJuRlTHQA6AgAAAA==.Ramah:BAAALgAECgUJDgAAAA==.Ramen:BAAALgADCgEJAQAAAA==.',
Re='Reignstorm:BAABLgAECn8hAAIJAAkJfgudDgBDAQAJAAkJfgudDgBDAQAAAA==.Reivax:BAABLgAECn8yAAISAAkJNhSVLgD5AQASAAkJNhSVLgD5AQAAAA==.Renjiyomo:BAAALgAECgYJBgAAAA==.Rethelm:BAAALgAECgYJEwAAAA==.Retreats:BAAALgADCgUJBQAAAA==.Retsella:BAAALgADCgkJIgAAAA==.Reveum:BAABLgAECn8+AAMPAAgJlw2RGABVAQAPAAgJlw2RGABVAQAYAAYJXwt0LgDjAAAAAA==.Revân:BAAALgAECgYJBgAAAA==.',
Rh='Rhaegár:BAABLgAECn8UAAIRAAYJkxJEcAAeAQARAAYJkxJEcAAeAQAAAA==.',
Ro='Robyerto:BAAALgADCgMJAwAAAA==.Rogl:BAACLgAFFH8OAAIMAAYJXyHXBQBSAgAMAAYJXyHXBQBSAgAuAAQKfx0AAgwABwkbIFEcAFoCAAwABwkbIFEcAFoCAAAA.Rosgard:BAAALgADCggJCAAAAA==.',
Ru='Ruffruff:BAAALgAECgkJBgAAAA==.Ruhll:BAAALgAECgMJBAAAAA==.Ruminate:BAAALgADCgYJCgABLgAECgMJBgACAAAAAA==.Rustychi:BAABLgAECn8VAAIZAAYJdw3oOQDwAAAZAAYJdw3oOQDwAAAAAA==.',
['Rá']='Rámpapi:BAABLgAECn8WAAIaAAQJeBrWLAA4AQAaAAQJeBrWLAA4AQAAAA==.',
Sa='Sammaile:BAABLgAECn8ZAAIVAAYJJCH4GAAWAgAVAAYJJCH4GAAWAgAAAA==.Sarahsmith:BAABLgAECn8aAAIdAAYJ5ANAvAC4AAAdAAYJ5ANAvAC4AAAAAA==.Saucypeach:BAAALgAECgYJDQAAAA==.',
Sc='Scamander:BAABLgAECn8WAAISAAkJDxYTJgAiAgASAAkJDxYTJgAiAgAAAA==.Scarmouse:BAAALgAECgEJAQAAAA==.',
Se='Seifer:BAAALgADCgkJJQAAAA==.Semnickmonk:BAAALgAECgMJBAAAAA==.Senjosaku:BAABLgAECn8YAAIBAAgJCSQXEADNAgABAAgJCSQXEADNAgABLgAFFAQJEQAEAEAaAA==.Serigo:BAABLgAECn8ZAAIEAAYJtw3apwAWAQAEAAYJtw3apwAWAQAAAA==.Serral:BAAALgAFFAEJAQAAAA==.',
Sh='Shaxx:BAAALgAECgIJAgABLgAECgYJGQAEALcNAA==.Shellshocked:BAAALgADCgkJDwAAAA==.',
Sk='Skayley:BAAALgADCgUJBQAAAA==.',
Sm='Smoochy:BAAALgAECgEJAQAAAA==.',
Sn='Sneknyto:BAAALgAECgMJAwAAAA==.',
So='Solysz:BAAALgAECgYJEwAAAA==.Sophietheone:BAAALgADCgIJAgAAAA==.Soten:BAAALgAECgMJAwABLgAECgUJDgACAAAAAA==.Soß:BAACLgAFFH8KAAIEAAQJBBrgJAAhAQAEAAQJBBrgJAAhAQAuAAQKfyEAAgQABwnPIZxSAEACAAQABwnPIZxSAEACAAAA.',
Sp='Spongébob:BAAALgAECgIJAgAAAA==.Spork:BAAALgAECgMJBgAAAA==.',
St='Stimcheck:BAAALgADCgcJBwABLgADCggJCAACAAAAAA==.Stmary:BAAALgADCgQJBAAAAA==.Stormm:BAAALgAECgYJBgAAAA==.Størmzmisery:BAAALgAECgUJBQAAAA==.',
Su='Subzéro:BAABLgAECn8kAAIEAAYJnA3QqgARAQAEAAYJnA3QqgARAQAAAA==.',
Sw='Sweetwhisper:BAAALgAECgcJEwAAAA==.',
Sy='Sylitae:BAAALgADCgkJHwAAAA==.',
['Så']='Såbëtha:BAAALgADCgMJBQAAAA==.',
Ta='Tahuu:BAAALgADCgUJBAABLgAECgYJFQALAIUUAA==.Tazzen:BAAALgAECgQJBQAAAA==.',
Te='Teletern:BAAALgADCgUJBwAAAA==.Tempeststørm:BAAALgAECgUJBwAAAA==.',
Th='Thaunelian:BAAALgAECgcJDwABLgAECgkJKgAZAHIXAA==.Theblueguy:BAAALgADCgMJAwAAAA==.Thoristain:BAABLgAECn8aAAIbAAYJ/hEsHgD4AAAbAAYJ/hEsHgD4AAAAAA==.Thorshman:BAAALgADCgkJCgABLgAECgYJGgAbAP4RAA==.Thrain:BAABLgAECn8rAAIBAAkJiQ0jVACxAQABAAkJiQ0jVACxAQAAAA==.Threefive:BAAALgAECgQJBQAAAA==.',
To='Torvar:BAAALgADCgEJAgAAAA==.Totemíc:BAAALgAECgQJBQAAAA==.',
Tp='Tpops:BAAALgADCgQJBAAAAA==.',
Tu='Tulku:BAAALgADCgIJBAAAAA==.',
Ty='Tyrdrea:BAAALgADCgkJCQAAAA==.',
Un='Unholypwnage:BAAALgAECgYJBgAAAA==.',
Va='Vallak:BAAALgAECgQJBAAAAA==.',
Ve='Velarion:BAAALgAECgEJAQAAAA==.Veryundead:BAABLgAECn8yAAIXAAkJ/xJFBgDQAQAXAAkJ/xJFBgDQAQAAAA==.',
Vo='Void:BAABLgAECn8VAAIOAAYJwBeEIQA0AQAOAAYJwBeEIQA0AQAAAA==.Voidmara:BAAALgAECgEJAwAAAA==.Voíd:BAAALgAECgEJAQAAAA==.',
Vr='Vrylykos:BAAALgAECgYJCgAAAA==.',
Vy='Vyneda:BAAALgADCgUJBQABLgAECgYJFQALAIUUAA==.',
Wa='Waddlez:BAAALgAECgEJAQAAAA==.Wardawg:BAAALgADCgEJAQABLgAECggJIwAFACQjAA==.Wargrylls:BAAALgADCgcJBwAAAA==.',
We='Wendrin:BAAALgAECgYJDAAAAA==.',
Wh='White:BAAALgAECgQJBwAAAA==.',
Wo='Wolvynlyfe:BAAALgADCgIJAgAAAA==.',
Xa='Xanarine:BAABLgAECn8VAAMLAAYJhRQvRABnAQALAAYJhRQvRABnAQABAAIJtQdHIQFbAAAAAA==.Xavíous:BAAALgADCgYJBgAAAA==.',
Xe='Xeeva:BAABLgAECn8YAAITAAYJzxXZQgB0AQATAAYJzxXZQgB0AQAAAA==.',
Xu='Xuralxia:BAAALgAECgEJBgAAAA==.',
Yz='Yzinia:BAAALgADCgMJAwAAAA==.',
Zi='Zink:BAAALgAECgEJAQAAAA==.Ziyad:BAABLgAECn8aAAQDAAkJdhFsHQCzAQADAAkJnA9sHQCzAQANAAMJwxMIIQCWAAAMAAEJLgdp0wAjAAAAAA==.',
Zy='Zyn:BAAALgAECgUJCwAAAA==.',
['Zè']='Zèró:BAABLgAECn8WAAMbAAYJnBwdFABgAQAbAAYJnBwdFABgAQABAAIJPxCjEAFzAAAAAA==.',
['Ðü']='Ðüß:BAAALgADCgIJAgABLgAECgMJAwACAAAAAA==.',
['Ön']='Öna:BAABLgAECn8yAAISAAkJRBeHHwBAAgASAAkJRBeHHwBAAgAAAA==.',
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
