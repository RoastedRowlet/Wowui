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

local lookup = {'Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Ababear:BAAANQADCgYICwAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Ahnna:BAAANQADCgEIAQAAAA==.',
Al='Alarrius:BAAANQAECgIIAgAAAA==.Allionys:BAAANQADCggIDgAAAA==.Aloris:BAAANQADCggIDQAAAA==.',
Am='Amanises:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.Amilara:BAAANQADCgUICQAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Anania:BAAANQADCgUIBgABNQADCgUIBwABAAAAAA==.Andinestiri:BAAANQADCggIBgAAAA==.Andolastrasz:BAAANQADCgYICgAAAA==.Angelic:BAAANQADCgcIBwAAAA==.',
Ao='Ao:BAAANQAECgEIAQAAAA==.',
Ap='Apotic:BAAANQAECgEIAQAAAA==.',
Aq='Aquamaree:BAAANQADCgYICAAAAA==.Aquilla:BAAANQAECggIDQAAAA==.',
Ar='Archenea:BAAANQADCggIDwAAAA==.Archenore:BAAANQADCggICAAAAA==.Ariisa:BAAANQADCgUIBwAAAA==.Around:BAAANQADCgQIBgABNQADCgcIDgABAAAAAA==.',
As='Askip:BAAANQADCgIIAgAAAA==.Astrud:BAAANQADCgUICQAAAA==.Asukka:BAAANQADCgMIAwAAAA==.Asëya:BAAANQADCggIDgAAAA==.',
At='Atomique:BAAANQAECgIIBAABNQAECgYICQABAAAAAA==.Attenborough:BAAANQADCgYIBgAAAA==.',
Av='Avesa:BAAANQADCgUIBgAAAA==.Avoidant:BAAANQADCgYICQAAAA==.',
Az='Azazell:BAAANQADCgUICAAAAA==.Azenea:BAAANQADCggIDgAAAA==.',
Ba='Babomage:BAEANQAECgcIDQAAAA==.Baculum:BAAANQADCgcIDQAAAA==.Baieghzieghl:BAAANQADCgUIBQAAAA==.',
Be='Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAAANQADCgcIBwAAAA==.',
Bi='Bigbutter:BAAANQADCgUICgAAAA==.Bittydrood:BAAANQADCgYIBwAAAA==.Bittylexis:BAAANQADCgcIDQAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAAANQAECgIIAgAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Blèu:BAAANQADCggIEAAAAA==.',
Br='Braggs:BAAANQADCgMIBAAAAA==.Brewballs:BAAANQADCggIDQAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCgEIAQAAAA==.Bucket:BAAANQADCgYIBgAAAA==.Bunnicula:BAAANQAECgEIAQAAAA==.',
['Bö']='Böömer:BAAANQADCgUIEQAAAA==.',
Ca='Caelphia:BAAANQADCgYICgAAAA==.Caimage:BAAANQAECgUIBgAAAA==.Cainnaszun:BAAANQADCgEIAQABNQADCgUIBgABAAAAAA==.Cainnaszunn:BAAANQADCgUIBgAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Caythus:BAABNQAECoERAAQCAAkJFSQZAQBQAwACAAkJuCMZAQBQAwADAAMJ9iCkIgAqAQAEAAEJFyb+BwBwAAAAAA==.Caythuz:BAABNQAECoENAAMDAAcJmiAODQDvAQADAAYJRyAODQDvAQACAAUJGhrzFAB6AQABNQAECgkJEQACABUkAA==.',
Ce='Celeana:BAAANQADCgQIBAAAAA==.Ceryin:BAAANQADCgIIAgAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chainheal:BAAANQABCgIIAgAAAA==.Chakabad:BAAANQADCgYIBwAAAA==.Chalgah:BAAANQADCgIIAgAAAA==.Chenahala:BAAANQADCgYIBwAAAA==.Chåni:BAAANQAFFAEIAQAAAA==.',
Ck='Ckayz:BAAANQADCggIDgAAAA==.',
Cl='Clam:BAAANQADCgcIBwAAAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQADCgcICQAAAA==.Coldstonez:BAAANQADCgQIBAAAAA==.Conanascus:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.Corrupteded:BAAANQADCgUIBQAAAA==.',
Cr='Crispysock:BAAANQADCgcICwAAAA==.Crowe:BAAANQADCgQIBgAAAA==.',
Cy='Cynderr:BAAANQADCggIEwAAAA==.',
Da='Daisymayhem:BAAANQABCgQIBQAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkisis:BAAANQADCgYIBwAAAA==.Darknara:BAAANQAECgQIBgAAAA==.Darkzy:BAAANQAECgEIAgAAAA==.Dartol:BAAANQADCgUICAAAAA==.Dawni:BAAANQADCgUICAAAAA==.',
De='Deathjeff:BAAANQADCgcICwAAAA==.',
Di='Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQADCgYIDAAAAA==.Dirtwhistle:BAAANQAECgYIBgAAAA==.',
Dr='Dragondh:BAAANQAECgUIBgAAAA==.Drosi:BAAANQADCggIDwAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
Ea='Earthesance:BAAANQADCgIIAgAAAA==.',
Eb='Ebeb:BAAANQADCgcIDQAAAA==.',
Ei='Eiwe:BAAANQADCgMIAwAAAA==.',
El='Eleanne:BAAANQADCgcIDQAAAA==.Electricfury:BAAANQADCgYIDAAAAA==.Ellebasi:BAAANQADCgUICQAAAA==.Ellebazy:BAAANQADCggIDAAAAA==.',
Em='Emmri:BAAANQADCgYICAAAAA==.Empty:BAAANQAECgIIAgAAAA==.',
En='Enazen:BAAANQADCgcICwAAAA==.Enlighthyn:BAAANQAECgcICwAAAA==.',
Er='Erlas:BAAANQADCgIIAgAAAA==.Erui:BAAANQADCgYIBwAAAA==.',
Ev='Evilrayne:BAAANQAECgIIAgAAAA==.',
Fa='Fanfiction:BAAANQADCgYIBgAAAA==.Fatherfingur:BAAANQADCgEIAQAAAA==.',
Fe='Featara:BAAANQADCgEIAQAAAA==.Felmonger:BAAANQADCggICwAAAA==.Feloak:BAAANQADCggIDQAAAA==.Feredir:BAAANQADCgUICQAAAA==.',
Fi='Fires:BAAANQAECgIIAgAAAA==.',
Fo='Folexper:BAAANQADCgYIBwAAAA==.',
Fr='Frostman:BAAANQAECgEIAQAAAA==.',
Fu='Furryfury:BAAANQAECgMIAwAAAA==.Fusrodah:BAAANQAECgEIAQAAAA==.Fuzzyewok:BAAANQADCggIDwAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAgAAAA==.Gameshark:BAAANQADCgYICwAAAA==.Gawdzirra:BAAANQADCgcIDQAAAA==.Gaylordgerva:BAAANQADCgIIAwAAAA==.Gaz:BAAANQADCggIDgAAAQ==.',
Ge='George:BAAANQADCgMIAwAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Go='Gohibasi:BAAANQADCgQIBAAAAA==.Gossamerfeet:BAAANQAECgEIAQAAAA==.',
Gr='Graceosilver:BAAANQADCgUIBwAAAA==.Gregnor:BAAANQADCggIDwAAAA==.Gremöry:BAAANQAECgQIBQAAAA==.Grover:BAAANQAECgEIAQAAAA==.Grumpybunbun:BAAANQAECgEIAQAAAA==.Grüm:BAAANQADCgUICQAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAAANQADCgYICAAAAA==.',
Ha='Hairypotter:BAAANQADCgIIAwABNQADCgYIBwABAAAAAA==.Hallie:BAAANQADCgUIBwAAAA==.Harlu:BAAANQADCggIDQAAAA==.Hartbroke:BAAANQADCggICAAAAA==.',
He='Helbourne:BAAANQADCggIDgAAAA==.',
Hu='Huna:BAAANQADCgYIBgAAAA==.',
Hw='Hwanwok:BAAANQAECgEIAgAAAA==.',
Id='Ideal:BAAANQADCgEIAQAAAA==.',
Ig='Ignited:BAAANQADCgUICQAAAA==.',
Im='Imadragon:BAAANQAECgMIAwAAAA==.Imbac:BAAANQADCgIIAgAAAA==.Imdeadguy:BAAANQAECgEIAQAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCgYICwAAAA==.Ironhelmhtr:BAAANQADCgUIBQAAAA==.Ironscythe:BAAANQADCgIIAgAAAA==.',
Ja='Jazlee:BAAANQADCggIDQAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Jezmund:BAAANQADCggIDgAAAA==.',
Ji='Jinathy:BAAANQAECgEIAQAAAA==.',
Ju='Juaranir:BAAANQADCgYICQAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Justac:BAAANQADCgEIAQAAAA==.',
['Já']='Jáß:BAAANQAECgQIBAAAAA==.',
Ka='Kaldonor:BAAANQAECgEIAQAAAA==.Kalenia:BAAANQAECgIIAgAAAA==.Kalvayre:BAAANQADCgUIBwAAAA==.Kanzoorb:BAAANQAECgQIBAAAAA==.Karinea:BAEANQADCgcIDQAAAA==.Karpana:BAEANQAECgQIBAAAAA==.Karworg:BAAANQADCgYIBwAAAA==.Kashir:BAAANQADCgUICQAAAA==.Kazimirah:BAAANQADCgQIBgAAAA==.Kazrael:BAAANQADCgQIBgAAAA==.',
Ki='Kikora:BAAANQADCgYIBgAAAA==.Kittykitty:BAAANQAECgIIAgAAAA==.',
Ko='Kolzane:BAEANQAECgcICwAAAA==.',
Kr='Krezz:BAAANQADCggIDgAAAA==.',
Ku='Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAAANQAECgQIBQAAAA==.',
Ky='Kyth:BAAANQADCgcICAAAAA==.',
La='Laquatas:BAAANQADCggIBgAAAA==.',
Li='Lifebloomer:BAAANQADCgYIBwABNQAECggIDwABAAAAAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQADCgMIAwAAAA==.Littlehell:BAAANQADCgcIBwAAAA==.',
Lu='Lucaafer:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Lunamoonclaw:BAAANQADCgcICgAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyzoldas:BAAANQADCggIBgAAAA==.',
['Lö']='Löwryder:BAAANQADCgQICAAAAA==.',
Ma='Mae:BAAANQAECgEIAQAAAA==.Maemura:BAAANQADCgUICQAAAA==.Magdalaiina:BAAANQADCggIDgAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magîkarp:BAAANQADCgcIDAAAAA==.Malchromatus:BAAANQAECgEIAQAAAA==.Marcosio:BAAANQADCgIIAgAAAA==.Marmaladia:BAAANQADCgUIBQAAAA==.Marsala:BAAANQAECgYICgAAAA==.',
Me='Mearkman:BAAANQADCgQICAAAAA==.Meatyfajita:BAAANQAECgIIAgAAAA==.Meinfurion:BAAANQADCgYICgAAAA==.Memedecay:BAAANQAECgIIAgAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Merlinthos:BAAANQADCgUIBgABNQAECgIIAgABAAAAAA==.Metaljack:BAAANQADCggIDwAAAA==.',
Mi='Miasma:BAAANQADCgUIBQAAAA==.Midith:BAAANQADCgMIAwAAAA==.Minecraft:BAAANQAECgYICgAAAA==.Mingyue:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Mirajåne:BAAANQAECgYICgAAAA==.Mishaweha:BAAANQADCggIBgAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.Mistlegend:BAAANQADCgcICAAAAA==.',
Mo='Modar:BAAANQAECgMIAwAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCgUIBQAAAA==.',
Mu='Musterd:BAAANQADCgUIBQAAAA==.Muzzin:BAAANQADCgQIBAAAAA==.',
['Må']='Måddløck:BAAANQADCgUIBgAAAA==.',
Na='Nahray:BAAANQADCgEIAQAAAA==.',
Ne='Neiidra:BAAANQADCgUIBQAAAA==.Nepheleah:BAAANQAECgUIBQAAAA==.Nesca:BAAANQAECgEIAQAAAA==.Nesmoth:BAAANQADCgcIDQAAAA==.Ness:BAAANQADCgcICwAAAA==.Nessecity:BAAANQADCgYIDAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQABCgIIBAAAAA==.Niiborracho:BAAANQADCgcICQAAAA==.Niiko:BAAANQADCgUICAAAAA==.',
No='Norntrox:BAAANQADCggIDQAAAA==.Nothannah:BAAANQAECgQIBQAAAA==.',
Og='Ogreatsxtra:BAAANQADCgQIBQAAAA==.',
On='Onix:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Or='Orctism:BAAANQADCggICAAAAA==.',
Ow='Owlsonatotem:BAAANQADCgcIDgAAAA==.',
Oz='Ozhawk:BAAANQADCggIDgAAAA==.',
Pa='Padreburrito:BAAANQADCgYICwAAAA==.Pakno:BAAANQADCgUIBQAAAA==.Pamely:BAAANQAECgQIBAAAAA==.',
Ph='Pharmit:BAAANQAECgMIAwAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
['Pâ']='Pândâmoníum:BAAANQADCgUICQAAAA==.',
['På']='Påimon:BAAANQADCgYICwAAAA==.',
Re='Real:BAAANQAECgEIAQAAAA==.Realia:BAAANQAECgEIAQAAAA==.Reikio:BAAANQABCgIIAgAAAA==.Reptar:BAAANQADCgcIBwAAAA==.Revoke:BAAANQADCgYICQAAAA==.',
Ro='Roßyn:BAAANQAECgIIAgAAAA==.',
Ru='Rubah:BAAANQADCggIBgAAAA==.Ruroni:BAAANQADCgcIDQAAAA==.',
Ry='Ryniel:BAAANQADCgUICAAAAA==.',
['Rì']='Rìzz:BAAANQAECgEIAQAAAA==.',
Sa='Saintdeamon:BAAANQADCgYIDAAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQADCgUIBwAAAA==.Sannaggi:BAAANQAECgEIAQAAAA==.Sarahnox:BAAANQADCggIBgAAAA==.Saramoon:BAAANQAECgEIAQAAAA==.Sargent:BAAANQADCgQIBAAAAA==.Saryaa:BAAANQADCggIBgAAAA==.Sashchi:BAAANQADCgcIDQAAAA==.Sassenach:BAAANQADCgYICgAAAA==.Saudelber:BAAANQADCgUIBQAAAA==.',
Se='Sehmet:BAAANQADCgQIBQAAAA==.Seliria:BAAANQADCggIDwAAAA==.Seoulmate:BAAANQAECgIIAgAAAA==.',
Sh='Shadowk:BAAANQABCgIIAgAAAA==.Shaye:BAAANQADCgUIBQAAAA==.Shelari:BAAANQABCgIIAgAAAA==.Shieldbro:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgYICQAAAA==.Shotfoot:BAAANQADCggIDAAAAA==.Shwang:BAAANQADCgcIDQAAAA==.',
Si='Silentio:BAAANQAECgIIAgAAAA==.Sinofwrath:BAAANQAECgIIAgAAAA==.Sinsidious:BAAANQADCggIDgAAAA==.Siwin:BAAANQAECggIDQAAAA==.',
Sk='Skribb:BAAANQAECgIIAgAAAA==.',
Sm='Smiley:BAAANQAECgcIDQAAAA==.Smoko:BAAANQADCgUIBwAAAA==.',
Sn='Snorlax:BAAANQAECgEIAQAAAA==.Snowsu:BAAANQAECgcIDQAAAA==.Snowxstorm:BAAANQADCggIDwAAAA==.',
So='Solidvodka:BAAANQADCgcICwAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAAANQADCggIDwAAAA==.',
Sp='Splashzone:BAAANQADCgYICwAAAA==.',
St='Staqua:BAAANQADCgQIBgAAAA==.Stateomatter:BAAANQADCggIBgAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Summdari:BAAANQAECgIIAgAAAA==.Summrot:BAAANQADCggIBgAAAA==.Sunfrostt:BAAANQADCgUIBQAAAA==.',
Sy='Sylvalesta:BAAANQADCgQIBgAAAA==.',
Ta='Talyon:BAAANQADCgYIBgAAAA==.',
Te='Tekeeladin:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Tekeelà:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Tekelemental:BAAANQAECgMIBAAAAA==.Tempestra:BAAANQADCgcIDQAAAA==.Tenebria:BAAANQADCgYIBgAAAA==.Terrorhungry:BAAANQADCgYICgAAAA==.',
Th='Thalstrasza:BAAANQAECgEIAQAAAA==.The:BAAANQADCgUICQAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAAANQAECgEIAQAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tietus:BAAANQADCgUIBQAAAA==.',
Tl='Tlanimass:BAAANQADCggIDQAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAECgcICwABAAAAAA==.',
Ts='Tsyubaki:BAAANQADCgYIBgAAAA==.',
Tw='Twerkngherkn:BAAANQADCgUIBwAAAA==.',
Ty='Tybalt:BAAANQAECggIAgAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.',
Ul='Uldric:BAAANQADCggICAAAAA==.',
Un='Unslayable:BAAANQADCggIDQAAAA==.',
Uz='Uzzy:BAAANQADCgYIBwAAAA==.',
Va='Valandir:BAAANQADCgYICgAAAA==.Valyst:BAAANQADCgQIBgAAAA==.',
Ve='Veliry:BAAANQADCgYICQAAAA==.Verbera:BAAANQAECgYICAAAAA==.Verrenth:BAAANQADCgcIDAAAAA==.',
Vi='Viduus:BAAANQADCgQIBwAAAA==.',
Vo='Voidwithin:BAAANQAECgIIAgAAAA==.Voljinforeva:BAAANQADCgIIAgAAAA==.',
Vu='Vulfox:BAAANQAECgMIAwAAAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQADCgUIBgAAAA==.',
Wi='Wickedholi:BAAANQADCgcIBwABNQAECgcICwABAAAAAA==.Wickedsmaht:BAAANQAECgcICwAAAA==.Widowghast:BAAANQADCgEIAQAAAA==.Willowísp:BAAANQAECgMIAwAAAA==.Witerally:BAAANQADCgQIBQAAAA==.',
Wo='Woggers:BAAANQADCgUIBgAAAA==.',
Wu='Wujo:BAEANQADCgcIDAAAAA==.',
Xa='Xalthea:BAAANQAECggIBwAAAA==.Xandapriest:BAAANQADCgYICwABNQAECgUIBQABAAAAAA==.Xanlock:BAAANQADCgIIAgAAAA==.',
Xp='Xpddevour:BAAANQAECgEIAQAAAA==.',
Xt='Xtendron:BAAANQAECgYICQAAAA==.',
Ye='Yenti:BAAANQADCgUIDwAAAA==.',
Za='Zaco:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Zap:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Zi='Ziggie:BAAANQADCgcICgAAAA==.',
Zo='Zookee:BAAANQADCggICwAAAA==.',
Zu='Zulizek:BAAANQADCgcIBwAAAA==.',
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
