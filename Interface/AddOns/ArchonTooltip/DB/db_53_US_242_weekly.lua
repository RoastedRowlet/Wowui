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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Druid-Balance','Druid-Restoration',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Ababear:BAAANQADCgYICwAAAA==.',
Ad='Ademai:BAAANQABCgMIBQAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Ahnna:BAAANQADCgEIAQAAAA==.',
Al='Alarrius:BAAANQAECgQIBAAAAA==.Albedö:BAAANQADCgIIAgABNQAECgcIEQABAAAAAA==.Allionys:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgEIAQAAAA==.',
Am='Amanises:BAAANQADCgYICQAAAA==.Amilara:BAAANQADCgYIDwAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Anania:BAAANQADCgYIDAABNQADCgcIDgABAAAAAA==.Andinestiri:BAAANQADCggIBgAAAA==.Andolastrasz:BAAANQAECgEIAQAAAA==.Angelic:BAAANQADCgcIDQAAAA==.',
Ao='Ao:BAAANQAECgQIBAAAAA==.',
Ap='Apotic:BAAANQAECgQIBQAAAA==.Apuntar:BAAANQADCggICAAAAA==.',
Aq='Aquamaree:BAAANQADCgYICgAAAA==.Aquilla:BAABNQAECoEYAAICAAkJ7xvkCwDaAgACAAkJ7xvkCwDaAgAAAA==.',
Ar='Archenea:BAAANQADCggIEAAAAA==.Archenore:BAAANQADCggIEAAAAA==.Argord:BAAANQADCggICAAAAA==.Arhianrod:BAAANQABCgIIAgAAAA==.Ariisa:BAAANQADCgYIDQAAAA==.Around:BAAANQADCgUICwABNQAECgQIBAABAAAAAA==.Artty:BAEANQADCgUICgABNQAECgYICgABAAAAAA==.',
As='Askip:BAAANQADCgIIAgAAAA==.Astrud:BAAANQADCgYIDwAAAA==.Asukka:BAAANQADCggICwAAAA==.Asëya:BAAANQADCggIDgAAAA==.',
At='Atomique:BAAANQAECgUICQABNQAECgcIEAABAAAAAA==.Attenborough:BAAANQADCgYIBgAAAA==.',
Av='Avesa:BAAANQADCgYIDAAAAA==.Avoidant:BAAANQADCggIEQAAAA==.',
Az='Azazell:BAAANQADCgYIDQAAAA==.Azenea:BAAANQAECgEIAQAAAA==.',
Ba='Babomage:BAEBNQAECoEXAAMDAAkJdCRMAAB6AwADAAkJdCRMAAB6AwAEAAcJaRgdOgBRAgAAAA==.Baculum:BAAANQADCggIFQAAAA==.Baieghzieghl:BAAANQADCgcIBwAAAA==.Bandolero:BAAANQADCggICAAAAA==.',
Be='Beangles:BAAANQADCggICAAAAA==.Beckyy:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Beefstewed:BAAANQADCgIIAgAAAA==.Bekkÿ:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAAANQAECgMIAwAAAA==.',
Bi='Bigbutter:BAAANQADCgYIEgAAAA==.Bittybow:BAAANQABCgYIBgAAAA==.Bittydrood:BAAANQADCgYIDQAAAA==.Bittylexis:BAAANQADCggIFQAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAAANQAECgIIAgAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgcIDAABAAAAAA==.Blèu:BAAANQAECgUIBQAAAA==.',
Bo='Boggrog:BAAANQABCgMIAwABNQADCgYIDwABAAAAAQ==.Bokan:BAAANQADCgEIAQAAAA==.',
Br='Braggs:BAAANQADCgYICgAAAA==.Brewballs:BAAANQAECgEIAQAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCgEIAQAAAA==.Bucket:BAAANQAECgEIAQAAAA==.Bunnicula:BAAANQAECgQIBQAAAA==.',
['Bö']='Böömer:BAAANQADCgcIHQAAAA==.',
Ca='Caelphia:BAAANQADCggIEwAAAA==.Caimage:BAAANQAECgYIDAAAAA==.Cainnaszun:BAAANQADCgEIAQABNQADCgYIDAABAAAAAA==.Cainnaszunn:BAAANQADCgYIDAAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Cattform:BAAANQADCggICAAAAA==.Caythus:BAACNQAFFIEIAAQFAAUJxhyRAgAMAQAFAAMJrxiRAgAMAQAGAAIJrxaIAgC9AAAHAAEJOySmAABvAAA1AAQKgRoABAYACQlFJqIAAJcDAAYACQnnI6IAAJcDAAUACAnuJacBAHUDAAcAAQkXJt4NAG4AAAAA.Caythuz:BAABNQAECoEOAAMFAAcJmiDGKgC8AQAFAAYJRyDGKgC8AQAGAAUJGhqMGQBfAQABNQAFFAUICAAFAMYcAA==.',
Ce='Celeana:BAAANQADCgYICgAAAA==.Celencia:BAAANQADCgEIAQAAAA==.Ceryin:BAAANQADCgIIAgAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chainheal:BAAANQABCgIIAgAAAA==.Chakabad:BAAANQADCgYIBwAAAA==.Chalgah:BAAANQADCgIIAgAAAA==.Chenahala:BAAANQADCgYIDQAAAA==.Chåni:BAAANQAFFAEIAQAAAA==.',
Ck='Ckayz:BAAANQAECgIIAgAAAA==.',
Cl='Clam:BAAANQADCggIDwAAAA==.Claw:BAAANQAECgQIBAAAAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQADCggICgAAAA==.Coldstonez:BAAANQADCggIDAAAAA==.Conanascus:BAAANQADCgcIDgABNQAECgMIBQABAAAAAA==.Corrupteded:BAAANQADCgUIBQAAAA==.',
Cr='Crispysock:BAAANQADCgcICwAAAA==.Crowe:BAAANQADCgUICwAAAA==.',
Cy='Cynderr:BAAANQAECgEIAQAAAA==.',
Da='Daisymayhem:BAAANQABCgUIBgAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkfury:BAAANQADCgYIBgAAAA==.Darkisis:BAAANQADCgYIDQAAAA==.Darknara:BAAANQAECgUICwAAAA==.Darkzy:BAAANQAECgEIAwAAAA==.Dartol:BAAANQADCgYIDgAAAA==.Dasubertakem:BAAANQADCgEIAQAAAA==.Dawni:BAAANQAECgMIAwAAAA==.',
De='Deathjeff:BAAANQAECgEIAQAAAA==.',
Di='Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQAECgEIAQAAAA==.Dirtwhistle:BAAANQAECgcIDQAAAA==.',
Dr='Dragondh:BAAANQAECgYIDQAAAA==.Drazsi:BAAANQADCggICAAAAA==.Drosi:BAAANQAECgIIAgAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
['Dø']='Døddy:BAAANQABCgEIAQABNQAECgIIAgABAAAAAA==.',
Ea='Earthesance:BAAANQADCgMIAwAAAA==.',
Eb='Ebeb:BAAANQADCggIFQAAAA==.',
Ei='Eiwe:BAAANQADCgYICQAAAA==.',
El='Eleanne:BAAANQADCggIFQAAAA==.Electricfury:BAAANQADCggIDgAAAA==.Ellebasi:BAAANQADCgYIDwAAAA==.Ellebazy:BAAANQAECgEIAQAAAA==.',
Em='Emmri:BAAANQADCgYICAAAAA==.',
En='Enazen:BAAANQAECgEIAQAAAA==.Enlighthyn:BAAANQAFFAIIAgAAAA==.',
Er='Erlas:BAAANQADCgYICAAAAA==.Erui:BAAANQADCgYIDQAAAA==.',
Et='Etorion:BAAANQABCgEIAQAAAA==.Etrexxig:BAAANQADCgYIBQAAAA==.',
Ev='Evilrayne:BAAANQAECgUICwAAAA==.',
Fa='Fanfiction:BAAANQAECgUIBQAAAA==.Fatherfingur:BAAANQADCgMIAwAAAA==.',
Fe='Featara:BAAANQADCgEIAQAAAA==.Felmonger:BAAANQADCggIEwAAAA==.Feloak:BAAANQAECgIIAgAAAA==.Feredir:BAAANQADCgYIDwAAAA==.',
Fi='Fires:BAAANQAECgMIBQAAAA==.Fistandilius:BAAANQAECgEIAQAAAA==.',
Fo='Folexper:BAAANQADCggIDwAAAA==.',
Fr='Frostman:BAAANQAECgQIBQAAAA==.',
Fu='Furryfury:BAAANQAECgcICQAAAA==.Fusrodah:BAAANQAECgQIBQAAAA==.Fuzzyewok:BAAANQAECgIIAgAAAA==.',
Ga='Gabaghoul:BAAANQAECgQIBAAAAA==.Gameshark:BAAANQADCggIEwAAAA==.Gawdzirra:BAAANQADCgcIDQAAAA==.Gaylordgerva:BAAANQAECgEIAQAAAA==.Gaz:BAAANQAECgQIBAAAAQ==.',
Ge='George:BAAANQADCgYICQAAAA==.',
Gh='Ghazghküll:BAAANQADCgcICAAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Gl='Gluum:BAAANQADCgQIBAAAAA==.',
Go='Gohibasi:BAAANQADCgYICgAAAA==.Gorzarpixx:BAAANQAECgEIAQAAAA==.Gossamerfeet:BAAANQAECgEIAQAAAA==.',
Gr='Graceosilver:BAAANQADCgYIDQAAAA==.Gregnor:BAAANQAECgIIAgAAAA==.Gremöry:BAAANQAECgQICAAAAA==.Grover:BAAANQAECgQIBQAAAA==.Grumpybunbun:BAAANQAECgEIAwAAAA==.Grüm:BAAANQADCgYIDwAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAAANQAECgIIAgAAAA==.',
Ha='Hairypotter:BAAANQADCgUICAABNQADCgYIDQABAAAAAA==.Haldar:BAAANQADCgMIAwAAAA==.Hallie:BAAANQADCgcIDgAAAA==.Harlu:BAAANQAECgEIAQAAAA==.Hartbroke:BAAANQAECgEIAQAAAA==.Haunter:BAAANQABCgQIBQABNQAECgQIBQABAAAAAA==.Hayeon:BAAANQAECgEIAQAAAA==.',
He='Helbourne:BAAANQAECgEIAQAAAA==.',
Hu='Huna:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Hw='Hwanwok:BAAANQAECgEIAwAAAA==.',
Ic='Icemage:BAAANQADCgUIBwAAAA==.',
Id='Ideal:BAAANQADCgEIAQAAAA==.',
Ig='Ignited:BAAANQADCgYIDwAAAA==.',
Im='Imadragon:BAAANQAECgQIBwAAAA==.Imbac:BAAANQADCgMIBQAAAA==.Imdeadguy:BAAANQAECgQIBQAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCgYIEQAAAA==.Ironhelmhtr:BAAANQADCgYICwAAAA==.Ironscythe:BAAANQADCgIIAgAAAA==.',
Ja='Jazlee:BAAANQAECgEIAQAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Jezmund:BAAANQAECgQIBAAAAA==.',
Ji='Jinathy:BAAANQAECgIIAwAAAA==.',
Ju='Juaranir:BAAANQAECgEIAQAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Justac:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Justdrood:BAAANQAECgEIAQAAAA==.',
['Jà']='Jàß:BAAANQAECgMIAwAAAA==.',
['Já']='Jáß:BAAANQAECgYICgAAAA==.',
Ka='Kahleah:BAAANQADCgEIAQAAAA==.Kaldonor:BAAANQAECgQIBQAAAA==.Kalenia:BAAANQAECgQIBgAAAA==.Kalvayre:BAAANQAECgEIAQAAAA==.Kanzoorb:BAAANQAECgYICgAAAA==.Kareshka:BAAANQAECggIBwAAAA==.Karinea:BAEANQADCggIDgAAAA==.Karpana:BAEANQAECgQICAAAAA==.Karworg:BAAANQADCggIDwAAAA==.Kashir:BAAANQADCggIEQAAAA==.Kashira:BAAANQADCgYIBgABNQADCggIEQABAAAAAA==.Kathelee:BAAANQAECgIIAgAAAA==.Kazimirah:BAAANQADCgYIDAAAAA==.Kazrael:BAAANQADCgYIDAAAAA==.',
Ke='Kevinbeacon:BAEANQAECgYIAQAAAA==.',
Kh='Khonsu:BAAANQAECgIIAgAAAA==.Khryy:BAAANQADCgUIBQABNQADCgUIBQABAAAAAA==.',
Ki='Kikora:BAAANQADCgcIDQAAAA==.Kittykitty:BAAANQAECgMIBQAAAA==.',
Ko='Kolzane:BAEANQAFFAIIAgAAAA==.',
Kr='Krezz:BAAANQAECgEIAQAAAA==.',
Ku='Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAAANQAECggIDAAAAA==.',
Ky='Kyth:BAAANQAECgEIAQAAAA==.Kythtok:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.',
Li='Lifebloomer:BAAANQADCgcICQABNQAECgkJGgAIAE0kAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQADCggICwAAAA==.Littlehell:BAAANQAECgQIBAAAAA==.',
Lu='Lucaafer:BAAANQADCgYIEQABNQAECgUICgABAAAAAA==.Lunamoonclaw:BAAANQAECgQIBAAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyntrax:BAAANQADCgcIBwAAAA==.',
['Lö']='Löwryder:BAAANQADCgcIDwAAAA==.',
Ma='Mae:BAAANQAECgIIBAAAAA==.Maemura:BAAANQADCgYIDwAAAA==.Magdalaiina:BAAANQAECgEIAQAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magîkarp:BAAANQADCggIFQAAAA==.Malchromatus:BAAANQAECgQIBQAAAA==.Marcosio:BAAANQADCgUIBwAAAA==.Marmaladia:BAAANQADCggIDQAAAA==.Marsala:BAAANQAECgYIDgAAAA==.',
Me='Mearkman:BAAANQADCgcIDwAAAA==.Meatyfajita:BAAANQAECgQIBgAAAA==.Meinfurion:BAAANQAECgEIAQAAAA==.Meladie:BAAANQADCgIIAgAAAA==.Melevolent:BAAANQABCgQIBAAAAA==.Memedecay:BAAANQAECgUIBwAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECgUIBwABAAAAAA==.Merlinthos:BAAANQADCgcIDQABNQAECgMIBQABAAAAAA==.Messra:BAAANQADCgMIAwAAAA==.Metaljack:BAAANQAECgIIAgAAAA==.',
Mi='Miasma:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Midith:BAAANQADCgQIBAAAAA==.Minecraft:BAAANQAECgYIDgAAAA==.Mingyue:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Mirajåne:BAAANQAECgcIEQAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.',
Mo='Modar:BAAANQAECgYICQAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCggIDQAAAA==.',
Mu='Musterd:BAAANQADCgUIBQAAAA==.Muzzin:BAAANQADCgUIBQAAAA==.',
['Må']='Måddløck:BAAANQADCgUICwAAAA==.',
Na='Nahray:BAAANQADCgQIBAAAAA==.Namaera:BAAANQADCgcIBwAAAA==.',
Ne='Neiidra:BAAANQADCgcIBwAAAA==.Nepheleah:BAAANQAECgcIDAAAAA==.Nesca:BAAANQAECgEIAQAAAA==.Nesmoth:BAAANQADCgcIFAAAAA==.Ness:BAAANQAECgMIAwAAAA==.Nessecity:BAAANQADCgYIDAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQABCgIIBAAAAA==.Niiborracho:BAAANQAECgEIAQAAAA==.Niiko:BAAANQADCgYIDgAAAA==.',
No='Nobullsheep:BAAANQABCgQIBAAAAA==.Norntrox:BAAANQAECgEIAQAAAA==.Nothannah:BAAANQAECgcIDAAAAA==.',
Og='Ogreatsxtra:BAAANQADCgYICwAAAA==.',
Ol='Ol:BAAANQADCggICAAAAA==.',
On='Onethiccyboi:BAAANQADCgEIAQAAAA==.Onix:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Or='Orctism:BAAANQADCggIEgAAAA==.',
Ow='Owlsonatotem:BAAANQADCgcIDgAAAA==.',
Oz='Ozhawk:BAAANQAECgEIAQAAAA==.',
Pa='Padreburrito:BAAANQADCgYICwAAAA==.Pakno:BAAANQADCgUIBQAAAA==.Pamely:BAAANQAECgUICwAAAA==.',
Ph='Pharmit:BAAANQAECgMIBQAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
['Pà']='Pàt:BAAANQAECgIIBAAAAA==.',
['Pâ']='Pândâmoníum:BAAANQADCgcIEAAAAA==.',
['På']='Påimon:BAAANQADCgYIDgAAAA==.',
Re='Real:BAAANQAECgQIBQAAAA==.Realia:BAAANQAECgYIBwAAAA==.Redangus:BAAANQADCgIIAgABNQADCgUIBwABAAAAAA==.Reikio:BAAANQABCgIIAgAAAA==.Reptar:BAAANQADCgcIBwABNQAECgkJGQAJADYiAA==.Revoke:BAAANQADCgcIEAAAAA==.',
Ro='Roßyn:BAAANQAECgQIAgAAAA==.',
Ru='Ruroni:BAAANQADCggIFgAAAA==.',
Ry='Ryniel:BAAANQADCgcIDwAAAA==.',
['Ré']='Rédundant:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
['Rì']='Rìzz:BAAANQAECgUIBgAAAA==.',
Sa='Sabrinalee:BAAANQADCgEIAQAAAA==.Saintdeamon:BAAANQADCgYIDAAAAA==.Sak:BAAANQADCgUIBQAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQADCgcIDgAAAA==.Sannaggi:BAAANQAECgEIAQAAAA==.Saramoon:BAAANQAECgIIAwAAAA==.Sargent:BAAANQADCgUIBQAAAA==.Sashchi:BAAANQAECgEIAQAAAA==.Sassenach:BAAANQAECgEIAQAAAA==.Saudelber:BAAANQADCgcIBwAAAA==.',
Sc='Scrotius:BAAANQABCgQIAwAAAA==.',
Se='Sedaelina:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Sehmet:BAAANQADCgYICwAAAA==.Seliria:BAAANQAECgIIAgAAAA==.Seoulmate:BAAANQAECgQIBgAAAA==.Sera:BAAANQAECgIIAgAAAA==.',
Sh='Shadowk:BAAANQABCgIIAgAAAA==.Shaye:BAAANQADCgYICwAAAA==.Shelari:BAAANQABCgIIAgAAAA==.Shieldbro:BAAANQADCgEIAQABNQAECgYIBQABAAAAAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgcIFgAAAA==.Shotfoot:BAAANQAECgQIBAAAAA==.Shwang:BAAANQADCggIFQAAAA==.',
Si='Silentio:BAAANQAECgMIBQAAAA==.Silihunt:BAAANQAECgMIAwAAAA==.Sinofwrath:BAAANQAECgIIBAAAAA==.Sinsidious:BAAANQADCggIDgAAAA==.Siwin:BAEBNQAECoEYAAMKAAkJ6SUxAADbAwAKAAkJ6SUxAADbAwAJAAIJyRU/SwB4AAAAAA==.',
Sk='Skribb:BAAANQAECgQIBgAAAA==.',
Sm='Smiley:BAAANQAECgcIDQAAAA==.Smoko:BAAANQADCgYIDQAAAA==.',
Sn='Sneakyboi:BAAANQAECgYIBQAAAA==.Snorlax:BAAANQAECgQIBQAAAA==.Snowsu:BAAANQAFFAIIAgAAAA==.Snowxstorm:BAAANQAECgIIAgAAAA==.',
So='Soaringeagle:BAAANQABCgQIBgAAAA==.Solidvodka:BAAANQAECgEIAQAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAAANQAECgIIAgAAAA==.',
Sp='Splashzone:BAAANQADCggIEwAAAA==.',
St='Staqua:BAAANQADCgYIDAAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Summdari:BAAANQAECgMIBQAAAA==.Sunfrostt:BAAANQADCgcIDAAAAA==.',
Sy='Syanana:BAAANQADCgYIBgAAAA==.Sylvalesta:BAAANQADCgYIDAAAAA==.',
Ta='Tacgnol:BAAANQADCgYIBgAAAA==.Talyon:BAAANQAECgEIAQAAAA==.Tanayla:BAAANQADCgYIBgAAAA==.',
Te='Tekeeladin:BAAANQADCgIIAwABNQAECgUIBgABAAAAAA==.Tekeelà:BAAANQAECgQIBAABNQAECgUIBgABAAAAAA==.Tekelemental:BAAANQAECgQICAAAAA==.Tempestra:BAAANQADCggIFQAAAA==.Tenebria:BAAANQAECgcIBwAAAA==.Terrorhungry:BAAANQADCggIEgAAAA==.',
Th='Thalstrasza:BAAANQAECgQIBQAAAA==.The:BAAANQADCgcIEAAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAAANQAECgQIBQAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tietus:BAAANQADCgcIBwAAAA==.',
Tl='Tlanimass:BAAANQAECgEIAQAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAECgcIEgABAAAAAA==.',
Ts='Tsyubaki:BAAANQAECgQIBAAAAA==.',
Tw='Twerkngherkn:BAAANQADCgUICwAAAA==.',
Ty='Tybalt:BAAANQAECggIBQAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.',
Ul='Uldric:BAAANQAECgEIAQAAAA==.',
Un='Undeaddude:BAAANQABCgYIBgAAAA==.Unslayable:BAAANQADCggIFQAAAA==.',
Uz='Uzzy:BAAANQADCgYIDQAAAA==.',
Va='Valandir:BAAANQADCggIDAAAAA==.Valyst:BAAANQADCgYIDAAAAA==.Varya:BAAANQABCgQIAwAAAA==.',
Ve='Veliry:BAAANQADCgYIDwAAAA==.Verbera:BAAANQAECgcIDwAAAA==.Verrenth:BAAANQADCgcIDAABNQAECgYIBQABAAAAAA==.',
Vi='Viduus:BAAANQADCgYIDQAAAA==.',
Vo='Voidrodent:BAAANQAECggIBgAAAA==.Voidwithin:BAAANQAECgQIBgAAAA==.Voljinforeva:BAAANQADCgQIBgAAAA==.',
Vu='Vulfox:BAAANQAECgMIBQAAAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQADCgYICgAAAA==.Warwickk:BAAANQABCgIIAgABNQADCgUIBQABAAAAAA==.',
Wi='Wickedholi:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.Wickedsmaht:BAAANQAECgcIEgAAAA==.Widowghast:BAAANQAECgIIAgAAAA==.Willowísp:BAAANQAECgQIBwAAAA==.Witerally:BAAANQADCgYICgAAAA==.',
Wo='Woggers:BAAANQADCgYICwAAAA==.',
Wu='Wujo:BAEANQAECgEIAQAAAA==.',
Xa='Xalthea:BAAANQAECggICgAAAA==.Xandapriest:BAAANQADCgYICwABNQAECgcIDAABAAAAAA==.Xanlock:BAAANQADCgIIAgAAAA==.',
Xi='Xingyue:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.',
Xp='Xpddevour:BAAANQAECgUIBgAAAA==.',
Xt='Xtena:BAAANQADCgIIAgAAAA==.Xtendron:BAAANQAECgcIEAAAAA==.',
Ye='Yegarmiester:BAAANQADCgcIBwAAAA==.Yenti:BAAANQADCgcIFgAAAA==.',
['Yâ']='Yâni:BAAANQADCgIIAgAAAA==.',
Za='Zaco:BAAANQAECgQIBAAAAA==.Zap:BAAANQADCgYICgABNQAECgQIBQABAAAAAA==.',
Zi='Ziggie:BAAANQAECgIIAgAAAA==.',
Zo='Zookee:BAAANQADCggIEwAAAA==.',
Zu='Zulizek:BAAANQAECgMIAwAAAA==.',
['Ûr']='Ûrta:BAAANQADCgEIAQAAAA==.',
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
