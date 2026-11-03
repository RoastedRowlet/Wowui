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

local lookup = {'DeathKnight-Blood','Shaman-Restoration','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Mage-Arcane','Warlock-Destruction','Warrior-Protection','Warrior-Fury','Paladin-Protection','Warrior-Arms','Monk-Windwalker','Rogue-Subtlety','Paladin-Holy','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Unknown-Unknown','Druid-Guardian','Mage-Frost','Mage-Fire','DeathKnight-Frost','Evoker-Devastation','Priest-Holy','Evoker-Augmentation','Shaman-Enhancement','DemonHunter-Havoc','Paladin-Retribution','Rogue-Assassination','Priest-Shadow','Rogue-Outlaw','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Shaman-Elemental','DeathKnight-Unholy','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aardz:BAAANQADCggIDgAAAA==.',
Ab='Abeblinkin:BAAANQADCgYICgAAAA==.Abraxîs:BAAANQAECgYIBwAAAA==.',
Ac='Acindis:BAABNQAECn84AAIBAAoKcRJJOwAYAgABAAoKcRJJOwAYAgAAAA==.',
Ae='Aeless:BAAANQAECgQICAAAAA==.Aelless:BAAANQADCgEIAQAAAA==.',
Ah='Ahzure:BAAANQAECgcIDgABNQAECgkJMAACACkbAA==.',
Ai='Aithinne:BAAANQADCgUICgAAAA==.',
Al='Alch:BAAANQADCgQICAAAAA==.Aleandi:BAAANQADCgUIBQAAAA==.Aledil:BAAANQAECgcICwAAAA==.Alynara:BAABNQAECn82AAIDAAoKmxhzUgB5AgADAAoKmxhzUgB5AgAAAA==.',
Am='Amalthea:BAABNQAECn8ZAAMEAAoKjAZgtQBkAQAEAAoKCgZgtQBkAQAFAAEKMghzJgA1AAAAAA==.Amiri:BAAANQADCgEIAQAAAA==.Amoredis:BAAANQADCgEIAQAAAA==.',
An='Anume:BAAANQADCgYIDwAAAA==.Anwas:BAAANQADCgEIAQAAAA==.',
Ap='Apally:BAAANQADCgUIBQAAAA==.',
Ar='Aragan:BAAANQADCgQIBQAAAA==.Arellean:BAAANQADCgQIBAAAAA==.Arese:BAABNQAECn8bAAIGAAgKbB6aVgDnAQAGAAgKbB6aVgDnAQAAAA==.Aron:BAAANQADCgEIAQAAAA==.',
As='Asmodea:BAAANQADCgUIBgAAAA==.Asphonix:BAAANQAECgEIAQAAAA==.Asyllann:BAAANQADCgEIAQAAAA==.',
Az='Azzif:BAABNQAECn8eAAMHAAkKvgUiDQDTAAAHAAgKWwYiDQDTAAAEAAgKXAHLKgFoAAAAAA==.',
Ba='Babybluz:BAAANQAECgUIBgAAAA==.Backstabbath:BAAANQADCgQIBAAAAA==.Baifeng:BAAANQADCgEIAQAAAA==.Bandayde:BAAANQADCgYIBQAAAA==.Barlas:BAAANQAECgUIBAAAAA==.',
Be='Beauriley:BAABNQAECn83AAMIAAoKHgtMHAB4AQAIAAoKHgtMHAB4AQAJAAEKdAYsLwAjAAAAAA==.Behomethan:BAAANQAECggIDwAAAA==.Belorc:BAAANQADCgUIBQAAAA==.Berian:BAAANQAECgIIAgAAAA==.',
Bi='Bigpapafreez:BAAANQADCggIDwABNQAECgoKTgAKAPMdAA==.Billbetaray:BAABNQAECn8WAAILAAkKfRbzmwDWAQALAAkKfRbzmwDWAQAAAA==.',
Bl='Blux:BAAANQADCgEIAQAAAA==.Bløødsong:BAAANQADCgEIAgAAAA==.',
Bo='Bolton:BAAANQADCgYIBgAAAA==.Bombchele:BAABNQAECn8uAAIMAAgKcR8UDQBgAgAMAAgKcR8UDQBgAgAAAA==.Bowogibrann:BAAANQADCgQIBAAAAA==.',
Br='Bratticusrex:BAABNQAECn8vAAIJAAgKrgj2FwAgAQAJAAgKrgj2FwAgAQAAAA==.Brazier:BAAANQADCggICAAAAA==.Bresowar:BAAANQADCgIIBAAAAA==.Brien:BAAANQADCgEIAQAAAA==.Brynthe:BAAANQADCgYIDwAAAA==.',
Bu='Bunnylicious:BAABNQAECn87AAICAAkKuSUxCgBcAwACAAkKuSUxCgBcAwAAAA==.Bunnymedic:BAAANQAECgMIAwABNQAECgkJOwACALklAA==.',
Ca='Caebrylla:BAABNQAECn8pAAIDAAkKiROuXQDHAQADAAkKiROuXQDHAQAAAA==.Cajun:BAABNQAECn8rAAILAAkKJBjMPgAaAgALAAkKJBjMPgAaAgABNQAFFAYIIQANAPUXAA==.Calistie:BAAANQADCggICQAAAA==.Callipygea:BAAANQADCgIIAgAAAA==.Calver:BAAANQADCgUIBQAAAA==.Camil:BAAANQADCgMIAwABNQAECgoKNgADAK4OAA==.Cang:BAAANQADCgEIAgAAAA==.Catalina:BAABNQAECn9CAAIOAAoKPh9rFgAkAwAOAAoKPh9rFgAkAwAAAA==.',
Ce='Cecimorte:BAABNQAECn8qAAIBAAgKaxPONABKAQABAAgKaxPONABKAQAAAA==.',
Ch='Chargeasap:BAAANQADCgUIBQAAAA==.Charttopper:BAAANQAECgQIBAABNQAECgoKIAAOAKgUAA==.Chinashop:BAAANQAECgQIAwABNQAECggIFgAPAOMgAA==.Chonker:BAABNQAECn9CAAMQAAoK/BUXFQAxAgAQAAoK/BUXFQAxAgARAAkKvxHPPAAQAgAAAA==.Chuckforrest:BAAANQADCgIIAwABNQAECgYIBgASAAAAAA==.',
Ci='Cihato:BAABNQAECn88AAITAAoK3xjiFAAZAgATAAoK3xjiFAAZAgAAAA==.',
Cl='Claye:BAAANQAECgIIAgAAAA==.Cleveistic:BAAANQADCgUICAABNQAECgMIBgASAAAAAA==.Cleveland:BAAANQAECgMIBgAAAA==.',
Co='Coldshoulder:BAABNQAECn8nAAQGAAgKxhK/mQBEAQAGAAcKRBK/mQBEAQAUAAIK7BPvLgCHAAAVAAIKRA2iBgB8AAAAAA==.Corelas:BAAANQAECgMIBQAAAA==.Couchdad:BAAANQAECgQICAABNQAECgYICAASAAAAAA==.',
Cr='Crazymadman:BAAANQAECgIIAgAAAA==.Crysallis:BAAANQADCggIHgAAAA==.',
Cy='Cynide:BAAANQADCgYJBgAAAA==.Cyyrene:BAAANQABCgEIAQABNQAECgoKHAAWALQRAA==.',
Da='Dall:BAAANQAECgIIAwAAAA==.Damo:BAAANQAECgcICAAAAA==.Danale:BAAANQADCgYJCgAAAA==.Danknugz:BAAANQAECgcIEgAAAA==.Darwina:BAAANQADCgEIAQAAAA==.Dawnson:BAABNQAECn8YAAIOAAgKGxmlUwAfAgAOAAgKGxmlUwAfAgAAAA==.',
De='Deadscream:BAAANQAECggIBgAAAA==.Deathlich:BAABNQAECn8aAAIWAAkKGhZyMACrAQAWAAkKGhZyMACrAQAAAA==.Demogless:BAAANQAECgQIBwAAAA==.Desyrel:BAAANQAECgIIAgABNQAECgcICAASAAAAAA==.',
Dh='Dharknight:BAAANQAECgQIBgABNQAECgUIBwASAAAAAA==.Dharkuul:BAAANQADCgEIAQABNQAECgUIBwASAAAAAA==.',
Di='Didimissfire:BAEBNQAECn87AAIDAAoKVQtFWgDQAQADAAoKVQtFWgDQAQAAAA==.Diefatty:BAAANQADCgMIAwAAAA==.',
Do='Doll:BAAANQADCgQIBAAAAA==.',
Dr='Draeven:BAAANQAECgYIDAAAAA==.Dranalis:BAAANQADCgYICAAAAA==.Dredlok:BAAANQADCgYIEQAAAA==.',
Du='Dumonster:BAABNQAECn8UAAIJAAYKgQKqJQCBAAAJAAYKgQKqJQCBAAAAAA==.Dustdevil:BAAANQAECgYICQABNQAECggIFgAPAOMgAA==.',
Ee='Eeaassyy:BAAANQADCgYICgAAAA==.',
El='Elaraa:BAAANQADCgQIBAAAAA==.Eldorath:BAAANQAECgIIAgAAAA==.Elev:BAAANQADCgMIBgAAAA==.Elizabeth:BAAANQADCgUIBQAAAA==.',
Er='Eris:BAAANQADCggICQAAAA==.Erzascar:BAAANQAECgEIAQAAAA==.',
Es='Estrogen:BAABNQAECn8wAAIXAAoKzCN+AwBvAwAXAAoKzCN+AwBvAwAAAA==.',
Ev='Eventhorizon:BAAANQAECgYIAgAAAA==.Evolett:BAAANQADCgQIBQAAAA==.',
Fa='Fatbox:BAABNQAECn8zAAMJAAkKgh8CBQDcAgAJAAkKgh8CBQDcAgALAAEKrA0uVAEyAAAAAA==.Fayth:BAABNQAECn81AAIYAAoKHB1qMgCeAgAYAAoKHB1qMgCeAgAAAA==.',
Fe='Fearblade:BAAANQADCgMIAwAAAA==.Fearkin:BAABNQAECn8vAAMZAAkKIw7+CwCbAQAZAAkKrAz+CwCbAQAXAAcKxw0XDABgAQAAAA==.Fenastic:BAABNQAECn8nAAMEAAcKpAftuwBVAQAEAAcKpAftuwBVAQAFAAEKtwd2MAA0AAAAAA==.Feyrah:BAAANQAECgEIAQAAAA==.',
Fi='Fiobhe:BAAANQAECgMIBQAAAA==.Fixeruper:BAAANQAECggIEgAAAA==.',
Fo='Fonz:BAAANQADCgYIBgABNQAECgQIDwASAAAAAA==.',
['Fí']='Físter:BAAANQADCgMIAwABNQAECgoKLAAaAHccAA==.',
Ga='Gazember:BAAANQAECgEIAQABNQAECgoKKQACABgWAA==.',
Ge='Geauxt:BAAANQAECgUIBwABNQAFFAYIIQANAPUXAA==.',
Gl='Glenlizzo:BAAANQADCgEJAgABNQAECgMIBgASAAAAAA==.Glenroyce:BAAANQAECgMIBgAAAA==.Gless:BAABNQAECn88AAMIAAkK7gxTEwBJAQAIAAkK7gxTEwBJAQALAAEKAAC1XwEnAAAAAA==.',
Gn='Gnoretreat:BAABNQAECn88AAILAAoKvRimOgArAgALAAoKvRimOgArAgAAAA==.',
Go='Goss:BAAANQAECggICAAAAA==.',
Gu='Gueret:BAAANQABCgIIAgAAAA==.',
Gw='Gwinnivor:BAAANQAECgIIAgAAAA==.',
Ha='Haenus:BAAANQADCgMIAwAAAA==.Haill:BAAANQAECgUIBgABNQAECggIGQACAE0ZAA==.Hamhock:BAAANQAECgIIAgABNQAECgkJMwAJAIIfAA==.Hanis:BAAANQADCgQIBwAAAA==.',
He='Hellìos:BAAANQADCgYIBgABNQAECgIIAgASAAAAAA==.',
Hy='Hyborian:BAABNQAECn8jAAIDAAcKCw0doQArAQADAAcKCw0doQArAQABNQADCgIIBAASAAAAAA==.',
Ic='Icandy:BAAANQADCgMIAgAAAA==.Icecuber:BAAANQADCgUIBwAAAA==.',
Ih='Ihatepallys:BAAANQADCgYICwAAAA==.',
Ii='Iikeomgikr:BAACNQAFFH8FAAIYAAIKdA84JQCDAAAYAAIKdA84JQCDAAA1AAQKfywAAhgACgrFEis8ABECABgACgrFEis8ABECAAAA.',
Il='Ilidank:BAABNQAECn8WAAIPAAgK4yA8BwCYAgAPAAgK4yA8BwCYAgAAAA==.Ilya:BAAANQAECgcIBwAAAA==.',
In='Indigo:BAABNQAECn8wAAICAAkKKRsgUAAlAgACAAkKKRsgUAAlAgAAAA==.Ineffablyss:BAAANQAECgYIBgABNQAFFAIIBQAYAHQPAA==.Innron:BAABNQAECn8uAAIbAAoKMwzPLgBgAQAbAAoKMwzPLgBgAQAAAA==.',
Io='Iol:BAAANQADCgIIAgAAAA==.Iolaus:BAAANQAECgcIBwAAAA==.',
Ir='Irisblue:BAAANQADCgYIAwAAAA==.',
Ja='Jaque:BAAANQADCgYIDwAAAA==.',
Je='Jeybieber:BAAANQAECgEIAwAAAA==.Jezzea:BAAANQADCgYIDAAAAA==.',
Ji='Jinjix:BAAANQADCgYIDwAAAA==.',
Jo='Jolenee:BAAANQAECgUIBQAAAA==.Jolike:BAAANQAECggIAgAAAA==.Jonly:BAAANQADCgQICgAAAA==.Jonoa:BAAANQAECggIDAAAAA==.',
['Jú']='Júdgemental:BAABNQAECn8oAAMOAAkKNBjuTAA2AgAOAAkKNBjuTAA2AgAcAAUKhxVxxwAIAQAAAA==.',
Ka='Kair:BAAANQADCgcICAAAAA==.Kalsium:BAAANQADCgUJEAAAAA==.Kami:BAAANQAECgIIAwAAAA==.Kattastrophy:BAAANQAECgEIAQAAAA==.Katteya:BAAANQAECgQIBAAAAA==.Kattia:BAABNQAECn88AAIDAAkKGQnVcQCTAQADAAkKGQnVcQCTAQAAAA==.',
Ki='Killinkair:BAAANQAECgYIDgAAAA==.Kinomihime:BAABNQAECn8yAAMUAAoKJRDqDQDPAQAUAAoKJRDqDQDPAQAGAAEKMAa+xwE0AAAAAA==.Kirajoy:BAABNQAECn87AAMHAAkKyQbiMwD0AAAEAAgKsAYrdABFAQAHAAcKYwLiMwD0AAAAAA==.Kisses:BAAANQADCgYICgAAAA==.',
Kl='Klyndori:BAAANQADCgMIAwAAAA==.',
Kn='Knyghtt:BAABNQAECn8gAAIJAAoKXAuyDQBiAQAJAAoKXAuyDQBiAQAAAA==.',
Ko='Konoa:BAAANQADCgEIAgAAAA==.',
Kr='Kraviz:BAAANQADCgcICwAAAA==.Krombopolous:BAAANQADCggICgABNQAECggILwADACMMAA==.Krystle:BAAANQAECgcICwAAAA==.',
La='Lanfeer:BAAANQADCgEIAgAAAA==.',
Le='Leftyloose:BAAANQADCgYIBAAAAA==.Leorna:BAAANQADCgQIBQAAAA==.',
Li='Lightcure:BAAANQAECgQIBwABNQAECggICwASAAAAAA==.Lilfonz:BAAANQAECgQIDwAAAA==.Lishalan:BAAANQAECgYIBwAAAA==.Littlejohn:BAAANQAECgQIBwABNQAECggIFgAPAOMgAA==.',
Lo='Logarth:BAAANQAECgYICwAAAA==.Londonfog:BAAANQADCggIEwAAAA==.Loppandload:BAAANQAECgEIAQAAAA==.Loppsang:BAAANQAECgQIBAAAAA==.Lorcan:BAABNQAECn87AAILAAoK3x8LWwB7AgALAAoK3x8LWwB7AgAAAA==.',
Lr='Lroye:BAACNQAFFH8hAAMNAAYK9RfdBwBeAQANAAYK9RfdBwBeAQAdAAEK2w0uIABIAAA1AAQKf04AAw0ACgrkJFQCAI8DAA0ACgrkJFQCAI8DAB0AAQrOGyNQAFQAAAAA.',
Lu='Lucyfer:BAAANQADCgcIDQABNQAECgcICAASAAAAAA==.Lucyferr:BAABNQAECn8UAAIGAAYKzQK5ggG/AAAGAAYKzQK5ggG/AAABNQAECgcICAASAAAAAA==.Ludicrispeed:BAAANQADCgYIAwAAAA==.Luliak:BAAANQAECgIIAgABNQAFFAUIDAAaACYaAA==.Lunabren:BAAANQADCgcIBgAAAA==.Lunamina:BAAANQAECgEIAQAAAA==.',
['Lì']='Lìllith:BAABNQAECn8WAAMYAAgKjA18lwBPAQAYAAcKrQx8lwBPAQAeAAYKfgqOLQDhAAABNQAFFAIIBQAcAFIOAA==.',
Ma='Madmacs:BAAANQADCgEIAQAAAA==.Madoka:BAABNQAECn8wAAILAAoK6xNqUgDUAQALAAoK6xNqUgDUAQAAAA==.Mariophra:BAABNQAECn8lAAICAAgKQRMPUACgAQACAAgKQRMPUACgAQAAAA==.Maxdemon:BAAANQADCgcIDAAAAA==.Maxpal:BAAANQADCgYIDwAAAA==.',
Mc='Mcnastyqt:BAAANQADCgIIAgAAAA==.',
Me='Mesdel:BAAANQAECgEIAQABNQAECggIBgASAAAAAA==.',
Mi='Mikki:BAAANQADCgIIAgAAAA==.Misstorgo:BAAANQAECgQICQAAAA==.',
Mo='Mohegian:BAAANQADCgEIAgAAAA==.Mokoko:BAABNQAECn8aAAMdAAoKdBWrCQAYAgAdAAoKKhWrCQAYAgAfAAMKFA1QCABzAAAAAA==.Momoka:BAABNQAECn8WAAMcAAgK9A8IuwAdAQAcAAcKFxIIuwAdAQAKAAIK8APvUgBAAAAAAA==.Monfro:BAAANQAECgYICAAAAA==.Monnethir:BAAANQADCgUIBQAAAA==.Moogatoo:BAAANQAECgEIAQAAAA==.Moonbane:BAABNQAECn83AAMHAAoKcBz+BQCwAgAHAAoKcBz+BQCwAgAEAAQKZAzL+wDUAAAAAA==.Moonmist:BAAANQADCgEIAQABNQAECggIGQACAE0ZAA==.Mordecai:BAABNQAECn8aAAIDAAkKpBqraQBAAgADAAkKpBqraQBAAgAAAA==.',
Mu='Musturd:BAAANQADCgEIAQAAAA==.',
My='Myaquean:BAAANQADCgYIDwAAAA==.Mystogan:BAAANQADCgYIDwAAAA==.Myth:BAABNQAECn8vAAMRAAkKHxb9NwAuAgARAAkKHxb9NwAuAgAQAAgKvhHFKABeAQAAAA==.Mythelea:BAAANQAECgEIAQAAAA==.',
Na='Naavi:BAAANQAECgUICAAAAA==.Nakeefa:BAAANQADCgYIBwAAAA==.Natsuu:BAABNQAECn81AAMDAAkK4BHIWQDSAQADAAkK4BHIWQDSAQAgAAIK1wMrDwBNAAAAAA==.',
Ne='Nefertiti:BAAANQADCggIAwAAAA==.Nekona:BAAANQADCgQIBAAAAA==.Neron:BAACNQAFFH8FAAIcAAIKUg4UHgCHAAAcAAIKUg4UHgCHAAA1AAQKf0AAAhwACgrMH8sxAAQDABwACgrMH8sxAAQDAAAA.',
Ni='Niany:BAAANQAECgMIBgAAAA==.',
Nj='Njoror:BAAANQAECgIIAgAAAA==.',
No='Nonoffensive:BAAANQADCggIDwAAAA==.Norky:BAAANQABCgUICQABNQAECgIIAgASAAAAAA==.Nottapally:BAAANQAECggIDQABNQAECgoKIAAOAKgUAA==.',
Os='Ossiferous:BAAANQAECgYIDgAAAA==.',
Ou='Outerlimits:BAABNQAECn8cAAIWAAoKtBGiOgB2AQAWAAoKtBGiOgB2AQAAAA==.',
Pa='Pamboo:BAABNQAECn9EAAIOAAoKjQ/ZMgAgAgAOAAoKjQ/ZMgAgAgAAAA==.Patticake:BAAANQAECggICAAAAA==.',
Pe='Pearle:BAAANQAECggICAAAAA==.Penthesilea:BAAANQADCgEIAQAAAA==.',
Po='Potatoslicer:BAAANQADCgQIBAAAAA==.',
Pr='Priestiô:BAAANQAECgUICgAAAA==.Pringo:BAABNQAECn8ZAAMGAAkKTAQE1gDTAAAGAAkKTAQE1gDTAAAUAAEKAAB0QQAAAAAAAA==.',
Pu='Pukka:BAAANQABCgQIBAABNQAECgoKLwAYABAjAA==.',
Py='Pylea:BAAANQAECgIIAQAAAA==.',
Ra='Ramindizzle:BAABNQAECn87AAIhAAoKSRERFADJAQAhAAoKSRERFADJAQAAAA==.Randomname:BAABNQAECn8iAAIDAAkKCBnyYwC2AQADAAkKCBnyYwC2AQABNQAECgkJKAAOADQYAA==.',
Re='Refreshing:BAAANQADCggIDwAAAA==.Rekki:BAAANQAECgQICAABNQAECgcICAASAAAAAA==.Retastic:BAAANQADCgUIBgAAAA==.',
Ri='Rigmarole:BAAANQAECgcIDAAAAA==.',
Ro='Rocksmasher:BAAANQADCgEIAQABNQAECgoKIAAOAKgUAA==.Ronun:BAAANQADCggIDAAAAA==.Roograh:BAAANQAECgEIAQAAAA==.Rook:BAAANQAECgEIAQAAAA==.Rooklyn:BAABNQAECn87AAIOAAoKvxIORADQAQAOAAoKvxIORADQAQAAAA==.Roye:BAACNQAFFH8GAAIcAAUKkRW8DwDhAAAcAAUKkRW8DwDhAAA1AAQKf0AAAhwACgp6JbkFAF0DABwACgp6JbkFAF0DAAE1AAUUBgghAA0A9RcA.',
Ru='Ruffiyo:BAAANQAECggICwAAAA==.Rugrahh:BAAANQADCgYIBgABNQAECgEIAQASAAAAAA==.Rugzco:BAACNQAFFH8GAAIiAAIKtQ31BwCAAAAiAAIKtQ31BwCAAAA1AAQKfzIAAiIACgr8GM4QAHICACIACgr8GM4QAHICAAAA.Ruìn:BAAANQAECgUICgAAAA==.',
Ry='Ryalla:BAAANQADCgEIAgAAAA==.',
['Ræ']='Ræñ:BAAANQAECgcIBwAAAA==.',
Sa='Sabina:BAABNQAECn82AAIjAAoK2AhOjQCDAQAjAAoK2AhOjQCDAQAAAA==.Sadako:BAAANQAECgcICAAAAA==.Sadness:BAAANQADCggIJwAAAA==.Sadorick:BAAANQAECgQIBAAAAA==.Sadôrick:BAAANQADCggIDQAAAA==.Sageguy:BAAANQADCgcIDwAAAA==.Saintkitiara:BAAANQADCgEIAQAAAA==.Sango:BAABNQAECn8uAAIbAAoKwRMkHwDYAQAbAAoKwRMkHwDYAQAAAA==.Sarenity:BAAANQADCggIDgAAAA==.Savagelykill:BAAANQADCggIEAAAAA==.',
Sc='Scotch:BAABNQAECn81AAMcAAkKRhJggQCJAQAcAAkKRhJggQCJAQAKAAMKkREwWAAyAAAAAA==.Scotchnwater:BAAANQAECgcICAAAAA==.Scratchies:BAAANQAECggIEQAAAA==.',
Se='Seiwar:BAABNQAFFH8GAAILAAMKqAd9KAC5AAALAAMKqAd9KAC5AAAAAA==.',
Sh='Shadornia:BAAANQAECgMIBwAAAA==.Shadowcrwlr:BAAANQADCgQIBAAAAA==.Shamanio:BAABNQAECn88AAMCAAoKIiULCwBoAwACAAoKIiULCwBoAwAjAAIKCxQR0wBBAAAAAA==.Shammbulance:BAABNQAECn8YAAMjAAkKzA85WABDAQAjAAgKxA05WABDAQACAAYK6ANwowCqAAABNQAECgkJKAAOADQYAA==.Shamsham:BAAANQADCgEIAgAAAA==.Sharaaz:BAAANQADCgUIBQAAAA==.Shatoya:BAAANQADCgcIAwAAAA==.',
Si='Silverytwo:BAAANQADCggIFgAAAA==.Silverywolfe:BAAANQAECgQIBQAAAA==.Simony:BAAANQADCggICAABNQAECgcICAASAAAAAA==.Sintia:BAAANQAECgYIDAABNQAECgoKLwAYABAjAA==.',
Sk='Skovak:BAAANQAECgUIBgAAAA==.Skoveth:BAAANQAECgIIAQAAAA==.',
So='Sorayae:BAABNQAECn8vAAIYAAoKECPyCAB8AwAYAAoKECPyCAB8AwAAAA==.',
Sp='Specialk:BAAANQAECgQIBQAAAA==.Splooshh:BAAANQADCggIDwABNQAECggICwASAAAAAA==.',
St='Steeler:BAAANQAECgEIAQABNQADCgIIBAASAAAAAA==.Stinkfoot:BAABNQAECn8eAAIBAAgKihWlSQDRAQABAAgKihWlSQDRAQAAAA==.Stormkissed:BAAANQAECgQICQAAAA==.Strawman:BAAANQAECggIEQAAAA==.',
Su='Sulvazud:BAAANQADCgEIAQAAAA==.Sunil:BAABNQAECn82AAIYAAkKdhjmNwAmAgAYAAkKdhjmNwAmAgAAAA==.',
Sy='Syclone:BAAANQAECgMIBgABNQAFFAIICAABAL0fAA==.Sypha:BAABNQAECn8ZAAIGAAoKohJTRQAYAgAGAAoKohJTRQAYAgAAAA==.',
['Så']='Såriel:BAAANQADCgEIAQAAAA==.',
Ta='Taetheras:BAAANQAECggIDgAAAA==.Tahlyn:BAAANQAECgcIBwABNQAECgkJMAACACkbAA==.Tattianna:BAAANQADCggIHwAAAA==.Tavendar:BAABNQAECn8yAAMOAAoKyRxLKQBVAgAOAAkKZBxLKQBVAgAcAAIKSwV0jAFJAAABNQAECgIIAgASAAAAAA==.Taírn:BAAANQADCgEIAQABNQAECgoKLAAaAHccAA==.',
Tc='Tcshmaster:BAAANQAECgIIAQAAAA==.',
Te='Texgrebner:BAAANQAECgYIEgABNQAECggIFgAPAOMgAA==.',
Th='Theeyedoctor:BAAANQADCggIBwABNQAECgoKIAAOAKgUAA==.Theodoric:BAAANQADCgEIAQAAAA==.Thunderslate:BAABNQAECn8gAAMOAAoKqBQ3KQBVAgAOAAkKBRY3KQBVAgAKAAYKmxD+MgBKAQAAAA==.Thyrok:BAABNQAECn8UAAIbAAgK3AfKOwARAQAbAAgK3AfKOwARAQAAAA==.',
Ti='Tigreth:BAABNQAECn88AAMcAAoKKg2ttQCzAQAcAAoKKg2ttQCzAQAKAAUK+wenWQB3AAAAAA==.Tinkerballa:BAAANQADCggJFQAAAA==.',
To='Toastal:BAAANQAECgIIAgAAAA==.Tokxi:BAAANQADCgQIBwABNQAECgoKIwAKAMUVAA==.Totemzasap:BAAANQAECgQICAAAAA==.',
Tr='Traductus:BAAANQAECgMIAgAAAA==.Tragik:BAABNQAECn87AAIaAAoKrwunEADNAQAaAAoKrwunEADNAQAAAA==.Trisandra:BAAANQAECgMIBAAAAA==.',
Tu='Tuugadark:BAABNQAECn83AAIEAAoKPRtfNwCuAgAEAAoKPRtfNwCuAgAAAA==.',
Tz='Tzulari:BAAANQAECgUIBwAAAA==.',
Ul='Ulyaoth:BAAANQADCgUIBgAAAA==.',
Un='Unbroken:BAAANQADCgMIAwAAAA==.Unprepared:BAAANQABCgEIAQABNQAECggIJwAGAMYSAA==.',
Va='Vasdeferens:BAAANQADCgEIAQAAAA==.Vayona:BAAANQADCgEIAQAAAA==.',
Ve='Vedros:BAAANQADCgYICgAAAA==.Verbina:BAAANQAECgYIDwABNQAECgkJMAACACkbAA==.Vespertilia:BAAANQAECgUIBQAAAA==.',
Vo='Vorukh:BAAANQAECgIIBAAAAA==.',
Vy='Vynas:BAAANQAECgEIAQAAAA==.',
Wa='Warhorse:BAAANQADCgEIAQAAAA==.Warlockgroo:BAAANQADCgcIDAABNQADCggIMwASAAAAAA==.Warriorgroo:BAAANQADCggIMwAAAA==.',
Wh='Whácker:BAAANQAECgIIAgABNQAECgoKLAAaAHccAA==.',
Wi='Wickdlovly:BAAANQAECgQIBAABNQAECggIGQACAE0ZAA==.Wickedslicks:BAABNQAECn8fAAIRAAgK3hxEHgDbAQARAAgK3hxEHgDbAQAAAA==.',
Wr='Wreckshop:BAAANQADCgYIEAABNQAECggILgAMAHEfAA==.',
Xe='Xenøcide:BAAANQADCgcIDAAAAA==.',
Xi='Xiatus:BAAANQAECgcIEAABNQAECgoKSAAkAMklAA==.',
Xo='Xoren:BAAANQAECgEIAQABNQAECgcICAASAAAAAA==.',
Xx='Xxdeathz:BAAANQABCgMIAwABNQAECggIIAAOANwbAA==.Xxlockz:BAAANQAECgQIBAABNQAECggIIAAOANwbAA==.Xxpallyz:BAABNQAECn8gAAIOAAgK3BsNTwAvAgAOAAgK3BsNTwAvAgAAAA==.',
Yo='Yohh:BAABNQAECn8yAAICAAoKFhN2SwA1AgACAAoKFhN2SwA1AgAAAA==.Yorie:BAAANQADCgMIAwAAAA==.',
Yu='Yuriko:BAABNQAECn88AAMiAAoKLBBeHAC+AQAiAAoKLBBeHAC+AQAlAAEK4wUXJAAsAAAAAA==.',
Za='Zadory:BAAANQADCggIDQAAAA==.Zaidan:BAAANQADCggIEQAAAA==.',
Ze='Zendous:BAAANQAECgYIBgAAAA==.',
Zi='Zippitydooda:BAABNQAECn8ZAAICAAgKTRnpQgDXAQACAAgKTRnpQgDXAQAAAA==.',
Zo='Zodiacc:BAABNQAECn86AAITAAoKPSAICAD/AgATAAoKPSAICAD/AgAAAA==.Zornhealer:BAAANQAECgIIAgABNQAECgYICAASAAAAAA==.Zorrn:BAAANQAECgYICAAAAA==.',
['Zí']='Zílch:BAAANQAECgEIAQAAAA==.',
['Zî']='Zîlch:BAAANQADCgcIBwAAAA==.',
['Zö']='Zölä:BAAANQAECgQIBwABNQAECgYIBwASAAAAAA==.',
['Çh']='Çhrìs:BAAANQAECgQICAAAAA==.',
['Çú']='Çúrsè:BAAANQADCgIIBAAAAA==.',
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
