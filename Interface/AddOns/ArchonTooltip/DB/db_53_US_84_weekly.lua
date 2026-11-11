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

local lookup = {'DeathKnight-Blood','Shaman-Restoration','Unknown-Unknown','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Mage-Arcane','Warlock-Destruction','Warrior-Protection','Warrior-Fury','Paladin-Protection','Warrior-Arms','Monk-Windwalker','Rogue-Subtlety','Paladin-Holy','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Fire','DeathKnight-Frost','Evoker-Devastation','Priest-Holy','Evoker-Augmentation','Shaman-Enhancement','DemonHunter-Havoc','Paladin-Retribution','Rogue-Assassination','Priest-Shadow','Rogue-Outlaw','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Shaman-Elemental','DeathKnight-Unholy','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aardz:BAAANQADCggIDgAAAA==.',
Ab='Abeblinkin:BAAANQADCgYICQAAAA==.Abraxîs:BAAANQAECgYICAAAAA==.',
Ac='Acindis:BAABNQAECn84AAIBAAoKcRJJOwAYAgABAAoKcRJJOwAYAgAAAA==.',
Ae='Aeless:BAAANQAECgUIDAAAAA==.Aelless:BAAANQAECgEIAQAAAA==.Aerendal:BAAANQADCgMIAwAAAA==.',
Ah='Ahzure:BAAANQAECgcIEQABNQAECgoKNgACAFAbAA==.',
Ai='Aithinne:BAAANQADCgUICQAAAA==.',
Al='Alch:BAAANQADCgQICAAAAA==.Aleandi:BAAANQADCgYIBQAAAA==.Aledil:BAAANQAECgcIDgAAAA==.Alghul:BAAANQADCgYIBgABNQAECgcIEgADAAAAAA==.Alynara:BAABNQAECn85AAIEAAoKGBtzUgB5AgAEAAoKGBtzUgB5AgAAAA==.',
Am='Amalthea:BAABNQAECn8bAAMFAAoKjAZgtQBkAQAFAAoKCgZgtQBkAQAGAAEKMgjZKwA1AAAAAA==.Amoredis:BAAANQABCggIGQAAAA==.',
An='Anume:BAAANQADCgYIDgAAAA==.Anwas:BAAANQAECgEIBAAAAA==.',
Ap='Apally:BAAANQADCgUIBQAAAA==.',
Ar='Aragan:BAAANQADCggIDAAAAA==.Arellean:BAAANQADCgQIBAAAAA==.Arese:BAABNQAECn8cAAIHAAgKbB40YQDkAQAHAAgKbB40YQDkAQAAAA==.',
As='Asmodea:BAAANQADCgUIBQAAAA==.Asphonix:BAAANQAECgEIAgAAAA==.',
Az='Azzif:BAABNQAECn8gAAMIAAkK9gbqDADiAAAIAAgKyAfqDADiAAAFAAgKXAHLKgFoAAAAAA==.',
Ba='Babybluz:BAAANQAECgQICgAAAA==.Backstabbath:BAAANQADCgQIAwAAAA==.Baifeng:BAAANQABCggIFQAAAA==.Bandayde:BAAANQADCgYIBQAAAA==.Barlas:BAAANQAECgUIBAAAAA==.',
Be='Beauriley:BAABNQAECn8+AAMJAAoKmwtMHAB4AQAJAAoKmwtMHAB4AQAKAAEKdAarNQAjAAAAAA==.Behomethan:BAAANQAECggIEAAAAA==.Belorc:BAAANQADCgUIBQAAAA==.Berian:BAAANQAECgIIAwAAAA==.',
Bi='Bigpapafreez:BAAANQADCggIDQABNQAECgoKWQALAPAfAA==.Billbetaray:BAABNQAECn8gAAIMAAoKiBlXMwBkAgAMAAoKiBlXMwBkAgAAAA==.',
Bl='Blux:BAAANQADCgEIAQAAAA==.Bløødsong:BAAANQADCgEIAQAAAA==.',
Bo='Bolton:BAAANQADCgYIBgAAAA==.Bombchele:BAABNQAECn83AAINAAkK9CCNBwDpAgANAAkK9CCNBwDpAgAAAA==.Bowogibrann:BAAANQADCgQIBAAAAA==.',
Br='Bratticusrex:BAABNQAECn8zAAIKAAgK0wn2FwAgAQAKAAgK0wn2FwAgAQAAAA==.Brazier:BAAANQADCggICAAAAA==.Bresowar:BAAANQAECgQIAwAAAA==.Brynthe:BAAANQADCgYIDwAAAA==.',
Bu='Bunnylicious:BAABNQAECn8+AAICAAoKLiW9BQCyAwACAAoKLiW9BQCyAwAAAA==.Bunnymedic:BAAANQAECgYICAABNQAECgoKPgACAC4lAA==.',
Ca='Caebrylla:BAABNQAECn8vAAIEAAkKaRXtXAD3AQAEAAkKaRXtXAD3AQAAAA==.Cajun:BAABNQAECn80AAIMAAkKrR/6FAD1AgAMAAkKrR/6FAD1AgABNQAFFAcIIgAOAM0YAA==.Calistie:BAAANQADCggICAAAAA==.Callipygea:BAAANQADCgIIAgAAAA==.Calver:BAAANQADCgUIBQAAAA==.Camil:BAAANQADCgMIAwABNQAECgoKOgAEAPgPAA==.Cang:BAAANQABCggIJwAAAA==.Catalina:BAABNQAECn9CAAIPAAoKPh9rFgAkAwAPAAoKPh9rFgAkAwAAAA==.',
Ce='Cecimorte:BAABNQAECn8wAAIBAAgKaxPQOgBIAQABAAgKaxPQOgBIAQAAAA==.',
Ch='Chargeasap:BAAANQADCgUIBQAAAA==.Charttopper:BAAANQAECgQIBQABNQAECgoKIgAPAKgUAA==.Chinashop:BAAANQAECgQIBAABNQAECggIFgAQAOMgAA==.Chonker:BAABNQAECn9GAAMRAAoKORZoGAA2AgARAAoKORZoGAA2AgASAAkKdxPPPAAQAgAAAA==.Chuckforrest:BAAANQADCgIIAgABNQAECgYIBgADAAAAAA==.',
Ci='Cihato:BAABNQAECn9DAAITAAoKExniFAAZAgATAAoKExniFAAZAgAAAA==.',
Cl='Claye:BAAANQAECgIIAgAAAA==.Cleveistic:BAAANQADCgUIBwABNQAECgMIBgADAAAAAA==.Cleveland:BAAANQAECgMIBgAAAA==.',
Co='Coldshoulder:BAABNQAECn8sAAQHAAgK7xKdqABAAQAHAAcKRBKdqABAAQAUAAIKaBTvLgCHAAAVAAIKRA0cCAB2AAAAAA==.Corelas:BAAANQAECgMIBQAAAA==.Couchdad:BAAANQAECgUIDQABNQAECgcIEgADAAAAAA==.',
Cr='Crazymadman:BAAANQAECgIIAgAAAA==.Crysallis:BAAANQADCggIHgAAAA==.',
Cy='Cynide:BAAANQADCgYJBgAAAA==.Cyyrene:BAAANQABCgEIAQABNQAECgoKIAAWALISAA==.',
Da='Dall:BAAANQAECgIIAwAAAA==.Damo:BAAANQAECgcICgAAAA==.Danale:BAAANQADCgYJCgAAAA==.Danknugz:BAABNQAECn8UAAIBAAgKNQuAegAOAQABAAgKNQuAegAOAQAAAA==.Darwina:BAAANQAECgEIBQAAAA==.Dawnson:BAABNQAECn8ZAAIPAAkKKRmyPQANAgAPAAkKKRmyPQANAgAAAA==.',
De='Deadscream:BAAANQAECggICgAAAA==.Deathlich:BAABNQAECn8kAAIWAAoKexePJAAaAgAWAAoKexePJAAaAgAAAA==.Demogless:BAAANQAECgYIDQAAAA==.Desyrel:BAAANQAECgIIAwABNQAECgcICAADAAAAAA==.',
Dh='Dharknight:BAAANQAECgUICAAAAA==.Dharkuul:BAAANQABCgYICQABNQAECgUICAADAAAAAA==.',
Di='Didimissfire:BAEBNQAECn8/AAIEAAoK/wtKYgDpAQAEAAoK/wtKYgDpAQAAAA==.Diefatty:BAAANQADCgMIAwAAAA==.',
Do='Doll:BAAANQADCgQIBAAAAA==.',
Dr='Draeven:BAAANQAECgYIDAAAAA==.Dranalis:BAAANQAECgEIBAAAAA==.Dredlok:BAAANQADCgYIEAAAAA==.',
Du='Dumonster:BAABNQAECn8WAAIKAAYKgQKqJQCBAAAKAAYKgQKqJQCBAAAAAA==.Dustdevil:BAAANQAECgYICQABNQAECggIFgAQAOMgAA==.',
Ee='Eeaassyy:BAAANQADCgYICQAAAA==.',
El='Elaraa:BAAANQADCgQIBAAAAA==.Eldorath:BAAANQAECgIIAgAAAA==.Elev:BAAANQADCgMIAwAAAA==.Elizabeth:BAAANQADCgUIBQAAAA==.',
Er='Eris:BAAANQADCggICAAAAA==.Erzascar:BAAANQAECgEIAQAAAA==.',
Es='Estrogen:BAABNQAECn8zAAIXAAoK3yR+AwBvAwAXAAoK3yR+AwBvAwAAAA==.',
Ev='Eventhorizon:BAAANQAECgYIAgAAAA==.Evolett:BAAANQAECgEIBQAAAA==.',
Fa='Fatbox:BAABNQAECn88AAMKAAoKNiBgAwDNAgAKAAoKNiBgAwDNAgAMAAEKrA0uVAEyAAAAAA==.Fayth:BAABNQAECn88AAIYAAoKeh1qMgCeAgAYAAoKeh1qMgCeAgAAAA==.',
Fe='Fearblade:BAAANQADCgMIAwAAAA==.Fearblast:BAAANQAECgYIBgAAAA==.Fearkin:BAABNQAECn8yAAMZAAoKCQ72CAB8AQAZAAoKGg32CAB8AQAXAAcKxw2rDQBdAQAAAA==.Fenastic:BAABNQAECn8rAAMFAAcKpAftuwBVAQAFAAcKpAftuwBVAQAGAAEKtwd2MAA0AAAAAA==.Fermy:BAAANQAECgIIAQAAAA==.Feyrah:BAAANQAECgEIAQAAAA==.',
Fi='Fiobhe:BAAANQAECgMIBQAAAA==.Fixeruper:BAABNQAECn8ZAAIYAAoK7QJkhwAqAQAYAAoK7QJkhwAqAQAAAA==.',
Fo='Fonz:BAAANQADCgYIBgABNQAECgQIDwADAAAAAA==.',
['Fí']='Físter:BAAANQADCgMIAwABNQAECgoKLAAaAHccAA==.',
Ga='Gajeal:BAAANQAECgYIBgAAAA==.Gazember:BAAANQAECgEIAQABNQAECgoKMAACAIkWAA==.',
Ge='Geauxt:BAAANQAECgUICAABNQAFFAcIIgAOAM0YAA==.',
Gl='Glenlizzo:BAAANQADCgEJAQABNQAECgMIBgADAAAAAA==.Glenroyce:BAAANQAECgMIBgAAAA==.Gless:BAABNQAECn8/AAMJAAoKIg7cEQCDAQAJAAoKIg7cEQCDAQAMAAEKAAC1XwEnAAAAAA==.',
Gn='Gnoretreat:BAABNQAECn9AAAIMAAoKphkBQQAwAgAMAAoKphkBQQAwAgAAAA==.',
Go='Goss:BAAANQAECggICAAAAA==.',
Gu='Gueret:BAAANQABCgIIAgAAAA==.',
Gw='Gwinnivor:BAAANQAECgIIAgAAAA==.',
Ha='Haenus:BAAANQADCgMIAwAAAA==.Haill:BAAANQAECgcIDQABNQAECggIHwACAE0ZAA==.Hamhock:BAAANQAECgIIAgABNQAECgoKPAAKADYgAA==.Hanis:BAAANQADCgQIBwAAAA==.',
He='Hellìos:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.',
Hy='Hyborian:BAABNQAECn8qAAIEAAgKCQz+mQBkAQAEAAgKCQz+mQBkAQABNQAECgQIAwADAAAAAA==.',
Ic='Icandy:BAAANQADCgMIAgAAAA==.Icecuber:BAAANQADCgUIBwAAAA==.',
Ih='Ihatepallys:BAAANQADCgYICQAAAA==.',
Ii='Iikeomgikr:BAACNQAFFH8FAAIYAAIKdA/WKQB+AAAYAAIKdA/WKQB+AAA1AAQKfzAAAhgACgrFEphIAAACABgACgrFEphIAAACAAAA.',
Il='Ilidank:BAABNQAECn8WAAIQAAgK4yA8BwCYAgAQAAgK4yA8BwCYAgAAAA==.Ilya:BAAANQAECgcIBwAAAA==.',
In='Indigo:BAABNQAECn82AAICAAoKUBsWMABKAgACAAoKUBsWMABKAgAAAA==.Ineffablyss:BAAANQAECgYIDAABNQAFFAIIBQAYAHQPAA==.Innron:BAABNQAECn8yAAIbAAoKrgyhMwBoAQAbAAoKrgyhMwBoAQAAAA==.',
Io='Iol:BAAANQADCgIIAgAAAA==.Iolaus:BAAANQAECgcIBwAAAA==.',
Ir='Irisblue:BAAANQADCgYIAwAAAA==.',
Ja='Jaque:BAAANQADCgYIDwAAAA==.',
Je='Jeybieber:BAAANQAECgEIAwAAAA==.Jezzea:BAAANQADCgYICwAAAA==.',
Ji='Jinjix:BAAANQADCgYIDQAAAA==.',
Jo='Jolenee:BAAANQAECgQIBwAAAA==.Jolike:BAAANQAECggIAwAAAA==.Jonly:BAAANQADCgQIBwAAAA==.Jonoa:BAAANQAECggIDgAAAA==.',
['Jú']='Júdgemental:BAABNQAECn8rAAMPAAkKNBjuTAA2AgAPAAkKNBjuTAA2AgAcAAYKKRPzwwA2AQAAAA==.',
Ka='Kaelae:BAAANQAECgMIAwABNQAECgoKLwAYABAjAA==.Kair:BAAANQADCgcIBwAAAA==.Kalsium:BAAANQADCgUJDAAAAA==.Kami:BAAANQAECgIIAwAAAA==.Kattastrophy:BAAANQAECgEIAQAAAA==.Katteya:BAAANQAECgQIBAAAAA==.Kattia:BAABNQAECn9AAAIEAAoKLwm5bADOAQAEAAoKLwm5bADOAQAAAA==.',
Ki='Killinkair:BAAANQAECgYIEwAAAA==.Kinomihime:BAABNQAECn85AAMUAAoKmhDqDQDPAQAUAAoKmhDqDQDPAQAHAAEKMAa+xwE0AAAAAA==.Kirajoy:BAABNQAECn9EAAMFAAoKogd6awCBAQAFAAkKjQd6awCBAQAIAAcKYwLiMwD0AAAAAA==.Kisses:BAAANQAECgEIAQAAAA==.',
Kl='Klyndori:BAAANQADCgMIAwAAAA==.',
Kn='Knyghtt:BAABNQAECn8kAAIKAAoKoAubDwBoAQAKAAoKoAubDwBoAQAAAA==.',
Kr='Kraviz:BAAANQADCgcICgAAAA==.Krombopolous:BAAANQADCggICgABNQAECgkJMwAEACMMAA==.Krystle:BAAANQAECgcIEAAAAA==.',
Le='Leftyloose:BAAANQADCgYIBAAAAA==.Leorna:BAAANQADCgQIBQAAAA==.',
Li='Lightcure:BAAANQAECgQICAABNQAECggICwADAAAAAA==.Lilfonz:BAAANQAECgQIDwAAAA==.Lishalan:BAAANQAECgYIBwAAAA==.Littlejohn:BAAANQAECgQIBwABNQAECggIFgAQAOMgAA==.',
Lo='Logarth:BAAANQAECgcIDQAAAA==.Londonfog:BAAANQAECgEIAQAAAA==.Loppandload:BAAANQAECgEIAQAAAA==.Loppsang:BAAANQAECgQIBAAAAA==.Lorcan:BAABNQAECn9CAAIMAAoK4h8LWwB7AgAMAAoK4h8LWwB7AgAAAA==.',
Lr='Lroye:BAACNQAFFH8iAAMOAAcKzRjsBQC9AQAOAAcKzRjsBQC9AQAdAAEK2w0uIABIAAA1AAQKf04AAw4ACgrkJFQCAI8DAA4ACgrkJFQCAI8DAB0AAQrOG1pTAFQAAAAA.',
Lu='Lucyfer:BAAANQADCgcIDQABNQAECgcICAADAAAAAA==.Lucyferr:BAABNQAECn8UAAIHAAYKzQK5ggG/AAAHAAYKzQK5ggG/AAABNQAECgcICAADAAAAAA==.Ludicrispeed:BAAANQADCgYIAwAAAA==.Luliak:BAAANQAECgIIAwABNQAFFAYIDQAaAGUbAA==.Lunabren:BAAANQADCggIDgAAAA==.Lunamina:BAAANQAECgEIAQAAAA==.',
['Lì']='Lìllith:BAABNQAECn8WAAMYAAgKjA18lwBPAQAYAAcKrQx8lwBPAQAeAAYKfgr6MgDgAAABNQAFFAIIBQAcAFIOAA==.',
Ma='Madoka:BAABNQAECn8yAAIMAAoKvRSrXQDSAQAMAAoKvRSrXQDSAQAAAA==.Mardreaux:BAAANQAECgEIAgAAAA==.Mariophra:BAABNQAECn8rAAICAAgKQRMwXACOAQACAAgKQRMwXACOAQAAAA==.Maxdemon:BAAANQADCgcIDAAAAA==.Maxpal:BAAANQADCgYIDgAAAA==.',
Mc='Mcnastyqt:BAAANQADCgIIAgAAAA==.',
Me='Mesdel:BAAANQAECgEIAgABNQAECggIBgADAAAAAA==.',
Mi='Mikki:BAAANQADCgIIAgAAAA==.Misstorgo:BAAANQAECgQICQAAAA==.',
Mo='Mohegian:BAAANQABCgQIAwAAAA==.Mokoko:BAABNQAECn8eAAMdAAoKEheLCQA4AgAdAAoKyBaLCQA4AgAfAAMKFA3MCABzAAAAAA==.Momoka:BAABNQAECn8bAAMcAAoKjxOVcwDUAQAcAAkKmhWVcwDUAQALAAIK8ANYWgA/AAAAAA==.Monfro:BAAANQAECgYICQAAAA==.Monnethir:BAAANQADCgUIBQAAAA==.Moogatoo:BAAANQAECgEIBAAAAA==.Moonbane:BAABNQAECn8+AAMIAAoK+hz+BQCwAgAIAAoK+hz+BQCwAgAFAAQKZAzL+wDUAAAAAA==.Moonmist:BAAANQAECgEIAwABNQAECggIHwACAE0ZAA==.Mordecai:BAABNQAECn8dAAIEAAkKpBqraQBAAgAEAAkKpBqraQBAAgAAAA==.',
My='Myaquean:BAAANQADCgYIDgAAAA==.Mystogan:BAAANQADCgYIDgAAAA==.Myth:BAABNQAECn8vAAMSAAkKHxb9NwAuAgASAAkKHxb9NwAuAgARAAgKvhHGLgBdAQAAAA==.Mythelea:BAAANQAECgEIAQAAAA==.',
Na='Naavi:BAAANQAECgQICQAAAA==.Nakeefa:BAAANQAECgEIAgAAAA==.Natsuu:BAABNQAECn84AAMEAAoK4xEjUAAYAgAEAAoK4xEjUAAYAgAgAAIK1wMoEQBKAAAAAA==.',
Ne='Nefertiti:BAAANQADCggIAwAAAA==.Nekona:BAAANQADCgQIBAAAAA==.Neron:BAACNQAFFH8FAAIcAAIKUg7WIgCEAAAcAAIKUg7WIgCEAAA1AAQKf0QAAhwACgrMH8sxAAQDABwACgrMH8sxAAQDAAAA.',
Ni='Niany:BAAANQAECgMIBgAAAA==.',
Nj='Njoror:BAAANQAECgIIAwAAAA==.',
No='Nonoffensive:BAAANQADCggIDwAAAA==.Norky:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.Nottapally:BAAANQAECggIDwABNQAECgoKIgAPAKgUAA==.Noxxon:BAAANQAECgEIAgAAAA==.',
Os='Ossiferous:BAAANQAECgYIDwAAAA==.',
Ou='Outerlimits:BAABNQAECn8gAAIWAAoKshL2PgCKAQAWAAoKshL2PgCKAQAAAA==.',
Pa='Pamboo:BAABNQAECn9IAAIPAAoKSRDiNwAoAgAPAAoKSRDiNwAoAgAAAA==.Patticake:BAAANQAECggICAAAAA==.',
Pe='Pearle:BAAANQAECggICAAAAA==.Penthesilea:BAAANQABCggICQAAAA==.',
Po='Potatoslicer:BAAANQADCgQIBAAAAA==.',
Pr='Priestiô:BAAANQAECgUIDQAAAA==.Pringo:BAABNQAECn8bAAMHAAkK9gRcwwAOAQAHAAkK9gRcwwAOAQAUAAEKAABMSAAAAAAAAA==.',
Pu='Pukka:BAAANQABCgQIBAABNQAECgoKLwAYABAjAA==.',
Py='Pylea:BAAANQAECgIIAwAAAA==.',
Qa='Qahnaarin:BAAANQAECgEIAQAAAA==.',
Ra='Ramindizzle:BAABNQAECn8/AAIhAAoKjRLZFADkAQAhAAoKjRLZFADkAQAAAA==.Randomname:BAABNQAECn8iAAIEAAkKCBlydQAlAgAEAAkKCBlydQAlAgABNQAECgkJKwAPADQYAA==.',
Re='Refreshing:BAAANQADCggIDwAAAA==.Rekki:BAAANQAECgUIDQABNQAECgcICAADAAAAAA==.Retastic:BAAANQADCgUIBQAAAA==.',
Ri='Rigmarole:BAAANQAECgcIEAAAAA==.',
Ro='Rocksmasher:BAAANQADCgEIAQABNQAECgoKIgAPAKgUAA==.Ronun:BAAANQADCggICwAAAA==.Roograh:BAAANQAECgEIAQAAAA==.Rook:BAAANQAECgEIAQAAAA==.Rooklyn:BAABNQAECn9CAAIPAAoKOhOdSwDSAQAPAAoKOhOdSwDSAQAAAA==.Roye:BAACNQAFFH8GAAIcAAUKkRUJEwDeAAAcAAUKkRUJEwDeAAA1AAQKf0AAAhwACgp6Jd4HAFgDABwACgp6Jd4HAFgDAAE1AAUUBwgiAA4AzRgA.',
Ru='Ruffiyo:BAAANQAECggICwAAAA==.Rugrahh:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Rugzco:BAACNQAFFH8GAAIiAAIKtQ0JCQCAAAAiAAIKtQ0JCQCAAAA1AAQKfzIAAiIACgr8GM4QAHICACIACgr8GM4QAHICAAAA.Ruìn:BAAANQAECgUICgAAAA==.',
Ry='Ryalla:BAAANQABCgEIAQAAAA==.',
['Ræ']='Ræñ:BAAANQAECgcICAAAAA==.',
Sa='Sabina:BAABNQAECn88AAIjAAoKIglOjQCDAQAjAAoKIglOjQCDAQAAAA==.Sadako:BAAANQAECgcICAAAAA==.Sadorick:BAAANQAECgQIBAAAAA==.Sadôrick:BAAANQADCggIDQAAAA==.Sageguy:BAAANQADCgcIDwAAAA==.Saintkitiara:BAAANQABCgMIAwAAAA==.Sango:BAABNQAECn83AAIbAAoKbBVOHwD8AQAbAAoKbBVOHwD8AQAAAA==.Sarenity:BAAANQADCggIFgAAAA==.Savagelykill:BAAANQADCggIDgAAAA==.',
Sc='Scotch:BAABNQAECn85AAMcAAoKOxPpZwDvAQAcAAoKOxPpZwDvAQALAAMKkRF+XwAyAAAAAA==.Scotchnwater:BAAANQAECgYIDQAAAA==.Scratchies:BAABNQAECn8cAAIRAAoKchHUIgDDAQARAAoKchHUIgDDAQAAAA==.',
Se='Seiwar:BAABNQAFFH8GAAIMAAMKqAd9KAC5AAAMAAMKqAd9KAC5AAAAAA==.Serebus:BAAANQAECgEIAQAAAA==.',
Sh='Shadornia:BAAANQAECgMICQAAAA==.Shadowcrwlr:BAAANQADCgQIBAAAAA==.Shamangroo:BAAANQAECgEIAQAAAA==.Shamanio:BAABNQAECn8/AAMCAAoKWyULCwBoAwACAAoKWyULCwBoAwAjAAIKCxRS5ABBAAAAAA==.Shammbulance:BAABNQAECn8YAAMjAAkKzA/2YwBCAQAjAAgKxA32YwBCAQACAAYK6AMRsQCmAAABNQAECgkJKwAPADQYAA==.Sharaaz:BAAANQADCgUIBQAAAA==.Shatoya:BAAANQADCgcIAwAAAA==.',
Si='Silverytwo:BAAANQADCggIHgAAAA==.Silverywolfe:BAAANQAECgQIBQAAAA==.Simony:BAAANQADCggICAABNQAECgcICAADAAAAAA==.Sintia:BAAANQAECgYIDAABNQAECgoKLwAYABAjAA==.',
Sk='Skovak:BAAANQAECgUICAAAAA==.Skoveth:BAAANQAECgIIAwAAAA==.',
So='Sorayae:BAABNQAECn8vAAIYAAoKECPyCAB8AwAYAAoKECPyCAB8AwAAAA==.',
Sp='Specialk:BAAANQAECgQIBQAAAA==.Splooshh:BAAANQADCggIDgABNQAECggICwADAAAAAA==.',
St='Steeler:BAAANQAECgMIAwABNQAECgQIAwADAAAAAA==.Stinkfoot:BAABNQAECn8eAAIBAAgKihWlSQDRAQABAAgKihWlSQDRAQAAAA==.Stormkissed:BAAANQAECgQICQAAAA==.Strawman:BAABNQAECn8VAAIeAAkKCBrzEgAVAgAeAAkKCBrzEgAVAgAAAA==.',
Su='Sulvazud:BAAANQAECgYIBgAAAA==.Sunil:BAABNQAECn8/AAMYAAoK+RbyNABWAgAYAAoK+RbyNABWAgAeAAQKpQSvRwB5AAAAAA==.',
Sy='Syclone:BAAANQAECgMIBgABNQAFFAIICAABAL0fAA==.Sypha:BAABNQAECn8bAAIHAAoKVRQFSQAlAgAHAAoKVRQFSQAlAgAAAA==.',
Ta='Taetheras:BAABNQAECn8WAAIHAAgKagdHqwA7AQAHAAgKagdHqwA7AQAAAA==.Tahlyn:BAAANQAECggIDQABNQAECgoKNgACAFAbAA==.Tattianna:BAAANQADCggIGwAAAA==.Tavendar:BAABNQAECn8yAAMPAAoKyRw0MQBKAgAPAAkKZBw0MQBKAgAcAAIKSwV0jAFJAAABNQAECgIIAgADAAAAAA==.Taírn:BAAANQADCgEIAQABNQAECgoKLAAaAHccAA==.',
Tc='Tcshmaster:BAAANQAECgIIAwAAAA==.',
Te='Texgrebner:BAAANQAECgYIEgABNQAECggIFgAQAOMgAA==.',
Th='Theeyedoctor:BAAANQADCggIBwABNQAECgoKIgAPAKgUAA==.Thunderslate:BAABNQAECn8iAAMPAAoKqBRHMABOAgAPAAkKBRZHMABOAgALAAYKmxD+MgBKAQAAAA==.Thyrok:BAABNQAECn8aAAIbAAgKOgthPAA0AQAbAAgKOgthPAA0AQAAAA==.',
Ti='Tigreth:BAABNQAECn9DAAMcAAoKSw2ttQCzAQAcAAoKSw2ttQCzAQALAAUK+wenWQB3AAAAAA==.Tinkerballa:BAAANQADCggJEgAAAA==.',
To='Toastal:BAAANQAECgIIAgAAAA==.Tokxi:BAAANQADCgQIBgABNQAECgoKIwALAMUVAA==.Totemzasap:BAAANQAECgQICAAAAA==.',
Tr='Traductus:BAAANQAECgMIAwAAAA==.Tragik:BAABNQAECn8/AAIaAAoKhwwmEgDcAQAaAAoKhwwmEgDcAQAAAA==.Treetrunkz:BAAANQAECgEIAQAAAA==.Trisandra:BAAANQAECgMIBAAAAA==.',
Tu='Tuugadark:BAABNQAECn86AAIFAAoKGRxfNwCuAgAFAAoKGRxfNwCuAgAAAA==.',
Tz='Tzulari:BAAANQAECgUIBwABNQAECgUICAADAAAAAA==.',
Ul='Ulyaoth:BAAANQADCgUIBQAAAA==.',
Un='Unbroken:BAAANQADCgMIAwAAAA==.Unprepared:BAAANQAECgEIAQABNQAECggILAAHAO8SAA==.',
Va='Vasdeferens:BAAANQABCgMIAwAAAA==.',
Ve='Vedros:BAAANQADCgYICQAAAA==.Verbina:BAAANQAECgQIEAABNQAECgoKNgACAFAbAA==.Vespertilia:BAAANQAECgUIBQAAAA==.',
Vo='Vorukh:BAAANQAECgcICwAAAA==.',
Vy='Vynas:BAAANQAECgEIAQAAAA==.',
Wa='Warlockgroo:BAAANQADCgcICgABNQAECgEIAQADAAAAAA==.Warriorgroo:BAAANQADCggILgABNQAECgEIAQADAAAAAA==.',
Wh='Whácker:BAAANQAECgIIAgABNQAECgoKLAAaAHccAA==.',
Wi='Wickdlovly:BAAANQAECgUICAABNQAECggIHwACAE0ZAA==.Wickedslicks:BAABNQAECn8iAAISAAgK3hz8IQDYAQASAAgK3hz8IQDYAQAAAA==.',
Wr='Wreckshop:BAAANQADCgYIDwABNQAECgkJNwANAPQgAA==.',
Xe='Xenøcide:BAAANQADCgcICwAAAA==.',
Xi='Xiatus:BAAANQAECgcIEwABNQAECgoKUQAkAMklAA==.',
Xo='Xoren:BAAANQAECgEIAgABNQAECgcICAADAAAAAA==.',
Xx='Xxdeathz:BAAANQABCgMIAwABNQAECggIJgAPAP0bAA==.Xxlockz:BAAANQAECgQIBAABNQAECggIJgAPAP0bAA==.Xxpallyz:BAABNQAECn8mAAIPAAgK/RsNTwAvAgAPAAgK/RsNTwAvAgAAAA==.',
Yo='Yohh:BAABNQAECn81AAICAAoKtxN2SwA1AgACAAoKtxN2SwA1AgAAAA==.Yorie:BAAANQADCgMIAwAAAA==.',
Yu='Yuriko:BAABNQAECn9DAAQiAAoKahBeHAC+AQAiAAoKahBeHAC+AQANAAYKKQZrPgClAAAlAAEK4wXCJwApAAAAAA==.',
Za='Zadory:BAAANQADCggIDAAAAA==.Zaidan:BAAANQADCggIEAAAAA==.',
Ze='Zendous:BAAANQAECgYIBgAAAA==.',
Zi='Zippitydooda:BAABNQAECn8fAAMCAAgKTRnkSwDMAQACAAgKTRnkSwDMAQAjAAEKAAAWGAEAAAAAAA==.',
Zo='Zodiacc:BAABNQAECn8+AAITAAoKPSAICAD/AgATAAoKPSAICAD/AgAAAA==.Zornhealer:BAAANQAECgYICAABNQAECgcIEgADAAAAAA==.Zorrn:BAAANQAECgcIEgAAAA==.',
['Zí']='Zílch:BAAANQAECgEIAQAAAA==.',
['Zî']='Zîlch:BAAANQADCgcIBwAAAA==.',
['Zö']='Zölä:BAAANQAECgQICAABNQAECgYICAADAAAAAA==.',
['Çh']='Çhrìs:BAAANQAECgQICgAAAA==.',
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
