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

local lookup = {'DeathKnight-Blood','Shaman-Restoration','Hunter-BeastMastery','Warrior-Protection','Paladin-Protection','Warrior-Fury','Rogue-Subtlety','Paladin-Holy','Unknown-Unknown','Druid-Balance','Druid-Restoration','Druid-Guardian','Evoker-Devastation','Warrior-Arms','Priest-Holy','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc','Mage-Frost','Mage-Arcane','Warlock-Destruction','DeathKnight-Frost','Rogue-Assassination','Shaman-Enhancement','Paladin-Retribution','Shaman-Elemental','Hunter-Marksmanship','Monk-Mistweaver','DeathKnight-Unholy',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abeblinkin:BAAANQADCgYICQAAAA==.Abraxîs:BAAANQAECgYIBwAAAA==.',
Ac='Acindis:BAABNQAECoEoAAIBAAkKWQs/VACBAQABAAkKWQs/VACBAQAAAA==.',
Ae='Aeless:BAAANQAECgIJAgAAAA==.Aelless:BAAANQADCgEIAQAAAA==.',
Ah='Ahzure:BAAANQAECgYICAABNQAECgcIHAACAMsYAA==.',
Ai='Aithinne:BAAANQADCgUICQAAAA==.',
Al='Alch:BAAANQADCgQIBAAAAA==.Aleandi:BAAANQADCgUIBQAAAA==.Aledil:BAAANQAECgYICgAAAA==.Alynara:BAABNQAECoEbAAIDAAgK8xnCSABsAgADAAgK8xnCSABsAgAAAA==.',
Am='Amalthea:BAAANQAECgYICwAAAA==.Amoredis:BAAANQABCgcIDwAAAA==.',
An='Anume:BAAANQADCgYIDgAAAA==.Anwas:BAAANQABCgIIAgAAAA==.',
Ap='Apally:BAAANQADCgUIBQAAAA==.',
Ar='Aragan:BAAANQADCgQIBAAAAA==.Arellean:BAAANQADCgQIBAAAAA==.Arese:BAAANQAECgUIDgAAAA==.',
As='Asmodea:BAAANQADCgUJBQAAAA==.Asphonix:BAAANQAECgEIAQAAAA==.',
Az='Azzif:BAAANQAECgYIAwAAAA==.',
Ba='Babybluz:BAAANQAECgEIAgAAAA==.Baifeng:BAAANQABCggIEgAAAA==.Bandayde:BAAANQADCgEIAQAAAA==.',
Be='Beauriley:BAABNQAECoEfAAIEAAgK5gw5GAB8AQAEAAgK5gw5GAB8AQAAAA==.Behomethan:BAAANQAECgYICwAAAA==.Belorc:BAAANQADCgIIAgAAAA==.Berian:BAAANQAECgIIAgAAAA==.',
Bi='Bigpapafreez:BAAANQADCggIDQABNQAECgkJJgAFACcbAA==.Billbetaray:BAAANQAECgYICwAAAA==.',
Bl='Blux:BAAANQADCgEIAQAAAA==.Bløødsong:BAAANQADCgEIAQAAAA==.',
Bo='Bombchele:BAAANQAECgYIDwAAAA==.Bowogibrann:BAAANQADCgQIBAAAAA==.',
Br='Bratticusrex:BAABNQAECoEdAAIGAAgKBgYSFgAYAQAGAAgKBgYSFgAYAQAAAA==.Brazier:BAAANQADCggICAAAAA==.Bresowar:BAAANQADCgIIAgAAAA==.Brynthe:BAAANQADCgYICwAAAA==.',
Bu='Bunnylicious:BAABNQAECoEcAAICAAcKwyPXIQDCAgACAAcKwyPXIQDCAgAAAA==.Bunnymedic:BAAANQAECgMIAwABNQAECgcIHAACAMMjAA==.',
Ca='Caebrylla:BAAANQAECgUIDwAAAA==.Cajun:BAAANQAECggIDwABNQAFFAUIEwAHAA4VAA==.Calistie:BAAANQABCgYIBwAAAA==.Callipygea:BAAANQADCgIIAgAAAA==.Camil:BAAANQADCgMIAwABNQAECggIIAADAG8OAA==.Cang:BAAANQABCgcIFgAAAA==.Catalina:BAABNQAECoEnAAIIAAgKph9xHwDcAgAIAAgKph9xHwDcAgAAAA==.',
Ce='Cecimorte:BAAANQAECgUIDwAAAA==.',
Ch='Chargeasap:BAAANQADCgUIBQAAAA==.Charttopper:BAAANQADCgUIBQABNQAECgMIAwAJAAAAAA==.Chinashop:BAAANQAECgMIAwABNQAECgYICgAJAAAAAA==.Chonker:BAABNQAECoEiAAMKAAgK5A/APwDSAQAKAAgK5A/APwDSAQALAAUK5RSsOQAbAQAAAA==.Chuckforrest:BAAANQADCgIIAgABNQAECgYIBgAJAAAAAA==.',
Ci='Cihato:BAABNQAECoEhAAIMAAgKyhV7EgD4AQAMAAgKyhV7EgD4AQAAAA==.',
Cl='Cleveistic:BAAANQADCgMIBAABNQAECgEIAgAJAAAAAA==.Cleveland:BAAANQAECgEIAgAAAA==.',
Co='Coldshoulder:BAAANQAECgUIDQAAAA==.Corelas:BAAANQAECgIIAwAAAA==.Couchdad:BAAANQADCggIFwAAAA==.',
Cr='Crazymadman:BAAANQADCggIGwAAAA==.Crysallis:BAAANQADCggIHgAAAA==.',
Cy='Cynide:BAAANQADCgYJBgAAAA==.',
Da='Dall:BAAANQAECgIIAwAAAA==.Damo:BAAANQAECgYJCAAAAA==.Danale:BAAANQADCgYJCgAAAA==.Danknugz:BAAANQAECgUIDAAAAA==.Dawnson:BAAANQAECgUICgAAAA==.',
De='Deadscream:BAAANQAECggIBgAAAA==.Deathlich:BAAANQAECgYICwAAAA==.Demogless:BAAANQAECgMIAwAAAA==.Desyrel:BAAANQAECgIIAgABNQAECgQICwAJAAAAAA==.',
Dh='Dharknight:BAAANQAECgQIBgAAAA==.Dharkuul:BAAANQABCgYICAABNQAECgQIBgAJAAAAAA==.',
Di='Didimissfire:BAEBNQAECoEeAAIDAAgKtgjLiwDBAQADAAgKtgjLiwDBAQAAAA==.Diefatty:BAAANQADCgMIAwAAAA==.Dilaudid:BAAANQAECggICAAAAA==.',
Dr='Draeven:BAAANQABCgIIAgAAAA==.Dranalis:BAAANQADCgYICAAAAA==.Dredlok:BAAANQADCgYIEAAAAA==.',
Du='Dumonster:BAAANQAECgMIBAAAAA==.',
Ea='Eamishal:BAAANQADCgMIAwAAAA==.',
Ee='Eeaassyy:BAAANQADCgQIBQAAAA==.',
El='Elaraa:BAAANQADCgQIBAAAAA==.Elev:BAAANQADCgMIAwAAAA==.Elizabeth:BAAANQADCgUIBQAAAA==.',
Er='Eris:BAAANQADCggICAAAAA==.Erzascar:BAAANQAECgEIAQAAAA==.',
Es='Estrogen:BAABNQAECoEgAAINAAgKMiVpAwBiAwANAAgKMiVpAwBiAwAAAA==.',
Ev='Eventhorizon:BAAANQAECgYIAgAAAA==.Evolett:BAAANQADCgQIBAAAAA==.',
Fa='Fatbox:BAABNQAECoEcAAMGAAcKCBwICQAkAgAGAAcKCBwICQAkAgAOAAEKrA0iNgEzAAAAAA==.Fayth:BAABNQAECoEfAAIPAAgKFx2dLACXAgAPAAgKFx2dLACXAgAAAA==.',
Fe='Fearkin:BAAANQAECgYIDgAAAA==.Fenastic:BAABNQAECoEZAAMQAAYKLQZExgAQAQAQAAYKGgZExgAQAQARAAEKtwf4KwA0AAAAAA==.Fermy:BAAANQABCgIIAQAAAA==.Feyrah:BAAANQAECgEIAQAAAA==.',
Fi='Fiobhe:BAAANQAECgIIAwAAAA==.Fixeruper:BAAANQAECgYIDAAAAA==.',
Fo='Fonz:BAAANQADCgYIBgABNQAECgQIBQAJAAAAAA==.',
Ge='Geauxt:BAAANQAECgQIBwABNQAFFAUIEwAHAA4VAA==.',
Gl='Glenlizzo:BAAANQADCgEJAQABNQAECgEIAgAJAAAAAA==.Glenroyce:BAAANQAECgEIAgAAAA==.Gless:BAABNQAECoEcAAIEAAcKQQzgGwBRAQAEAAcKQQzgGwBRAQAAAA==.',
Gn='Gnoretreat:BAABNQAECoEgAAIOAAgKthn9XgBSAgAOAAgKthn9XgBSAgAAAA==.',
Gw='Gwinnivor:BAAANQADCgEIAQAAAA==.',
Ha='Haill:BAAANQABCgIIAgABNQAECgUICQAJAAAAAA==.Hamhock:BAAANQAECgIIAgABNQAECgcIHAAGAAgcAA==.',
He='Hellìos:BAAANQADCgYIBgABNQAECgIIAgAJAAAAAA==.',
Hy='Hyborian:BAAANQAECgUICQABNQADCgIIAgAJAAAAAA==.',
Ic='Icandy:BAAANQADCgMIAgAAAA==.Icecuber:BAAANQADCgMIAwAAAA==.',
Ih='Ihatepallys:BAAANQADCgYICQAAAA==.',
Ii='Iikeomgikr:BAAANQAECgUIDgAAAA==.',
Il='Ilidank:BAAANQAECgYICQABNQAECgYICgAJAAAAAA==.Ilya:BAAANQAECgcIBwAAAA==.',
In='Indigo:BAABNQAECoEcAAICAAcKyxjnUAD1AQACAAcKyxjnUAD1AQAAAA==.Ineffablyss:BAAANQABCgYICAABNQAECgUIDgAJAAAAAA==.Innron:BAABNQAECoEbAAISAAgKagziOAC3AQASAAgKagziOAC3AQAAAA==.',
Io='Iol:BAAANQADCgIIAgAAAA==.',
Ir='Irisblue:BAAANQADCgYIAwAAAA==.',
Ja='Jaque:BAAANQADCgYICwAAAA==.',
Je='Jezzea:BAAANQADCgYICwAAAA==.',
Ji='Jinjix:BAAANQADCgYIDQAAAA==.',
Jo='Jolike:BAAANQAECgEIAgAAAA==.Jonly:BAAANQADCgQIBAAAAA==.Jonoa:BAAANQAECgYIDAAAAA==.',
['Jú']='Júdgemental:BAAANQAECggIDQAAAA==.',
Ka='Kair:BAAANQADCgcIBwAAAA==.Kalsium:BAAANQADCgUJDAAAAA==.Kami:BAAANQAECgIIAwAAAA==.Kattastrophy:BAAANQAECgEIAQAAAA==.Katteya:BAAANQADCggIJwAAAA==.Kattia:BAABNQAECoEdAAIDAAcK9AjjowCLAQADAAcK9AjjowCLAQAAAA==.',
Ki='Killinkair:BAAANQAECgYICAAAAA==.Kinomihime:BAABNQAECoEfAAMTAAgKERJACwDZAQATAAgKERJACwDZAQAUAAEKMAa6pwE0AAAAAA==.Kirajoy:BAABNQAECoEcAAMVAAcKzwM3MQD3AAAVAAcKegM3MQD3AAAQAAYKBgJC9gCrAAAAAA==.Kisses:BAAANQADCgYICgAAAA==.',
Kn='Knyghtt:BAAANQAECgYICAAAAA==.',
Kr='Kraviz:BAAANQADCgcICgAAAA==.Krystle:BAAANQAECgUIBQAAAA==.',
Le='Leftyloose:BAAANQADCgYIBAAAAA==.Leorna:BAAANQADCgQIBQAAAA==.',
Li='Lightcure:BAAANQAECgIIAwABNQAECggIIAAWAJIXAA==.Lilfonz:BAAANQAECgQIBQAAAA==.Littlejohn:BAAANQAECgQIBgABNQAECgYICgAJAAAAAA==.',
Lo='Logarth:BAAANQAECgEIAgABNQAECgIIAgAJAAAAAA==.Londonfog:BAAANQADCggIEwAAAA==.Loppandload:BAAANQAECgEIAQAAAA==.Loppsang:BAAANQADCgEJAQAAAA==.Lorcan:BAABNQAECoEgAAIOAAgKpxsYVQBvAgAOAAgKpxsYVQBvAgAAAA==.',
Lr='Lroye:BAACNQAFFIETAAMHAAUKDhV8BQC3AQAHAAUKDhV8BQC3AQAXAAEK2w2GGQBNAAA1AAQKgTIAAwcACQrDJMYBAKMDAAcACQrDJMYBAKMDABcAAQo3DMWHADkAAAAA.',
Lu='Lucyfer:BAAANQADCgcIDQABNQAECgQICwAJAAAAAA==.Lucyferr:BAAANQAECgQICwAAAA==.Ludicrispeed:BAAANQADCgYIAwAAAA==.Luliak:BAAANQAECgIIAgABNQAFFAMIBwAYANggAA==.Lunabren:BAAANQADCgcIBgAAAA==.Lunamina:BAAANQAECgEIAQAAAA==.',
['Lì']='Lìllith:BAAANQAECgYIDAABNQAECgkJJgAZAKQfAA==.',
Ma='Mariophra:BAAANQAECgUIDwAAAA==.Maxdemon:BAAANQADCgUIBQAAAA==.Maxpal:BAAANQADCgYIDgAAAA==.',
Mc='Mcnastyqt:BAAANQADCgIIAgAAAA==.',
Me='Mesdel:BAAANQAECgEIAQABNQAECggIGgAaABsbAA==.',
Mi='Mikki:BAAANQADCgIIAgAAAA==.Misstorgo:BAAANQADCggIKAAAAA==.',
Mo='Mohegian:BAAANQABCgQIAwAAAA==.Monfro:BAAANQAECgUICAAAAA==.Monnethir:BAAANQADCgUIBQAAAA==.Moogatoo:BAAANQAECgEIAQAAAA==.Moonbane:BAABNQAECoEfAAMVAAgKnBz8BQCoAgAVAAgKnBz8BQCoAgAQAAQKNA6Q4ADbAAAAAA==.Moonmist:BAAANQABCgUIBQABNQAECgUICQAJAAAAAA==.Mordecai:BAAANQAECgUIBwAAAA==.',
My='Myaquean:BAAANQADCgYIDgAAAA==.Mystogan:BAAANQADCgYIDgAAAA==.Myth:BAABNQAECoEcAAMKAAcKnRZIPADoAQAKAAcKnRZIPADoAQALAAIKvw+4WwBhAAAAAA==.',
Na='Naavi:BAAANQAECgEIAQAAAA==.Nakeefa:BAAANQADCgYIBgAAAA==.Natsuu:BAABNQAECoEbAAIDAAcKxxIbcwD9AQADAAcKxxIbcwD9AQAAAA==.',
Ne='Nefertiti:BAAANQADCggIAgAAAA==.Neron:BAABNQAECoEmAAIZAAkKpB+ILQD0AgAZAAkKpB+ILQD0AgAAAA==.',
Ni='Niany:BAAANQAECgEIAgAAAA==.',
Nj='Njoror:BAAANQAECgIIAgAAAA==.',
No='Norky:BAAANQABCgUICQABNQABCgMIAwAJAAAAAA==.',
Os='Ossiferous:BAAANQAECgYICgAAAA==.',
Ou='Outerlimits:BAAANQAECgcIDQAAAA==.',
Pa='Pamboo:BAABNQAECoEiAAIIAAgKGQnadACRAQAIAAgKGQnadACRAQAAAA==.Patticake:BAAANQAECggICAAAAA==.',
Pe='Penthesilea:BAAANQABCgYIBwAAAA==.',
Po='Potatoslicer:BAAANQADCgQIBAAAAA==.',
Pr='Priestiô:BAAANQAECgQIBQAAAA==.Pringo:BAAANQAECgUICgAAAA==.',
Ra='Ramindizzle:BAABNQAECoEiAAIbAAgKxRHPKADjAQAbAAgKxRHPKADjAQAAAA==.Randomname:BAAANQAECgcICgABNQAECggIDQAJAAAAAA==.',
Re='Refreshing:BAAANQADCgUIBwAAAA==.Rekki:BAAANQAECgIIBAABNQAECgQICwAJAAAAAA==.Retastic:BAAANQADCgUIBQAAAA==.',
Ri='Rigmarole:BAAANQAECgUICgAAAA==.',
Ro='Rocksmasher:BAAANQADCgEIAQABNQAECgMIAwAJAAAAAA==.Ronun:BAAANQADCggICwAAAA==.Rook:BAAANQAECgEIAQAAAA==.Rooklyn:BAABNQAECoEgAAIIAAgK1Q0dZQDDAQAIAAgK1Q0dZQDDAQAAAA==.Roye:BAABNQAECoEjAAIZAAkKQSChIwAdAwAZAAkKQSChIwAdAwABNQAFFAUIEwAHAA4VAA==.',
Ru='Ruffiyo:BAAANQADCggICAABNQAECggIIAAWAJIXAA==.Rugrahh:BAAANQADCgYIBgAAAA==.Rugzco:BAABNQAECoEcAAIcAAgKiBf5EwAQAgAcAAgKiBf5EwAQAgAAAA==.Ruìn:BAAANQAECgIJBQAAAA==.',
Ry='Ryalla:BAAANQABCgEIAQAAAA==.',
['Ræ']='Ræñ:BAAANQADCgYICgAAAA==.',
Sa='Sabina:BAABNQAECoEhAAIaAAgKKgdmegCDAQAaAAgKKgdmegCDAQAAAA==.Sadako:BAAANQADCggIJAABNQAECgQICwAJAAAAAA==.Sadness:BAAANQADCggIGAAAAA==.Sadorick:BAAANQADCggIJAAAAA==.Sageguy:BAAANQADCgcIDwAAAA==.Saintkitiara:BAAANQABCgMIAwAAAA==.Sango:BAABNQAECoEcAAISAAgKBQudOgCsAQASAAgKBQudOgCsAQAAAA==.Sarenity:BAAANQADCgYIBgAAAA==.Savagelykill:BAAANQADCggIDgAAAA==.',
Sc='Scotch:BAABNQAECoEcAAMZAAcKNBMxogClAQAZAAcKNBMxogClAQAFAAEKjxEtYwAyAAAAAA==.Scotchnwater:BAAANQADCgMIAwAAAA==.Scratchies:BAAANQAECgQIBgAAAA==.',
Se='Seiwar:BAAANQAFFAMIBAAAAA==.',
Sh='Shadornia:BAAANQAECgMIBwAAAA==.Shadowcrwlr:BAAANQADCgQIBAAAAA==.Shamangroo:BAAANQABCgcIEAABNQADCgYIGwAJAAAAAA==.Shamanio:BAABNQAECoElAAICAAkKAyKBCQBhAwACAAkKAyKBCQBhAwAAAA==.Shammbulance:BAAANQAECggICAABNQAECggIDQAJAAAAAA==.Shamsham:BAAANQABCgIIAgAAAA==.Sharaaz:BAAANQADCgUIBQAAAA==.Shatoya:BAAANQADCgcIAwAAAA==.',
Si='Silverytwo:BAAANQADCggIDwAAAA==.Silverywolfe:BAAANQAECgEIAQAAAA==.',
Sk='Skovak:BAAANQAECgQIBQAAAA==.Skoveth:BAAANQAECgEIAQAAAA==.',
So='Sorayae:BAABNQAECoEjAAIPAAgK9CSxDgA7AwAPAAgK9CSxDgA7AwAAAA==.',
Sp='Specialk:BAAANQAECgEIAQAAAA==.Splooshh:BAAANQADCggIDgABNQAECggIIAAWAJIXAA==.',
St='Steeler:BAAANQADCgcIBwABNQADCgIIAgAJAAAAAA==.Stinkfoot:BAAANQAECgYIDwAAAA==.Stormkissed:BAAANQADCggIKAAAAA==.Strawman:BAAANQAECgYIBwAAAA==.',
Su='Sugarush:BAAANQADCgQIBAABNQAECgUICQAJAAAAAA==.Sulvazud:BAAANQADCgEIAQAAAA==.Sunil:BAABNQAECoEcAAIPAAcKtRPuZgC2AQAPAAcKtRPuZgC2AQAAAA==.',
Sy='Syclone:BAAANQAECgMIBgABNQAECgkJWwAWAEgkAA==.',
Ta='Taetheras:BAAANQAECgIIAgAAAA==.Tahlyn:BAAANQAECgEIAQABNQAECgcIHAACAMsYAA==.Tattianna:BAAANQADCgYIFwAAAA==.Tavendar:BAABNQAECoEcAAMIAAcKfR9bSAAmAgAIAAYKWB9bSAAmAgAZAAIKmAaMXQFJAAABNQABCgMIAwAJAAAAAA==.',
Te='Texgrebner:BAAANQAECgYICgAAAA==.',
Th='Theeyedoctor:BAAANQADCggIBwABNQAECgMIAwAJAAAAAA==.Thunderslate:BAAANQAECgMIAwAAAA==.Thyrok:BAAANQAECgMIAwAAAA==.',
Ti='Tigreth:BAABNQAECoEhAAMZAAgKWQ7TmQC4AQAZAAgKUA7TmQC4AQAFAAMKWguBTwB5AAAAAA==.Tinkerballa:BAAANQADCggJEgAAAA==.',
To='Toastal:BAAANQAECgIIAgAAAA==.Totemzasap:BAAANQAECgQICAAAAA==.',
Tr='Traductus:BAAANQAECgIIAgAAAA==.Tragik:BAABNQAECoEhAAIYAAgKCAguFgDZAQAYAAgKCAguFgDZAQAAAA==.Trisandra:BAAANQAECgIIAgAAAA==.',
Tu='Tuugadark:BAABNQAECoEfAAIQAAgKNR6QLgCzAgAQAAgKNR6QLgCzAgAAAA==.',
Tz='Tzulari:BAAANQAECgQIBAABNQAECgQIBgAJAAAAAA==.',
Ul='Ulyaoth:BAAANQADCgUIBQAAAA==.',
Un='Unbroken:BAAANQADCgMIAwAAAA==.Unprepared:BAAANQABCgEIAQABNQAECgUIDQAJAAAAAA==.',
Va='Vasdeferens:BAAANQABCgMIAwAAAA==.',
Ve='Vedros:BAAANQADCgYICQAAAA==.Verbina:BAAANQAECgQICQABNQAECgcIHAACAMsYAA==.',
Vo='Vorukh:BAAANQAECgIIBAAAAA==.',
Wa='Warlockgroo:BAAANQABCggICwABNQADCgYIGwAJAAAAAA==.Warriorgroo:BAAANQADCgYIGwAAAA==.',
Wi='Wickdlovly:BAAANQABCggIEAABNQAECgUICQAJAAAAAA==.Wickedslicks:BAAANQAECgUIDwAAAA==.',
Wr='Wreckshop:BAAANQADCgYIDwABNQAECgYIDwAJAAAAAA==.',
Xe='Xenøcide:BAAANQADCgcICwAAAA==.',
Xi='Xiatus:BAAANQAECgQICAABNQAECgkJKgAdAEklAA==.',
Xo='Xoren:BAAANQAECgEIAQABNQAECgQICwAJAAAAAA==.',
Xx='Xxlockz:BAAANQADCgIIAgABNQAECgUIDwAJAAAAAA==.Xxpallyz:BAAANQAECgUIDwAAAA==.',
Yo='Yohh:BAABNQAECoEaAAICAAgKOBNiTAAFAgACAAgKOBNiTAAFAgAAAA==.Yorie:BAAANQADCgMIAwAAAA==.',
Yu='Yuriko:BAABNQAECoEhAAIcAAgKCw99GQC5AQAcAAgKCw99GQC5AQAAAA==.',
Za='Zadory:BAAANQADCggIDAAAAA==.Zaidan:BAAANQADCgYIDAAAAA==.',
Ze='Zendous:BAAANQAECgYIBgAAAA==.',
Zi='Zippitydooda:BAAANQAECgUICQAAAA==.',
Zo='Zodiacc:BAABNQAECoEeAAIMAAgK3R8JBwDoAgAMAAgK3R8JBwDoAgAAAA==.Zornhealer:BAAANQADCgEIAQABNQADCggIFwAJAAAAAA==.Zorrn:BAAANQADCgUIBwABNQADCggIFwAJAAAAAA==.',
['Zí']='Zílch:BAAANQAECgEIAQAAAA==.',
['Zö']='Zölä:BAAANQAECgQIBwABNQAECgYIBwAJAAAAAA==.',
['Çh']='Çhrìs:BAAANQAECgQICAAAAA==.',
['Çú']='Çúrsè:BAAANQADCgIIAwAAAA==.',
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
