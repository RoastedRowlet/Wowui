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

local lookup = {'DeathKnight-Blood','Shaman-Restoration','Unknown-Unknown','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Mage-Arcane','Warlock-Destruction','Warrior-Protection','Warrior-Fury','Paladin-Protection','Warrior-Arms','Monk-Windwalker','Rogue-Subtlety','Paladin-Holy','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Fire','DeathKnight-Frost','Evoker-Devastation','Priest-Holy','Evoker-Augmentation','Shaman-Enhancement','Shaman-Elemental','DemonHunter-Havoc','Paladin-Retribution','Rogue-Assassination','Priest-Shadow','Rogue-Outlaw','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','DeathKnight-Unholy','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aardz:BAAANQADCggIDgAAAA==.',
Ab='Abeblinkin:BAAANQADCgYICQAAAA==.Abraxîs:BAAANQAECgYIBwAAAA==.',
Ac='Acindis:BAABNQAECn84AAIBAAoKcRJJOwAYAgABAAoKcRJJOwAYAgAAAA==.',
Ae='Aeless:BAAANQAECgUIDAAAAA==.Aelless:BAAANQAECgEIAQAAAA==.Aerendal:BAAANQADCgMIAwAAAA==.',
Ah='Ahzure:BAAANQAECgYIDgABNQAECgoKPAACAFAbAA==.',
Ai='Aithinne:BAAANQADCgUICQAAAA==.',
Al='Alch:BAAANQADCgQIDAAAAA==.Aleandi:BAAANQADCgYIBQAAAA==.Aledil:BAAANQAECgYICwAAAA==.Alghul:BAAANQADCgYIBgABNQAECgcICAADAAAAAA==.Alunite:BAAANQADCggICAABNQAECgQICAADAAAAAA==.Alynara:BAABNQAECn85AAIEAAoKGBtzUgB5AgAEAAoKGBtzUgB5AgAAAA==.',
Am='Amalthea:BAABNQAECn8bAAMFAAoKjAZgtQBkAQAFAAoKCgZgtQBkAQAGAAEKMgiILwAzAAAAAA==.Amoredis:BAAANQABCggIGQAAAA==.',
An='Anume:BAAANQADCgYIDgAAAA==.Anwas:BAAANQABCgIIAgAAAA==.',
Ap='Apally:BAAANQADCgUIBQAAAA==.',
Ar='Aragan:BAAANQADCggIDAAAAA==.Arellean:BAAANQADCgQIBAAAAA==.Arese:BAABNQAECn8cAAIHAAgKbB6FaQDgAQAHAAgKbB6FaQDgAQAAAA==.',
As='Asmodea:BAAANQADCgUIBQAAAA==.Asphonix:BAAANQAECgEIAQAAAA==.',
Az='Azzif:BAABNQAECn8gAAMIAAkK9gZsDgDfAAAIAAgKyAdsDgDfAAAFAAgKXAHLKgFoAAAAAA==.',
Ba='Babybluz:BAAANQAECgMIBgAAAA==.Backstabbath:BAAANQADCgQIAwAAAA==.Baifeng:BAAANQABCggIFQAAAA==.Bandayde:BAAANQADCgYIBQAAAA==.Barlas:BAAANQAECgUIBAAAAA==.',
Be='Beauriley:BAABNQAECn8+AAMJAAoKmwtMHAB4AQAJAAoKmwtMHAB4AQAKAAEKdAaZOgAiAAAAAA==.Behomethan:BAAANQAECggIDwAAAA==.Belorc:BAAANQADCgUIBQAAAA==.Berian:BAAANQAECgIIAgAAAA==.',
Bi='Bigpapafreez:BAAANQADCggIDQABNQAECgoKXQALAHcgAA==.Billbetaray:BAABNQAECn8gAAIMAAoKiBl1OABeAgAMAAoKiBl1OABeAgAAAA==.',
Bl='Blux:BAAANQADCgEIAQAAAA==.Bløødsong:BAAANQADCgEIAQAAAA==.',
Bo='Bolton:BAAANQADCgYIBgAAAA==.Bombchele:BAABNQAECn83AAINAAkK9CBDCADnAgANAAkK9CBDCADnAgAAAA==.Bowogibrann:BAAANQADCgQIBAAAAA==.',
Br='Bratticusrex:BAABNQAECn81AAIKAAgK0wn2FwAgAQAKAAgK0wn2FwAgAQAAAA==.Brazier:BAAANQADCggICAAAAA==.Bresowar:BAAANQAECgMIBgAAAA==.Brynthe:BAAANQADCggIFgAAAA==.',
Bu='Bunnylicious:BAABNQAECn8/AAICAAoKWyVsBgCyAwACAAoKWyVsBgCyAwAAAA==.Bunnymedic:BAAANQAECgcIDwABNQAECgoKPwACAFslAA==.',
Ca='Caebrylla:BAABNQAECn8xAAIEAAoKSheXPABeAgAEAAoKSheXPABeAgAAAA==.Cajun:BAABNQAECn80AAIMAAkKrR+aFwDvAgAMAAkKrR+aFwDvAgABNQAFFAcIIgAOAM0YAA==.Calistie:BAAANQADCggICAAAAA==.Callipygea:BAAANQADCgIIAgAAAA==.Calver:BAAANQADCgUIBwAAAA==.Camil:BAAANQADCgMIAwABNQAECgoKOgAEAPgPAA==.Cang:BAAANQABCggIKQAAAA==.Catalina:BAABNQAECn9CAAIPAAoKPh9rFgAkAwAPAAoKPh9rFgAkAwAAAA==.',
Ce='Cecimorte:BAABNQAECn8yAAIBAAkKaROqMwB7AQABAAkKaROqMwB7AQAAAA==.',
Ch='Chargeasap:BAAANQADCgUIBQAAAA==.Charttopper:BAAANQAECgQIBAABNQAECgoKIwAPAKgUAA==.Chinashop:BAAANQAECgQIAwABNQAECgkJFwAQABEfAA==.Chonker:BAABNQAECn9KAAMRAAoKihYyGgA9AgARAAoKihYyGgA9AgASAAkKTxTPPAAQAgAAAA==.Chuckforrest:BAAANQADCgIIAgABNQAECgYIBgADAAAAAA==.',
Ci='Cihato:BAABNQAECn9DAAITAAoKExniFAAZAgATAAoKExniFAAZAgAAAA==.',
Cl='Claye:BAAANQAECgIIAgAAAA==.Cleveistic:BAAANQADCgUIBwABNQAECgMIBgADAAAAAA==.Cleveland:BAAANQAECgMIBgAAAA==.',
Co='Coldshoulder:BAABNQAECn8sAAQHAAgK7xJUsgBAAQAHAAcKRBJUsgBAAQAUAAIKaBTvLgCHAAAVAAIKRA0PCQB2AAAAAA==.Corelas:BAAANQAECgUICgAAAA==.Couchdad:BAAANQAECgUIEgABNQAECgcICAADAAAAAA==.',
Cr='Crazymadman:BAAANQAECgIIAgAAAA==.Crysallis:BAAANQADCggIHgAAAA==.',
Cy='Cynide:BAAANQADCgYJBgAAAA==.Cyyrene:BAAANQABCgEIAQABNQAECgoKJAAWADwUAA==.',
Da='Dall:BAAANQAECgIIAwAAAA==.Damo:BAAANQAECgcICAAAAA==.Danale:BAAANQADCgYJCgAAAA==.Danknugz:BAABNQAECn8UAAIBAAgKNQuAegAOAQABAAgKNQuAegAOAQAAAA==.Dawnson:BAABNQAECn8ZAAIPAAkKKRlUQwAHAgAPAAkKKRlUQwAHAgAAAA==.',
De='Deadscream:BAAANQAECggIBgAAAA==.Deathlich:BAABNQAECn8oAAIWAAoKexfyJwAZAgAWAAoKexfyJwAZAgAAAA==.Demogless:BAAANQAECgYIEgAAAA==.Desyrel:BAAANQAECgIIAgABNQAECgcICAADAAAAAA==.',
Dh='Dharknight:BAAANQAECgUICAAAAA==.Dharkuul:BAAANQABCgYICQABNQAECgUICAADAAAAAA==.',
Di='Didimissfire:BAEBNQAECn9DAAIEAAoK/wuEbQDnAQAEAAoK/wuEbQDnAQAAAA==.Diefatty:BAAANQADCgMIAwAAAA==.',
Do='Doll:BAAANQADCgQIBAAAAA==.',
Dr='Draeven:BAAANQAECgYIDQAAAA==.Dranalis:BAAANQADCgYICAAAAA==.Dredlok:BAAANQADCgYIEAAAAA==.',
Du='Dumonster:BAABNQAECn8YAAIKAAYKgQKqJQCBAAAKAAYKgQKqJQCBAAAAAA==.Dustdevil:BAAANQAECgYICQABNQAECgkJFwAQABEfAA==.',
Ee='Eeaassyy:BAAANQADCgYICQAAAA==.',
El='Elaraa:BAAANQADCgQIBAAAAA==.Eldorath:BAAANQAECgIIAgAAAA==.Elev:BAAANQADCgMIAwAAAA==.Elizabeth:BAAANQADCgUIBQAAAA==.',
Er='Eris:BAAANQADCggICAAAAA==.Erzascar:BAAANQAECgEIAQAAAA==.',
Es='Estrogen:BAABNQAECn8zAAIXAAoK3yR+AwBvAwAXAAoK3yR+AwBvAwAAAA==.',
Ev='Eventhorizon:BAAANQAECgYIAgAAAA==.Evolett:BAAANQADCgQIBAAAAA==.',
Fa='Fatbox:BAABNQAECn9CAAMKAAoKAiKHAgD/AgAKAAoKAiKHAgD/AgAMAAEKrA0uVAEyAAAAAA==.Fayth:BAABNQAECn88AAIYAAoKeh1qMgCeAgAYAAoKeh1qMgCeAgAAAA==.',
Fe='Fearblade:BAAANQADCgMIAwAAAA==.Fearblast:BAAANQAECggIDgAAAA==.Fearkin:BAABNQAECn8yAAMZAAoKCQ6oCQB5AQAZAAoKGg2oCQB5AQAXAAcKxw2WDgBcAQAAAA==.Fenastic:BAABNQAECn8rAAMFAAcKpAftuwBVAQAFAAcKpAftuwBVAQAGAAEKtwd2MAA0AAAAAA==.Feyrah:BAAANQAECgEIAQAAAA==.',
Fi='Fiobhe:BAAANQAECgUICgAAAA==.Fixeruper:BAABNQAECn8cAAIYAAoKVQMIigA7AQAYAAoKVQMIigA7AQAAAA==.',
Fo='Fonz:BAAANQADCgYIBgABNQAECgQIEwADAAAAAA==.',
['Fí']='Físter:BAAANQADCgMIAwABNQAECgoKLAAaAHccAA==.',
Ga='Gajeal:BAAANQAECgYIDAAAAA==.Gazember:BAAANQAECgEIAQABNQAECgoKOQACALUYAA==.',
Ge='Geauxt:BAAANQAECgUIBwABNQAFFAcIIgAOAM0YAA==.',
Gl='Glenlizzo:BAAANQADCgEJAQABNQAECgMIBgADAAAAAA==.Glenroyce:BAAANQAECgMIBgAAAA==.Gless:BAABNQAECn9DAAMJAAoKuw7EEgCOAQAJAAoKuw7EEgCOAQAMAAEKAAC1XwEnAAAAAA==.',
Gn='Gnoretreat:BAABNQAECn9EAAIMAAoKphmCRQAwAgAMAAoKphmCRQAwAgAAAA==.',
Go='Goss:BAAANQAECggICAAAAA==.',
Gu='Gueret:BAAANQABCgIIAgAAAA==.',
Gw='Gwinnivor:BAAANQAECgIIAgAAAA==.',
Ha='Haenus:BAAANQADCgYIBgAAAA==.Haill:BAAANQAECgUIDwABNQAECgkJIgACAOwWAA==.Hamhock:BAAANQAECgMIBQABNQAECgoKQgAKAAIiAA==.Hanis:BAAANQADCgQIBwAAAA==.',
He='Hellìos:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.Hevn:BAAANQADCggICAABNQAECgcICAADAAAAAA==.',
Hy='Hyborian:BAABNQAECn8uAAIEAAkK9wtWigCjAQAEAAkK9wtWigCjAQABNQAECgMIBgADAAAAAA==.',
Ic='Icandy:BAAANQADCgMIAgAAAA==.Icecuber:BAAANQADCgUIBwAAAA==.',
Ih='Ihatepallys:BAAANQADCgYICQAAAA==.',
Ii='Iikeomgikr:BAACNQAFFH8FAAIYAAIKdA9WLQB7AAAYAAIKdA9WLQB7AAA1AAQKfzAAAhgACgrFEjZPAPwBABgACgrFEjZPAPwBAAAA.',
Il='Ilidank:BAABNQAECn8XAAIQAAkKER88BwCYAgAQAAkKER88BwCYAgAAAA==.Ilya:BAAANQAECgcIBwAAAA==.',
In='Indigo:BAABNQAECn88AAMCAAoKUBuONQBEAgACAAoKUBuONQBEAgAbAAEKEgvb+AA5AAAAAA==.Ineffablyss:BAAANQAECgYICwABNQAFFAIIBQAYAHQPAA==.Innron:BAABNQAECn81AAIcAAoKTw54NAB7AQAcAAoKTw54NAB7AQAAAA==.',
Io='Iol:BAAANQADCgIIAgAAAA==.Iolaus:BAAANQAECgcIBwAAAA==.',
Ir='Irisblue:BAAANQADCgYIAwAAAA==.',
Ja='Jaque:BAAANQADCgYIFAAAAA==.',
Je='Jeybieber:BAAANQAECgEIAwAAAA==.Jezzea:BAAANQADCgYICwAAAA==.',
Ji='Jinjix:BAAANQADCgYIDQAAAA==.',
Jo='Jolenee:BAAANQAECgQIBwAAAA==.Jolike:BAAANQAECggIAwAAAA==.Jonly:BAAANQADCgQIBwAAAA==.Jonoa:BAAANQAECggIDAAAAA==.',
['Jú']='Júdgemental:BAABNQAECn8tAAMPAAkKZhjuTAA2AgAPAAkKZhjuTAA2AgAdAAYKKRMV0wAyAQAAAA==.',
Ka='Kaelae:BAAANQAECgMIAwABNQAECgoKLwAYABAjAA==.Kair:BAAANQADCgcIBwAAAA==.Kalsium:BAAANQADCgUJDAAAAA==.Kami:BAAANQAECgIIAwAAAA==.Kattastrophy:BAAANQAECgQIBAAAAA==.Katteya:BAAANQAECgQIBAAAAA==.Kattia:BAABNQAECn9HAAIEAAoKawp6cADgAQAEAAoKawp6cADgAQAAAA==.',
Ki='Killinkair:BAAANQAECgYIDgAAAA==.Kinomihime:BAABNQAECn85AAMUAAoKmhDqDQDPAQAUAAoKmhDqDQDPAQAHAAEKMAa+xwE0AAAAAA==.Kirajoy:BAABNQAECn9NAAMFAAoK1wcEcgCFAQAFAAkK1wcEcgCFAQAIAAcKYwLiMwD0AAAAAA==.Kisses:BAAANQADCgYICgAAAA==.Kitkatt:BAAANQADCggICAAAAA==.',
Kl='Klyndori:BAAANQADCgMIAwAAAA==.',
Kn='Knyghtt:BAABNQAECn8oAAIKAAoKQwy9EABuAQAKAAoKQwy9EABuAQAAAA==.',
Kr='Kraviz:BAAANQADCgcICgAAAA==.Krombopolous:BAAANQADCggICgABNQAECgoKNwAEAKMMAA==.Krystle:BAAANQAECgcICwAAAA==.',
Le='Leftyloose:BAAANQADCgYIBAAAAA==.Leorna:BAAANQADCgQIBQAAAA==.',
Li='Lightcure:BAAANQAECgQIBwABNQAECggICwADAAAAAA==.Lilfonz:BAAANQAECgQIEwAAAA==.Lishalan:BAAANQAECgYIBwAAAA==.Littlejohn:BAAANQAECgQIBwABNQAECgkJFwAQABEfAA==.',
Lo='Logarth:BAAANQAECggIEQAAAA==.Loppandload:BAAANQAECgIIAQAAAA==.Loppsang:BAAANQAECgQIBAAAAA==.Lorcan:BAABNQAECn9CAAIMAAoK4h8LWwB7AgAMAAoK4h8LWwB7AgAAAA==.',
Lr='Lroye:BAACNQAFFH8iAAMOAAcKzRg6BwC9AQAOAAcKzRg6BwC9AQAeAAEK2w0uIABIAAA1AAQKf04AAw4ACgrkJFQCAI8DAA4ACgrkJFQCAI8DAB4AAQrOG2pVAFMAAAAA.',
Lu='Lucyfer:BAAANQADCgcIDQABNQAECgcICAADAAAAAA==.Lucyferr:BAABNQAECn8UAAIHAAYKzQK5ggG/AAAHAAYKzQK5ggG/AAABNQAECgcICAADAAAAAA==.Ludicrispeed:BAAANQADCgYIAwAAAA==.Luliak:BAAANQAECgIIAgABNQAFFAYIDQAaAGUbAA==.Lunabren:BAAANQADCggIDgAAAA==.Lunamina:BAAANQAECgEIAQAAAA==.',
['Lì']='Lìllith:BAABNQAECn8WAAMYAAgKjA18lwBPAQAYAAcKrQx8lwBPAQAfAAYKfgrANgDgAAABNQAFFAMICAAdALYPAA==.',
Ma='Madoka:BAABNQAECn80AAIMAAoKahaXUwADAgAMAAoKahaXUwADAgAAAA==.Mariophra:BAABNQAECn8tAAICAAkKeBJDVwC2AQACAAkKeBJDVwC2AQAAAA==.Maxdemon:BAAANQADCgcIDAAAAA==.Maxpal:BAAANQADCgYIDgAAAA==.',
Mc='Mcnastyqt:BAAANQADCgIIAgAAAA==.',
Me='Mesdel:BAAANQAECgEIAQABNQAECggIBgADAAAAAA==.',
Mi='Mikki:BAAANQADCgIIAgAAAA==.Misstorgo:BAAANQAECgUIEwAAAA==.',
Mo='Mohegian:BAAANQABCgQIAwAAAA==.Mokoko:BAABNQAECn8gAAMeAAoKGxhCCQBOAgAeAAoKGxhCCQBOAgAgAAMKFA0eCQBzAAAAAA==.Momoka:BAABNQAECn8jAAMdAAoKYRcqSwBJAgAdAAoKYRcqSwBJAgALAAIK8AN1XwA/AAAAAA==.Monfro:BAAANQAECgYICAAAAA==.Monnethir:BAAANQADCgUIBQAAAA==.Moogatoo:BAAANQAECgEIAQAAAA==.Moonbane:BAABNQAECn8+AAMIAAoK+hz+BQCwAgAIAAoK+hz+BQCwAgAFAAQKZAzL+wDUAAAAAA==.Mordecai:BAABNQAECn8dAAIEAAkKpBqraQBAAgAEAAkKpBqraQBAAgAAAA==.',
My='Myaquean:BAAANQADCgYIDgAAAA==.Mystogan:BAAANQADCgYIDgAAAA==.Myth:BAABNQAECn8wAAMSAAkKlRb9NwAuAgASAAkKlRb9NwAuAgARAAgKvhGyMgBcAQAAAA==.Mythelea:BAAANQAECgEIAQAAAA==.',
Na='Naavi:BAAANQAECgQICAAAAA==.Nakeefa:BAAANQADCgYIBgAAAA==.Natsuu:BAABNQAECn86AAMEAAoKdBPfUAArAgAEAAoKdBPfUAArAgAhAAIK1wOWEgBKAAAAAA==.',
Ne='Nefertiti:BAAANQADCggIAwAAAA==.Nekona:BAAANQADCgQIBAAAAA==.Neron:BAACNQAFFH8IAAIdAAMKtg+8FwDQAAAdAAMKtg+8FwDQAAA1AAQKf0gAAh0ACgrMH8sxAAQDAB0ACgrMH8sxAAQDAAAA.',
Ni='Niany:BAAANQAECgMIBgAAAA==.',
Nj='Njoror:BAAANQAECgUIBwAAAA==.',
No='Nonoffensive:BAAANQADCggIDwAAAA==.Norky:BAAANQABCgUICQABNQAECgIIAgADAAAAAA==.Nottapally:BAABNQAECn8ZAAIBAAoKBQqrOQBcAQABAAoKBQqrOQBcAQABNQAECgoKIwAPAKgUAA==.',
Os='Ossiferous:BAAANQAECgYIDgAAAA==.',
Ou='Outerlimits:BAABNQAECn8kAAIWAAoKPBQ8OwCyAQAWAAoKPBQ8OwCyAQAAAA==.Outrageous:BAAANQADCgUIBQAAAA==.',
Pa='Pamboo:BAABNQAECn9MAAIPAAoKhhKHNwA9AgAPAAoKhhKHNwA9AgAAAA==.Patticake:BAAANQAECggICAAAAA==.',
Pe='Pearle:BAAANQAECggICAAAAA==.Penthesilea:BAAANQABCggICQAAAA==.',
Po='Potatoslicer:BAAANQADCgQIBAAAAA==.',
Pr='Priestiô:BAAANQAECgUICgAAAA==.Pringo:BAABNQAECn8bAAMHAAkK9gSBzQAOAQAHAAkK9gSBzQAOAQAUAAEKAABOTQAAAAAAAA==.',
Pu='Pukka:BAAANQABCgQIBAABNQAECgoKLwAYABAjAA==.',
Py='Pylea:BAAANQAECgEIAQAAAA==.',
Ra='Ramindizzle:BAABNQAECn9DAAIiAAoKmhNyFQDvAQAiAAoKmhNyFQDvAQAAAA==.Randomname:BAABNQAECn8iAAIEAAkKCBlydQAlAgAEAAkKCBlydQAlAgABNQAECgkJLQAPAGYYAA==.',
Re='Refreshing:BAAANQADCggIDwAAAA==.Rekki:BAAANQAECgUIDQABNQAECgcICAADAAAAAA==.Retastic:BAAANQADCgUIBQAAAA==.',
Ri='Rigmarole:BAAANQAECgcIDAAAAA==.',
Ro='Rocksmasher:BAAANQADCgEIAQABNQAECgoKIwAPAKgUAA==.Ronun:BAAANQADCggICwAAAA==.Roograh:BAAANQAECgEIAQAAAA==.Rook:BAAANQAECgEIAQAAAA==.Rooklyn:BAABNQAECn9CAAIPAAoKOhNRUgDLAQAPAAoKOhNRUgDLAQAAAA==.Roye:BAACNQAFFH8GAAIdAAUKkRXRFQDbAAAdAAUKkRXRFQDbAAA1AAQKf0AAAh0ACgp6JZUJAFEDAB0ACgp6JZUJAFEDAAE1AAUUBwgiAA4AzRgA.',
Ru='Ruffiyo:BAAANQAECggICwAAAA==.Rugrahh:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Rugzco:BAACNQAFFH8GAAIjAAIKtQ3KCQCAAAAjAAIKtQ3KCQCAAAA1AAQKfzIAAiMACgr8GM4QAHICACMACgr8GM4QAHICAAAA.Ruìn:BAAANQAECgUICgAAAA==.',
Ry='Ryalla:BAAANQABCgEIAQAAAA==.',
['Ræ']='Ræñ:BAAANQAECgcIBwAAAA==.',
Sa='Sabina:BAABNQAECn88AAIbAAoKIglOjQCDAQAbAAoKIglOjQCDAQAAAA==.Sadako:BAAANQAECgcICAAAAA==.Sadorick:BAAANQAECgQIBAAAAA==.Sadôrick:BAAANQADCggIDQAAAA==.Sageguy:BAAANQADCgcIDwAAAA==.Saintkitiara:BAAANQABCgMIAwAAAA==.Sango:BAABNQAECn84AAIcAAoKbBUXIgD5AQAcAAoKbBUXIgD5AQAAAA==.Sarenity:BAAANQADCggIFgAAAA==.Savagelykill:BAAANQADCggIDgAAAA==.',
Sc='Scotch:BAABNQAECn88AAMdAAoKuhNVbQD1AQAdAAoKuhNVbQD1AQALAAMKkRHOZAAyAAAAAA==.Scotchnwater:BAAANQAECgYIEQAAAA==.Scratchies:BAAANQAECggIEQAAAA==.',
Se='Seiwar:BAABNQAFFH8GAAIMAAMKqAd9KAC5AAAMAAMKqAd9KAC5AAAAAA==.',
Sh='Shadornia:BAAANQAECgMIBwAAAA==.Shadowcrwlr:BAAANQADCgQIBAAAAA==.Shamangroo:BAAANQADCggIEwABNQADCggILgADAAAAAA==.Shamanio:BAABNQAECn8/AAMCAAoKWyULCwBoAwACAAoKWyULCwBoAwAbAAIKCxRO7wBBAAAAAA==.Shammbulance:BAABNQAECn8YAAMbAAkKzA+bbABCAQAbAAgKxA2bbABCAQACAAYK6AO4uQCmAAABNQAECgkJLQAPAGYYAA==.Sharaaz:BAAANQADCgUIBQAAAA==.Shatoya:BAAANQADCgcIAwAAAA==.Shroomified:BAAANQADCgQIBAAAAA==.',
Si='Silverytwo:BAAANQADCggIJgAAAA==.Silverywolfe:BAAANQAECgQIBQAAAA==.Simony:BAAANQADCggICAABNQAECgcICAADAAAAAA==.Sintia:BAAANQAECgYIDAABNQAECgoKLwAYABAjAA==.',
Sk='Skovak:BAAANQAECgUIBgAAAA==.Skoveth:BAAANQAECgIIAQAAAA==.',
So='Sorayae:BAABNQAECn8vAAIYAAoKECPyCAB8AwAYAAoKECPyCAB8AwAAAA==.',
Sp='Specialk:BAAANQAECggIBQAAAA==.Splooshh:BAAANQADCggIDgABNQAECggICwADAAAAAA==.',
St='Steeler:BAAANQAECgMIBAABNQAECgMIBgADAAAAAA==.Stinkfoot:BAABNQAECn8eAAIBAAgKihWlSQDRAQABAAgKihWlSQDRAQAAAA==.Stormkissed:BAAANQAECgQIDQAAAA==.Strawman:BAABNQAECn8VAAIfAAkKCBqGFAAVAgAfAAkKCBqGFAAVAgAAAA==.',
Su='Subotai:BAAANQADCgYIBwAAAA==.Suki:BAAANQADCggICAAAAA==.Sulvazud:BAAANQAECgYIBgAAAA==.Sunil:BAABNQAECn9IAAMYAAoKRBfxOABYAgAYAAoKRBfxOABYAgAfAAQKpQR1TAB5AAAAAA==.',
Sy='Syclone:BAAANQAECgMIBgABNQAFFAIICgAWAHwhAA==.Sypha:BAABNQAECn8dAAIHAAoKXxQXTgAlAgAHAAoKXxQXTgAlAgAAAA==.',
Ta='Taetheras:BAABNQAECn8bAAIHAAgKpgf8sgA+AQAHAAgKpgf8sgA+AQAAAA==.Tahlyn:BAAANQAECggIEwABNQAECgoKPAACAFAbAA==.Talshiar:BAAANQAECgQIBAAAAA==.Tattianna:BAAANQADCggIGwAAAA==.Tavendar:BAABNQAECn8yAAMPAAoKyRzzNgA/AgAPAAkKZBzzNgA/AgAdAAIKSwV0jAFJAAABNQAECgIIAgADAAAAAA==.Taírn:BAAANQADCgEIAQABNQAECgoKLAAaAHccAA==.',
Tc='Tcshmaster:BAAANQAECgEIAQAAAA==.',
Te='Texgrebner:BAAANQAECgYIEgABNQAECgkJFwAQABEfAA==.',
Th='Theeyedoctor:BAAANQADCggIBwABNQAECgoKIwAPAKgUAA==.Thunderslate:BAABNQAECn8jAAMPAAoKqBT1NABJAgAPAAkKBRb1NABJAgALAAYKmxD+MgBKAQAAAA==.Thyrok:BAABNQAECn8cAAIcAAkKfg2XNAB7AQAcAAkKfg2XNAB7AQAAAA==.',
Ti='Tigreth:BAABNQAECn9DAAMdAAoKSw2ttQCzAQAdAAoKSw2ttQCzAQALAAUK+wenWQB3AAAAAA==.Tinkerballa:BAAANQADCggJEgAAAA==.',
To='Toastal:BAAANQAECgIIAgAAAA==.Tokxi:BAAANQADCgQIBgABNQAECgoKIwALAMUVAA==.Totemzasap:BAAANQAECgQICAAAAA==.',
Tr='Traductus:BAAANQAECgMIAgAAAA==.Tragik:BAABNQAECn9DAAIaAAoKygyvEwDcAQAaAAoKygyvEwDcAQAAAA==.Trisandra:BAAANQAECgMIBAAAAA==.',
Tu='Tuugadark:BAABNQAECn8+AAIFAAoKFh1fNwCuAgAFAAoKFh1fNwCuAgAAAA==.',
Tz='Tzulari:BAAANQAECgUIBwABNQAECgUICAADAAAAAA==.',
Ul='Ulyaoth:BAAANQADCgUIBQAAAA==.',
Un='Unbroken:BAAANQADCgMIAwAAAA==.Unprepared:BAAANQABCgEIAQABNQAECggILAAHAO8SAA==.',
Va='Vasdeferens:BAAANQABCgMIAwAAAA==.',
Ve='Vedros:BAAANQADCgYICQAAAA==.Verbina:BAAANQAECgQIDwABNQAECgoKPAACAFAbAA==.Vespertilia:BAAANQAECgUIBQAAAA==.',
Vo='Vorukh:BAAANQAECgcIDgAAAA==.',
Vy='Vynas:BAAANQAECgEIAQAAAA==.',
Wa='Warlockgroo:BAAANQADCgcICgABNQADCggILgADAAAAAA==.Warriorgroo:BAAANQADCggILgAAAA==.',
Wh='Whácker:BAAANQAECgIIAgABNQAECgoKLAAaAHccAA==.',
Wi='Wickdlovly:BAAANQAECgYIDQABNQAECgkJIgACAOwWAA==.Wickedslicks:BAABNQAECn8rAAISAAoKEB0DEQCiAgASAAoKEB0DEQCiAgAAAA==.',
Wr='Wreckshop:BAAANQADCgYIDwABNQAECgkJNwANAPQgAA==.',
Xe='Xenøcide:BAAANQADCgcICwAAAA==.',
Xi='Xiatus:BAAANQAECgcIEAABNQAECgoKWgAkAM0lAA==.',
Xo='Xoren:BAAANQAECgEIAQABNQAECgcICAADAAAAAA==.',
Xx='Xxdeathz:BAAANQABCgMIAwABNQAECgkJKQAPAEscAA==.Xxlockz:BAAANQAECgQIBAABNQAECgkJKQAPAEscAA==.Xxpallyz:BAABNQAECn8pAAIPAAkKSxyCMwBQAgAPAAkKSxyCMwBQAgAAAA==.',
Yo='Yohh:BAABNQAECn8+AAMCAAoKtxN2SwA1AgACAAoKtxN2SwA1AgAbAAkKIg9EQQDPAQAAAA==.Yorie:BAAANQADCgMIAwAAAA==.',
Yu='Yuriko:BAABNQAECn9DAAQjAAoKahBeHAC+AQAjAAoKahBeHAC+AQANAAYKKQY2QgClAAAlAAEK4wXhKQApAAAAAA==.',
Za='Zadory:BAAANQADCggIDAAAAA==.Zaidan:BAAANQADCggIEAAAAA==.',
Ze='Zendous:BAAANQAECgYIBgAAAA==.',
Zi='Zippitydooda:BAABNQAECn8iAAMCAAkK7BasSADxAQACAAkK7BasSADxAQAbAAEKAAAPIgEAAAAAAA==.',
Zo='Zodiacc:BAABNQAECn9BAAITAAoKPSAICAD/AgATAAoKPSAICAD/AgAAAA==.Zornhealer:BAAANQAECgcICAAAAA==.Zorrn:BAAANQAECgYIDgABNQAECgcICAADAAAAAA==.',
['Zí']='Zílch:BAAANQAECgEIAQAAAA==.',
['Zî']='Zîlch:BAAANQADCgcIBwAAAA==.',
['Zö']='Zölä:BAAANQAECgQIBwABNQAECgYIBwADAAAAAA==.',
['Çh']='Çhrìs:BAAANQAECgQICAAAAA==.',
['Çú']='Çúrsè:BAAANQADCgIIAwAAAA==.',
['Èn']='Èntity:BAAANQAECgcICgAAAA==.',
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
