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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Druid-Balance','Shaman-Enhancement','DemonHunter-Devourer','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Warrior-Arms','Warrior-Protection','Hunter-Marksmanship','Hunter-Survival','Priest-Shadow','Druid-Guardian','Paladin-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abdorei:BAAANQAECgYIEAAAAA==.',
Ac='Accilatim:BAAANQAECgcIDgAAAA==.',
Ag='Aggressive:BAAANQAECgIIAgAAAA==.Agries:BAAANQADCgYIAgAAAA==.',
Ai='Aiba:BAAANQAECgQICAABNQAECgUICQABAAAAAA==.',
Ak='Akcloud:BAAANQAECgcIDwAAAA==.',
Al='Alexei:BAAANQAECgMIBAAAAA==.Allhopeisded:BAAANQAECgEIAQAAAA==.',
An='Andii:BAAANQAECgcIDwAAAA==.Anglecat:BAAANQAECgYIDQAAAA==.Angusbeef:BAAANQAECgQICwAAAA==.',
Ar='Ardon:BAAANQAECgUICAAAAA==.',
As='Asteruis:BAABNQAECoEZAAICAAkKjhzeGAAFAwACAAkKjhzeGAAFAwAAAA==.Asuraa:BAAANQADCgIIAgAAAA==.',
Av='Avoral:BAAANQADCgEIAQAAAA==.',
Ba='Bafoonery:BAAANQADCgUIBQAAAA==.Bananashoes:BAAANQABCgEIAQAAAA==.Barkendremix:BAAANQADCgYIBgABNQAECgUIDAABAAAAAA==.Bathsheber:BAAANQADCgYIBgABNQAFFAUICQADAGcgAA==.Baulbuster:BAAANQAECgEIAQAAAA==.',
Be='Bearden:BAABNQAECoEiAAIEAAgKpyKSDwAsAwAEAAgKpyKSDwAsAwAAAA==.Belroy:BAAANQAECgEIAQAAAA==.',
Bi='Bighani:BAAANQAECgQIBAABNQAECgUIEQABAAAAAA==.',
Bj='Bjorum:BAABNQAECoEbAAIFAAgKJiJSBgD9AgAFAAgKJiJSBgD9AgAAAA==.',
Bo='Bodytwodafa:BAAANQAECgcIDAABNQAECgkJFgAGAJsSAA==.',
Br='Broken:BAAANQAECgQIBQAAAA==.Brucecampbel:BAAANQAECgEJAgAAAA==.',
Bu='Bubbleyou:BAAANQAECgUIBgAAAA==.',
['Bé']='Bécca:BAAANQAECgIIAwAAAA==.',
Ca='Calerina:BAAANQAECgIIAgAAAA==.Cantarella:BAAANQAECgYIEQAAAA==.Carlyle:BAABNQAECoEbAAMHAAgKJQwmjwCcAQAHAAcKfA0mjwCcAQAIAAIKPwyr2QBjAAAAAA==.Casadora:BAAANQABCgQIBgAAAA==.Caylara:BAAANQADCgYIBgAAAA==.',
Ch='Cheesecake:BAAANQADCgEIAQAAAA==.',
Cl='Claoibh:BAAANQAECgEJAQABNQAECgYIEAABAAAAAA==.',
Co='Collossuss:BAAANQADCggIEQAAAA==.Corno:BAAANQAECgIIAgAAAA==.',
Cu='Cuddles:BAAANQADCggIBwAAAA==.',
Da='Dafa:BAABNQAECoEWAAIGAAkKmxJAGQBeAgAGAAkKmxJAGQBeAgAAAA==.Dafaw:BAAANQAECgEIAQAAAA==.Darkstarr:BAAANQADCgcIIAAAAA==.Darwynne:BAAANQADCgEIAQAAAA==.',
De='Deddafa:BAAANQAECgIIAgAAAA==.Dekaar:BAAANQAECgQIBAAAAA==.Desdemonica:BAAANQAECgMICgAAAA==.',
Di='Diaff:BAAANQADCgMIAwAAAA==.Dillythewily:BAAANQADCggICAAAAA==.Dirtyspice:BAAANQAECgQICAAAAA==.',
Do='Domain:BAAANQAECgUIEQAAAA==.Domotouch:BAAANQAECgMIBQABNQAECgQICgABAAAAAA==.Donfalprun:BAABNQAECoEWAAIHAAgKiBwETABiAgAHAAgKiBwETABiAgAAAA==.Donot:BAAANQADCgcICAAAAA==.Doomstout:BAABNQAECoEWAAIJAAgK0RnoegBQAgAJAAgK0RnoegBQAgAAAA==.',
Dr='Draconus:BAAANQAECgUIAQAAAA==.Dralas:BAAANQAECgUIDgAAAA==.',
Du='Durex:BAABNQAECoEfAAIKAAgK7xdnWAA+AgAKAAgK7xdnWAA+AgAAAA==.Duskstout:BAAANQADCggIDgAAAA==.',
Ea='Earthcrusher:BAAANQADCgEJAgAAAA==.',
El='Eldron:BAAANQAECgUIDAAAAA==.Elij:BAAANQAECgUICAAAAA==.Elunaire:BAAANQADCgYJCQAAAA==.',
Em='Emelec:BAAANQADCgYJBgAAAA==.Emeraldwish:BAAANQAECgcIEAAAAA==.',
Es='Eskimojoe:BAAANQADCgYICQAAAA==.',
Ev='Evinco:BAAANQAECgYIDQAAAA==.',
Ex='Executie:BAACNQAFFIEHAAIKAAQKuRObEAA7AQAKAAQKuRObEAA7AQA1AAQKgSYAAwoACQoVIyQRAGMDAAoACQoVIyQRAGMDAAsABArOGMgcABIBAAAA.',
Ez='Ezmerrelda:BAAANQAECgQIBQAAAA==.',
Fa='Fancy:BAAANQAECgQIBAAAAA==.',
Fi='Fieryember:BAAANQAECgIIAgABNQAECgUIEQABAAAAAA==.Finni:BAAANQADCggJCAAAAA==.Fistvendor:BAAANQADCgYIBgAAAA==.',
Fl='Flasheals:BAABNQAECoEdAAIIAAgKoxiCNQBSAgAIAAgKoxiCNQBSAgAAAA==.',
Fr='Frostwave:BAAANQAECgQICwAAAA==.',
Fu='Fujiyama:BAAANQAECgQICgAAAA==.',
Gn='Gnometoaster:BAAANQAECgYICAAAAA==.',
Go='Goldendk:BAAANQAECgQIBAAAAA==.Goldendwarf:BAAANQAECgQIBgAAAA==.Goldenshield:BAAANQAECgYIBgAAAA==.',
Gr='Gravewrath:BAAANQADCgUJBwAAAA==.Groggi:BAAANQADCgIJAgAAAA==.',
Gu='Gunjamon:BAAANQADCgQICAAAAA==.',
Ha='Halppme:BAAANQAECgYIDAAAAA==.',
Ho='Hoowan:BAAANQADCgEIAQAAAA==.Horraoibhy:BAAANQAECgYIEAAAAA==.',
Im='Immogen:BAAANQADCgMIAwAAAA==.',
Is='Isklexi:BAABNQAECoEWAAIEAAcKYBLnPgCxAQAEAAcKYBLnPgCxAQAAAA==.',
Iy='Iyatil:BAAANQAECgIJAgAAAA==.',
Ja='Jabjek:BAAANQADCgYIBgAAAA==.Jamaz:BAAANQAECgEJAQAAAA==.Jamdalf:BAAANQAECgIIBAAAAA==.Jamocalypse:BAAANQAECgEIAQAAAA==.Jazal:BAAANQADCggIEgAAAA==.',
Jt='Jtull:BAAANQADCgYICgAAAA==.',
Ka='Kanamé:BAAANQADCggICAAAAA==.',
Ke='Kelisa:BAAANQAECgUIAQAAAA==.Keramono:BAAANQADCgQIBAAAAA==.',
Ki='Kimaera:BAAANQADCgMIAgAAAA==.Kimjunggheal:BAAANQABCgQIBAAAAA==.',
Kr='Kreshath:BAAANQADCgYICQAAAA==.Krinxy:BAAANQADCgYIBgAAAA==.',
Ku='Kuratcha:BAAANQAECgQIDAABNQAECgUIEQABAAAAAA==.',
['Kí']='Kíng:BAAANQAECgQIBwABNQAECgUIEQABAAAAAA==.',
La='Ladelock:BAAANQAECgQICwAAAA==.',
Le='Leaf:BAAANQAECgYICAAAAA==.',
Li='Liadan:BAAANQAECgYIEQAAAA==.Lighteye:BAAANQAECgQICQAAAA==.Linesdel:BAAANQADCgcIBwAAAA==.',
Lo='Lomm:BAAANQAECgUIDAAAAA==.',
Ma='Macklerina:BAAANQAECgYIDAAAAA==.Magicdorf:BAAANQAECgYIEQAAAA==.Manhitrogue:BAAANQAECgEIAQAAAA==.',
Mc='Mcgavin:BAAANQAECgIIAgAAAA==.',
Me='Megarayquaza:BAAANQAECgcIDgAAAA==.',
Mi='Mikeyouk:BAAANQADCgUICAAAAA==.Minimum:BAAANQAECgcIDAAAAA==.Misties:BAAANQADCgQIBAAAAA==.',
Mo='Monnöke:BAAANQAECgQICwAAAA==.Mooneater:BAAANQAECgUIDwAAAA==.',
My='Myrolan:BAAANQAECgYIDQAAAA==.',
Na='Naturallight:BAAANQADCgYIBgAAAA==.',
Ne='Nergaoul:BAAANQADCgYIBgAAAA==.Nevyn:BAAANQAECgUICgAAAA==.',
Ni='Nightsage:BAAANQADCgIJAwAAAA==.Nightslayer:BAAANQAECgQICQAAAA==.Niji:BAAANQAECgUICQAAAA==.Nininhp:BAAANQADCgYIGAABNQAECgEIAQABAAAAAA==.Nithari:BAAANQAECgQJCAAAAA==.',
No='Nosst:BAAANQADCgQIBwAAAA==.Nostdormu:BAAANQADCgMIAwAAAA==.Nostu:BAAANQAECgcIEgAAAA==.Now:BAAANQAECgcJDQAAAA==.',
Oa='Oathra:BAAANQAECgYIDwAAAA==.',
Oh='Ohpa:BAAANQAECgUIEAAAAA==.',
Oj='Ojikan:BAAANQAECgcIEQAAAA==.',
Pa='Paje:BAAANQADCgUIBQAAAA==.Panday:BAAANQADCgIIAgAAAA==.Pathogenn:BAAANQADCgYIBQAAAA==.',
Pe='Peachoolong:BAAANQAECggIDgAAAA==.Peludisho:BAAANQADCgMIAwABNQAFFAIIAgABAAAAAA==.',
Ph='Phoblade:BAAANQAECgMIBAAAAA==.Phobreeze:BAAANQAECgQIBwAAAA==.Phogurl:BAAANQADCgQIBAAAAA==.',
Pi='Pirotess:BAABNQAECoEYAAIHAAgKchnKUABSAgAHAAgKchnKUABSAgAAAA==.',
Po='Popz:BAAANQADCgEIAQAAAA==.Pororo:BAAANQAECgEJAQAAAA==.',
Pr='Preorcthego:BAACNQAFFIEGAAMMAAQK8RLzDgDpAAAMAAMK0RXzDgDpAAACAAIKGxGxGACfAAA1AAQKgRwABAwACQpFHC4SAKkCAAwACQpoGy4SAKkCAA0ABAqPEZILAMUAAAIAAQo1I10AAWYAAAAA.Presiric:BAAANQADCgEJAgAAAA==.',
Pu='Puppye:BAAANQAECgQICAAAAA==.',
Re='Reeapally:BAABNQAECoEZAAMHAAcKPhWngADDAQAHAAcKPhWngADDAQAIAAYKTAhUjwAcAQAAAA==.Reylord:BAAANQADCgUICwAAAA==.',
Rh='Rheizen:BAAANQAECgYIDwAAAA==.',
Ro='Ropopo:BAAANQAECgIIAwABNQAECgQICAABAAAAAA==.',
['Rö']='Röyksopp:BAAANQAECgMICQAAAA==.',
Sa='Salbahe:BAAANQADCgUIBQAAAA==.Samarah:BAAANQADCgIJAgAAAA==.Sandewor:BAAANQADCgYICAABNQADCggJFwABAAAAAA==.Sarafyn:BAAANQAECgQJCAAAAA==.Sauceguzzler:BAAANQADCgYIBAAAAA==.',
Se='Seragaki:BAAANQAECgQIDwAAAA==.',
Sh='Sheepwarrior:BAAANQAECgcIEgAAAA==.',
Si='Siegescale:BAAANQAECgMICAAAAA==.Siegrorc:BAAANQADCgcIEwAAAA==.Sindrila:BAAANQAECgIIBAAAAA==.Sionshope:BAAANQADCgIJAwAAAA==.',
Sl='Slaybelle:BAAANQADCgcIBwAAAA==.Slayerhunt:BAAANQADCggJFwAAAA==.Slayerlock:BAAANQADCgUIAQAAAA==.Slayertin:BAAANQADCgYIFAABNQADCggJFwABAAAAAA==.Sleptforever:BAAANQAECgQICgAAAA==.Slumped:BAAANQADCgEIAQAAAA==.',
So='Sorian:BAAANQADCgEIAQAAAA==.',
St='Stonehand:BAABNQAECoElAAIOAAkKOxffEQCiAgAOAAkKOxffEQCiAgAAAA==.Strongbow:BAAANQAECgUIDQAAAA==.',
Su='Subudai:BAAANQAECgYIDgAAAA==.Sugarboi:BAABNQAECoEZAAIPAAgKhw7IFgB3AQAPAAgKhw7IFgB3AQAAAA==.',
Sx='Sxytrev:BAAANQAECgEIAQAAAA==.',
Ta='Tatonka:BAAANQADCgEIAQAAAA==.Tatsuryu:BAAANQABCgYJBgAAAA==.',
Tb='Tbizkut:BAAANQAECgEIAQAAAA==.',
Th='Then:BAAANQAECgcIEgAAAA==.Thisfar:BAAANQAECgIIAgABNQAECgQICgABAAAAAA==.',
Ti='Timemaster:BAAANQADCgIJAwAAAA==.',
To='Tokido:BAAANQAECgIIAgAAAA==.Tongpakfu:BAAANQAECgEIAQAAAA==.Topflight:BAAANQAECgQIBwAAAA==.',
Tr='Trailblazegu:BAAANQADCgYIDwAAAA==.Troiikka:BAAANQAECgQIBQAAAA==.Troiikâ:BAABNQAECoEZAAIQAAYK+wv7LQAUAQAQAAYK+wv7LQAUAQAAAA==.Troikä:BAAANQADCgIIAgAAAA==.',
Tz='Tzolkin:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
Ul='Uldirtydemon:BAABNQAECoEaAAMGAAcK9xwLGgBUAgAGAAcK9xwLGgBUAgARAAEKOwzwbQBCAAAAAA==.Uldirtydruid:BAAANQAECgEIAQAAAA==.',
Un='Unsamana:BAAANQAECgQIBwABNQAECgUIEQABAAAAAA==.',
Up='Update:BAAANQAECgcIEAAAAA==.',
Uw='Uwantwar:BAAANQADCggIEAAAAA==.',
Ve='Velari:BAAANQADCggICAAAAA==.',
Vi='Vidich:BAAANQAECgMIBQAAAA==.Viralus:BAAANQADCgcICQAAAA==.',
Vo='Vomai:BAAANQADCggIHAAAAA==.',
Wa='Wanaatlarboy:BAAANQAECgcIEgAAAA==.Waywyrd:BAAANQAECgMIAwAAAA==.',
Wu='Wunderbar:BAAANQAECgQICwAAAA==.Wunderburger:BAAANQADCgIIAgAAAA==.Wunderground:BAAANQADCgIIAgAAAA==.',
Xa='Xannada:BAAANQADCgYICQAAAA==.',
Xo='Xodiak:BAAANQAECgQIBwAAAA==.',
Yo='Yodadogownz:BAAANQADCgEIAQAAAA==.Yoh:BAAANQAECgcIDwAAAA==.',
Za='Zarutobi:BAAANQAECgQIBQABNQAECgUICQABAAAAAA==.',
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
